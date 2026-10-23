class_name Tutorial
extends PanelContainer
## Онбординг первого дня (GDD §16, M6-5): последовательные подсказки, шаг закрывается сам,
## когда игрок сделал нужное. Справка по управлению — из меню паузы.

const STEPS := ["TUT_SCOUT", "TUT_FIND", "TUT_BRING", "TUT_CHECKPOINT", "TUT_SAWMILL", "TUT_ASSIGN", "TUT_WALL", "TUT_DUSK", "TUT_DONE"]

var game: Node
var step: int = 0
var text_l: Label
var enabled: bool = true
var _acc: float = 0.0
var _done_t: float = 0.0


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	custom_minimum_size = Vector2(560, 0)
	add_theme_stylebox_override("panel", UiTheme.skin("panel", 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.tape(tr("TUT_TITLE"), 12))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(UiTheme.button(tr("TUT_SKIP"), func() -> void:
		enabled = false
		visible = false))
	v.add_child(h)
	text_l = UiTheme.label("", 16)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size = Vector2(530, 0)
	v.add_child(text_l)
	_show()


func _show() -> void:
	text_l.text = tr(STEPS[step])
	position = Vector2((get_viewport_rect().size.x - custom_minimum_size.x) * 0.5, 96)


func show_help() -> void:
	enabled = false
	visible = true
	text_l.text = tr("HELP_CONTROLS")
	position = Vector2((get_viewport_rect().size.x - custom_minimum_size.x) * 0.5, 96)


func _process(delta: float) -> void:
	if not enabled:
		return
	_acc -= delta
	if _acc > 0.0:
		return
	_acc = 0.5
	if _check(STEPS[step]):
		step = mini(step + 1, STEPS.size() - 1)
		Sfx.play("ui_ok")
		_show()
	if STEPS[step] == "TUT_DONE":
		_done_t += 0.5
		if _done_t > 12.0:
			enabled = false
			visible = false


func _check(id: String) -> bool:
	var w: World = game.world
	match id:
		"TUT_SCOUT":
			for uid in game.selection.units:
				var a := w.agents.get_agent(uid)
				if a != null and a.type == "scout":
					return true
		"TUT_FIND":
			for a in w.agents.list:
				if a.kind == Agent.Kind.CIVILIAN and a.civ == Agent.Civ.FOLLOWING:
					return true
		"TUT_BRING":
			return int(w.economy.stats.get("rescued", 0)) > 0 or w.clock.day > 1
		"TUT_CHECKPOINT":
			return not w.buildings.all_of("checkpoint", false).is_empty()
		"TUT_SAWMILL":
			return not w.buildings.all_of("sawmill", false).is_empty()
		"TUT_ASSIGN":
			for b in w.buildings.all_of("sawmill"):
				if not b.workers.is_empty():
					return true
		"TUT_WALL":
			return not w.buildings.all_of("wall_wood", false).is_empty() or not w.buildings.all_of("floodlight", false).is_empty()
		"TUT_DUSK":
			return w.clock.phase >= 2 or w.clock.day > 1
	return false
