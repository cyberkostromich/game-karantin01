class_name Hud
extends CanvasLayer
## Сборка HUD (docs/07_ui_hud.md §1). Все тексты — через tr() с ключами assets/i18n/ru.csv.

var game: Node
var root := Control.new()
var console := PanelContainer.new()   # нижняя консоль: миникарта | выделение | приказы (как в AoE IV / SC2)
var top := TopBar.new()
var alerts := Alerts.new()
var minimap := Minimap.new()
var selection_panel := SelectionPanel.new()
var command_card := CommandCard.new()
var tech := TechTreeWindow.new()
var radio := RadioPanel.new()
var game_over := GameOverScreen.new()
var tutorial := Tutorial.new()
var pause_menu := PauseMenu.new()
var hint := Label.new()
var fps := Label.new()
var loading: PanelContainer
var loading_bar := ProgressBar.new()


func setup(g: Node) -> void:
	game = g
	layer = 10
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	console.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(console)
	for c: Control in [top, alerts, minimap, selection_panel, command_card, radio]:
		root.add_child(c)
		c.setup(g)
	_layout_bottom()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300, -270)
	hint.custom_minimum_size = Vector2(600, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiTheme.ACCENT)
	hint.add_theme_font_size_override("font_size", 15)
	root.add_child(hint)
	fps.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fps.add_theme_font_size_override("font_size", 11)
	fps.add_theme_color_override("font_color", UiTheme.DIM)
	fps.visible = OS.is_debug_build()   # счётчик — только для разработки
	root.add_child(fps)
	var rep := radio.report_node()
	rep.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rep.position = Vector2(-270, 110)
	root.add_child(rep)
	for c: Control in [tech, tutorial, game_over, pause_menu]:
		root.add_child(c)
		c.setup(g)
	_loading()
	root.get_viewport().size_changed.connect(_layout_bottom)


const CONSOLE_H := 228.0


func _layout_bottom() -> void:
	var vs := root.get_viewport_rect().size
	var y0 := vs.y - CONSOLE_H
	console.position = Vector2(0, y0)
	console.size = Vector2(vs.x, CONSOLE_H)
	minimap.position = Vector2(12, vs.y - minimap.custom_minimum_size.y - 12)
	command_card.position = Vector2(vs.x - command_card.custom_minimum_size.x - 12, y0 + 12)
	var sx := minimap.position.x + minimap.custom_minimum_size.x + 14
	selection_panel.position = Vector2(sx, y0 + 12)
	selection_panel.custom_minimum_size = Vector2(command_card.position.x - 14 - sx, CONSOLE_H - 24)
	selection_panel.size = selection_panel.custom_minimum_size
	fps.position = Vector2(vs.x - 260, y0 - 18)
	tech.position = (vs - tech.custom_minimum_size) * 0.5
	game_over.position = (vs - game_over.custom_minimum_size) * 0.5
	radio.position = Vector2(vs.x - 380, 66)


func _loading() -> void:
	loading = PanelContainer.new()
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_theme_stylebox_override("panel", UiTheme.box(Color("15171a"), 0))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	loading.add_child(v)
	var t := UiTheme.digits(tr("GAME_TITLE").to_upper(), 54)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UiTheme.caps(tr("LOADING_CITY"), 14, UiTheme.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	loading_bar.custom_minimum_size = Vector2(420, 12)
	loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	v.add_child(loading_bar)
	root.add_child(loading)


func set_loading(frac: float, done: bool) -> void:
	loading_bar.value = frac
	loading.visible = not done


func set_hint(t: String) -> void:
	hint.text = t


func toggle_tech(ws: int = -1) -> void:
	if tech.visible:
		tech.visible = false
	else:
		tech.open(ws)


func toggle_pause_menu() -> void:
	pause_menu.toggle()


func _process(_delta: float) -> void:
	fps.text = "%d FPS · %s %d · %.1f ms" % [Engine.get_frames_per_second(), tr("HUD_ZOMBIES"), game.world.zombies.alive_n, game.sim_ms]
