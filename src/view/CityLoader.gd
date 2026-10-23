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
	_backdrop()
	var c0 := Vector2i(floori(bounds.position.x / chunk_m), floori(bounds.position.y / chunk_m))
	var c1 := Vector2i(floori(bounds.end.x / chunk_m), floori(bounds.end.y / chunk_m))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var p := dir.path_join("chunks/chunk_%d_%d.glb" % [cx, cz])
			if ResourceLoader.exists(p):
				pending.append(p)
	total = pending.size()


## Ориентиры за пределами карты (силуэт МГУ на горизонте) и на POI без своей модели в OSM.
func _backdrop() -> void:
	var arr: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pois.json")))
	if not (arr is Array):
		return
	for p: Dictionary in arr:
		var model := ""
		match String(p["id"]):
			"mgu": model = "models/city/city_mgu.glb"
			"radio_tower": model = "models/city/city_radio_mast.glb"
		if model == "":
			continue
		var n := Look.instance(model)
		n.position = Vector3(float(p["x"]), 0, float(p["z"]))
		if String(p["id"]) == "mgu":
			n.rotation.y = deg_to_rad(-30)
		add_child(n)


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


## Порциями в главном потоке: фоновая загрузка glTF-сцен параллельно с загрузкой моделей
## в главном потоке приводила к падению движка (docs/decisions.md D-9).
func poll(budget_ms: int = 40) -> void:
	var t0 := Time.get_ticks_msec()
	while not pending.is_empty() and Time.get_ticks_msec() - t0 < budget_ms:
		var p := pending[pending.size() - 1]
		pending.remove_at(pending.size() - 1)
		_add_chunk(load(p) as PackedScene)
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
