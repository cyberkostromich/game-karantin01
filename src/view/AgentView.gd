class_name AgentView
extends Node3D
## Вид одного военного/мирного. Процедурная анимация по узлам модели (M0-8): гуманоиды — HumanAnim,
## башня, отдача ствола и покачивание техники, роторы вертолёта. Узлы ищутся по именам — контракт арт-библии §5.

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
var human: HumanAnim
var team_col := Color.WHITE
var _last_tint: float = -1.0
var recoil: float = 0.0
var _last_cd: float = 0.0
var _last_status: String = ""


func build(a: Agent, model_path: String, team: Color) -> void:
	agent_id = a.id
	kind = a.kind
	model = Look.instance(model_path)
	var k := Config.f("rules.view.humanoid_scale") if a.kind == Agent.Kind.INFANTRY or a.kind == Agent.Kind.CIVILIAN else Config.f("rules.view.vehicle_scale")
	model.scale = Vector3.ONE * k
	add_child(model)
	for pn: String in ["turret", "barrel", "rotor_main", "rotor_tail"]:
		var n := Look.find(model, pn)
		if n != null:
			parts[pn] = n
			rest[pn] = n.transform
	if a.kind == Agent.Kind.INFANTRY or a.kind == Agent.Kind.CIVILIAN:
		human = HumanAnim.new()
		human.setup(model, a.kind == Agent.Kind.INFANTRY and Look.find(model, "weapon") != null, a.kind == Agent.Kind.CIVILIAN, a.id)
	_collect_meshes(model)
	team_col = team
	_tint(0.0)
	phase = fmod(float(a.id) * 1.37, TAU)
	_make_ring(a.radius)
	if a.is_unit():
		_make_team_disc(a.radius, team)
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
	tm.inner_radius = r * 1.4 + 0.45
	tm.outer_radius = r * 1.4 + 0.75
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.09
	var rm := Look.unlit(Color(0.35, 1.0, 0.45, 0.9))
	rm.render_priority = 7
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)


## Диск цвета игрока под своими юнитами (как в CoH/AoE IV): в коопе на 4 игроков видно, чьи бойцы,
## и отряд не теряется на траве. Выделение — отдельное кольцо поверх.
func _make_team_disc(r: float, team: Color) -> void:
	var d := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 1.2 + 0.35
	cm.bottom_radius = cm.top_radius
	cm.height = 0.02
	cm.radial_segments = 20
	cm.rings = 1
	d.mesh = cm
	d.position.y = 0.08   # дороги и поле арены лежат на 0.02–0.06 м — диск чуть выше, но ниже щиколоток
	var dm := Look.unlit(Color(team.r, team.g, team.b, 0.24))
	dm.render_priority = 6   # после туманного прохода (priority 5) — иначе пост-эффект тумана затирает прозрачное
	d.material_override = dm
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)


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
	if kind == Agent.Kind.VEHICLE:
		_vehicle(a, delta, moving)
	elif kind == Agent.Kind.AIR:
		_heli(a, delta)
	else:
		rotation.y = lerp_angle(rotation.y, a.facing, minf(1.0, delta * 12.0))
		human.update(a, delta)
	var frac := a.hp / maxf(1.0, a.max_hp)
	var show_hp := selected or frac < 0.999
	hp_bg.visible = show_hp
	hp_fg.visible = show_hp
	if show_hp:
		hp_fg.scale.x = maxf(0.01, frac)
		(hp_fg.material_override as StandardMaterial3D).albedo_color = Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.3, 0.2), 1.0 - frac)
	_tint(1.0 if a.infected and a.infect_detected else 0.0)


## Цвет игрока и тинт заражения — подменой общего материала (Look.char_mat), не параметрами экземпляра.
func _tint(t: float) -> void:
	if t == _last_tint:
		return
	_last_tint = t
	for m in meshes:
		if m.material_override is ShaderMaterial:
			var tex: Texture2D = m.get_meta("skin_tex") if m.has_meta("skin_tex") else null
			m.material_override = Look.char_mat(tex, team_col, t > 0.0)


## Смерть: гуманоид падает (HumanAnim.die), техника и вертолёт исчезают сразу (взрыв рисует Fx).
## Возвращает true, пока анимация идёт.
func dying(delta: float) -> bool:
	if human == null:
		return false
	ring.visible = false
	hp_bg.visible = false
	hp_fg.visible = false
	status.visible = false
	return human.die(model, delta)


func _vehicle(a: Agent, delta: float, moving: bool) -> void:
	if moving:
		hull_yaw = lerp_angle(hull_yaw, atan2(a.vel.x, a.vel.y), minf(1.0, delta * 4.0))
	rotation.y = hull_yaw
	if parts.has("turret"):
		var t: Node3D = parts["turret"]
		t.rotation.y = lerp_angle(t.rotation.y, a.facing - hull_yaw, minf(1.0, delta * 5.0))
	if a.atk_cd > _last_cd + 0.01:
		recoil = 1.0
	_last_cd = a.atk_cd
	recoil = maxf(0.0, recoil - delta * 4.0)
	if parts.has("barrel"):  # откат ствола и клевок корпуса при выстреле
		var b: Node3D = parts["barrel"]
		b.position.z = (rest["barrel"] as Transform3D).origin.z - recoil * 0.35
	phase += delta * 8.0
	model.rotation.x = (sin(phase) * 0.012 if moving else 0.0) - recoil * 0.03


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
