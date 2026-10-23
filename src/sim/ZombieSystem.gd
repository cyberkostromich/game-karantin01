class_name ZombieSystem
extends RefCounted
## Зомби — не узлы, а строки в Packed-массивах (tech spec §3.1, ADR-3). FSM — в ZombieBrain.

enum S { IDLE, INVESTIGATE, CHASE, ATTACK, HORDE, FEEDING }
const NO_TARGET := -1

var world: World
var types: PackedStringArray = []        # индекс → id из zombies.json
var t_hp := PackedFloat32Array()
var t_speed := PackedFloat32Array()
var t_sight := PackedFloat32Array()
var t_hearing := PackedFloat32Array()
var t_armor: PackedStringArray = []
var t_attack: Array[Dictionary] = []
var t_infect := PackedFloat32Array()
var t_radius := PackedFloat32Array()

var count: int = 0                         # верхняя граница использованных слотов
var alive_n: int = 0
var pos := PackedVector2Array()
var prev := PackedVector2Array()           # позиция на прошлом тике — для интерполяции во view
var vel := PackedVector2Array()
var goal := PackedVector2Array()           # точка блуждания / шума
var home := PackedVector2Array()
var hp := PackedFloat32Array()
var type_id := PackedByteArray()
var state := PackedByteArray()
var target := PackedInt32Array()           # >=0 агент; <=-2 постройка (-(id+2)); -1 нет
var timer := PackedFloat32Array()
var atk_cd := PackedFloat32Array()
var lose_t := PackedFloat32Array()
var blocked_t := PackedFloat32Array()
var buff_t := PackedFloat32Array()         # бафф крикуна
var flags := PackedByteArray()             # бит 0 — член орды, бит 1 — спит (LOD), бит 2 — ослеплён дымом
var alive := PackedByteArray()
var free_list := PackedInt32Array()
var hash := SpatialHash.new()
var kills_total: int = 0

const F_HORDE := 1
const F_DORMANT := 2
const F_BLIND := 4


func setup(w: World) -> void:
	world = w
	types.clear()
	for k in Config.keys_of("zombies"):
		if k == "ai" or Config.opt("zombies.%s.static" % k, false):
			continue
		types.append(k)
		var base := "zombies.%s." % k
		t_hp.append(Config.f(base + "hp"))
		t_speed.append(Config.f(base + "speed"))
		t_sight.append(Config.f(base + "sight"))
		t_hearing.append(Config.f(base + "hearing_mult"))
		t_armor.append(String(Config.g(base + "armor")))
		var atk: Variant = Config.g(base + "attack")
		t_attack.append(atk if atk is Dictionary else {})
		t_infect.append(Config.f(base + "infect_chance"))
		t_radius.append(float(Config.opt("rules.sim_tuning.zombie_radius_by_type." + k, Config.f("rules.sim_tuning.zombie_radius"))))
	hash.setup(w.grid.origin, w.grid.size_m(), Config.f("rules.sim_tuning.zombie_hash_cell_m"))


func type_index(id: String) -> int:
	return types.find(id)


## Packed-массивы — значения (copy-on-write), поэтому каждый расширяем явно, не через общий список.
func _grow(n: int) -> void:
	pos.resize(n)
	prev.resize(n)
	vel.resize(n)
	goal.resize(n)
	home.resize(n)
	hp.resize(n)
	timer.resize(n)
	atk_cd.resize(n)
	lose_t.resize(n)
	blocked_t.resize(n)
	buff_t.resize(n)
	type_id.resize(n)
	state.resize(n)
	flags.resize(n)
	alive.resize(n)
	target.resize(n)


func spawn(t: int, p: Vector2, st: int = S.IDLE, g: Vector2 = Vector2.ZERO) -> int:
	var i: int
	if not free_list.is_empty():
		i = free_list[free_list.size() - 1]
		free_list.resize(free_list.size() - 1)
	else:
		i = count
		count += 1
		if count > pos.size():
			_grow(maxi(64, pos.size() * 2))
	pos[i] = p
	prev[i] = p
	vel[i] = Vector2.ZERO
	goal[i] = g if st != S.IDLE else p
	home[i] = p
	hp[i] = t_hp[t] * world.zombie_hp_mult
	type_id[i] = t
	state[i] = st
	target[i] = NO_TARGET
	timer[i] = Config.f("zombies.ai.investigate_timeout_s") if st == S.INVESTIGATE else 0.0
	atk_cd[i] = 0.0
	lose_t[i] = 0.0
	blocked_t[i] = 0.0
	buff_t[i] = 0.0
	flags[i] = F_HORDE if st == S.HORDE else 0
	alive[i] = 1
	alive_n += 1
	return i


func kill(i: int, dir: float = 0.0) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	alive_n -= 1
	kills_total += 1
	free_list.append(i)
	world.emit("zombie_died", [pos[i], int(type_id[i]), dir])


## Урон зомби (после множителя брони). Возвращает true, если убит.
func damage(i: int, amount: float, dir: float = 0.0) -> bool:
	if alive[i] == 0:
		return false
	hp[i] -= amount
	flags[i] &= ~F_DORMANT
	if hp[i] <= 0.0:
		kill(i, dir)
		return true
	return false


func armor_of(i: int) -> String:
	return t_armor[type_id[i]]


func rebuild_hash() -> void:
	hash.rebuild(pos, alive, count)


## Шум: idle/спящие и блуждающие идут проверить источник (GDD §9). Охота и атака не сбиваются.
func on_noise(events: Array[Vector3]) -> void:
	var tmp := PackedInt32Array()
	var timeout := Config.f("zombies.ai.investigate_timeout_s")
	var max_hear := 0.0
	for h in t_hearing:
		max_hear = maxf(max_hear, h)
	for e in events:
		var p := Vector2(e.x, e.y)
		hash.query(p, e.z * max_hear, tmp)
		for i in tmp:
			var st := state[i]
			if st == S.CHASE or st == S.ATTACK:
				continue
			if pos[i].distance_to(p) > e.z * t_hearing[type_id[i]]:
				continue
			if st == S.HORDE and pos[i].distance_to(p) > e.z * 0.5:
				continue  # орда сворачивает только на близкий шум
			state[i] = S.INVESTIGATE
			goal[i] = p + Vector2(world.rng.randf_range(-4, 4), world.rng.randf_range(-4, 4))
			timer[i] = timeout
			flags[i] &= ~F_DORMANT


## Ближайшая точка цели и её «радиус» (для дистанции атаки). Невалидная цель → Vector3.INF.
func target_info(t: int, from: Vector2) -> Vector3:
	if t >= 0:
		var a: Agent = world.agents.get_agent(t)
		if a == null or not a.alive or not a.targetable():
			return Vector3.INF
		return Vector3(a.pos.x, a.pos.y, a.radius)
	if t <= -2:
		var b: Building = world.buildings.get_building(-(t + 2))
		if b == null or not b.alive:
			return Vector3.INF
		var c := from.clamp(b.rect_m.position, b.rect_m.end)
		return Vector3(c.x, c.y, 0.0)
	return Vector3.INF


func update(dt: float) -> void:
	var brain := world.zombie_brain
	var tick := world.tick
	for i in count:
		if alive[i] == 0:
			continue
		prev[i] = pos[i]
		var f := flags[i]
		if (f & F_DORMANT) != 0:
			if (i + tick) % 8 != 0:
				continue
			brain.think(i, dt * 8.0, tick)
			continue
		brain.think(i, dt, tick)


## Шаг с коллизией по сетке: скольжение по стенам; упёрся в нашу постройку — запоминаем её.
## Возвращает id постройки, в которую упёрлись, или -1.
func step(i: int, v: Vector2, dt: float) -> int:
	var g := world.grid
	var p := pos[i]
	var np := p + v * dt
	var ni := g.idx_of(np)
	if g.zombie_walkable_i(ni):
		pos[i] = np
		return -1
	var hit := g.occ[ni] if ni >= 0 else -1
	var nx := Vector2(np.x, p.y)
	if g.zombie_walkable(nx):
		pos[i] = nx
		return hit
	var nz := Vector2(p.x, np.y)
	if g.zombie_walkable(nz):
		pos[i] = nz
		return hit
	return hit


## Расталкивание соседей (каждый 2-й тик, только вблизи активности).
func separate(i: int) -> Vector2:
	var tmp := world.tmp_ids
	var r := t_radius[type_id[i]] * 2.2
	hash.query(pos[i], r, tmp, 6)
	var push := Vector2.ZERO
	var p := pos[i]
	for j in tmp:
		if j == i:
			continue
		var d := p - pos[j]
		var l := d.length()
		if l < 0.001:
			d = Vector2(world.rng.randf() - 0.5, world.rng.randf() - 0.5)
			l = 0.01
		push += d / l * (r - l) / r
	return push


func alive_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in count:
		if alive[i] != 0:
			out.append(i)
	return out
