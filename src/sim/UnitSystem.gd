class_name UnitSystem
extends RefCounted
## Военные (GDD §7): таргетинг по приоритетам, огонь, шум, лечение, гарнизоны, транспорт, топливо вертолёта.
## Способности — Abilities.gd, обучение — TrainingSystem.gd.

var world: World
var tmp := PackedInt32Array()
var scan_s: float = 0.25
var prio_default: Dictionary
var prio_sniper: Dictionary
var specials: PackedStringArray = ["screamer", "spitter", "brute", "giant", "walker_armored"]


func setup(w: World) -> void:
	world = w
	scan_s = Config.f("rules.sim_tuning.scan_interval_s")
	prio_default = Config.d("combat.target_priority.default_vs")
	prio_sniper = Config.d("combat.target_priority.sniper_vs")


func update(dt: float) -> void:
	for a in world.agents.list.duplicate():
		if not a.alive or not a.is_unit():
			continue
		_timers(a, dt)
		if not a.alive:
			continue
		if a.hidden:
			if a.container >= 0 and _in_tower(a):
				_combat(a, dt)
			continue
		_orders(a)
		_combat(a, dt)
		_noise(a, dt)
		if a.type == "medic":
			_heal(a, dt)
		if a.type == "tank" or a.ram_t > 0.0:
			_crush(a, dt)
		if a.type == "scout":
			_reveal(a)


func _timers(a: Agent, dt: float) -> void:
	for k: String in a.ability_cd.keys():
		a.ability_cd[k] = maxf(0.0, float(a.ability_cd[k]) - dt)
	if a.camo_t > 0.0:
		a.camo_t -= dt
	if a.ram_t > 0.0:
		a.ram_t -= dt
		if a.ram_t <= 0.0:
			a.speed_mult = 1.0
	if a.temp_life >= 0.0:
		a.temp_life -= dt
		if a.temp_life <= 0.0:
			world.agents.remove(a)
			world.emit("unit_died", [a.id, a.type, a.pos])
			return
	if a.kind == Agent.Kind.AIR:
		world.heli.update_fuel(a, dt)


# ------------------------------------------------------------------ приказы
func _orders(a: Agent) -> void:
	match a.order:
		Agent.Order.PATROL:
			if not a.moving:
				var to := a.patrol_b if a.pos.distance_to(a.patrol_b) > 2.0 else a.patrol_a
				var other := a.patrol_a if to == a.patrol_b else a.patrol_b
				a.patrol_a = other
				a.patrol_b = to
				world.agents.move_to(a, to)
		Agent.Order.ENTER:
			_try_enter(a)
		Agent.Order.MOVE, Agent.Order.AMOVE:
			if not a.moving and not world.agents.path_queue.has(a.id):
				a.order = Agent.Order.NONE


func _try_enter(a: Agent) -> void:
	var b := world.buildings.get_building(a.order_target) if not a.order_target_unit else null
	if b != null and b.alive:
		if a.pos.distance_to(b.rect_m.get_center()) <= b.half_extent() + Config.f("rules.sim_tuning.garrison_enter_radius_m"):
			garrison(a, b)
		elif not a.moving:
			world.agents.move_to(a, b.door)
		return
	var v := world.agents.get_agent(a.order_target) if a.order_target_unit else null
	if v != null and v.alive and v.is_unit():
		if a.pos.distance_to(v.pos) <= v.radius + Config.f("rules.sim_tuning.transport_enter_radius_m"):
			board(a, v)
		elif not a.moving or a.dest.distance_to(v.pos) > 6.0:
			world.agents.move_to(a, v.pos)
		return
	a.order = Agent.Order.NONE


# ------------------------------------------------------------------ бой
func _range(a: Agent, key: String = "attack") -> float:
	var r := Config.f("units.%s.%s.range" % [a.type, key])
	if a.hidden and a.container >= 0:
		var b := world.buildings.get_building(a.container)
		if b != null:
			r += float(b.data().get("garrison_range_bonus", 0.0))
	if a.type == "sniper" and world.map.is_high_ground(a.pos):
		r *= 1.0 + Config.f("units.sniper.high_ground_range_bonus")
	return r


func _combat(a: Agent, dt: float) -> void:
	a.atk_cd -= dt
	a.atk2_cd -= dt
	a.scan_cd -= dt
	if a.order == Agent.Order.MOVE and a.moving:
		return
	if a.kind == Agent.Kind.AIR and a.fuel <= 0.0:
		return
	var rng := _range(a)
	if a.scan_cd <= 0.0:
		a.scan_cd = scan_s
		_pick_target(a, rng)
	var z := world.zombies
	if a.target_z >= 0 and (z.alive[a.target_z] == 0 or z.pos[a.target_z].distance_to(a.pos) > rng):
		a.target_z = -1
	if a.target_z >= 0:
		var tp := z.pos[a.target_z]
		a.facing = atan2(tp.x - a.pos.x, tp.y - a.pos.y)
		if a.atk_cd <= 0.0:
			_fire(a, "attack", tp, a.target_z)
	elif a.target_nest >= 0:
		var n: MapPoi = world.map.nest_by_id(a.target_nest)
		if n == null or not n.alive or n.pos.distance_to(a.pos) > rng + n.radius:
			a.target_nest = -1
		elif a.atk_cd <= 0.0:
			_fire(a, "attack", n.pos, -1, n)
	if a.type == "tank" and a.atk2_cd <= 0.0:
		var j := _best_zombie(a, _range(a, "attack_secondary"))
		if j >= 0:
			_fire(a, "attack_secondary", z.pos[j], j)


func _pick_target(a: Agent, rng: float) -> void:
	if a.order == Agent.Order.ATTACK and a.order_target >= 0:
		var n := world.map.nest_by_id(a.order_target)
		if n != null and n.alive:
			a.target_nest = n.id
			if n.pos.distance_to(a.pos) > rng + n.radius:
				if not a.moving:
					world.agents.move_to(a, n.pos)
				return
			a.stop()
			return
		a.order = Agent.Order.NONE
	var j := _best_zombie(a, rng)
	if j >= 0:
		a.target_z = j
		if a.order == Agent.Order.AMOVE and a.moving:
			a.stop()
			a.order_pos = a.dest
		return
	a.target_z = -1
	if a.order == Agent.Order.AMOVE and not a.moving and a.pos.distance_to(a.order_pos) > 3.0:
		world.agents.move_to(a, a.order_pos)
	elif a.order == Agent.Order.NONE and a.kind != Agent.Kind.AIR:
		_engage_in_vision(a)
	if a.target_nest < 0:
		for n in world.map.nests:
			if n.alive and n.pos.distance_to(a.pos) <= rng + n.radius and a.order != Agent.Order.MOVE:
				a.target_nest = n.id
				break


## Простаивающий боец сам идёт на зомби в поле зрения, но не дальше поводка от своей точки (GDD §7).
func _engage_in_vision(a: Agent) -> void:
	if a.order_pos == Vector2.ZERO:
		a.order_pos = a.pos
	var leash := Config.f("rules.sim_tuning.idle_engage_leash_m")
	var j := world.zombies.hash.nearest(a.pos, world.mods.vision_of(a))
	if j >= 0 and world.zombies.pos[j].distance_to(a.order_pos) < leash:
		world.agents.move_to(a, world.zombies.pos[j])
		a.order = Agent.Order.AMOVE
		a.order_pos = a.pos
	elif not a.moving and a.pos.distance_to(a.order_pos) > 4.0:
		world.agents.move_to(a, a.order_pos)


func _best_zombie(a: Agent, rng: float) -> int:
	var z := world.zombies
	z.hash.query(a.pos, rng, tmp, 48)
	var prio := prio_sniper if a.type == "sniper" else prio_default
	var best := -1
	var best_s := 0.0
	for j in tmp:
		var tname := z.types[z.type_id[j]]
		var d := z.pos[j].distance_to(a.pos)
		var s := float(prio.get(tname, 3)) / (1.0 + d * 0.05)
		if j == a.target_z:
			s *= 1.25  # не дёргаемся между целями
		if s > best_s:
			best_s = s
			best = j
	return best


func _fire(a: Agent, key: String, tp: Vector2, zi: int, nest: MapPoi = null) -> void:
	var atk := Config.d("units.%s.%s" % [a.type, key])
	var rof := float(atk["rof"])
	if key == "attack":
		a.atk_cd = 1.0 / rof
	else:
		a.atk2_cd = 1.0 / rof
	var dmg := float(atk["damage"]) * a.dmg_mult
	if a.ability_cd.get("_aimed", 0.0) > 0.0 and zi >= 0 and specials.has(world.zombies.types[world.zombies.type_id[zi]]):
		dmg *= Config.f("units.abilities.aimed_shot.damage_mult_vs_special")
		a.ability_cd["_aimed"] = 0.0
	var dtype := String(atk["damage_type"])
	var aoe := float(atk.get("aoe", 0.0))
	if nest != null:
		world.map.damage_nest(nest, dmg * world.combat.k(dtype, "structure"))
	elif aoe > 0.0:
		world.combat.aoe(tp, aoe, dmg, dtype, "shell" if a.type == "tank" else "burst")
	elif zi >= 0:
		world.combat.hit_zombie(zi, dmg, dtype, a.pos)
	world.noise.emit(a.pos, world.mods.noise_attack(a))
	var h := Config.f("rules.sim_tuning.unit_fire_height_m")
	if a.kind == Agent.Kind.AIR:
		h = Config.f("rules.sim_tuning.heli_altitude_m")
	world.emit("shot_fired", [Vector3(a.pos.x, h, a.pos.y), Vector3(tp.x, 1.0, tp.y), a.type])


func _noise(a: Agent, dt: float) -> void:
	var n := Config.f("units.%s.noise_move" % a.type)
	if n <= 0.0 or not a.moving:
		return
	a.noise_cd -= dt
	if a.noise_cd <= 0.0:
		a.noise_cd = Config.f("rules.sim_tuning.continuous_noise_interval_s")
		world.noise.emit(a.pos, n)


func _heal(a: Agent, dt: float) -> void:
	a.heal_cd -= dt
	if a.heal_cd > 0.0:
		return
	a.heal_cd = 1.0
	var h := Config.d("units.medic.heal")
	world.agents.hash.query(a.pos, float(h["range"]), tmp)
	var best: Agent = null
	var worst := 1.0
	for k in tmp:
		var b: Agent = world.agents.hash_list[k]
		if b.kind == Agent.Kind.VEHICLE or b.kind == Agent.Kind.AIR or not b.alive:
			continue
		var frac := b.hp / b.max_hp
		if frac < worst:
			worst = frac
			best = b
		if b.infected and not b.infect_detected:
			b.infect_detected = true  # медик «осматривает» соседей (GDD §8.2)
			world.emit("infection_detected", [b.id, b.pos, "medic"])
	if best != null:
		best.hp = minf(best.max_hp, best.hp + float(h["hps"]) * world.mods.medic_heal_mult(a))
	world.abilities.auto_antidote(a)


func _crush(a: Agent, _dt: float) -> void:
	if not a.moving:
		return
	var c := Config.d("units.tank.crush")
	var mult := Config.f("units.abilities.ram.crush_damage_mult") if a.ram_t > 0.0 else 1.0
	var z := world.zombies
	z.hash.query(a.pos, a.radius + Config.f("rules.sim_tuning.vehicle_crush_radius_extra"), tmp)
	var affects: Array = c["affects"]
	for j in tmp:
		if affects.has(z.types[z.type_id[j]]):
			world.combat.hit_zombie(j, float(c["damage"]) * mult * _dt * 4.0, "crush", a.pos)


## Разведчик видит мирных сквозь туман (GDD §6.1).
func _reveal(a: Agent) -> void:
	if (world.tick + a.id) % 10 != 0:
		return
	var r := Config.f("units.scout.passive.survivor_reveal_radius")
	world.civilians.reveal_around(a.pos, r)


# ------------------------------------------------------------------ гарнизон и транспорт
func _in_tower(a: Agent) -> bool:
	var b := world.buildings.get_building(a.container)
	return b != null and b.alive and b.data().has("garrison")


func in_cover(a: Agent) -> bool:
	var b := world.buildings.building_near(a.pos, 2.5)
	return b != null and b.type == "sandbags" and b.complete()


func garrison(a: Agent, b: Building) -> bool:
	var cap := int(b.data().get("garrison", 0))
	if not b.complete() or b.garrison.size() >= cap or a.kind != Agent.Kind.INFANTRY:
		a.order = Agent.Order.NONE
		return false
	b.garrison.append(a.id)
	a.hidden = true
	a.container = b.id
	a.pos = b.pos
	a.stop()
	a.order = Agent.Order.NONE
	return true


func eject_garrison(b: Building) -> void:
	for id in b.garrison:
		var a := world.agents.get_agent(id)
		if a != null:
			a.hidden = false
			a.container = -1
			a.pos = world.grid.nearest_walkable(b.door)
	b.garrison.clear()


func transport_cap(v: Agent, civ: bool) -> int:
	return int(Config.opt("units.%s.transport.%s" % [v.type, "civilians" if civ else "infantry"], 0))


func board(a: Agent, v: Agent) -> bool:
	var civ := a.kind == Agent.Kind.CIVILIAN
	var n := 0
	for pid in v.passengers:
		var p := world.agents.get_agent(pid)
		if p != null and (p.kind == Agent.Kind.CIVILIAN) == civ:
			n += 1
	if n >= transport_cap(v, civ) or (not civ and a.kind != Agent.Kind.INFANTRY):
		a.order = Agent.Order.NONE
		return false
	v.passengers.append(a.id)
	a.hidden = true
	a.container = v.id
	a.stop()
	a.order = Agent.Order.NONE
	return true


func unload(v: Agent) -> void:
	eject_passengers(v, false)


func eject_passengers(v: Agent, damaged: bool) -> void:
	for pid in v.passengers:
		var a := world.agents.get_agent(pid)
		if a == null:
			continue
		a.hidden = false
		a.container = -1
		a.pos = world.grid.nearest_walkable(v.pos + Vector2(world.rng.randf_range(-3, 3), world.rng.randf_range(-3, 3)))
		if damaged:
			a.hp *= Config.f("rules.sim_tuning.ejected_crew_hp_frac")
		if a.kind == Agent.Kind.CIVILIAN:
			world.civilians.after_unload(a)
	v.passengers.clear()


func passenger_count(v: Agent) -> int:
	return v.passengers.size()
