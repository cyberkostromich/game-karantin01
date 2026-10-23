class_name Selection
extends RefCounted
## Текущее выделение игрока: юниты, мирные, одна постройка или один объект карты.

signal changed

var units: Array[int] = []
var civs: Array[int] = []
var building: int = -1
var poi: int = -1
var groups: Dictionary = {}   # 1..9 → Array[int]


func clear() -> void:
	units.clear()
	civs.clear()
	building = -1
	poi = -1
	changed.emit()


func is_empty() -> bool:
	return units.is_empty() and civs.is_empty() and building < 0 and poi < 0


func set_agents(u: Array[int], c: Array[int], add := false) -> void:
	if not add:
		units.clear()
		civs.clear()
	building = -1
	poi = -1
	for id in u:
		if not units.has(id):
			units.append(id)
	for id in c:
		if not civs.has(id):
			civs.append(id)
	changed.emit()


func set_building(id: int) -> void:
	units.clear()
	civs.clear()
	poi = -1
	building = id
	changed.emit()


func set_poi(id: int) -> void:
	units.clear()
	civs.clear()
	building = -1
	poi = id
	changed.emit()


## Убрать мёртвых/исчезнувших (вызывается раз в кадр).
func prune(world: World) -> void:
	var before := units.size() + civs.size()
	units = units.filter(func(id: int) -> bool: return world.agents.get_agent(id) != null)
	civs = civs.filter(func(id: int) -> bool: return world.agents.get_agent(id) != null)
	var gone := building >= 0 and world.buildings.get_building(building) == null
	if gone:
		building = -1
	if gone or units.size() + civs.size() != before:
		changed.emit()


func all_agents() -> Array[int]:
	var out: Array[int] = []
	out.append_array(units)
	out.append_array(civs)
	return out
