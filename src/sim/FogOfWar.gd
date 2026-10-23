class_name FogOfWar
extends RefCounted
## Туман войны, общий для команды (tech spec §3.6): 0 — не открыто, EXPLORED — открыто, VISIBLE — видно сейчас.
## display — готовый байтовый растр для текстуры тумана во view.

const UNSEEN := 0
const EXPLORED := 110
const VISIBLE := 255

var world: World
var origin: Vector2
var cell: float = 4.0
var w: int = 0
var h: int = 0
var display := PackedByteArray()
var _lit := PackedInt32Array()
var _circles: Dictionary = {}        # радиус в клетках → PackedInt32Array смещений (dx,dy)
var version: int = 0
var building_vision: float = 15.0
var enabled: bool = true


func setup(wd: World) -> void:
	world = wd
	origin = wd.grid.origin
	cell = Config.f("rules.sim_tuning.fog_cell_m")
	var sz := wd.grid.size_m()
	w = ceili(sz.x / cell)
	h = ceili(sz.y / cell)
	display.resize(w * h)
	display.fill(UNSEEN)
	building_vision = Config.f("rules.sim_tuning.building_vision_m")


func _offsets(rc: int) -> PackedInt32Array:
	if _circles.has(rc):
		return _circles[rc]
	var o := PackedInt32Array()
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			if dx * dx + dy * dy <= rc * rc:
				o.append(dx)
				o.append(dy)
	_circles[rc] = o
	return o


func update() -> void:
	if not enabled:
		return
	for i in _lit:
		display[i] = EXPLORED
	_lit.clear()
	for a in world.agents.list:
		if not a.alive:
			continue
		if a.is_unit():
			_stamp(a.pos, world.mods.vision_of(a) + _container_vision(a))
		elif a.rescued and not a.hidden:
			_stamp(a.pos, a.vision * 0.5)
	for b in world.buildings.list:
		if b.complete():
			_stamp(b.pos, float(b.data().get("vision", building_vision)))
	for r in world.abilities.reveals:
		_stamp(r["pos"], float(r["r"]))
	version += 1


## Юнит в вышке видит дальше (buildings.tower.vision).
func _container_vision(a: Agent) -> float:
	if not a.hidden or a.container < 0:
		return 0.0
	var b := world.buildings.get_building(a.container)
	return float(b.data().get("vision", 0.0)) if b != null else 0.0


func _stamp(p: Vector2, r: float) -> void:
	var cx := int((p.x - origin.x) / cell)
	var cy := int((p.y - origin.y) / cell)
	var o := _offsets(ceili(r / cell))
	var n := o.size()
	var k := 0
	while k < n:
		var x := cx + o[k]
		var y := cy + o[k + 1]
		k += 2
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		var i := y * w + x
		if display[i] != VISIBLE:
			display[i] = VISIBLE
			_lit.append(i)


func reveal_all() -> void:
	display.fill(VISIBLE)
	enabled = false
	version += 1


func visible(p: Vector2) -> bool:
	var x := int((p.x - origin.x) / cell)
	var y := int((p.y - origin.y) / cell)
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return display[y * w + x] == VISIBLE


func explored(p: Vector2) -> bool:
	var x := int((p.x - origin.x) / cell)
	var y := int((p.y - origin.y) / cell)
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return display[y * w + x] != UNSEEN
