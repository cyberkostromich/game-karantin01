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
	position = Vector2(-380, 66)
	custom_minimum_size = Vector2(370, 0)
	add_theme_constant_override("separation", 6)
	add_child(goals_box)
	add_child(log_box)
	report = PanelContainer.new()
	report.add_theme_stylebox_override("panel", UiTheme.box(Color(0.1, 0.11, 0.13, 0.95), 10, 14))
	report_l = UiTheme.label("", 16, UiTheme.TEXT, true)
	report_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_l.custom_minimum_size = Vector2(520, 0)
	report.add_child(report_l)
	report.visible = false
	Events.scenario_event.connect(_on_event)
	Events.dawn_report.connect(_on_dawn)
	Events.objective_updated.connect(func(id: String, st: String) -> void:
		goals[id] = st
		_goals())
	Events.wave_announced.connect(func(n: int, dirs: PackedStringArray, _c: Dictionary) -> void:
		var names: PackedStringArray = []
		for d in dirs:
			names.append(tr("DIR_" + d))
		say(tr("RADIO_DUSK") % [n, ", ".join(names)], UiTheme.DANGER))
	goals["quota"] = "active"
	_goals()


func report_node() -> Control:
	return report


func say(text: String, col: Color = UiTheme.TEXT) -> void:
	var p := PanelContainer.new()
	var sb := UiTheme.box(Color(0.1, 0.11, 0.13, 0.88), 8)
	sb.border_color = UiTheme.ACCENT
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := UiTheme.label("📻 " + text, 13, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(350, 0)
	p.add_child(l)
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
	goals_box.add_child(UiTheme.caps(tr("GOALS_TITLE"), 11, UiTheme.ACCENT))
	for id: String in goals:
		var st := String(goals[id])
		var text := tr("GOAL_" + id.to_upper())
		if id == "quota":
			var p := w.scenario.people_on_arena()
			text = tr("GOAL_QUOTA") % [Config.i("rules.victory.evacuation_quota_people"), w.clock.total_days, int(p["civilians"]) + int(p["children"]) + int(p["soldiers"])]
		var l := UiTheme.label(("✓ " if st == "done" else "• ") + text, 13, UiTheme.OK if st == "done" else UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(350, 0)
		goals_box.add_child(l)


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
