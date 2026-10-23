class_name CityLoader
extends Node3D
## Грузит город, собранный tools/osm_city: чанки 128 м (фоновая загрузка), ориентиры, подложку.
## Деревья и остовы — ResourceNodesView (это ресурсные узлы sim, они исчезают при выработке).

signal progress_changed(frac: float)
signal loaded

var dir: String
var pending: PackedStringArray = []
var total: int = 0
var view_range: float = 900.0
var _chunks_root := Node3D.new()


func start(city_dir: String, bounds: Rect2, chunk_m: float) -> void:
	dir = city_dir
	_chunks_root.name = "Chunks"
	add_child(_chunks_root)
	_ground(bounds)
	for name in ["arena", "fortress"]:
		var p := dir.path_join("landmarks/%s.glb" % name)
		if ResourceLoader.exists(p):
			var n: Node3D = (load(p) as PackedScene).instantiate()
			n.name = name.capitalize()
			Look.apply_material(n, Look.palette_double())
			add_child(n)
	var c0 := Vector2i(floori(bounds.position.x / chunk_m), floori(bounds.position.y / chunk_m))
	var c1 := Vector2i(floori(bounds.end.x / chunk_m), floori(bounds.end.y / chunk_m))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var p := dir.path_join("chunks/chunk_%d_%d.glb" % [cx, cz])
			if ResourceLoader.exists(p):
				pending.append(p)
				ResourceLoader.load_threaded_request(p, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE)
	total = pending.size()


## Подложка шире карты, чтобы край мира не был пустотой.
func _ground(bounds: Rect2) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = bounds.size + Vector2(3000, 3000)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("4e6a38").darkened(0.15)
	m.roughness = 1.0
	mi.material_override = m
	mi.position = Vector3(bounds.get_center().x, -0.08, bounds.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func is_done() -> bool:
	return pending.is_empty()


func poll(budget: int = 24) -> void:
	var done := 0
	var i := 0
	while i < pending.size() and done < budget:
		var p := pending[i]
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_add_chunk(ResourceLoader.load_threaded_get(p) as PackedScene)
			pending.remove_at(i)
			done += 1
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("CityLoader: не загрузился %s" % p)
			pending.remove_at(i)
		else:
			i += 1
	progress_changed.emit(1.0 - float(pending.size()) / maxf(1.0, total))
	if pending.is_empty():
		loaded.emit()


func _add_chunk(ps: PackedScene) -> void:
	if ps == null:
		return
	var n: Node3D = ps.instantiate()
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		match String(mi.name):
			"buildings":
				mi.material_override = Look.city()
				mi.visibility_range_end = view_range
			"water":
				mi.material_override = Look.water()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mi.material_override = Look.palette_double()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = view_range
	_chunks_root.add_child(n)
