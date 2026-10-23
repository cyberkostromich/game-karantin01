extends Node
## Точка входа: главное меню → матч → обратно в меню.
## Отладка (аргументы после "--"): --autostart, --shot=путь.png, --shot-at=сек, --cam=x,z, --zoom=0..1,
## --speed=N, --reveal, --select=тип, --skip=сек, --nohud — для скриншотов и смоук-прогонов из CI.
## Без --autostart --shot снимает главное меню.
## Демо-запись: --bot (за игрока командует BotPlayer — теми же командами, что человек), --record=папка
## --record-for=сек_игры (кадр на каждый кадр движка; удобно с --fixed-fps 10), --follow — камера-режиссёр.

var menu: MainMenu
var game: Game
var args: Dictionary = {}
var _t: float = 0.0
var _shot_done := false
var bot: BotPlayer
var _frame: int = 0
var _rec_t0: float = -1.0
var _cam_target := Vector2.INF


func _ready() -> void:
	get_window().title = tr("GAME_TITLE")
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("autostart"):
		_start_game({"mode": "solo", "pid": 1, "seed": int(args.get("seed", "7")), "difficulty": "normal",
			"players": [{"pid": 1, "name": "P1", "doctrines": ["infantry", "civil_defense"]}]})
	else:
		_show_menu()


func _show_menu() -> void:
	if game != null:
		game.queue_free()
		game = null
	menu = MainMenu.new()
	menu.start_requested.connect(_start_game)
	add_child(menu)


func _start_game(opts: Dictionary) -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	game = Game.new()
	add_child(game)
	game.exited.connect(_show_menu)
	game.start(opts)
	if args.has("speed"):
		game.speed = float(args["speed"])
	if args.has("reveal"):
		game.world.fog.reveal_all()
	if args.has("bot"):
		bot = BotPlayer.new()
		bot.setup(game.world, 1)
		game.hud.tutorial.enabled = false
		game.hud.tutorial.visible = false
	if args.has("skip"):
		for _k in int(float(args["skip"]) / game.world.dt):
			if bot != null:
				bot.update(game.world.dt)
			game.world.step()


func _process(delta: float) -> void:
	if args.has("shot") and not _shot_done and menu != null:
		_t += delta
		if _t >= float(args.get("shot-at", "3")):
			_save_shot()
		return
	if game != null and game.ready_to_play:
		if bot != null:
			bot.update(delta * game.speed)
		if args.has("follow"):
			_direct(delta)
		if args.has("record"):
			_record()
	if not args.has("shot") or _shot_done or game == null or not game.ready_to_play:
		return
	_t += delta
	if args.has("nohud"):
		game.hud.visible = false
	if args.has("cam"):
		var c: PackedStringArray = String(args["cam"]).split(",")
		game.cam.focus(Vector2(float(c[0]), float(c[1])))
	if args.has("zoom"):
		game.cam.zoom_target = float(args["zoom"])
		game.cam.zoom = float(args["zoom"])
	if args.has("select") and _t > 0.5 and game.selection.is_empty():
		var ids: Array[int] = []
		for a in game.world.agents.list:
			if a.type == String(args["select"]):
				ids.append(a.id)
		game.selection.set_agents(ids, [])
	if _t >= float(args.get("shot-at", "3")):
		if args.has("dbg-inst"):
			_dbg_instances()
		_save_shot()


## Сколько геометрии на каком шейдере (поиск перерасхода параметров экземпляра в WebGL).
func _dbg_instances() -> void:
	var cnt := {}
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var m := (n as GeometryInstance3D).material_override as ShaderMaterial
		var key := m.shader.resource_path if m != null and m.shader != null else "other"
		cnt[key] = int(cnt.get(key, 0)) + 1
	print("DBG ", cnt)


## Камера-режиссёр для демо: днём — над базой, когда орда у стен — к центру схватки.
func _direct(delta: float) -> void:
	var w: World = game.world
	var hq := w.map.hq_pos
	var want := hq + Vector2(0, 40)
	var z := w.zombies
	var sum := Vector2.ZERO
	var n := 0
	for i in z.count:
		if z.alive[i] != 0 and z.pos[i].distance_to(hq) < 170.0:
			sum += z.pos[i]
			n += 1
	if n > 8:
		want = (sum / n).lerp(hq, 0.35)
	_cam_target = want if _cam_target == Vector2.INF else _cam_target.lerp(want, minf(1.0, delta * 0.6))
	game.cam.focus(_cam_target)
	if args.has("zoom"):
		game.cam.zoom_target = float(args["zoom"])


func _record() -> void:
	var w: World = game.world
	if _rec_t0 < 0.0:
		_rec_t0 = w.time
		DirAccess.make_dir_recursive_absolute(String(args["record"]))
	get_viewport().get_texture().get_image().save_jpg("%s/%05d.jpg" % [args["record"], _frame], 0.9)
	_frame += 1
	if w.time - _rec_t0 >= float(args.get("record-for", "60")):
		print("RECORDED ", _frame, " frames")
		get_tree().quit()


func _save_shot() -> void:
	_shot_done = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(String(args["shot"]))
	print("SHOT saved ", args["shot"])
	get_tree().quit()
