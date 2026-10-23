class_name Look
extends RefCounted
## Общие материалы и загрузка моделей (tech spec §6): один палитровый материал на весь мир,
## модели по путям из data/*.json ("models/units/unit_assault.glb" → res://assets/...).

const PALETTE_TEX := "res://assets/textures/palette.png"
const PART_NAMES: PackedStringArray = ["body", "head", "arm_l", "arm_r", "leg_l", "leg_r", "weapon", "shin_l", "shin_r",
	"forearm_l", "forearm_r"]

static var _mats: Dictionary = {}
static var _scenes: Dictionary = {}
static var _merged: Dictionary = {}


static func asset(path: String) -> String:
	return path if path.begins_with("res://") else "res://assets/" + path


static func _shader_mat(key: String, shader_path: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	if key != "water":
		m.set_shader_parameter("palette", load(PALETTE_TEX))
	_mats[key] = m
	return m


static func palette() -> ShaderMaterial:
	return _shader_mat("palette", "res://src/view/shaders/palette.gdshader")


static func palette_double() -> ShaderMaterial:
	return _shader_mat("palette_double", "res://src/view/shaders/palette_double.gdshader")


static func palette_ghost() -> ShaderMaterial:
	return _shader_mat("ghost", "res://src/view/shaders/palette_ghost.gdshader")


static func city() -> ShaderMaterial:
	return _shader_mat("city", "res://src/view/shaders/city.gdshader")


static func water() -> ShaderMaterial:
	return _shader_mat("water", "res://src/view/shaders/water.gdshader")


static func zombie(type: String) -> ShaderMaterial:
	var key := "zombie_" + type
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://src/view/shaders/zombie.gdshader")
	m.set_shader_parameter("palette", load(PALETTE_TEX))
	_mats[key] = m
	return m


static func scene(path: String) -> PackedScene:
	var p := asset(path)
	if not _scenes.has(p):
		_scenes[p] = load(p)
	return _scenes[p]


## Инстанс модели с палитровым материалом на всех мешах.
static func instance(path: String, mat: Material = null) -> Node3D:
	var ps := scene(path)
	if ps == null:
		push_error("Look: нет модели %s" % path)
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	apply_material(n, mat if mat != null else palette())
	return n


static func apply_material(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		apply_material(c, mat)


static func find(n: Node, node_name: String) -> Node3D:
	if n.name == node_name and n is Node3D:
		return n
	for c in n.get_children():
		var r := find(c, node_name)
		if r != null:
			return r
	return null


## Сливает все меши модели в один (для MultiMesh). UV2.x — индекс части (PART_NAMES) для вершинной анимации,
## pivots — позиции узлов-частей в пространстве корня (точки вращения конечностей).
static func merged(path: String) -> Dictionary:
	var p := asset(path)
	if _merged.has(p):
		return _merged[p]
	var root: Node3D = scene(p).instantiate()
	var st := {"verts": PackedVector3Array(), "norms": PackedVector3Array(), "uvs": PackedVector2Array(), "uv2": PackedVector2Array()}
	var pivots := {}
	_collect(root, Transform3D.IDENTITY, -1, st, pivots)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = st["verts"]
	arr[Mesh.ARRAY_NORMAL] = st["norms"]
	arr[Mesh.ARRAY_TEX_UV] = st["uvs"]
	arr[Mesh.ARRAY_TEX_UV2] = st["uv2"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	root.free()
	var out := {"mesh": mesh, "pivots": pivots}
	_merged[p] = out
	return out


static func _collect(n: Node, xf: Transform3D, part: int, st: Dictionary, pivots: Dictionary) -> void:
	var my_xf := xf
	var my_part := part
	if n is Node3D:
		my_xf = xf * (n as Node3D).transform
		var idx := PART_NAMES.find(String(n.name))
		if idx >= 0:
			my_part = idx
			pivots[String(n.name)] = my_xf.origin
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var idx_arr: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var order := idx_arr if not idx_arr.is_empty() else PackedInt32Array(range(v.size()))
			for i in order:
				st["verts"].append(my_xf * v[i])
				st["norms"].append((my_xf.basis * nr[i]).normalized())
				st["uvs"].append(uv[i])
				st["uv2"].append(Vector2(maxi(my_part, 0), 0))
	for c in n.get_children():
		_collect(c, my_xf, my_part, st, pivots)


static func team_color(pid: int) -> Color:
	var cols: Array = Config.a("rules.players.team_colors")
	if pid <= 0 or cols.is_empty():
		return Color(cols[0]) if not cols.is_empty() else Color.WHITE
	return Color(cols[(pid - 1) % cols.size()])


static var _icons: Dictionary = {}


## Иконка 64/128 px из assets/icons/png (для Sprite3D и HUD).
static func icon(id: String, size: int = 64) -> Texture2D:
	var key := "%s@%d" % [id, size]
	if not _icons.has(key):
		var p := "res://assets/icons/png/%d/%s.png" % [size, id]
		_icons[key] = load(p) if ResourceLoader.exists(p) else null
	return _icons[key]


static func unlit(color: Color, no_depth := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = no_depth
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
