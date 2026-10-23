class_name AgentView
extends Node3D
## Вид одного военного/мирного. Процедурная анимация по узлам модели (M0-8): шаг ногами и руками,
## башня и ствол техники, роторы вертолёта. Узлы ищутся по именам — контракт арт-библии §5.

var agent_id: int = 0
var kind: int = 0
var model: Node3D
var parts: Dictionary = {}       # имя узла → Node3D
var rest: Dictionary = {}        # имя узла → Basis в позе покоя
var phase: float = 0.0
var hull_yaw: float = 0.0
var ring: MeshInstance3D
var hp_bg: MeshInstance3D
var hp_fg: MeshInstance3D
var status: Sprite3D
var selected: bool = false
var meshes: Array[GeometryInstance3D] = []
var _last_status: String = ""


func build(a: Agent, model_path: String, team: Color) -> void:
	agent_id = a.id
	kind = a.kind
	model = Look.instance(model_path)
	var k := Config.f("rules.view.humanoid_scale") if a.kind == Agent.Kind.INFANTRY or a.kind == Agent.Kind.CIVILIAN else Config.f("rules.view.vehicle_scale")
	model.scale = Vector3.ONE * k
	add_child(model)
	for pn: String in ["leg_l", "leg_r", "arm_l", "arm_r", "head", "body", "turret", "barrel", "rotor_main", "rotor_tail", "weapon"]:
		var n := Look.find(model, pn)
		if n != null:
			parts[pn] = n
			rest[pn] = n.transform.basis
	_collect_meshes(model)
	for m in meshes:
		m.set_instance_shader_parameter("team_color", team)
	phase = fmod(float(a.id) * 1.37, TAU)
	_make_ring(a.radius)
	_make_hp(a)
	status = Sprite3D.new()
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status.pixel_size = 0.012
	status.no_depth_test = true
	status.render_priority = 10
	status.position.y = 3.2 if kind != Agent.Kind.VEHICLE else 5.0
	status.visible = false
	add_child(status)


func _collect_meshes(n: Node) -> void:
	if n is GeometryInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)


func _make_ring(r: float) -> void:
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r + 0.35
	tm.outer_radius = r + 0.6
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.05
	ring.material_override = Look.unlit(Color(0.35, 1.0, 0.45, 0.9))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)


func _make_hp(a: Agent) -> void:
	var y := 2.9 if a.kind != Agent.Kind.VEHICLE else 4.6
	var w := 1.0 if a.kind != Agent.Kind.VEHICLE else 3.0
	hp_bg = _bar(Color(0.1, 0.1, 0.1, 0.8), w, y, 0)
	hp_fg = _bar(Color(0.35, 0.9, 0.4), w, y, 1)


func _bar(c: Color, w: float, y: float, prio: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, 0.14)
	mi.mesh = q
	var m := Look.unlit(c, true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.render_priority = 8 + prio
	mi.material_override = m
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func set_selected(v: bool) -> void:
	selected = v
	ring.visible = v


func set_status(icon_id: String) -> void:
	if icon_id == _last_status:
		return
	_last_status = icon_id
	status.visible = icon_id != ""
	if icon_id != "":
		status.texture = Look.icon(icon_id)


## Обновление позы. pos/prev — из sim, alpha — интерполяция между тиками.
func animate(a: Agent, p: Vector2, delta: float, altitude: float) -> void:
	position = Vector3(p.x, altitude, p.y)
	var moving := a.vel.length_squared() > 0.01
	var spd := a.vel.length()
	if kind == Agent.Kind.VEHICLE:
		_vehicle(a, delta, moving)
	elif kind == Agent.Kind.AIR:
		_heli(a, delta)
	else:
		rotation.y = lerp_angle(rotation.y, a.facing, minf(1.0, delta * 12.0))
		_walk(delta, spd, moving)
	var frac := a.hp / maxf(1.0, a.max_hp)
	var show_hp := selected or frac < 0.999
	hp_bg.visible = show_hp
	hp_fg.visible = show_hp
	if show_hp:
		hp_fg.scale.x = maxf(0.01, frac)
		(hp_fg.material_override as StandardMaterial3D).albedo_color = Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.3, 0.2), 1.0 - frac)
	var tint := 0.0
	if a.infected and a.infect_detected:
		tint = 1.0
	for m in meshes:
		m.set_instance_shader_parameter("infect_tint", tint)


func _walk(delta: float, spd: float, moving: bool) -> void:
	var amp := clampf(spd / 5.0, 0.0, 1.2) * 0.7 if moving else 0.0
	phase += delta * (4.0 + spd * 1.6)
	var s := sin(phase) * amp
	_swing("leg_l", s)
	_swing("leg_r", -s)
	_swing("arm_l", -s * 0.6)
	_swing("arm_r", s * 0.6 if not parts.has("weapon") else s * 0.15)
	if parts.has("body"):
		var b: Node3D = parts["body"]
		b.position.y = absf(sin(phase)) * 0.04 * amp


func _swing(pn: String, ang: float) -> void:
	if parts.has(pn):
		var n: Node3D = parts[pn]
		n.transform.basis = Basis(Vector3.RIGHT, ang) * (rest[pn] as Basis)


func _vehicle(a: Agent, delta: float, moving: bool) -> void:
	if moving:
		hull_yaw = lerp_angle(hull_yaw, atan2(a.vel.x, a.vel.y), minf(1.0, delta * 4.0))
	rotation.y = hull_yaw
	if parts.has("turret"):
		var t: Node3D = parts["turret"]
		t.rotation.y = lerp_angle(t.rotation.y, a.facing - hull_yaw, minf(1.0, delta * 5.0))
	if parts.has("hull") or true:
		model.rotation.x = sin(phase) * 0.01 if moving else 0.0
		phase += delta * 8.0


func _heli(a: Agent, delta: float) -> void:
	if a.vel.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(a.vel.x, a.vel.y), minf(1.0, delta * 3.0))
		model.rotation.x = lerpf(model.rotation.x, 0.15, delta * 2.0)
	else:
		rotation.y = lerp_angle(rotation.y, a.facing, minf(1.0, delta * 2.0))
		model.rotation.x = lerpf(model.rotation.x, 0.0, delta * 2.0)
	if parts.has("rotor_main"):
		(parts["rotor_main"] as Node3D).rotate_y(delta * 28.0)
	if parts.has("rotor_tail"):
		(parts["rotor_tail"] as Node3D).rotate_x(delta * 40.0)
