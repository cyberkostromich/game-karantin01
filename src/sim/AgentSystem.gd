class_name AgentSystem
extends RefCounted
## Хранилище агентов (военные + мирные), пространственный хеш и движение по путям.
## Боевая логика — UnitSystem, жизнь мирных — CivilianSystem.

var world: World
var list: Array[Agent] = []
var by_id: Dictionary = {}
var next_id: int = 1
var hash := SpatialHash.new()
var hash_list: Array[Agent] = []
var _hpos := PackedVector2Array()
var _halive := PackedByteArray()
var path_queue: Array[int] = []
var paths_per_tick: int = 8
var sep_r: float = 0.9
var tmp := PackedInt32Array()


func setup(w: World) -> void:
	world = w
	hash.setup(w.grid.origin, w.grid.size_m(), Config.f("rules.sim_tuning.agent_hash_cell_m"))
	paths_per_tick = Config.i("rules.sim_tuning.paths_per_tick")
	sep_r = Config.f("rules.sim_tuning.agent_separation_radius")


func get_agent(id: int) -> Agent:
	return by_id.get(id)


func add(a: Agent) -> Agent:
	a.id = next_id
	next_id += 1
	list.append(a)
	by_id[a.id] = a
	return a


func remove(a: Agent) -> void:
	a.alive = false
	by_id.erase(a.id)
	list.erase(a)


## Военный юнит по units.json с модификаторами доктрин/технологий/черт (World.mods).
func spawn_unit(type: String, owner: int, p: Vector2, trait_id: String = "") -> Agent:
	var u := Config.d("units." + type)
	var a := Agent.new()
	a.type = type
	a.owner = owner
	a.pos = world.grid.nearest_walkable(p) if u["category"] != "air" else p
	a.dest = a.pos
	match String(u["category"]):
		"infantry": a.kind = Agent.Kind.INFANTRY
		"vehicle": a.kind = Agent.Kind.VEHICLE
		"air": a.kind = Agent.Kind.AIR
	a.armor = u["armor"]
	a.trait_id = trait_id
	a.hp_mult = world.mods.unit_hp_mult(type, owner, trait_id)
	a.dmg_mult = world.mods.unit_damage_mult(type, owner, trait_id)
	a.max_hp = float(u["hp"]) * a.hp_mult
	a.hp = a.max_hp
	a.speed = float(u["speed"]) * world.mods.unit_speed_mult(type, owner, trait_id)
	a.vision = float(u["vision"])
	a.radius = Config.f("rules.sim_tuning.unit_radius.%s" % u["category"])
	if a.kind == Agent.Kind.AIR:
		a.fuel = world.mods.heli_flight_time(owner)
	add(a)
	return a


func spawn_civilian(p: Vector2, child: bool, st: int) -> Agent:
	var key := "civilians.child." if child else "civilians.adult."
	var a := Agent.new()
	a.kind = Agent.Kind.CIVILIAN
	a.type = "child" if child else "adult"
	a.is_child = child
	a.owner = -1
	a.pos = p
	a.dest = p
	a.armor = Config.g(key + "armor")
	a.max_hp = Config.f(key + "hp")
	a.hp = a.max_hp
	a.speed = Config.f(key + "speed")
	a.vision = Config.f(key + "vision")
	a.radius = Config.f("rules.sim_tuning.unit_radius.civilian")
	a.civ = st
	add(a)
	return a


func rebuild_hash() -> void:
	hash_list.clear()
	_hpos.resize(list.size())
	_halive.resize(list.size())
	var n := 0
	for a in list:
		if a.alive and not a.hidden:
			hash_list.append(a)
			_hpos[n] = a.pos
			_halive[n] = 1
			n += 1
	hash.rebuild(_hpos, _halive, n)


# ------------------------------------------------------------------ движение
func move_to(a: Agent, p: Vector2) -> void:
	a.dest = p
	a.moving = true
	a.stuck_t = 0.0
	if a.kind == Agent.Kind.AIR:
		a.path = PackedVector2Array([p])
		a.path_i = 0
		return
	a.path = PackedVector2Array()
	a.path_i = 0
	if not path_queue.has(a.id):
		path_queue.append(a.id)


func process_paths() -> void:
	var n := 0
	while n < paths_per_tick and not path_queue.is_empty():
		var a := get_agent(path_queue.pop_front())
		if a == null or not a.alive or not a.moving:
			continue
		a.path = world.paths.find_path(a.pos, a.dest)
		a.path_i = 0
		if a.path.is_empty():
			a.moving = false
		n += 1


func update_movement(dt: float) -> void:
	for a in list:
		if not a.alive or a.hidden:
			continue
		if a.moving and not a.path.is_empty():
			_follow(a, dt)
		else:
			a.vel = Vector2.ZERO
		if a.kind != Agent.Kind.AIR and a.kind != Agent.Kind.VEHICLE:
			_separate(a, dt)


func _follow(a: Agent, dt: float) -> void:
	var target := a.path[a.path_i]
	var d := target - a.pos
	var l := d.length()
	var spd := a.speed * a.speed_mult * world.mods.terrain_speed_mult(a)
	var step := spd * dt
	if l <= step:
		a.pos = target
		a.path_i += 1
		if a.path_i >= a.path.size():
			a.moving = false
			a.vel = Vector2.ZERO
		return
	var v := d / l * spd
	a.vel = v
	a.facing = atan2(v.x, v.y)
	if a.kind == Agent.Kind.AIR:
		a.pos += v * dt
		return
	var np := a.pos + v * dt
	var g := world.grid
	if g.walkable(np):
		a.pos = np
		a.stuck_t = maxf(0.0, a.stuck_t - dt)
		return
	if g.walkable(Vector2(np.x, a.pos.y)):
		a.pos.x = np.x
	elif g.walkable(Vector2(a.pos.x, np.y)):
		a.pos.y = np.y
	a.stuck_t += dt
	if a.stuck_t > 1.0:
		a.stuck_t = 0.0
		move_to(a, a.dest)


func _separate(a: Agent, dt: float) -> void:
	hash.query(a.pos, sep_r * 2.0, tmp, 6)
	var push := Vector2.ZERO
	for k in tmp:
		var b: Agent = hash_list[k]
		if b == a or b.kind == Agent.Kind.AIR:
			continue
		var d := a.pos - b.pos
		var l := d.length()
		var r := a.radius + b.radius
		if l < r and l > 0.0001:
			push += d / l * (r - l)
	if push != Vector2.ZERO:
		var np := a.pos + push * minf(1.0, dt * 8.0)
		if world.grid.walkable(np):
			a.pos = np


# ------------------------------------------------------------------ выборки
func units_of(owner: int) -> Array[Agent]:
	var out: Array[Agent] = []
	for a in list:
		if a.alive and a.is_unit() and (owner < 0 or a.owner == owner):
			out.append(a)
	return out


func civilians() -> Array[Agent]:
	var out: Array[Agent] = []
	for a in list:
		if a.alive and a.kind == Agent.Kind.CIVILIAN:
			out.append(a)
	return out


func nearest_free_adult(p: Vector2) -> Agent:
	var best: Agent = null
	var bd := INF
	for a in list:
		if a.is_free_adult() and a.rescued:
			var d := a.pos.distance_squared_to(p)
			if d < bd:
				bd = d
				best = a
	return best
