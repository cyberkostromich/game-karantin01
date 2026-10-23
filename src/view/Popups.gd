class_name Popups
extends Node3D
## Всплывающие подписи над миром: «+5 дерево» у лесопилки при сдаче ноши, «+1 штурмовик» у казармы —
## игрок видит, что экономика и найм работают (обратная связь как в AoE/Frostpunk).

const LIFE := 1.8
const MAX := 24

var world: World
var pool: Array[Label3D] = []
var t := PackedFloat32Array()
var _i: int = 0


func setup(w: World) -> void:
	world = w
	for k in MAX:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 11
		l.font = UiTheme.font_n if UiTheme.font_n != null else null
		l.font_size = 64
		l.pixel_size = 0.02
		l.outline_size = 14
		l.outline_modulate = Color(0.05, 0.05, 0.05, 0.85)
		l.visible = false
		add_child(l)
		pool.append(l)
		t.append(0.0)
	Events.resource_delivered.connect(func(res: String, n: float, p: Vector2) -> void:
		if n >= 0.5:
			show_text(p, "+%d %s" % [int(round(n)), tr("RES_" + res.to_upper()).to_lower()], _color(res)))
	Events.unit_trained.connect(func(id: int, type: String, _o: int) -> void:
		var a := world.agents.get_agent(id)
		if a != null:
			show_text(a.pos, "+1 " + String(Config.g("units.%s.name_ru" % type)).to_lower(), UiTheme.OK))


func _color(res: String) -> Color:
	match res:
		"wood": return Color("e0a86a")
		"iron": return Color("c3ccd4")
		"food": return Color("f2c45a")
	return UiTheme.TEXT


func show_text(p: Vector2, text: String, c: Color) -> void:
	if not world.fog.visible(p):
		return
	var l := pool[_i]
	t[_i] = LIFE
	_i = (_i + 1) % MAX
	l.text = text
	l.modulate = c
	l.position = Vector3(p.x, 3.2, p.y)
	l.visible = true


func render(delta: float) -> void:
	for k in MAX:
		if t[k] <= 0.0:
			continue
		t[k] -= delta
		var l := pool[k]
		l.position.y += delta * 1.2
		l.modulate.a = clampf(t[k] / 0.6, 0.0, 1.0)
		if t[k] <= 0.0:
			l.visible = false
