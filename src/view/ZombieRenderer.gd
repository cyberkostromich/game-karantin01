class_name ZombieRenderer
extends Node3D
## MultiMesh на тип зомби (tech spec §3.1): буфер трансформов пишется одним set_buffer за кадр.
## Видны только зомби в открытой туманом зоне; трупы доигрывают падение ещё corpse_s секунд.

const FLOATS := 16   # 12 трансформ + 4 custom
const CORPSE_S := 4.0

var world: World
var mmis: Array[MultiMeshInstance3D] = []
## Один общий буфер: тип k занимает [k*cap, (k+1)*cap) инстансов. Packed-массивы копируются при записи,
## если лежат в Array, поэтому храним один член-массив и пишем в него напрямую.
var buf := PackedFloat32Array()
var cap: int = 0
var counts := PackedInt32Array()
var corpses: Array[Dictionary] = []   # {pos, type, dir, t}
var phases := PackedFloat32Array()
var visible_count: int = 0
var max_speed: float = 6.0
var scale_k: float = 1.0


func setup(w: World) -> void:
	world = w
	scale_k = Config.f("rules.view.zombie_scale")
	for k in w.zombies.types.size():
		var t := w.zombies.types[k]
		var m := Look.merged(String(Config.g("zombies.%s.model" % t)))
		var piv: Dictionary = m["pivots"]
		var mesh: ArrayMesh = m["mesh"]
		for si in mesh.get_surface_count():  # палитра и скин — по материалу на поверхность
			var mat := Look.zombie(t, m["textures"][si])
			for pn: String in piv:
				mat.set_shader_parameter("piv_" + pn, piv[pn])
			mat.set_shader_parameter("stride", Config.f("zombies.%s.speed" % t) * 2.2 + 2.0)
			mesh.surface_set_material(si, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m["mesh"]
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.extra_cull_margin = 4000.0  # инстансы по всей карте; AABB сам по себе бесполезен
		add_child(mmi)
		mmis.append(mmi)
	counts.resize(mmis.size())
	Events.zombie_died.connect(_on_died)


func _on_died(pos: Vector2, type: int, dir: float) -> void:
	if corpses.size() > 300:
		corpses.pop_front()
	corpses.append({"pos": pos, "type": type, "dir": dir, "t": 0.0})


## alpha — доля между прошлым и текущим тиком (интерполяция движения).
func render(alpha: float, delta: float, cam_pos: Vector3) -> void:
	var z := world.zombies
	var fog := world.fog
	counts.fill(0)
	var n_types := mmis.size()
	var need := z.alive_n + corpses.size() + 16
	if need > cap:
		cap = need + 256
		buf.resize(cap * FLOATS * n_types)
	if phases.size() < z.count:
		var old := phases.size()
		phases.resize(z.count + 256)
		for i in range(old, phases.size()):
			phases[i] = fmod(float(i) * 0.6180339, 1.0)
	var cam := Vector2(cam_pos.x, cam_pos.z)
	var view_r2 := pow(maxf(250.0, cam_pos.y * 3.5), 2.0)
	for i in z.count:
		if z.alive[i] == 0:
			continue
		var p := z.prev[i].lerp(z.pos[i], alpha)
		if p.distance_squared_to(cam) > view_r2 or not fog.visible(p):
			continue
		var t := z.type_id[i]
		var v := z.vel[i]
		var ang := atan2(v.x, v.y) if v.length_squared() > 0.0001 else 0.0
		var spd := clampf(v.length() / max_speed, 0.0, 1.0)
		_write(t, p, ang, phases[i], float(z.state[i]) / 255.0, spd, 0.0)
	_corpses(delta)
	visible_count = 0
	for k in n_types:
		var mm := mmis[k].multimesh
		var c := counts[k]
		visible_count += c
		if mm.instance_count != c:
			mm.instance_count = c
		if c > 0:
			var o := k * cap * FLOATS
			mm.buffer = buf.slice(o, o + c * FLOATS)


func _write(t: int, p: Vector2, ang: float, phase: float, st: float, spd: float, die: float) -> void:
	if counts[t] >= cap:
		return
	var o := (t * cap + counts[t]) * FLOATS
	var c := cos(ang) * scale_k
	var s := sin(ang) * scale_k
	# строки базиса: поворот вокруг Y
	buf[o] = c
	buf[o + 1] = 0.0
	buf[o + 2] = s
	buf[o + 3] = p.x
	buf[o + 4] = 0.0
	buf[o + 5] = scale_k
	buf[o + 6] = 0.0
	buf[o + 7] = 0.0
	buf[o + 8] = -s
	buf[o + 9] = 0.0
	buf[o + 10] = c
	buf[o + 11] = p.y
	buf[o + 12] = phase
	buf[o + 13] = st
	buf[o + 14] = spd
	buf[o + 15] = die
	counts[t] += 1


func _corpses(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for c in corpses:
		c["t"] = float(c["t"]) + delta
		var tt := float(c["t"])
		if tt >= CORPSE_S:
			continue
		keep.append(c)
		var p: Vector2 = c["pos"]
		if world.fog.visible(p):
			_write(int(c["type"]), p, float(c["dir"]), 0.0, 0.0, 0.0, maxf(0.01, tt / CORPSE_S))
	corpses = keep
