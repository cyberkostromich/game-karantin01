class_name Alerts
extends VBoxContainer
## Стек алертов слева (docs/07 §1): до 5, клик — камера к событию, пробел — к последнему.
## Цвет по типу: заражение — зелёный, атака — красный, мирные — синий, дефицит — жёлтый, наука — оранжевый.

const MAX := 5
const LIFE := 9.0
const COLORS := {"infected": UiTheme.INFECT, "attack": UiTheme.DANGER, "civilians": UiTheme.INFO,
	"deficit": UiTheme.WARN, "research": UiTheme.ACCENT, "wave": UiTheme.DANGER, "objective": UiTheme.ACCENT,
	"fuel": UiTheme.WARN, "info": UiTheme.DIM}

var game: Node
var last_pos := Vector2.INF
var _cool: Dictionary = {}   # kind → секунд до следующего такого же


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(10, 62)
	custom_minimum_size = Vector2(270, 0)
	add_theme_constant_override("separation", 4)
	Events.civilian_infected.connect(func(_id: int, p: Vector2, inside: bool) -> void:
		if inside: push("infected", tr("ALERT_BITE_BASE"), p))
	Events.infection_detected.connect(func(_id: int, p: Vector2, by: String) -> void: push("infected", tr("ALERT_DETECTED_" + by.to_upper()), p))
	Events.outbreak_in_base.connect(func(p: Vector2) -> void: push("infected", tr("ALERT_OUTBREAK"), p, true))
	Events.building_attacked.connect(func(_id: int, p: Vector2) -> void: push("attack", tr("ALERT_ATTACK"), p))
	Events.civilian_found.connect(func(_id: int, p: Vector2) -> void: push("civilians", tr("ALERT_FOUND"), p))
	Events.civilian_rescued.connect(func(_id: int, p: Vector2) -> void: push("civilians", tr("ALERT_RESCUED"), p))
	Events.power_deficit.connect(func(_ids: PackedInt32Array) -> void: push("deficit", tr("ALERT_POWER"), Vector2.INF))
	Events.research_completed.connect(func(t: String) -> void: push("research", tr("ALERT_RESEARCH") % String(Config.g("tech.%s.name_ru" % t)), Vector2.INF, true))
	Events.wave_started.connect(func(n: int) -> void: push("wave", tr("ALERT_WAVE") % n, Vector2.INF, true))
	Events.unit_trained.connect(func(_id: int, t: String, _o: int) -> void: push("info", tr("ALERT_TRAINED") % String(Config.g("units.%s.name_ru" % t)), Vector2.INF, true))
	Events.building_completed.connect(func(id: int, t: String) -> void:
		var b := game.world.buildings.get_building(id) as Building
		if t != "hq" and b != null and not b.is_wall_like():
			push("info", tr("ALERT_BUILT") % String(Config.g("buildings.%s.name_ru" % t)), b.pos))
	Events.nest_destroyed.connect(func(_id: int, p: Vector2) -> void: push("objective", tr("ALERT_NEST"), p, true))
	Events.loot_collected.connect(func(_t: String, loot: Dictionary, p: Vector2) -> void: push("objective", tr("ALERT_LOOT") % _loot_text(loot), p, true))
	Events.recruit_failed.connect(func(reason: String) -> void: push("deficit", tr(reason), Vector2.INF, true))
	Events.alert.connect(func(kind: String, text: String, p: Vector2) -> void: push(kind, tr(text), p, true))
	Events.unit_died.connect(func(_id: int, t: String, p: Vector2) -> void: push("attack", tr("ALERT_UNIT_DIED") % String(Config.g("units.%s.name_ru" % t)), p))


func _loot_text(loot: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in loot:
		parts.append("+%d %s" % [int(loot[k]), tr("RES_" + k.to_upper())])
	return ", ".join(parts)


func push(kind: String, text: String, p: Vector2, force := false) -> void:
	if not force and float(_cool.get(kind + text, 0.0)) > 0.0:
		return
	_cool[kind + text] = 4.0
	if p != Vector2.INF:
		last_pos = p
	var b := Button.new()
	b.text = "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.custom_minimum_size = Vector2(270, 30)
	var sb := UiTheme.box(Color(0.1, 0.11, 0.13, 0.9), 6)
	sb.border_color = COLORS.get(kind, UiTheme.DIM)
	sb.border_width_left = 4
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_font_size_override("font_size", 13)
	b.set_meta("t", LIFE)
	if p != Vector2.INF:
		b.pressed.connect(func() -> void: game.cam.focus(p))
	add_child(b)
	move_child(b, 0)
	while get_child_count() > MAX:
		get_child(get_child_count() - 1).queue_free()
		remove_child(get_child(get_child_count() - 1))
	Sfx.play("alert_" + kind)


func _process(delta: float) -> void:
	for k: String in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)
	for c in get_children():
		var t := float(c.get_meta("t", LIFE)) - delta
		c.set_meta("t", t)
		(c as Control).modulate.a = clampf(t / 1.5, 0.0, 1.0)
		if t <= 0.0:
			c.queue_free()
