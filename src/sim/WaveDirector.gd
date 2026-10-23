class_name WaveDirector
extends RefCounted
## Ночные волны по формулам waves.json (GDD §2.3, M2-7), гнёзда в метро, фоновое население города.

const DIR_VEC := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}

var world: World
var night: int = 0
var directions: PackedStringArray = []
var composition: Dictionary = {}
var to_spawn: Array[Dictionary] = []   # очередь {type, dir}
var batch_cd: float = 0.0
var launched: bool = false
var spawned_total: int = 0
var _exprs: Dictionary = {}


func setup(w: World) -> void:
	world = w
	for t: String in Config.keys_of("waves.formulas"):
		var f := String(Config.g("waves.formulas.%s.f" % t))
		var e := Expression.new()
		var src := _to_expr(f)
		if e.parse(src, ["n", "a", "b", "p"]) != OK:
			push_error("WaveDirector: формула %s не разобрана: %s" % [t, src])
			continue
		_exprs[t] = e


## "a + b * n^p" → "a + b * pow(n, p)"; пояснения в скобках после числа отбрасываем.
static func _to_expr(f: String) -> String:
	var note := RegEx.new()
	note.compile("\\s*\\([^)]*[А-Яа-яЁё][^)]*\\)")
	var s := note.sub(f, "", true)
	var re := RegEx.new()
	re.compile("(\\([^()]*\\)|[A-Za-z0-9_.]+)\\^([A-Za-z0-9_.]+)")
	while true:
		var m := re.search(s)
		if m == null:
			break
		s = s.substr(0, m.get_start()) + "pow(%s, %s)" % [m.get_string(1), m.get_string(2)] + s.substr(m.get_end())
	return s


## Сколько зомби типа t в ночь n (до множителей игроков и сложности).
func base_count(t: String, n: int) -> int:
	var key := "waves.formulas." + t
	if n < Config.i(key + ".from_night") or not _exprs.has(t):
		return 0
	var e: Expression = _exprs[t]
	var v: Variant = e.execute([float(n), float(Config.opt(key + ".a", 0.0)), float(Config.opt(key + ".b", 0.0)),
		float(Config.opt(key + ".p", 1.0))])
	return maxi(0, int(round(float(v))))


func count_for(t: String, n: int) -> int:
	var c := float(base_count(t, n))
	if bool(Config.opt("waves.formulas.%s.scale" % t, true)):
		c *= world.players_mult() * world.difficulty_mult
	return int(round(c))


func directions_for(n: int) -> int:
	var dpn := Config.d("waves.spawn.directions_per_night")
	var best := 1
	var best_k := 0
	for k: String in dpn:
		if int(k) <= n and int(k) >= best_k:
			best_k = int(k)
			best = int(dpn[k])
	return best


# ------------------------------------------------------------------ фазы
func on_dusk(n: int) -> void:
	night = n
	var all: Array = Config.a("waves.spawn.directions").duplicate()
	var k := directions_for(n)
	directions = PackedStringArray()
	if world.scenario.migration_night == n:
		directions.append("N")
		all.erase("N")
	while directions.size() < k and not all.is_empty():
		var d: String = all[world.rng.randi() % all.size()]
		all.erase(d)
		directions.append(d)
	composition = {}
	for t: String in Config.keys_of("waves.formulas"):
		var c := count_for(t, n)
		if t == "walker" and world.scenario.migration_night == n:
			c = int(round(c * (1.0 + Config.f("waves.events.day_7.extra_walkers_mult"))))
		if c > 0:
			composition[t] = c
	launched = false
	world.emit("wave_announced", [n, directions, composition])


func update(dt: float) -> void:
	_nests(dt)
	if not world.clock.is_night():
		return
	if not launched and world.clock.night_elapsed() >= world.clock.durations[3] * Config.f("rules.day_cycle.horde_launch_at_night_fraction"):
		_launch()
	if to_spawn.is_empty():
		return
	batch_cd -= dt
	if batch_cd > 0.0:
		return
	batch_cd = Config.f("waves.spawn.batch_interval_s")
	for _k in Config.i("waves.spawn.batch_size"):
		if to_spawn.is_empty():
			break
		var s: Dictionary = to_spawn.pop_front()
		_spawn_one(String(s["type"]), String(s["dir"]))


func _launch() -> void:
	launched = true
	to_spawn.clear()
	var di := 0
	# перемешиваем типы, чтобы особые шли внутри орды, а не отдельной колонной
	var pool: Array[String] = []
	for t: String in composition:
		for _k in int(composition[t]):
			pool.append(t)
	for i in range(pool.size() - 1, 0, -1):
		var j := world.rng.randi() % (i + 1)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for t in pool:
		to_spawn.append({"type": t, "dir": directions[di % directions.size()]})
		di += 1
	batch_cd = 0.0
	world.emit("wave_started", [night])


func spawn_point(dir: String) -> Vector2:
	var v: Vector2 = DIR_VEC[dir]
	var dist := Config.f("waves.spawn.spawn_distance_m")
	var spread := Config.f("waves.spawn.spread_m")
	var perp := Vector2(-v.y, v.x)
	var p: Vector2 = world.map.hq_pos + v * dist + perp * world.rng.randf_range(-spread, spread)
	return world.grid.nearest_walkable(world.grid.clamp_pos(p), 140.0, true)


func _spawn_one(t: String, dir: String) -> void:
	var ti := world.zombies.type_index(t)
	if ti < 0:
		return
	world.zombies.spawn(ti, spawn_point(dir), ZombieSystem.S.HORDE)
	spawned_total += 1


# ------------------------------------------------------------------ гнёзда и фон
func _nests(dt: float) -> void:
	var cfg := Config.d("zombies.nest.spawn")
	var cap := int(float(cfg["ambient_cap_contrib"]) * world.players_mult())
	var walker := world.zombies.type_index(String(cfg["type"]))
	var night_horde := bool(Config.opt("waves.spawn.night_nest_horde", false))
	for n in world.map.nests:
		if not n.alive:
			continue
		n.timer -= dt
		if n.timer > 0.0:
			continue
		n.timer = float(cfg["night_interval_s"]) if world.clock.is_night() else float(cfg["interval_s"])
		n.spawned = n.spawned.filter(func(i: int) -> bool: return world.zombies.alive[i] != 0)
		if n.spawned.size() >= cap:
			continue
		var st := ZombieSystem.S.HORDE if world.clock.is_night() and night_horde else ZombieSystem.S.IDLE
		var p := world.grid.nearest_walkable(n.pos + Vector2(world.rng.randf_range(-6, 6), world.rng.randf_range(-6, 6)), 30.0, true)
		n.spawned.append(world.zombies.spawn(walker, p, st))


## Фоновые зомби города на старте: дальше от базы, гуще у гнёзд (rules.start.map_ambient_zombies).
func spawn_ambient() -> void:
	var total := int(round(Config.f("rules.start.map_ambient_zombies.base") +
		Config.f("rules.start.map_ambient_zombies.per_player") * world.players.size()))
	var walker := world.zombies.type_index("walker")
	var min_d := Config.f("rules.sim_tuning.ambient_min_dist_from_hq_m")
	var b := world.map.bounds
	var placed := 0
	var tries := 0
	while placed < total and tries < total * 20:
		tries += 1
		var p: Vector2
		if not world.map.nests.is_empty() and world.rng.randf() < Config.f("rules.sim_tuning.ambient_near_nest_share"):
			var n: MapPoi = world.map.nests[world.rng.randi() % world.map.nests.size()]
			p = n.pos + Vector2(world.rng.randf_range(-80, 80), world.rng.randf_range(-80, 80))
		else:
			p = Vector2(world.rng.randf_range(b.position.x, b.end.x), world.rng.randf_range(b.position.y, b.end.y))
		if p.distance_to(world.map.hq_pos) < min_d or not world.grid.zombie_walkable(p):
			continue
		world.zombies.spawn(walker, p, ZombieSystem.S.IDLE)
		placed += 1
