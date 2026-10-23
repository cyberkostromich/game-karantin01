class_name Fx
extends Node3D
## VFX по арт-библии §8: трассеры, вспышки, взрывы, кровь (частицы + пятна), крик, дым, напалм, ракеты.
## Слушает Events; длительные эффекты (дым, огонь, ракеты) рисует по спискам Abilities каждый кадр.

const MAX_TRACERS := 400
const MAX_DECALS := 300

var world: World
var cam: RtsCamera
var tracers: Array[Dictionary] = []
var im := ImmediateMesh.new()
var tracer_mi := MeshInstance3D.new()
var lights: Array[OmniLight3D] = []
var light_t := PackedFloat32Array()
var light_i: int = 0
var booms: Array[Dictionary] = []      # {node, t, life, r}
var blood_pool: Array[GPUParticles3D] = []
var blood_i: int = 0
var decals := MultiMeshInstance3D.new()
var decal_n: int = 0
var decal_buf := PackedFloat32Array()
var rings: Array[Dictionary] = []
var smoke_mm := MultiMeshInstance3D.new()
var fire_mm := MultiMeshInstance3D.new()
var flare_lights: Array[OmniLight3D] = []
var _t: float = 0.0


func setup(w: World, camera: RtsCamera) -> void:
	world = w
	cam = camera
	tracer_mi.mesh = im
	var tm := Look.unlit(Color.WHITE)
	tm.vertex_color_use_as_albedo = true
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mi.material_override = tm
	tracer_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer_mi.extra_cull_margin = 16384.0
	add_child(tracer_mi)
	for k in 10:
		var l := OmniLight3D.new()
		l.omni_range = 10.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lights.append(l)
		light_t.append(0.0)
	for k in 12:
		blood_pool.append(_make_blood())
	_setup_decals()
	_setup_mm(smoke_mm, _sphere(1.0), Look.unlit(Color(0.55, 0.56, 0.58, 0.55)))
	var fm := Look.unlit(Color(1.0, 0.55, 0.15, 0.85))
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.45, 0.1)
	fm.emission_energy_multiplier = 3.0
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 2.2
	cone.radial_segments = 5
	_setup_mm(fire_mm, cone, fm)
	Events.shot_fired.connect(_on_shot)
	Events.explosion.connect(_on_explosion)
	Events.zombie_died.connect(_on_zombie_died)
	Events.scream.connect(_on_scream)
	Events.civilian_turned.connect(func(_id: int, p: Vector2, _in: bool) -> void: _ring(p, 6.0, Color(0.6, 0.9, 0.4, 0.6), 1.2))
	Events.building_destroyed.connect(func(_id: int, _t2: String, p: Vector2) -> void: _boom(p, 6.0, Color(0.6, 0.55, 0.5, 0.7), 1.4))
	Events.infection_detected.connect(func(_id: int, p: Vector2, _by: String) -> void: _ring(p, 3.0, Color(0.6, 0.95, 0.4, 0.8), 1.0))


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s


func _setup_mm(mmi: MultiMeshInstance3D, mesh: Mesh, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)


func _make_blood() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.7
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -14, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = Color("7a1f1f")
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	p.draw_pass_1 = bm
	var mat := Look.unlit(Color("7a1f1f"))
	mat.vertex_color_use_as_albedo = true
	bm.material = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _setup_decals() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	q.orientation = PlaneMesh.FACE_Y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = MAX_DECALS
	mm.visible_instance_count = 0
	decals.multimesh = mm
	var m := Look.unlit(Color(0.32, 0.07, 0.07, 0.75))
	decals.material_override = m
	decals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decals.extra_cull_margin = 16384.0
	add_child(decals)


# ------------------------------------------------------------------ события
func _near_cam(p: Vector3) -> bool:
	return Vector2(p.x - cam.target.x, p.z - cam.target.z).length() < cam.height() * 3.0


func _on_shot(from: Vector3, to: Vector3, kind: String) -> void:
	if not _near_cam(from) or not world.fog.visible(Vector2(from.x, from.z)):
		return
	if tracers.size() >= MAX_TRACERS:
		tracers.pop_front()
	var col := Color(1.0, 0.85, 0.45)
	if kind == "tank" or kind == "bmp":
		col = Color(1.0, 0.6, 0.25)
	tracers.append({"a": from, "b": to, "t": 0.0, "c": col, "life": 0.09 if kind != "sniper" else 0.18})
	_flash(from, 0.06, 2.0 if kind in ["tank", "bmp", "heli"] else 1.0)


func _flash(p: Vector3, life: float, energy: float) -> void:
	var l := lights[light_i]
	light_i = (light_i + 1) % lights.size()
	l.position = p + Vector3(0, 0.3, 0)
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = energy
	light_t[lights.find(l)] = life


func _on_explosion(p: Vector2, r: float, kind: String) -> void:
	if not world.fog.visible(p):
		return
	_boom(p, maxf(r, 1.5), Color(1.0, 0.55, 0.2, 0.9), 0.5)
	_ring(p, r * 2.0, Color(0.55, 0.5, 0.45, 0.5), 0.8)
	_flash(Vector3(p.x, 1.5, p.y), 0.25, 6.0)
	if kind in ["shell", "grenade"] and _near_cam(Vector3(p.x, 0, p.y)):
		cam.shake(0.35 if kind == "shell" else 0.2)


func _on_zombie_died(p: Vector2, _type: int, _dir: float) -> void:
	if not world.fog.visible(p) or not _near_cam(Vector3(p.x, 0, p.y)):
		return
	var b := blood_pool[blood_i]
	blood_i = (blood_i + 1) % blood_pool.size()
	b.position = Vector3(p.x, 1.0, p.y)
	b.restart()
	_decal(p)


func _decal(p: Vector2) -> void:
	var mm := decals.multimesh
	var i := decal_n % MAX_DECALS
	var s := 0.6 + fmod(float(decal_n) * 0.618, 0.9)
	var a := fmod(float(decal_n) * 2.39, TAU)
	mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a).scaled(Vector3(s, 1, s)), Vector3(p.x, 0.07, p.y)))
	decal_n += 1
	mm.visible_instance_count = mini(decal_n, MAX_DECALS)


func _on_scream(p: Vector2, r: float) -> void:
	if world.fog.visible(p):
		_ring(p, minf(r, 60.0), Color(0.6, 0.9, 0.39, 0.35), 1.4)


func _boom(p: Vector2, r: float, c: Color, life: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere(1.0)
	mi.material_override = Look.unlit(c)
	mi.position = Vector3(p.x, 0.5, p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	booms.append({"node": mi, "t": 0.0, "life": life, "r": r})


func _ring(p: Vector2, r: float, c: Color, life: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 3
	mi.mesh = tm
	mi.material_override = Look.unlit(c)
	mi.position = Vector3(p.x, 0.2, p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	rings.append({"node": mi, "t": 0.0, "life": life, "r": r})


# ------------------------------------------------------------------ кадр
func render(delta: float) -> void:
	_t += delta
	_tracers(delta)
	for k in lights.size():
		if light_t[k] > 0.0:
			light_t[k] -= delta
			if light_t[k] <= 0.0:
				lights[k].light_energy = 0.0
	_anim_list(booms, delta, true)
	_anim_list(rings, delta, false)
	_persistent()


func _tracers(delta: float) -> void:
	im.clear_surfaces()
	var alive: Array[Dictionary] = []
	for t in tracers:
		t["t"] = float(t["t"]) + delta
		if float(t["t"]) < float(t["life"]):
			alive.append(t)
	tracers = alive
	if tracers.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for t in tracers:
		var k := float(t["t"]) / float(t["life"])
		var a: Vector3 = t["a"]
		var b: Vector3 = t["b"]
		var c: Color = t["c"]
		c.a = 1.0 - k
		im.surface_set_color(c)
		im.surface_add_vertex(a.lerp(b, k * 0.6))
		im.surface_set_color(c)
		im.surface_add_vertex(a.lerp(b, minf(1.0, k * 0.6 + 0.4)))
	im.surface_end()


func _anim_list(list: Array[Dictionary], delta: float, sphere: bool) -> void:
	var i := 0
	while i < list.size():
		var e: Dictionary = list[i]
		e["t"] = float(e["t"]) + delta
		var k := float(e["t"]) / float(e["life"])
		var n: MeshInstance3D = e["node"]
		if k >= 1.0:
			n.queue_free()
			list.remove_at(i)
			continue
		var r := float(e["r"]) * (0.4 + 0.6 * k if sphere else k)
		n.scale = Vector3(r, r * (0.7 if sphere else 0.05), r)
		var m := n.material_override as StandardMaterial3D
		m.albedo_color.a = (1.0 - k) * (0.9 if sphere else 0.6)
		i += 1


## Дым БМП, напалм и ракеты разведчика — из состояния Abilities (живут в sim, а не в событиях).
func _persistent() -> void:
	var ab := world.abilities
	var smm := smoke_mm.multimesh
	var puffs := ab.smokes.size() * 8
	smm.instance_count = puffs
	var k := 0
	for s in ab.smokes:
		var p: Vector2 = s["pos"]
		var r := float(s["r"])
		for j in 8:
			var a := float(j) * TAU / 8.0 + _t * 0.2
			var d := r * 0.55 * (0.5 + 0.5 * fmod(float(j) * 0.37, 1.0))
			var sc := r * 0.35 * minf(1.0, float(s["t"]) / 2.0 + 0.3)
			smm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(sc, sc * 0.8, sc)), Vector3(p.x + cos(a) * d, 1.2 + 0.3 * float(j % 3), p.y + sin(a) * d)))
			k += 1
	var fmm := fire_mm.multimesh
	var flames := 0
	for f in ab.fires:
		flames += int((f["a"] as Vector2).distance_to(f["b"]) / 1.5) + 1
	fmm.instance_count = flames
	k = 0
	for f in ab.fires:
		var a: Vector2 = f["a"]
		var b: Vector2 = f["b"]
		var n := int(a.distance_to(b) / 1.5) + 1
		for j in n:
			var p := a.lerp(b, float(j) / maxf(1.0, n - 1))
			var h := 0.8 + 0.5 * sin(_t * 12.0 + j)
			fmm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(1, h, 1)), Vector3(p.x + sin(j * 1.7) * 1.2, h, p.y + cos(j * 2.3) * 1.2)))
			k += 1
	while flare_lights.size() < ab.lures.size():
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.25, 0.2)
		l.omni_range = 30.0
		l.light_energy = 4.0
		add_child(l)
		flare_lights.append(l)
	for j in flare_lights.size():
		var on := j < ab.lures.size()
		flare_lights[j].visible = on
		if on:
			var p: Vector2 = ab.lures[j]["pos"]
			flare_lights[j].position = Vector3(p.x, 14.0 + sin(_t * 3.0), p.y)
			flare_lights[j].light_energy = 3.5 + sin(_t * 25.0) * 0.8
