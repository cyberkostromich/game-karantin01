class_name TopBar
extends PanelContainer
## Верхняя панель (docs/07_ui_hud.md §1): команда, часы и фаза, ресурсы с прогнозом, люди, мораль, скорость.

var game: Node
var players_box := HBoxContainer.new()
var clock_l: Label
var wave_l: Label
var res_labels: Dictionary = {}
var speed_l: Label
var _acc: float = 0.0


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 8
	offset_right = -8
	offset_top = 6
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	row.add_child(players_box)
	_players()
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 14)
	row.add_child(res)
	for spec: Array in [["food", "res_food"], ["power", "res_power"], ["wood", "res_wood"], ["iron", "res_iron"],
			["people", "res_people"], ["morale", "res_morale"], ["antidote", "abl_antidote"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(UiTheme.icon_rect(spec[1], 22))
		var l := UiTheme.label("—", 15, UiTheme.TEXT, true)
		h.add_child(l)
		res.add_child(h)
		res_labels[spec[0]] = l
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 0)
	clock_l = UiTheme.label("", 16, UiTheme.TEXT, true)
	clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_l = UiTheme.label("", 12, UiTheme.ACCENT, true)
	wave_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cb.add_child(clock_l)
	cb.add_child(wave_l)
	row.add_child(cb)
	speed_l = UiTheme.label("", 13, UiTheme.DIM)
	row.add_child(speed_l)
	row.add_child(UiTheme.button("☰", func() -> void: game.hud.toggle_pause_menu(), tr("HUD_MENU")))


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
		h.add_child(UiTheme.label("%s · %s" % [String(p.get("name", "P%d" % int(p["pid"]))), ", ".join(names)], 13, UiTheme.DIM))
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
		UiTheme.DANGER if float(e.res["food"]) < need else UiTheme.TEXT)
	var bal := e.power_balance()
	_put("power", "%+d" % int(round(bal)), "%s\n%s %d · %s %d%s" % [tr("RES_POWER"), tr("HUD_POWER_PROD"), int(e.power_prod),
		tr("HUD_POWER_USE"), int(e.power_use), ("\n%s %.0f/%.0f" % [tr("HUD_BATTERY"), e.battery, e.battery_cap]) if e.battery_cap > 0 else ""],
		UiTheme.DANGER if bal < 0 else UiTheme.TEXT)
	_put("wood", "%d/%d" % [int(e.res["wood"]), cap], tr("RES_WOOD"), UiTheme.TEXT)
	_put("iron", "%d/%d" % [int(e.res["iron"]), cap], tr("RES_IRON"), UiTheme.TEXT)
	var p := e.people()
	_put("people", "%d·%d·%d / %d" % [p["adults"], p["children"], p["soldiers"], e.housing()],
		"%s\n%s · %s · %s / %s\n%s: %d" % [tr("RES_PEOPLE"), tr("HUD_ADULTS"), tr("HUD_CHILDREN"), tr("HUD_SOLDIERS"), tr("HUD_HOUSING"),
		tr("HUD_FREE_RECRUITS"), w.training.free_recruits()], UiTheme.DANGER if e.housing() < int(p["total"]) else UiTheme.TEXT)
	var mc := UiTheme.OK if e.morale >= 70 else (UiTheme.TEXT if e.morale >= 30 else (UiTheme.ACCENT if e.morale >= 15 else UiTheme.DANGER))
	_put("morale", "%d" % int(e.morale), _morale_tip(e), mc)
	_put("antidote", "%d" % e.antidote_charges, tr("HUD_ANTIDOTE"), UiTheme.TEXT)
	(res_labels["antidote"] as Label).get_parent().visible = e.antidote_charges > 0
	var c := w.clock
	var icon := "☾" if c.is_night() else "☀"
	clock_l.text = "%s %d/%d  %s %s  %d:%02d" % [tr("HUD_DAY"), c.day, c.total_days, icon, tr("PHASE_" + c.phase_name().to_upper()),
		int(c.left()) / 60, int(c.left()) % 60]
	wave_l.text = _wave_text(w)
	speed_l.text = ("⏸" if game.paused else "×%d" % int(game.speed)) if w.players.size() == 1 else ""


func _put(key: String, text: String, tip: String, col: Color) -> void:
	var l: Label = res_labels[key]
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.get_parent().tooltip_text = tip


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
