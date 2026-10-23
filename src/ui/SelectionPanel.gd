class_name SelectionPanel
extends PanelContainer
## Карточка выделения (docs/07 §1): один — портрет, HP, статус, черта, владелец; несколько — сетка мини-карточек;
## постройка — прочность, стройка/очередь/исследование, работники, питание; объект карты — прогресс рейда.

var game: Node
var box := VBoxContainer.new()
var _acc: float = 0.0


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	custom_minimum_size = Vector2(420, 150)
	box.add_theme_constant_override("separation", 4)
	add_child(box)


func _process(delta: float) -> void:
	_acc -= delta
	if _acc > 0.0:
		return
	_acc = 0.2
	for c in box.get_children():
		c.queue_free()
	var s: Selection = game.selection
	var w: World = game.world
	visible = not s.is_empty()
	if not visible:
		return
	if s.building >= 0:
		var b := w.buildings.get_building(s.building)
		if b != null:
			_building(b)
	elif s.poi >= 0:
		_poi(w.map.pois[s.poi])
	else:
		var ids := s.all_agents()
		if ids.size() == 1:
			_agent(w.agents.get_agent(ids[0]))
		else:
			_group(ids)


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	return h


func _bar(frac: float, col: Color, w: float = 240.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(w, 10)
	p.show_percentage = false
	p.max_value = 1.0
	p.value = frac
	var sb := UiTheme.box(col, 3)
	p.add_theme_stylebox_override("fill", sb)
	return p


func _agent(a: Agent) -> void:
	if a == null:
		return
	var w: World = game.world
	var h := _row()
	var icon := ("civ_child" if a.is_child else "civ_adult") if a.kind == Agent.Kind.CIVILIAN else "unit_" + a.type
	h.add_child(UiTheme.icon_rect(icon, 64))
	var v := VBoxContainer.new()
	h.add_child(v)
	var name := String(Config.g("civilians.%s.name_ru" % a.type)) if a.kind == Agent.Kind.CIVILIAN else String(Config.g("units.%s.name_ru" % a.type))
	v.add_child(UiTheme.label(name, 17, UiTheme.TEXT, true))
	v.add_child(_bar(a.hp / a.max_hp, UiTheme.OK.lerp(UiTheme.DANGER, 1.0 - a.hp / a.max_hp)))
	v.add_child(UiTheme.label("%d / %d HP" % [int(a.hp), int(a.max_hp)], 12, UiTheme.DIM))
	var st: PackedStringArray = []
	if a.infected and a.infect_detected:
		st.append(tr("ST_INFECTED") % int(ceil(a.infect_t)))
	if a.kind == Agent.Kind.CIVILIAN:
		st.append(tr("CIV_" + Agent.Civ.keys()[a.civ]))
		if a.trait_id != "":
			var neg := bool(Config.opt("civilians.traits.%s.negative" % a.trait_id, false))
			v.add_child(UiTheme.label("★ " + String(Config.g("civilians.traits.%s.name_ru" % a.trait_id)), 13, UiTheme.DANGER if neg else UiTheme.WARN, true))
	else:
		st.append(tr("HUD_OWNER") + " P%d" % a.owner)
		if a.kind == Agent.Kind.AIR:
			st.append(tr("HUD_FUEL") + " %d%%" % int(100.0 * a.fuel / w.mods.heli_flight_time(a.owner)))
		if not a.passengers.is_empty():
			st.append(tr("HUD_PASSENGERS") + " %d" % a.passengers.size())
		if a.temp_life >= 0.0:
			st.append(tr("HUD_TEMP") % int(a.temp_life))
		if a.trait_id != "":
			st.append("★ " + String(Config.g("civilians.traits.%s.name_ru" % a.trait_id)))
	v.add_child(UiTheme.label(" · ".join(st), 12, UiTheme.DIM))


func _group(ids: Array[int]) -> void:
	var w: World = game.world
	box.add_child(UiTheme.caps(tr("HUD_SELECTED") % ids.size()))
	var g := GridContainer.new()
	g.columns = 10
	box.add_child(g)
	for id in ids.slice(0, 30):
		var a := w.agents.get_agent(id)
		if a == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(38, 38)
		b.icon = Look.icon(("civ_child" if a.is_child else "civ_adult") if a.kind == Agent.Kind.CIVILIAN else "unit_" + a.type)
		b.expand_icon = true
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = Color.WHITE.lerp(Color(1, 0.4, 0.3), 1.0 - a.hp / a.max_hp)
		b.pressed.connect(func() -> void: game.selection.set_agents([id] if a.is_unit() else [], [id] if not a.is_unit() else []))
		g.add_child(b)


func _building(b: Building) -> void:
	var w: World = game.world
	var d := b.data()
	var h := _row()
	h.add_child(UiTheme.icon_rect(String(d["icon"]).get_file().get_basename(), 56))
	var v := VBoxContainer.new()
	h.add_child(v)
	v.add_child(UiTheme.label(String(d["name_ru"]), 17, UiTheme.TEXT, true))
	v.add_child(_bar(b.hp / b.max_hp, UiTheme.OK.lerp(UiTheme.DANGER, 1.0 - b.hp / b.max_hp)))
	var info: PackedStringArray = ["%d / %d" % [int(b.hp), int(b.max_hp)]]
	if not b.complete():
		info.append(tr("HUD_CONSTRUCTION") % [int(b.progress * 100), b.builders.size()])
	elif b.upgrading_to != "":
		info.append(tr("HUD_UPGRADING") % int(b.upgrade_progress * 100))
	elif b.repairing:
		info.append(tr("HUD_REPAIRING"))
	if b.complete() and b.power_need > 0.0:
		info.append(tr("HUD_POWERED") if b.powered and b.enabled else tr("HUD_UNPOWERED"))
	v.add_child(UiTheme.label(" · ".join(info), 12, UiTheme.DIM))
	if b.worker_slots > 0:
		_workers(b)
	if not b.queue.is_empty():
		var q: Dictionary = b.queue[0]
		box.add_child(UiTheme.label(tr("HUD_TRAINING") % [String(Config.g("units.%s.name_ru" % String(q["unit"]))), b.queue.size()], 12, UiTheme.TEXT))
		box.add_child(_bar(1.0 - float(q["t"]) / float(q["total"]), UiTheme.ACCENT, 380))
	if not b.research.is_empty():
		box.add_child(UiTheme.label(tr("HUD_RESEARCHING") % String(Config.g("tech.%s.name_ru" % String(b.research["tech"]))), 12, UiTheme.TEXT))
		box.add_child(_bar(1.0 - float(b.research["t"]) / float(b.research["total"]), UiTheme.ACCENT, 380))
	if d.has("garrison"):
		box.add_child(UiTheme.label(tr("HUD_GARRISON") % [b.garrison.size(), int(d["garrison"])], 12, UiTheme.DIM))
	if b.type == "quarantine":
		box.add_child(UiTheme.label(tr("HUD_QUARANTINE") % [b.patients.size(), int(d["capacity"])], 12, UiTheme.DIM))


func _workers(b: Building) -> void:
	var w: World = game.world
	var h := _row()
	h.add_child(UiTheme.label(tr("HUD_WORKERS") + ":", 12, UiTheme.DIM))
	for k in b.worker_slots:
		var tr_ := TextureRect.new()
		tr_.custom_minimum_size = Vector2(30, 30)
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		if k < b.workers.size():
			var a := w.agents.get_agent(b.workers[k])
			tr_.texture = Look.icon("civ_adult")
			if a != null and a.trait_id != "":
				tr_.tooltip_text = String(Config.g("civilians.traits.%s.name_ru" % a.trait_id))
				tr_.modulate = UiTheme.WARN
		else:
			tr_.texture = Look.icon("civ_adult")
			tr_.modulate = Color(1, 1, 1, 0.2)
		h.add_child(tr_)


func _poi(p: MapPoi) -> void:
	var name := p.name if p.name != "" else tr("POI_" + p.type.to_upper())
	box.add_child(UiTheme.label(name, 17, UiTheme.TEXT, true))
	box.add_child(UiTheme.label(tr("POI_" + p.type.to_upper() + "_TIP"), 12, UiTheme.DIM))
	if p.type == "nest":
		box.add_child(_bar(p.hp / p.max_hp, UiTheme.DANGER))
	elif p.progress > 0.0 or p.done:
		box.add_child(_bar(p.progress, UiTheme.ACCENT))
		if p.done:
			box.add_child(UiTheme.label(tr("POI_DONE"), 12, UiTheme.OK))
