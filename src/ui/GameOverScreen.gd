class_name GameOverScreen
extends PanelContainer
## Финал (docs/07 §2): счёт по категориям, медали, график численности людей по дням.

var game: Node
var body := VBoxContainer.new()
var chart := Control.new()
var history: Array = []


func setup(g: Node) -> void:
	game = g
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(640, 520)
	add_theme_stylebox_override("panel", UiTheme.skin("panel", 24))
	add_child(body)
	body.add_theme_constant_override("separation", 8)
	Events.game_over.connect(show_result)


func show_result(win: bool, score: Dictionary) -> void:
	for c in body.get_children():
		c.queue_free()
	visible = true
	body.add_child(UiTheme.label(tr("GAME_WIN") if win else tr("GAME_LOSE"), 30, UiTheme.OK if win else UiTheme.DANGER, true))
	body.add_child(UiTheme.label(tr(String(score.get("reason", ""))), 15, UiTheme.DIM))
	var parts: Dictionary = score.get("parts", {})
	for k: String in parts:
		var h := HBoxContainer.new()
		var l := UiTheme.label(tr("SCORE_" + k.to_upper()), 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UiTheme.label(str(int(parts[k])), 15, UiTheme.TEXT, true))
		body.add_child(h)
	body.add_child(UiTheme.label("%s: %d" % [tr("SCORE_TOTAL"), int(score.get("total", 0))], 22, UiTheme.ACCENT, true))
	body.add_child(UiTheme.label("%s: %d · %s: %d" % [tr("SCORE_KILLS"), int(score.get("kills", 0)), tr("HUD_DAY"), int(score.get("day", 0))], 13, UiTheme.DIM))
	var medals: Array = score.get("medals", [])
	if not medals.is_empty():
		var names: PackedStringArray = []
		for m: String in medals:
			names.append("🏅 " + tr(m))
		body.add_child(UiTheme.label("  ".join(names), 15, UiTheme.WARN, true))
	history = score.get("history", [])
	chart.custom_minimum_size = Vector2(580, 150)
	chart.draw.connect(_draw_chart)
	body.add_child(UiTheme.caps(tr("SCORE_CHART")))
	body.add_child(chart)
	var row := HBoxContainer.new()
	row.add_child(UiTheme.button(tr("MENU_TO_MAIN"), func() -> void: game.exit_to_menu()))
	body.add_child(row)
	chart.queue_redraw()
	Sfx.play("win" if win else "lose")


func _draw_chart() -> void:
	var sz := chart.size
	chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.14, 0.15, 0.17))
	if history.size() < 1:
		return
	var series := {"adults": UiTheme.INFO, "children": UiTheme.WARN, "soldiers": UiTheme.OK}
	var mx := 1.0
	for h: Dictionary in history:
		for k: String in series:
			mx = maxf(mx, float(h[k]))
	for k: String in series:
		var pts := PackedVector2Array()
		for i in history.size():
			var x := sz.x * (float(i) / maxf(1.0, history.size() - 1))
			pts.append(Vector2(x, sz.y - 6 - (sz.y - 12) * float(history[i][k]) / mx))
		if pts.size() == 1:
			pts.append(pts[0] + Vector2(4, 0))
		chart.draw_polyline(pts, series[k], 2.0, true)
