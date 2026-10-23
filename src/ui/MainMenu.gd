class_name MainMenu
extends CanvasLayer
## Главное меню (M6-1): одиночная игра (выбор двух доктрин и сложности), кооп (лобби), настройки, выход.

signal start_requested(opts: Dictionary)

var root := Control.new()
var pages: Dictionary = {}
var picked: Array[String] = ["infantry", "civil_defense"]
var difficulty: String = "normal"
var doc_buttons: Dictionary = {}
var lobby: Lobby


func _ready() -> void:
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# фон — штабная карта Лужников с пометками (tools/asset_gen/ui_skin.py: menu_bg)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/menu_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var t1 := UiTheme.digits(tr("TITLE_1").to_upper(), 96, UiTheme.TEXT)
	t1.position = Vector2(76, 48)
	root.add_child(t1)
	var t2 := UiTheme.digits(tr("TITLE_2").to_upper(), 96, UiTheme.ACCENT)
	t2.position = Vector2(76, 150)
	root.add_child(t2)
	var sub := UiTheme.tape(tr("TITLE_SUB"), 14)
	sub.position = Vector2(80, 280)
	root.add_child(sub)
	var hz := UiTheme.hazard_strip(8)
	hz.position = Vector2(80, 268)
	hz.size = Vector2(120, 8)
	root.add_child(hz)
	_page_main()
	_page_solo()
	lobby = Lobby.new()
	lobby.start_requested.connect(func(o: Dictionary) -> void: start_requested.emit(o))
	lobby.back_requested.connect(func() -> void: show_page("main"))
	root.add_child(lobby)
	pages["lobby"] = lobby
	show_page("main")


func show_page(id: String) -> void:
	for k: String in pages:
		(pages[k] as Control).visible = k == id


func _box(id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(80, 340)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)
	pages[id] = v
	return v


func _big(text: String, cb: Callable) -> Button:
	var b := UiTheme.button(text.to_upper(), cb)
	b.custom_minimum_size = Vector2(380, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	for st: String in ["normal", "hover", "pressed"]:
		var sb := UiTheme.skin({"normal": "btn", "hover": "btn_hover", "pressed": "btn_pressed"}[st]).duplicate() as StyleBoxTexture
		sb.content_margin_left = 22
		b.add_theme_stylebox_override(st, sb)
	return b


func _page_main() -> void:
	var v := _box("main")
	v.add_child(_big(tr("MENU_SOLO"), func() -> void: show_page("solo")))
	v.add_child(_big(tr("MENU_HOST"), func() -> void:
		lobby.open(true)
		show_page("lobby")))
	v.add_child(_big(tr("MENU_JOIN"), func() -> void:
		lobby.open(false)
		show_page("lobby")))
	var settings := SettingsPanel.new()
	settings.build()
	settings.visible = false
	v.add_child(_big(tr("MENU_SETTINGS"), func() -> void: settings.visible = not settings.visible))
	v.add_child(settings)
	v.add_child(_big(tr("MENU_QUIT"), func() -> void: get_tree().quit()))
	var ver := UiTheme.mono("v%s · Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]], 12, UiTheme.DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(80, -58)
	root.add_child(ver)
	var credits := UiTheme.label(tr("MENU_CREDITS"), 12, UiTheme.DIM)   # ODbL требует указания OSM
	credits.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credits.position = Vector2(80, -38)
	root.add_child(credits)


func _page_solo() -> void:
	var v := _box("solo")
	v.add_child(UiTheme.tape(tr("SOLO_PICK_DOCTRINES"), 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for d in Config.keys_of("doctrines"):
		row.add_child(_doctrine_card(d))
	var diff := HBoxContainer.new()
	diff.add_theme_constant_override("separation", 8)
	diff.add_child(UiTheme.caps(tr("SOLO_DIFFICULTY"), 15, UiTheme.TEXT))
	for dk: String in ["normal", "hard"]:
		var b := UiTheme.button(tr("DIFF_" + dk.to_upper()), func() -> void:
			difficulty = dk
			_refresh())
		b.toggle_mode = true
		b.name = "diff_" + dk
		diff.add_child(b)
	v.add_child(diff)
	pages["solo_diff"] = diff
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_big(tr("SOLO_START"), _start_solo))
	h.add_child(_big(tr("MENU_BACK"), func() -> void: show_page("main")))
	v.add_child(h)
	pages.erase("solo_diff")
	_refresh()


func _doctrine_card(d: String) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(290, 250)
	b.add_theme_stylebox_override("pressed", UiTheme.skin("btn_active", 12))
	b.add_theme_stylebox_override("normal", UiTheme.skin("btn", 12))
	b.add_theme_stylebox_override("hover", UiTheme.skin("btn_hover", 12))
	var dd := Config.d("doctrines." + d)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_top = 12
	v.offset_right = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiTheme.icon_rect("doc_" + d, 40))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.add_child(UiTheme.caps(String(dd["name_ru"]), 19, UiTheme.TEXT))
	nv.add_child(UiTheme.label(String(dd.get("tagline_ru", "")), 13, UiTheme.DIM))
	head.add_child(nv)
	v.add_child(head)
	for line: String in dd.get("passive_ru", []):
		var l := UiTheme.label("— " + line, 14, UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(260, 0)
		v.add_child(l)
	v.add_child(UiTheme.caps(String(dd["ability"]["name_ru"]), 13, UiTheme.ACCENT))
	var ab := UiTheme.label(String(dd.get("ability_ru", dd["ability"]["effect"])), 13, UiTheme.DIM)
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ab.custom_minimum_size = Vector2(260, 0)
	v.add_child(ab)
	for c in v.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func() -> void:
		if picked.has(d):
			picked.erase(d)
		else:
			picked.append(d)
			while picked.size() > Config.i("rules.players.doctrines_per_player.1"):
				picked.pop_front()
		_refresh())
	doc_buttons[d] = b
	return b


func _refresh() -> void:
	for d: String in doc_buttons:
		(doc_buttons[d] as Button).button_pressed = picked.has(d)
	var solo := pages["solo"] as Control
	for dk: String in ["normal", "hard"]:
		var b := solo.find_child("diff_" + dk, true, false) as Button
		if b != null:
			b.button_pressed = difficulty == dk


func _start_solo() -> void:
	if picked.size() < Config.i("rules.players.doctrines_per_player.1"):
		return
	start_requested.emit({"mode": "solo", "pid": 1, "difficulty": difficulty, "seed": randi(),
		"players": [{"pid": 1, "name": Settings.player_name, "doctrines": picked.duplicate()}]})
