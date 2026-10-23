extends Node
## Точка входа: главное меню → матч → обратно в меню.
## Отладка (аргументы после "--"): --autostart, --shot=путь.png, --shot-at=сек, --cam=x,z, --zoom=0..1,
## --speed=N, --reveal, --select=тип — для скриншотов и смоук-прогонов из CI.

var menu: MainMenu
var game: Game
var args: Dictionary = {}
var _t: float = 0.0
var _shot_done := false


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


func _process(delta: float) -> void:
	if not args.has("shot") or _shot_done or game == null or not game.ready_to_play:
		return
	_t += delta
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
		_shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(args["shot"]))
		print("SHOT saved ", args["shot"])
		get_tree().quit()
