class_name RadioPanel
extends VBoxContainer
## Радио-реплики сценария (GDD §15, озвучки нет — только текст) и список текущих целей.
## Отчёт рассвета — модальная плашка на 4 с, не ставит паузу (docs/07 §2).

var game: Node
var log_box := VBoxContainer.new()
var goals_box := VBoxContainer.new()
var report: PanelContainer
var report_l: Label
var report_t: float = 0.0
var goals: Dictionary = {}   # id → state


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-380, 84)
	custom_minimum_size = Vector2(370, 0)
	add_theme_constant_override("separation", 6)
	add_child(goals_box)
	add_child(log_box)
	report = PanelContainer.new()
	report.add_theme_stylebox_override("panel", UiTheme.skin("panel", 18))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	report.add_child(rv)
	rv.add_child(UiTheme.tape(tr("REPORT_TAPE"), 13))
	report_l = UiTheme.label("", 16, UiTheme.TEXT)
	report_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_l.custom_minimum_size = Vector2(520, 0)
	rv.add_child(report_l)
	report.visible = false
	Events.scenario_event.connect(_on_event)
	Events.dawn_report.connect(_on_dawn)
	Events.objective_updated.connect(func(id: String, st: String) -> void:
		goals[id] = st
		_goals())
	Events.horde_updated.connect(func(n: int, comp: Dictionary) -> void:
		var total := 0
		for t: String in comp:
			total += int(comp[t])
		if n > 1:
			say(tr("RADIO_HORDE_GROWS") % [n, total], UiTheme.DANGER))
	goals["quota"] = "active"
	_goals()


func report_node() -> Control:
	return report


func say(text: String, col: Color = UiTheme.TEXT) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.skin("panel_dark", 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	v.add_child(UiTheme.caps(tr("RADIO_HEADER"), 11, UiTheme.ACCENT))
	var l := UiTheme.label(text, 14, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(350, 0)
	v.add_child(l)
	p.set_meta("t", 14.0)
	log_box.add_child(p)
	while log_box.get_child_count() > 3:
		var c := log_box.get_child(0)
		log_box.remove_child(c)
		c.queue_free()
	Sfx.play("radio")


func _on_event(_day: int, kind: String, text: String, pos: Vector2) -> void:
	if text != "":
		say(text, UiTheme.ACCENT if kind in ["objective", "evacuation", "final"] else UiTheme.TEXT)
	if kind == "radio" and pos != Vector2.ZERO:
		game.hud.alerts.push("civilians", tr("ALERT_RADIO_GROUP"), pos, true)


func _on_dawn(r: Dictionary) -> void:
	var lines: PackedStringArray = [tr("REPORT_TITLE") % (int(r["day"]) - 1)]
	lines.append(tr("REPORT_KILLS") % int(r["kills"]))
	lines.append(tr("REPORT_LOSSES") % [int(r["civ_lost"]), int(r["soldiers_lost"])])
	if int(r.get("births", 0)) > 0:
		lines.append(tr("REPORT_BIRTHS") % int(r["births"]))
	if int(r.get("rescued", 0)) > 0:
		lines.append(tr("REPORT_RESCUED") % int(r["rescued"]))
	lines.append(tr("REPORT_FOOD") % int(round(float(r.get("food_delta", 0.0)))))
	report_l.text = "\n".join(lines)
	report.visible = true
	report_t = 5.0


func _goals() -> void:
	for c in goals_box.get_children():
		c.queue_free()
	var w: World = game.world
	goals_box.add_child(UiTheme.tape(tr("GOALS_TITLE"), 12))
	for id: String in goals:
		var st := String(goals[id])
		var text := tr("GOAL_" + id.to_upper())
		if id == "quota":
			var p := w.scenario.people_on_arena()
			text = tr("GOAL_QUOTA") % [Config.i("rules.victory.evacuation_quota_people"), w.clock.total_days, int(p["civilians"]) + int(p["children"]) + int(p["soldiers"])]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var box := Panel.new()   # квадрат чек-листа: пустой — в работе, зелёный — выполнено
		box.custom_minimum_size = Vector2(11, 11)
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.position.y = 4
		box.add_theme_stylebox_override("panel", UiTheme.check_box(st == "done"))
		row.add_child(box)
		var l := UiTheme.label(text, 14, UiTheme.OK if st == "done" else UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(330, 0)
		row.add_child(l)
		goals_box.add_child(row)


func _process(delta: float) -> void:
	for c in log_box.get_children():
		var t := float(c.get_meta("t", 0.0)) - delta
		c.set_meta("t", t)
		(c as Control).modulate.a = clampf(t / 2.0, 0.0, 1.0)
		if t <= 0.0:
			c.queue_free()
	if report.visible:
		report_t -= delta
		report.modulate.a = clampf(report_t, 0.0, 1.0)
		if report_t <= 0.0:
			report.visible = false
	if Engine.get_process_frames() % 30 == 0:
		_goals()
