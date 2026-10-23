class_name ResourceNodesView
extends Node3D
## Деревья и остовы машин — MultiMesh по плиткам 256 м (отсечение камерой) и по моделям.
## Пересобирается, когда sim помечает узлы выработанными (MapSystem.nodes_dirty).

const TILE := 256.0
const TREE_MODELS: PackedStringArray = ["models/props/prop_tree_linden.glb", "models/props/prop_tree_birch.glb",
	"models/props/prop_tree_pine.glb", "models/props/prop_tree_poplar.glb"]
const WRECK_MODELS: PackedStringArray = ["models/props/prop_wreck_sedan_red.glb", "models/props/prop_wreck_sedan_white.glb",
	"models/props/prop_wreck_sedan_burnt.glb", "models/props/prop_wreck_truck.glb", "models/props/prop_wreck_trolleybus.glb"]

var world: World
var meshes: Array[Mesh] = []
var tiles: Dictionary = {}   # Vector2i → Array[MultiMeshInstance3D] по моделям


func setup(w: World) -> void:
	world = w
	for p in TREE_MODELS + WRECK_MODELS:
		meshes.append(Look.merged(p)["mesh"])
	rebuild()


func _model_index(i: int) -> int:
	var m := world.map
	return (m.node_variant[i] % TREE_MODELS.size()) if m.node_kind[i] == 0 else TREE_MODELS.size() + (m.node_variant[i] % WRECK_MODELS.size())


func rebuild() -> void:
	var m := world.map
	m.nodes_dirty = false
	var groups := {}   # Vector3i(tile.x, tile.y, model) → PackedFloat32Array
	for i in m.node_pos.size():
		if m.node_alive[i] == 0:
			continue
		var p := m.node_pos[i]
		var key := Vector3i(floori(p.x / TILE), floori(p.y / TILE), _model_index(i))
		if not groups.has(key):
			groups[key] = PackedFloat32Array()
		var b: PackedFloat32Array = groups[key]
		var rot := m.node_rot[i]
		var s := 0.85 + fmod(float(i) * 0.37, 0.35) if m.node_kind[i] == 0 else 1.0
		var c := cos(rot) * s
		var sn := sin(rot) * s
		b.append_array([c, 0.0, sn, p.x, 0.0, s, 0.0, 0.0, -sn, 0.0, c, p.y])
	for k: Vector2i in tiles:
		for mmi: MultiMeshInstance3D in tiles[k]:
			mmi.queue_free()
	tiles.clear()
	for key: Vector3i in groups:
		var buf: PackedFloat32Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.z]
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Look.palette()
		mmi.visibility_range_end = 800.0
		add_child(mmi)
		var tk := Vector2i(key.x, key.y)
		if not tiles.has(tk):
			tiles[tk] = []
		tiles[tk].append(mmi)


func _process(_delta: float) -> void:
	if world != null and world.map.nodes_dirty:
		rebuild()
