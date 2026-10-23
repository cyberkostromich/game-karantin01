class_name TechTreeWindow
extends PanelContainer
## Дерево технологий (docs/07 §2): 3 колонки по тирам, цена и время, «Исследовать» в выбранной Мастерской.

var game: Node
var workshop_id: int = -1
var cols := HBoxContainer.new()
var head: Label
var _acc: float = 0.0


func setup(g: Node) -> void:
	game = g
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(820, 430)
	var v := VBoxContainer.new()
	add_child(v)
	var top := HBoxContainer.new()
	head = UiTheme.label(tr("TECH_TITLE"), 20, UiTheme.TEXT, true)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	top.add_child(UiTheme.button("✕", func() -> void: visible = false))
	v.add_child(top)
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)


func open(ws: int) -> void:
	workshop_id = ws
	visible = true
	_rebuild()


func _workshop() -> Building:
	var w: World = game.world
	var b := w.buildings.get_building(workshop_id)
	if b != null and b.complete() and b.research.is_empty():
		return b
	for x in w.buildings.all_of("workshop"):
		if x.research.is_empty():
			return x
	return null


func _process(delta: float) -> void:
	if not visible:
		return
	_acc -= delta
	if _acc <= 0.0:
		_acc = 0.5
		_rebuild()


func _rebuild() -> void:
	for c in cols.get_children():
		c.queue_free()
	var w: World = game.world
	var ws := _workshop()
	head.text = tr("TECH_TITLE") + ("" if ws != null else "  · " + tr("TECH_NO_WORKSHOP"))
	for tier in [1, 2, 3]:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(260, 0)
		col.add_child(UiTheme.caps(tr("TECH_TIER") % tier))
		for t in Config.keys_of("tech"):
			if int(Config.g("tech.%s.tier" % t)) != tier:
				continue
			col.add_child(_card(t, w, ws))
		cols.add_child(col)


func _card(t: String, w: World, ws: Building) -> Control:
	var d := Config.d("tech." + t)
	var p := PanelContainer.new()
	var done := w.tech.has(t)
	var prog := w.tech.in_progress(t)
	p.add_theme_stylebox_override("panel", UiTheme.skin("btn_active" if prog else ("inset" if done else "btn"), 10))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UiTheme.caps(String(d["name_ru"]), 15, UiTheme.OK if done else UiTheme.TEXT))
	var lbl := UiTheme.label(String(d["effect"]), 11, UiTheme.DIM)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 240
	v.add_child(lbl)
	var costs: PackedStringArray = []
	for r: String in d["cost"]:
		costs.append("%d %s" % [int(d["cost"][r]), tr("RES_" + r.to_upper())])
	var req: PackedStringArray = []
	for r: String in d["requires"]:
		req.append(String(Config.g("tech.%s.name_ru" % r)))
	v.add_child(UiTheme.label("%s · %d %s%s" % [", ".join(costs), int(w.mods.tech_time(t)), tr("UNIT_SEC"),
		("\n" + tr("TECH_REQUIRES") + ": " + ", ".join(req)) if not req.is_empty() else ""], 11, UiTheme.DIM))
	if done:
		v.add_child(UiTheme.label(tr("TECH_DONE"), 12, UiTheme.OK, true))
	elif prog:
		v.add_child(UiTheme.label(tr("TECH_IN_PROGRESS"), 12, UiTheme.ACCENT, true))
	else:
		var err := w.tech.check(t)
		if ws == null:
			err = "TECH_NO_WORKSHOP"
		var b := UiTheme.button(tr("TECH_START"), func() -> void:
			game.send({"t": "research", "building_id": ws.id, "tech": t})
			_acc = 0.1, tr(err) if err != "" else "")
		b.disabled = err != ""
		v.add_child(b)
	return p
