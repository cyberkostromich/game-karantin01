class_name ZombieBrain
extends RefCounted
## FSM зомби (GDD §8.1): idle → investigate → chase → attack; орда идёт по flow-field к Штабу.
## Отделено от хранилища ZombieSystem, чтобы обе части были < 600 строк.

const S := ZombieSystem.S

var world: World
var z: ZombieSystem
var wander_r: float
var inv_timeout: float
var lose_s: float
var feed_s: float
var block_attack_s: float
var sep_k: float
var wake_r: float
var camo_r: float
var prio: Dictionary
var screamer_t: int = -1
var spitter_t: int = -1
var tmp := PackedInt32Array()


func setup(w: World) -> void:
	world = w
	z = w.zombies
	wander_r = Config.f("zombies.ai.idle_wander_radius")
	inv_timeout = Config.f("zombies.ai.investigate_timeout_s")
	lose_s = Config.f("zombies.ai.lose_target_s")
	feed_s = Config.f("zombies.ai.feeding_on_corpse_s")
	block_attack_s = Config.f("zombies.ai.building_attack_when_blocked_s")
	sep_k = Config.f("rules.sim_tuning.zombie_separation")
	wake_r = Config.f("rules.sim_tuning.zombie_wake_radius")
	camo_r = Config.f("rules.sim_tuning.camo_detect_radius")
	prio = Config.d("combat.target_priority.zombie_vs")
	screamer_t = z.type_index("screamer")
	spitter_t = z.type_index("spitter")


func think(i: int, dt: float, tick: int) -> void:
	match z.state[i]:
		S.IDLE: _idle(i, dt, tick)
		S.INVESTIGATE: _investigate(i, dt, tick)
		S.CHASE: _chase(i, dt, tick)
		S.ATTACK: _attack(i, dt)
		S.HORDE: _horde(i, dt, tick)
		S.FEEDING: _feeding(i, dt)
	if z.type_id[i] == screamer_t:
		_scream(i, dt)
	if z.buff_t[i] > 0.0:
		z.buff_t[i] -= dt


func speed_of(i: int) -> float:
	var s := z.t_speed[z.type_id[i]]
	if z.buff_t[i] > 0.0:
		s *= Config.f("zombies.screamer.scream.buff_speed_mult")
	if world.light.lit(z.pos[i]):
		s *= Config.f("combat.light.zombie_speed_in_light_mult")
	return s


# ------------------------------------------------------------------ состояния
func _idle(i: int, dt: float, tick: int) -> void:
	if (i + tick) % 4 == 0 and _acquire(i):
		return
	if (i + tick) % 20 == 0 and world.agents.hash.nearest(z.pos[i], wake_r) == -1:
		z.flags[i] |= ZombieSystem.F_DORMANT
	elif (i + tick) % 20 == 0:
		z.flags[i] &= ~ZombieSystem.F_DORMANT
	z.timer[i] -= dt
	if z.timer[i] <= 0.0:
		var r := world.rng
		z.goal[i] = z.home[i] + Vector2(r.randf_range(-wander_r, wander_r), r.randf_range(-wander_r, wander_r))
		z.timer[i] = r.randf_range(4.0, 10.0)
	_move_to(i, z.goal[i], speed_of(i) * 0.4, dt, tick, 1.0)


func _investigate(i: int, dt: float, tick: int) -> void:
	if (i + tick) % 2 == 0 and _acquire(i):
		return
	z.timer[i] -= dt
	var arrived := _move_to(i, z.goal[i], speed_of(i), dt, tick, 2.0)
	if arrived or z.timer[i] <= 0.0 or z.blocked_t[i] > 3.0:
		_resume(i)


func _chase(i: int, dt: float, tick: int) -> void:
	var t := z.target[i]
	var info := z.target_info(t, z.pos[i])
	if info == Vector3.INF:
		_resume(i)
		return
	var tp := Vector2(info.x, info.y)
	var d := z.pos[i].distance_to(tp) - info.z
	var rng := _range(i)
	if d <= rng:
		z.state[i] = S.ATTACK
		return
	if (i + tick) % 4 == 0:
		if d > z.t_sight[z.type_id[i]] * 1.5:
			z.lose_t[i] += dt * 4.0
			if z.lose_t[i] > lose_s:
				_resume(i)
				return
		else:
			z.lose_t[i] = 0.0
		if t <= -2 and (i + tick) % 8 == 0:
			_acquire(i)  # ломая стену, переключаемся на людей в поле зрения
	var hit := _move_to(i, tp, speed_of(i), dt, tick, 0.0, true)
	if hit and z.blocked_t[i] > block_attack_s:
		_attack_blocker(i)


func _attack(i: int, dt: float) -> void:
	var t := z.target[i]
	var info := z.target_info(t, z.pos[i])
	if info == Vector3.INF:
		_resume(i)
		return
	var tp := Vector2(info.x, info.y)
	var d := z.pos[i].distance_to(tp) - info.z
	if d > _range(i) * 1.3 + 0.3:
		z.state[i] = S.CHASE
		return
	var to := tp - z.pos[i]
	if to.length_squared() > 0.0001:
		z.vel[i] = to.normalized() * 0.01  # только разворот к цели
	z.atk_cd[i] -= dt
	if z.atk_cd[i] > 0.0:
		return
	var atk: Dictionary = z.t_attack[z.type_id[i]]
	if atk.is_empty():
		return
	z.atk_cd[i] = 1.0 / float(atk["rof"])
	if t >= 0:
		var killed := world.combat.zombie_hits_agent(i, world.agents.get_agent(t), atk)
		if killed:
			z.state[i] = S.FEEDING
			z.timer[i] = feed_s
	else:
		world.combat.zombie_hits_building(i, world.buildings.get_building(-(t + 2)), atk)


func _horde(i: int, dt: float, tick: int) -> void:
	if (i + tick) % 3 == 0 and _acquire(i):
		return
	var f := world.flow
	var dir := f.dir_at(z.pos[i])
	if dir == Vector2.ZERO:
		if f.in_window(z.pos[i]) and f.is_ready():
			# внутри окна без направления — мы у Штаба или в тупике: ищем ближайшую постройку
			_attack_nearby_building(i)
			return
		dir = (f.center - z.pos[i]).normalized()
	var v := dir * speed_of(i)
	if (i + tick) % 2 == 0:
		v += z.separate(i) * sep_k
	z.vel[i] = v
	var hit := z.step(i, v, dt)
	if hit >= 0:
		z.blocked_t[i] += dt
		if z.blocked_t[i] > block_attack_s:
			z.target[i] = -(hit + 2)
			z.state[i] = S.ATTACK
			z.blocked_t[i] = 0.0
	elif z.pos[i] == z.prev[i]:
		z.blocked_t[i] += dt
	else:
		z.blocked_t[i] = maxf(0.0, z.blocked_t[i] - dt)


func _feeding(i: int, dt: float) -> void:
	z.timer[i] -= dt
	z.vel[i] = Vector2.ZERO
	if z.timer[i] <= 0.0:
		_resume(i)


func _scream(i: int, dt: float) -> void:
	var st := z.state[i]
	if st == S.IDLE:
		return
	z.atk_cd[i] -= dt
	if z.atk_cd[i] > 0.0:
		return
	var sc := Config.d("zombies.screamer.scream")
	z.atk_cd[i] = float(sc["interval_s"])
	world.noise.emit(z.pos[i], float(sc["noise"]))
	z.hash.query(z.pos[i], float(sc["buff_radius"]), tmp)
	for j in tmp:
		z.buff_t[j] = float(sc["interval_s"])
	world.emit("scream", [z.pos[i], float(sc["noise"])])


# ------------------------------------------------------------------ вспомогательное
func _range(i: int) -> float:
	var t := z.type_id[i]
	if t == screamer_t:
		return Config.f("rules.sim_tuning.screamer_keep_distance")
	var atk: Dictionary = z.t_attack[t]
	return float(atk.get("range", 1.2)) + z.t_radius[t]


func lose_target(i: int) -> void:
	_resume(i)


## Выход из охоты: член орды возвращается в орду, остальные — бродить на месте.
func _resume(i: int) -> void:
	z.target[i] = ZombieSystem.NO_TARGET
	z.lose_t[i] = 0.0
	z.blocked_t[i] = 0.0
	if (z.flags[i] & ZombieSystem.F_HORDE) != 0:
		z.state[i] = S.HORDE
	else:
		z.state[i] = S.IDLE
		z.home[i] = z.pos[i]
		z.timer[i] = 0.0


## Ищем лучшую цель в поле зрения: приоритет (мирные > пехота > техника) / расстояние.
func _acquire(i: int) -> bool:
	var p := z.pos[i]
	if (z.flags[i] & ZombieSystem.F_BLIND) != 0:
		if world.abilities.in_smoke(p):
			return false
		z.flags[i] &= ~ZombieSystem.F_BLIND
	var t := z.type_id[i]
	var sight := z.t_sight[t]
	var ah := world.agents
	ah.hash.query(p, sight, tmp, 24)
	var best := -1
	var best_s := 0.0
	var can_air := t == spitter_t
	for k in tmp:
		var a: Agent = ah.hash_list[k]
		if not a.alive or not a.targetable():
			continue
		if a.kind == Agent.Kind.AIR and not can_air:
			continue
		var d := p.distance_to(a.pos)
		if a.camo_t > 0.0 and d > camo_r:
			continue
		var s := float(prio.get(a.priority_class(), 1)) / (1.0 + d * 0.1)
		if s > best_s:
			best_s = s
			best = a.id
	if best == -1:
		return false
	z.target[i] = best
	z.state[i] = S.CHASE
	z.lose_t[i] = 0.0
	z.flags[i] &= ~ZombieSystem.F_DORMANT
	return true


func _attack_blocker(i: int) -> void:
	var b := world.buildings.building_near(z.pos[i] + z.vel[i].normalized() * 1.5, 2.5)
	if b != null:
		z.target[i] = -(b.id + 2)
		z.state[i] = S.ATTACK
	z.blocked_t[i] = 0.0


func _attack_nearby_building(i: int) -> void:
	var b := world.buildings.building_near(z.pos[i], 6.0)
	if b != null:
		z.target[i] = -(b.id + 2)
		z.state[i] = S.CHASE
	else:
		z.vel[i] = Vector2.ZERO


## Движение к точке с обходом стен скольжением. Возвращает true по прибытии (или если упёрся при stop_on_block).
func _move_to(i: int, to: Vector2, spd: float, dt: float, tick: int, arrive_r: float, stop_on_block := false) -> bool:
	var d := to - z.pos[i]
	var l := d.length()
	if l <= arrive_r:
		z.vel[i] = Vector2.ZERO
		return true
	var v := d / l * minf(spd, l / dt)
	if (i + tick) % 2 == 0 and (z.flags[i] & ZombieSystem.F_DORMANT) == 0:
		v += z.separate(i) * sep_k
	z.vel[i] = v
	var before := z.pos[i]
	var hit := z.step(i, v, dt)
	if hit >= 0 or z.pos[i].distance_squared_to(before) < 0.0001:
		z.blocked_t[i] += dt
		return stop_on_block
	z.blocked_t[i] = maxf(0.0, z.blocked_t[i] - dt * 0.5)
	return false
