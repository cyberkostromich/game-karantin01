class_name Minimap
extends PanelContainer
## Миникарта (docs/07 §1): подложка из OSM, туман, свои юниты цветом игрока, мирные — белые,
## «?» — найденные, зомби в поле зрения — красные, гнёзда, волна — стрелка с края, пинги, рамка камеры.
## ЛКМ — камера, ПКМ — приказ движения выделенным.

var game: Node
var canvas := Control.new()
var base: Texture2D
var fog_mat := ShaderMaterial.new()
var tex_rect := TextureRect.new()
var pings: Array[Dictionary] = []
var size_px := Vector2(260, 204)
var _acc: float = 0.0


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	add_theme_stylebox_override("panel", UiTheme.skin("inset", 6))
	var w: World = g.world
	base = load(w.map.dir.path_join("minimap.png"))
	var asp := w.map.bounds.size.y / w.map.bounds.size.x
	size_px = Vector2(204 / asp, 204) if asp > 1.0 else Vector2(240, 240 * asp)
	custom_minimum_size = size_px + Vector2(12, 12)
	tex_rect.texture = base
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.custom_minimum_size = size_px
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D fog_tex : filter_linear;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat v = texture(fog_tex, UV).r;\n\tCOLOR = vec4(c.rgb * mix(0.62, 1.0, smoothstep(0.0, 0.45, v)) * mix(0.75, 1.0, smoothstep(0.5, 0.95, v)), 1.0);\n}\n"
	fog_mat.shader = sh
	tex_rect.material = fog_mat
	add_child(tex_rect)
	canvas.custom_minimum_size = size_px
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_overlay)
	canvas.gui_input.connect(_input_on_map)
	tex_rect.add_child(canvas)
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	Events.ping_placed.connect(func(pid: int, _k: String, p: Vector2) -> void: pings.append({"p": p, "t": 4.0, "c": Look.team_color(pid)}))
	Events.outbreak_in_base.connect(func(p: Vector2) -> void: pings.append({"p": p, "t": 4.0, "c": UiTheme.DANGER}))
	Events.scream.connect(func(p: Vector2, _r: float) -> void:
		if game.world.fog.visible(p): pings.append({"p": p, "t": 1.5, "c": UiTheme.INFECT}))


func _process(delta: float) -> void:
	for p in pings:
		p["t"] = float(p["t"]) - delta
	pings = pings.filter(func(p: Dictionary) -> bool: return float(p["t"]) > 0.0)
	_acc -= delta
	if _acc <= 0.0:
		_acc = 0.2
		fog_mat.set_shader_parameter("fog_tex", game.fog_view.tex)
		canvas.queue_redraw()


func to_map(p: Vector2) -> Vector2:
	var b: Rect2 = game.world.map.bounds
	return (p - b.position) / b.size * size_px


func to_world(m: Vector2) -> Vector2:
	var b: Rect2 = game.world.map.bounds
	return b.position + m / size_px * b.size


func _draw_overlay() -> void:
	var w: World = game.world
	for b in w.buildings.list:
		canvas.draw_rect(Rect2(to_map(b.rect_m.position), (b.rect_m.size / w.map.bounds.size * size_px).max(Vector2(2, 2))), UiTheme.ACCENT)
	for a in w.agents.list:
		if not a.alive or a.hidden:
			continue
		var m := to_map(a.pos)
		if a.is_unit():
			canvas.draw_rect(Rect2(m - Vector2(1.5, 1.5), Vector2(3, 3)), Look.team_color(a.owner))
		elif a.rescued:
			canvas.draw_rect(Rect2(m - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 0.95, 0.95))
		elif a.revealed or w.fog.visible(a.pos):
			canvas.draw_string(UiTheme.font_n, m + Vector2(-3, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.WARN)
	var z := w.zombies
	for i in z.count:
		if z.alive[i] != 0 and w.fog.visible(z.pos[i]):
			canvas.draw_rect(Rect2(to_map(z.pos[i]), Vector2(1.5, 1.5)), Color(0.9, 0.25, 0.2))
	for n in w.map.nests:
		if n.alive and w.fog.explored(n.pos):
			var c := to_map(n.pos)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), UiTheme.DANGER)
	_grid()
	for p in pings:
		var r := 4.0 + (4.0 - float(p["t"])) * 3.0
		canvas.draw_arc(to_map(p["p"]), r, 0, TAU, 16, p["c"], 1.5)
	_camera_rect()


## Координатная сетка и стороны света — как на штабной карте (север вверху, GDD §11).
func _grid() -> void:
	var line := Color(0.93, 0.9, 0.84, 0.07)
	for k in range(1, 4):
		canvas.draw_line(Vector2(size_px.x * k / 4.0, 0), Vector2(size_px.x * k / 4.0, size_px.y), line)
		canvas.draw_line(Vector2(0, size_px.y * k / 4.0), Vector2(size_px.x, size_px.y * k / 4.0), line)
	var f := UiTheme.font_n
	var c := Color(0.93, 0.9, 0.84, 0.7)
	canvas.draw_string(f, Vector2(size_px.x * 0.5 - 4, 13), tr("COMPASS_N"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
	canvas.draw_string(f, Vector2(size_px.x * 0.5 - 4, size_px.y - 4), tr("COMPASS_S"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
	canvas.draw_string(f, Vector2(4, size_px.y * 0.5 + 4), tr("COMPASS_W"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
	canvas.draw_string(f, Vector2(size_px.x - 12, size_px.y * 0.5 + 4), tr("COMPASS_E"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)


func _camera_rect() -> void:
	var cam: RtsCamera = game.cam
	var vs := cam.get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	for sp: Vector2 in [Vector2(0, 0), Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		pts.append(to_map(cam.ground_at(sp)))
	pts.append(pts[0])
	canvas.draw_polyline(pts, Color(1, 1, 1, 0.85), 1.0)


func _input_on_map(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		var p := to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			game.cam.focus(p)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not game.selection.units.is_empty():
			game.send({"t": "move", "units": game.selection.units, "pos": p, "queue": false, "amove": false})
	elif ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		game.cam.focus(to_world((ev as InputEventMouseMotion).position))
