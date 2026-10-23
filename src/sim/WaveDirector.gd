class_name WaveDirector
extends RefCounted
## Поток орды (D-15, вместо ночных волн GDD §2.3): зомби непрерывно появляются далеко от Штаба стаями
## с разных сторон и сразу идут на базу; за день типа t приходит count_for(t, день) — с каждым днём больше.
## Плюс гнёзда в метро и фоновое население города.

var world: World
var day: int = 0
var composition: Dictionary = {}     # тип → сколько придёт за текущий день (для HUD при разведке радиовышкой)
var spawned_total: int = 0
var stream_on: bool = true
var _acc: Dictionary = {}            # тип → накопленная «доля» зомби (дробная часть переносится)
var _pending: Array[int] = []        # набранные типы следующей стаи
var _pack_n: int = 0
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


## Сколько зомби типа t придёт за день n потока (с множителями игроков и сложности).
func count_for(t: String, n: int) -> int:
	var c := float(base_count(t, n))
	if bool(Config.opt("waves.formulas.%s.scale" % t, true)):
		c *= world.players_mult() * world.difficulty_mult * Config.f("waves.stream.day_mult")
	return int(round(c))


# ------------------------------------------------------------------ поток
func _new_day(n: int) -> void:
	day = n
	composition = {}
	for t: String in Config.keys_of("waves.formulas"):
		var c := count_for(t, n)
		if t == "walker" and world.scenario.migration_night == n:
			c = int(round(c * (1.0 + Config.f("waves.events.day_7.extra_walkers_mult"))))
		if c > 0:
			composition[t] = c
		if not _acc.has(t):
			_acc[t] = 0.5   # редкие (Великан) — к середине своего дня, а не на последней секунде
	world.emit("horde_updated", [n, composition])


func update(dt: float) -> void:
	_nests(dt)
	if world.clock.day != day:
		_new_day(world.clock.day)
	if not stream_on:
		return
	var cycle := 0.0
	for d in world.clock.durations:
		cycle += d
	# ночью поток гуще; дневная и ночная доли нормированы, чтобы за сутки пришло ровно composition
	var nm := Config.f("waves.stream.night_mult")
	var night_s: float = world.clock.durations[3]
	var k := (nm if world.clock.is_night() else 1.0) / (cycle - night_s + night_s * nm)
	for t: String in composition:
		_acc[t] = float(_acc[t]) + float(composition[t]) * k * dt
		while float(_acc[t]) >= 1.0:
			_acc[t] = float(_acc[t]) - 1.0
			_pending.append(world.zombies.type_index(t))
	if _pack_n <= 0:
		_pack_n = world.rng.randi_range(Config.i("waves.stream.pack_min"), Config.i("waves.stream.pack_max"))
	if _pending.size() >= _pack_n:
		_spawn_pack(_pending)
		_pending = []
		_pack_n = 0


## Стая появляется в одной точке на кольце spawn_distance_m со случайной стороны — внутри окна flow-field,
## поэтому сразу идёт к Штабу по полю путей.
func _spawn_pack(types: Array[int]) -> void:
	var cfg := Config.d("waves.stream")
	var a := world.rng.randf() * TAU
	var r := float(cfg["spawn_distance_m"]) + world.rng.randf_range(0.0, float(cfg["spawn_depth_m"]))
	var c := world.grid.nearest_walkable(world.grid.clamp_pos(world.map.hq_pos + Vector2(cos(a), sin(a)) * r), 140.0, true)
	var spread := float(cfg["pack_spread_m"])
	for t in types:
		if t < 0:
			continue
		var p := world.grid.nearest_walkable(c + Vector2(world.rng.randf_range(-spread, spread), world.rng.randf_range(-spread, spread)), 20.0, true)
		world.zombies.spawn(t, p, ZombieSystem.S.HORDE)
		spawned_total += 1


# ------------------------------------------------------------------ гнёзда и фон
func _nests(dt: float) -> void:
	var cfg := Config.d("zombies.nest.spawn")
	var cap := int(float(cfg["ambient_cap_contrib"]) * world.players_mult())
	var walker := world.zombies.type_index(String(cfg["type"]))
	var night_horde := bool(Config.opt("waves.nests.night_nest_horde", false))
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
