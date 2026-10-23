class_name TopBar
extends PanelContainer
## Верхняя панель (docs/07_ui_hud.md §1): команда, часы и фаза, ресурсы с прогнозом, люди, мораль, скорость.

var game: Node
var players_box := HBoxContainer.new()
var clock_l: Label
var day_l: Label
var phase_l: Label
var phase_bar: ProgressBar
var phase_icon: TextureRect
var wave_l: Label
var res_labels: Dictionary = {}
var speed_l: Label
var _acc: float = 0.0


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 0
	offset_right = 0
	offset_top = 0
	add_theme_stylebox_override("panel", UiTheme.skin("panel_dark", 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 4)
	row.add_child(res)
	for spec: Array in [["food", "res_food"], ["power", "res_power"], ["wood", "res_wood"], ["iron", "res_iron"],
			["people", "res_people"], ["morale", "res_morale"], ["antidote", "abl_antidote"]]:
		res.add_child(_plate(spec[0], spec[1]))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_clock())
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)
	row.add_child(players_box)
	_players()
	players_box.visible = game.world.players.size() > 1   # в одиночной игре плашка игроков — лишняя
	speed_l = UiTheme.caps("", 13, UiTheme.DIM)
	speed_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(speed_l)
	var menu := UiTheme.button(tr("HUD_MENU_SHORT").to_upper(), func() -> void: game.hud.toggle_pause_menu(), tr("HUD_MENU"))
	menu.custom_minimum_size = Vector2(72, 40)
	row.add_child(menu)


## Плашка ресурса: утопленный слот, глиф, крупное число Oswald, под ним — прогноз мелким капсом.
func _plate(key: String, icon_id: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.skin("inset", 6))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := UiTheme.icon_rect(icon_id, 26)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var l := UiTheme.digits("—", 19)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	var sub := UiTheme.caps("", 10, UiTheme.DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	p.custom_minimum_size = Vector2(92, 0)
	res_labels[key] = l
	res_labels[key + "_sub"] = sub
	return p


## Часы штаба: день, фаза с полосой, обратный отсчёт и направление волны — главное в выживании (GDD §5).
func _clock() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	day_l = UiTheme.caps("", 14, UiTheme.TEXT)
	day_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(day_l)
	clock_l = UiTheme.digits("", 24)
	h.add_child(clock_l)
	phase_icon = UiTheme.icon_rect("st_day", 22)
	h.add_child(phase_icon)
	phase_l = UiTheme.caps("", 14, UiTheme.WARN)
	phase_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(phase_l)
	phase_bar = ProgressBar.new()
	phase_bar.custom_minimum_size = Vector2(260, 8)
	phase_bar.show_percentage = false
	phase_bar.max_value = 1.0
	v.add_child(phase_bar)
	wave_l = UiTheme.caps("", 11, UiTheme.ACCENT)
	wave_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wave_l)
	return v


func _players() -> void:
	for c in players_box.get_children():
		c.queue_free()
	for p: Dictionary in game.world.players:
		var h := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = Look.team_color(int(p["pid"]))
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		var names: PackedStringArray = []
		for d: String in p.get("doctrines", []):
			names.append(String(Config.g("doctrines.%s.name_ru" % d)))
		dot.tooltip_text = ", ".join(names)
		h.add_child(UiTheme.caps(String(p.get("name", "P%d" % int(p["pid"]))), 12, UiTheme.DIM))
		players_box.add_child(h)


func _process(delta: float) -> void:
	_acc -= delta
	if _acc > 0.0:
		return
	_acc = 0.25
	var w: World = game.world
	var e := w.economy
	var cap := int(e.cap())
	var need := e.daily_food_need()
	_put("food", "%d" % int(e.res["food"]), "%s\n%s: −%.0f" % [tr("RES_FOOD"), tr("HUD_FOOD_AT_DAWN"), need],
		UiTheme.DANGER if float(e.res["food"]) < need else UiTheme.TEXT, "−%.0f %s" % [need, tr("HUD_AT_DAWN_SHORT")])
	var bal := e.power_balance()
	_put("power", "%+d" % int(round(bal)), "%s\n%s %d · %s %d%s" % [tr("RES_POWER"), tr("HUD_POWER_PROD"), int(e.power_prod),
		tr("HUD_POWER_USE"), int(e.power_use), ("\n%s %.0f/%.0f" % [tr("HUD_BATTERY"), e.battery, e.battery_cap]) if e.battery_cap > 0 else ""],
		UiTheme.DANGER if bal < 0 else UiTheme.TEXT, "%d / %d" % [int(e.power_prod), int(e.power_use)])
	_put("wood", "%d" % int(e.res["wood"]), tr("RES_WOOD"), UiTheme.TEXT, "/ %d" % cap)
	_put("iron", "%d" % int(e.res["iron"]), tr("RES_IRON"), UiTheme.TEXT, "/ %d" % cap)
	var p := e.people()
	_put("people", "%d" % int(p["total"]),
		"%s\n%s · %s · %s / %s\n%s: %d" % [tr("RES_PEOPLE"), tr("HUD_ADULTS"), tr("HUD_CHILDREN"), tr("HUD_SOLDIERS"), tr("HUD_HOUSING"),
		tr("HUD_FREE_RECRUITS"), w.training.free_recruits()], UiTheme.DANGER if e.housing() < int(p["total"]) else UiTheme.TEXT,
		"%d·%d·%d / %d" % [p["adults"], p["children"], p["soldiers"], e.housing()])
	var mc := UiTheme.OK if e.morale >= 70 else (UiTheme.TEXT if e.morale >= 30 else (UiTheme.ACCENT if e.morale >= 15 else UiTheme.DANGER))
	_put("morale", "%d" % int(e.morale), _morale_tip(e), mc, tr("RES_MORALE"))
	_put("antidote", "%d" % e.antidote_charges, tr("HUD_ANTIDOTE"), UiTheme.TEXT)
	_plate_of(res_labels["antidote"]).visible = e.antidote_charges > 0
	var c := w.clock
	day_l.text = ("%s %d/%d" % [tr("HUD_DAY"), c.day, c.total_days]).to_upper()
	clock_l.text = "%d:%02d" % [int(c.left()) / 60, int(c.left()) % 60]
	phase_l.text = tr("PHASE_" + c.phase_name().to_upper()).to_upper()
	phase_l.add_theme_color_override("font_color", UiTheme.INFO if c.is_night() else UiTheme.WARN)
	phase_bar.value = c.frac()
	phase_icon.texture = Look.icon("st_night" if c.is_dark() else "st_day")
	phase_bar.add_theme_stylebox_override("fill", UiTheme.fill(UiTheme.INFO if c.is_night() else UiTheme.WARN))
	wave_l.text = _wave_text(w)
	speed_l.text = (tr("HUD_PAUSED").to_upper() if game.paused else ("×%d" % int(game.speed) if game.speed != 1.0 else "")) \
		if w.players.size() == 1 else ""


func _put(key: String, text: String, tip: String, col: Color, sub: String = "") -> void:
	var l: Label = res_labels[key]
	l.text = text
	l.add_theme_color_override("font_color", col)
	(res_labels[key + "_sub"] as Label).text = sub
	_plate_of(l).tooltip_text = tip


func _plate_of(l: Label) -> Control:
	return l.get_parent().get_parent().get_parent()


func _morale_tip(e: Economy) -> String:
	var lines: PackedStringArray = [tr("RES_MORALE")]
	for k: String in e.morale_mods:
		lines.append("%+d  %s" % [int(e.morale_mods[k]), tr("MORALE_" + k.to_upper())])
	for k: String in e.event_morale:
		lines.append("%+d  %s" % [int(round(float(e.event_morale[k]))), tr("MORALE_EV_" + k.get_slice("_", 0).to_upper())])
	return "\n".join(lines)


func _wave_text(w: World) -> String:
	var wd := w.waves
	if wd.directions.is_empty() or w.clock.phase < 2 and not w.pois.wave_info_known():
		return ""
	var dirs: PackedStringArray = []
	for d in wd.directions:
		dirs.append(tr("DIR_" + d))
	var s := "%s %s" % [tr("HUD_WAVE_FROM"), ", ".join(dirs)]
	if w.pois.wave_info_known():
		var parts: PackedStringArray = []
		for t: String in wd.composition:
			parts.append("%s %d" % [String(Config.g("zombies.%s.name_ru" % t)), int(wd.composition[t])])
		s += " · " + ", ".join(parts)
	return s
