class_name MapSystem
extends RefCounted
## Карта из OSM (docs/04_map_moscow.md): ресурсные узлы, POI (лут, подстанция, радиовышка, форт),
## гнёзда в метро, высоты. Данные — assets/city/<map>/*.json, собранные tools/osm_city/build_city.py.

var world: World
var dir: String = ""
var bounds := Rect2()
var pois: Array[MapPoi] = []
var nests: Array[MapPoi] = []
var poi_by_key: Dictionary = {}
var spawns: Array = []
var zones: Dictionary = {}
var arena_center := Vector2.ZERO
var hq_pos := Vector2.ZERO
var gate_pos := Vector2.ZERO
var gate_outer := Vector2.ZERO
var high_ground: Array[Vector3] = []

# ресурсные узлы: деревья (wood) и остовы (iron)
var node_pos := PackedVector2Array()
var node_amount := PackedFloat32Array()
var node_kind := PackedByteArray()      # 0 — дерево, 1 — остов
var node_variant := PackedByteArray()   # модель для view
var node_rot := PackedFloat32Array()
var node_alive := PackedByteArray()
var node_hash := SpatialHash.new()
var node_claims := PackedByteArray()
var nodes_dirty: bool = true            # view пересобирает MultiMesh
var tree_kinds: PackedStringArray = ["linden", "birch", "pine", "poplar"]
var wreck_kinds: PackedStringArray = ["sedan_red", "sedan_white", "sedan_burnt", "truck", "trolleybus"]
var tmp := PackedInt32Array()


func setup(w: World, city_dir: String) -> void:
	world = w
	dir = city_dir


func _json(name: String) -> Variant:
	var txt := FileAccess.get_file_as_string(dir.path_join(name))
	return JSON.parse_string(txt) if txt != "" else null


## Сетка проходимости карты. Отдельно от POI: тесты подсовывают свою сетку.
func load_grid(g: Grid) -> bool:
	var rep: Variant = _json("report.json")
	if rep == null:
		push_error("MapSystem: нет %s/report.json — соберите город tools/osm_city/build_city.py" % dir)
		return false
	var b: Array = rep["bounds_m"]
	bounds = Rect2(Vector2(b[0], b[1]), Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1])))
	var tex: Texture2D = load(dir.path_join("navgrid.png"))
	var img: Image = tex.get_image() if tex != null else Image.load_from_file(dir.path_join("navgrid.png"))
	g.load_image(img, float(rep["cell_m"]), bounds.position)
	return true


func load_content() -> void:
	zones = _json("zones.json") if _json("zones.json") != null else {}
	spawns = _json("spawns.json") if _json("spawns.json") != null else []
	_load_arena()
	_load_nodes()
	_load_pois()


func _load_arena() -> void:
	var off: Array = Config.a("map.safe_zone.hq_offset_m")
	if zones.has("arena"):
		var a: Dictionary = zones["arena"]
		arena_center = Vector2(a["center"][0], a["center"][1])
		gate_pos = Vector2(a["gate"][0], a["gate"][1])
		gate_outer = Vector2(a["gate_outer"][0], a["gate_outer"][1])
	hq_pos = arena_center + Vector2(float(off[0]), float(off[2]))


func _load_nodes() -> void:
	var r: Variant = _json("resources.json")
	if r == null:
		return
	var wood := Config.f("map.resource_nodes_from_osm.tree.wood_per_node")
	var iron := Config.f("map.resource_nodes_from_osm.wreck.iron_per_node")
	for t: Dictionary in r["trees"]:
		_add_node(Vector2(t["x"], t["z"]), wood, 0, maxi(0, tree_kinds.find(String(t["kind"]))), world.rng.randf() * TAU)
	for t: Dictionary in r["wrecks"]:
		var k := String(t["kind"])
		_add_node(Vector2(t["x"], t["z"]), iron, 1, maxi(0, wreck_kinds.find(k)), deg_to_rad(float(t.get("rot", 0))))
	node_claims.resize(node_pos.size())
	node_hash.setup(bounds.position, bounds.size, 16.0)
	node_hash.rebuild(node_pos, node_alive, node_pos.size())
	for l: Dictionary in r["loot"]:
		var p := MapPoi.new()
		p.type = String(l["type"])
		p.pos = Vector2(l["x"], l["z"])
		p.name = String(l.get("name", ""))
		_add_poi(p)


func _add_node(p: Vector2, amount: float, kind: int, variant: int, rot: float) -> void:
	node_pos.append(p)
	node_amount.append(amount)
	node_kind.append(kind)
	node_variant.append(variant)
	node_rot.append(rot)
	node_alive.append(1)


func _load_pois() -> void:
	var arr: Variant = _json("pois.json")
	if arr == null:
		return
	for d: Dictionary in arr:
		if not bool(d.get("in_bounds", true)):
			continue
		var t := String(d["type"])
		var p := MapPoi.new()
		p.key = String(d["id"])
		p.type = t
		p.name = String(d.get("name_ru", ""))
		p.pos = Vector2(float(d.get("wx", d["x"])), float(d.get("wz", d["z"])))
		p.anchor = Vector2(float(d["x"]), float(d["z"]))
		match t:
			"metro_station":
				p.type = "nest"
				p.hp = Config.f("zombies.nest.hp")
				p.max_hp = p.hp
				p.radius = Config.f("rules.sim_tuning.nest_radius_m")
				p.timer = world.rng.randf() * Config.f("zombies.nest.spawn.interval_s")
				_add_poi(p)
				nests.append(p)
				continue
			"high_ground":
				high_ground.append(Vector3(p.anchor.x, p.anchor.y, Config.f("rules.sim_tuning.high_ground_radius_m")))
		_add_poi(p)


func _add_poi(p: MapPoi) -> void:
	p.id = pois.size()
	pois.append(p)
	if p.key != "":
		poi_by_key[p.key] = p


func poi(key: String) -> MapPoi:
	return poi_by_key.get(key)


func nest_by_id(id: int) -> MapPoi:
	if id < 0 or id >= pois.size():
		return null
	var p := pois[id]
	return p if p.type == "nest" else null


func is_high_ground(p: Vector2) -> bool:
	for h in high_ground:
		if p.distance_to(Vector2(h.x, h.y)) <= h.z:
			return true
	return false


func power_bonus() -> float:
	var s := poi("substation")
	return Config.f("buildings.map_poi.substation.power_when_repaired") if s != null and s.done else 0.0


# ------------------------------------------------------------------ ресурсные узлы
func nearest_node(kind: int, near: Vector2, around: Vector2, r: float) -> int:
	node_hash.query(around, r, tmp)
	var best := -1
	var bd := INF
	for i in tmp:
		if node_kind[i] != kind or node_alive[i] == 0 or node_amount[i] <= 0.0 or node_claims[i] >= 2:
			continue
		var d := node_pos[i].distance_squared_to(near)
		if d < bd:
			bd = d
			best = i
	return best


func take_from_node(i: int, amount: float) -> float:
	var got := minf(amount, node_amount[i])
	node_amount[i] -= got
	if node_amount[i] <= 0.0:
		node_alive[i] = 0  # дерево срублено / остов разобран — конечный ресурс (GDD §5)
		nodes_dirty = true
	return got


# ------------------------------------------------------------------ гнёзда
func damage_nest(n: MapPoi, amount: float) -> void:
	if not n.alive:
		return
	n.hp -= amount
	if n.hp <= 0.0:
		n.alive = false
		n.done = true
		var od := Config.d("zombies.nest.on_destroyed")
		world.score_add("nests", 1)
		world.economy.morale_event("nest_" + n.key, float(od["morale"]))
		world.emit("nest_destroyed", [n.id, n.pos])
		world.emit("objective_updated", [n.key, "done"])
