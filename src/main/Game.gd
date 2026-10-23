class_name Game
extends Node3D
## Матч: держит World (на хосте/соло — тикает его, на клиенте — получает снапшоты), виды, HUD и ввод.
## Фиксированный тик 20 Гц с аккумулятором; виды интерполируют между тиками (alpha).

signal exited

var opts: Dictionary = {}
var world := World.new()
var pid: int = 1
var is_client: bool = false
var speed: float = 1.0
var paused: bool = false
var menu_paused: bool = false
var acc: float = 0.0
var sim_ms: float = 0.0
var ready_to_play: bool = false

var cam := RtsCamera.new()
var city := CityLoader.new()
var nodes_view := ResourceNodesView.new()
var zombies_view := ZombieRenderer.new()
var agents_view := AgentViews.new()
var buildings_view := BuildingViews.new()
var poi_view := PoiViews.new()
var fog_view := FogRenderer.new()
var fx := Fx.new()
var daynight := DayNight.new()
var build := BuildController.new()
var select_ctl := SelectionController.new()
var selection := Selection.new()
var hud := Hud.new()
var markers: Array[Dictionary] = []


func start(o: Dictionary) -> void:
	opts = o
	pid = int(o.get("pid", 1))
	is_client = String(o.get("mode", "solo")) == "client"
	Keys.setup()
	if is_client:
		world.setup({"players": o["players"], "seed": int(o.get("seed", 1)), "empty": true, "difficulty": o.get("difficulty", "normal")})
		world.silent = true
	else:
		world.setup(o)
	if String(o.get("mode", "solo")) == "host":
		Net.attach_host(self)
	elif is_client:
		Net.attach_client(self)
	_build_scene()


func _build_scene() -> void:
	add_child(daynight)
	daynight.setup(world, Settings.shadows)
	add_child(cam)
	cam.bounds = world.map.bounds.grow(-40.0)
	cam.focus(world.map.hq_pos + Vector2(0, 12))
	cam.edge_scroll = Settings.edge_scroll
	add_child(city)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world.map.dir.path_join("report.json")))
	city.start(world.map.dir, world.map.bounds, float(rep.get("chunk_m", 128.0)))
	for v: Node in [nodes_view, zombies_view, agents_view, buildings_view, poi_view]:
		add_child(v)
		v.setup(world)
	add_child(fx)
	fx.setup(world, cam)
	cam.add_child(fog_view)
	fog_view.setup(world)
	add_child(build)
	build.game = self
	add_child(hud)
	select_ctl.game = self
	hud.setup(self)
	hud.root.add_child(select_ctl)
	hud.root.move_child(select_ctl, 0)
	selection.changed.connect(func() -> void: agents_view.set_selection(selection.all_agents()))
	Events.game_over.connect(func(_w: bool, _s: Dictionary) -> void: paused = true)
	agents_view.on_tick()


func send(cmd: Dictionary) -> void:
	cmd["pid"] = pid
	if is_client:
		Net.send_command(cmd)
	else:
		world.commands.push(cmd)


func _process(delta: float) -> void:
	if not city.is_done():
		city.poll()
		hud.set_loading(1.0 - float(city.pending.size()) / maxf(1.0, city.total), city.is_done())
		if not city.is_done():
			return
		ready_to_play = true
	if not is_client:
		_tick(delta)
	var alpha := clampf(acc / world.dt, 0.0, 1.0) if not is_client else Net.interp_alpha()
	selection.prune(world)
	cam.wasd_enabled = selection.units.is_empty() and not build.active()
	daynight.render(delta)
	zombies_view.render(alpha, delta, cam.position)
	agents_view.render(alpha, delta)
	buildings_view.render(delta)
	poi_view.render(delta)
	fog_view.render()
	fx.render(delta)
	_markers(delta)
	RenderingServer.global_shader_parameter_set("qm_time", world.time)


func _tick(delta: float) -> void:
	var running := not (paused or menu_paused) or (world.players.size() > 1)
	if not running:
		return
	acc += delta * speed
	var steps := 0
	var t0 := Time.get_ticks_usec()
	while acc >= world.dt and steps < 6:
		agents_view.on_tick()
		world.step()
		Net.after_tick()
		acc -= world.dt
		steps += 1
	if steps >= 6:
		acc = 0.0  # не догоняем — лучше замедлиться, чем «спираль смерти»
	if steps > 0:
		sim_ms = lerpf(sim_ms, float(Time.get_ticks_usec() - t0) / 1000.0 / steps, 0.1)


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k := ev as InputEventKey
	if hud.command_card.build_hotkey(k.physical_keycode):
		get_viewport().set_input_as_handled()
		return
	if k.is_action("menu"):
		if build.active():
			build.cancel()
		elif hud.command_card.build_mode:
			hud.command_card.toggle_build()
		elif hud.tech.visible:
			hud.tech.visible = false
		elif select_ctl.mode != SelectionController.Mode.NORMAL:
			select_ctl.set_mode(SelectionController.Mode.NORMAL)
		else:
			hud.toggle_pause_menu()
	elif k.is_action("build_menu"):
		hud.command_card.toggle_build()
	elif k.is_action("tech_tree") and selection.units.is_empty():
		hud.toggle_tech()
	elif k.is_action("cam_home"):
		cam.focus(world.map.hq_pos)
	elif k.is_action("cam_event") and hud.alerts.last_pos != Vector2.INF:
		cam.focus(hud.alerts.last_pos)
	elif k.is_action("idle_civs"):
		select_idle_civilians()
	elif k.is_action("speed_up") and world.players.size() == 1:
		speed = minf(speed * 2.0, 4.0)
	elif k.is_action("speed_down") and world.players.size() == 1:
		speed = maxf(speed * 0.5, 1.0)
	elif k.is_action("pause") and world.players.size() == 1:
		paused = not paused
	elif k.is_action("toggle_fog") and OS.is_debug_build():
		world.fog.reveal_all()
	elif k.physical_keycode == KEY_S and k.ctrl_pressed:
		for b in world.buildings.all_of("siren"):
			send({"t": "siren", "building_id": b.id})
			break
	else:
		return
	get_viewport().set_input_as_handled()


func begin_build(t: String) -> void:
	hud.command_card.build_mode = false
	build.begin(t)


func select_idle_civilians() -> void:
	var ids: Array[int] = []
	for a in world.agents.list:
		if a.alive and a.is_free_adult() and a.rescued:
			ids.append(a.id)
	selection.set_agents([], ids)
	if not ids.is_empty():
		cam.focus(world.agents.get_agent(ids[0]).pos)


## Отклик на приказ: кольцо на земле.
func marker(p: Vector2, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	tm.rings = 20
	tm.ring_segments = 3
	mi.mesh = tm
	mi.material_override = Look.unlit(c)
	mi.position = Vector3(p.x, 0.15, p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	markers.append({"n": mi, "t": 0.0})
	Sfx.play("ui_order")


func _markers(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for m in markers:
		m["t"] = float(m["t"]) + delta
		var n: MeshInstance3D = m["n"]
		var k := float(m["t"]) / 0.5
		if k >= 1.0:
			n.queue_free()
			continue
		var s := 1.5 - k
		n.scale = Vector3(s, 0.05, s)
		keep.append(m)
	markers = keep


func set_menu_pause(v: bool) -> void:
	menu_paused = v


func exit_to_menu() -> void:
	Net.leave()
	exited.emit()
