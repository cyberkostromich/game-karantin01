class_name World
extends RefCounted
## Корень симуляции: тик 20 Гц, порядок систем — tech spec §2.3. Не знает про узлы, ввод и UI.
## Наружу — только сигналы Events (через emit) и чтение состояния представлением.

var rng := RandomNumberGenerator.new()
var tick: int = 0
var time: float = 0.0
var dt: float = 0.05
var players: Array[Dictionary] = []     # {pid, name, doctrines, color}
var difficulty_mult: float = 1.0
var zombie_hp_mult: float = 1.0
var shared_control: bool = false
var fortress_captured: bool = false
var outbreaks: int = 0
var score: Dictionary = {}
var doctrine_cds: Dictionary = {}       # "pid:doctrine" → секунд до готовности
var night_breach: bool = false
var tmp_ids := PackedInt32Array()
var event_sink: Callable                # Net на хосте дублирует события клиентам
var silent: bool = false                # бот-прогон: не трогать Events

var grid := Grid.new()
var paths := Pathfinder.new()
var flow := FlowField.new()
var noise := NoiseSystem.new()
var light := LightMap.new()
var mods := Mods.new()
var clock := GameClock.new()
var map := MapSystem.new()
var zombies := ZombieSystem.new()
var zombie_brain := ZombieBrain.new()
var agents := AgentSystem.new()
var units := UnitSystem.new()
var abilities := Abilities.new()
var heli := HeliSystem.new()
var training := TrainingSystem.new()
var civilians := CivilianSystem.new()
var buildings := BuildSystem.new()
var economy := Economy.new()
var tech := TechSystem.new()
var waves := WaveDirector.new()
var pois := PoiSystem.new()
var combat := Combat.new()
var fog := FogOfWar.new()
var scenario := Scenario.new()
var commands := Commands.new()


## opts: players, difficulty ("normal"/"hard"), seed, city_dir, grid (готовая сетка для тестов), empty (без населения)
func setup(opts: Dictionary) -> void:
	rng.seed = int(opts.get("seed", 12345))
	dt = 1.0 / Config.f("rules.sim.tick_hz")
	for p: Dictionary in opts.get("players", [{"pid": 1, "name": "P1", "doctrines": ["infantry", "civil_defense"]}]):
		players.append(p)
	difficulty_mult = float(Config.opt("rules.difficulty.%s.wave_mult" % String(opts.get("difficulty", "normal")), 1.0))
	shared_control = players.size() == 1
	map.setup(self, String(opts.get("city_dir", Config.g("map.city_dir"))))
	if opts.has("grid"):
		grid = opts["grid"]
		map.bounds = Rect2(grid.origin, grid.size_m())
		map.hq_pos = opts.get("hq", grid.origin + grid.size_m() * 0.5)
		map.arena_center = map.hq_pos
		map.gate_outer = map.hq_pos
	elif not map.load_grid(grid):
		return
	_setup_systems()
	if not opts.has("grid"):
		map.load_content()
	flow.setup(grid, map.hq_pos, Config.f("rules.sim_tuning.flowfield_radius_m"), Config.f("rules.sim_tuning.flowfield_wall_cost_mult"))
	_start_state(bool(opts.get("empty", false)))
	flow.compute_now()


func _setup_systems() -> void:
	paths.setup(grid, Config.i("rules.sim_tuning.path_coarse_scale"), Config.i("rules.sim_tuning.path_smooth_lookahead"))
	light.setup(grid.origin, grid.size_m(), Config.f("rules.sim_tuning.light_cell_m"))
	for s: Variant in [mods, clock, zombies, agents, units, abilities, heli, training, civilians, buildings,
			economy, tech, waves, pois, combat, fog, scenario, commands]:
		s.setup(self)
	zombie_brain.setup(self)


func _start_state(empty: bool) -> void:
	var n := players.size()
	for r: String in Economy.RES:
		economy.res[r] = Config.f("rules.start.resources.%s.base" % r) + Config.f("rules.start.resources.%s.per_player" % r) * n
	economy.reset_stats()
	var hq_cell := grid.cell_of(map.hq_pos) - Vector2i(4, 4)
	buildings.place("hq", hq_cell, 0, 0, true)
	if empty:
		return
	var hq := buildings.hq
	for p in players:
		for t: String in Config.d("rules.start.units_per_player"):
			for _k in int(Config.g("rules.start.units_per_player." + t)):
				agents.spawn_unit(t, int(p["pid"]), hq.door + Vector2(rng.randf_range(-6, 6), rng.randf_range(2, 8)))
	var civ_n := int(Config.f("rules.start.civilians_in_base.base") + Config.f("rules.start.civilians_in_base.per_player") * n)
	for _k in civ_n:
		civilians.spawn(grid.nearest_walkable(hq.pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14))), Agent.Civ.IDLE, true)
	_spawn_map_civilians()
	waves.spawn_ambient()


## Мирные прячутся группами по 1–5 в POI-зданиях (civilians.json/spawn_groups); 15 — в монастыре.
func _spawn_map_civilians() -> void:
	var total := int(Config.f("rules.start.map_civilians.base") + Config.f("rules.start.map_civilians.per_player") * players.size())
	var g: Array = Config.a("civilians.spawn_groups.group_size")
	var spots: Array = map.spawns.filter(func(s: Dictionary) -> bool:
		return Vector2(s["x"], s["z"]).distance_to(map.hq_pos) > Config.f("rules.sim_tuning.civilian_min_dist_from_hq_m") and String(s["kind"]) != "fortress")
	var fort: Array = map.spawns.filter(func(s: Dictionary) -> bool: return String(s["kind"]) == "fortress")
	var fort_n := Config.i("rules.sim_tuning.fortress_civilians")
	for k in mini(fort_n, fort.size() * 3):
		var s: Dictionary = fort[k % fort.size()]
		_hide_civilian(Vector2(s["x"], s["z"]) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)), "fortress")
	var placed := 0
	while placed < total and not spots.is_empty():
		var s: Dictionary = spots[rng.randi() % spots.size()]
		spots.erase(s)
		var kind := String(s["kind"])
		var size := mini(rng.randi_range(int(g[0]), int(g[1])), total - placed)
		if kind == "rooftop":
			size = mini(size, Config.i("units.heli.transport.civilians"))
		for _k in size:
			var a := _hide_civilian(Vector2(s["x"], s["z"]) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), kind)
			if kind == "rooftop":
				a.civ = Agent.Civ.ROOFTOP
				a.hidden = true
		placed += size


func _hide_civilian(p: Vector2, kind: String) -> Agent:
	var a := civilians.spawn(p if kind == "rooftop" else grid.nearest_walkable(p, 10.0), Agent.Civ.UNAWARE, false)
	a.spawn_kind = kind
	return a


# ------------------------------------------------------------------ тик
func step() -> void:
	if scenario.over:
		return
	commands.apply_all()
	clock.advance(dt)
	agents.rebuild_hash()
	zombies.rebuild_hash()
	zombies.on_noise(noise.take())
	waves.update(dt)
	flow.poll()
	zombies.update(dt)
	agents.process_paths()
	agents.update_movement(dt)
	units.update(dt)
	abilities.update(dt)
	civilians.update(dt)
	buildings.update(dt)
	training.update(dt)
	tech.update(dt)
	pois.update(dt)
	economy.update(dt)
	combat.update_agents(dt)
	for k: String in doctrine_cds.keys():
		doctrine_cds[k] = maxf(0.0, float(doctrine_cds[k]) - dt)
	if tick % Config.i("rules.sim_tuning.fog_update_ticks") == 0:
		fog.update()
	scenario.update(dt)
	tick += 1
	time += dt


# ------------------------------------------------------------------ события фаз (из GameClock)
func on_dawn() -> void:
	if not night_breach:
		economy.morale_event("night_survived", Config.f("rules.morale.modifiers.night_survived_without_breach"))
	night_breach = false
	var report := economy.on_dawn()
	_update_lights()
	emit("dawn_report", [report])


func on_day_start() -> void:
	emit("day_started", [clock.day])
	scenario.on_day_start(clock.day)


func on_dusk() -> void:
	waves.on_dusk(clock.day)
	_update_lights()


func on_night() -> void:
	_update_lights()


func on_final_dawn() -> void:
	scenario.on_final_dawn()


func on_power_changed(b: Building) -> void:
	if b.type == "floodlight":
		_update_lights()


## Ночью работающие прожекторы дают круги света (GDD §9).
func _update_lights() -> void:
	var circles: Array[Vector3] = []
	if clock.is_dark() or clock.is_night():
		for b in buildings.all_of("floodlight"):
			if b.powered and b.enabled:
				circles.append(Vector3(b.pos.x, b.pos.y, Config.f("buildings.floodlight.light_radius")))
	light.rebuild(circles)


# ------------------------------------------------------------------ запросы
func in_base(p: Vector2) -> bool:
	return p.distance_to(map.arena_center) <= Config.f("map.safe_zone.radius_m")


func in_build_zone(p: Vector2) -> bool:
	if p.distance_to(map.hq_pos) <= Config.f("rules.base.build_radius_m"):
		return true
	if fortress_captured:
		var f := map.poi("novodevichy")
		return f != null and p.distance_to(f.anchor) <= Config.f("rules.base.fortress_build_radius_m")
	return false


func players_mult() -> float:
	return Config.f("rules.difficulty_scaling_by_players.%d" % clampi(players.size(), 1, 4))


func player_doctrines(pid: int) -> Array:
	for p in players:
		if int(p["pid"]) == pid:
			return p.get("doctrines", [])
	return []


func is_shared_control() -> bool:
	return shared_control


func doctrine_cd(pid: int, doctrine: String) -> float:
	return float(doctrine_cds.get("%d:%s" % [pid, doctrine], 0.0))


func set_doctrine_cd(pid: int, doctrine: String, v: float) -> void:
	doctrine_cds["%d:%s" % [pid, doctrine]] = v


func score_add(key: String, v: int) -> void:
	score[key] = int(score.get(key, 0)) + v


## sim → Events. Имя сигнала + аргументы; на хосте ещё и в сеть (event_sink).
func emit(signal_name: String, args: Array) -> void:
	if signal_name == "building_attacked" or signal_name == "civilian_turned":
		if clock.is_night():
			night_breach = night_breach or signal_name == "civilian_turned" or _breach_check(args)
	if signal_name == "unit_trained" and String(args[1]) == "tank":
		score_add("tanks_built", 1)
	if event_sink.is_valid():
		event_sink.call(signal_name, args)
	if silent:
		return
	var ml := Engine.get_main_loop()
	var ev: Node = (ml as SceneTree).root.get_node_or_null(^"Events") if ml is SceneTree else null
	if ev != null:
		ev.callv("emit_signal", [signal_name] + args)


func _breach_check(args: Array) -> bool:
	var b := buildings.get_building(int(args[0]))
	return b != null and not b.is_wall_like()
