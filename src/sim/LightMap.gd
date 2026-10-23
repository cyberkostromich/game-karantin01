class_name LightMap
extends RefCounted
## Растр освещённости ночью (прожекторы, GDD §9): дешёвая проверка «зомби/юнит в свете» для тысяч зомби.

var origin: Vector2
var cell: float = 4.0
var w: int = 0
var h: int = 0
var lit_cells := PackedByteArray()
var circles: Array[Vector3] = []


func setup(org: Vector2, size: Vector2, cell_m: float) -> void:
	origin = org
	cell = cell_m
	w = ceili(size.x / cell)
	h = ceili(size.y / cell)
	lit_cells.resize(w * h)
	lit_cells.fill(0)


## circles: (x, z, радиус) — перерисовать целиком (вызывается при изменении питания прожекторов).
func rebuild(new_circles: Array[Vector3]) -> void:
	if new_circles == circles:
		return
	circles = new_circles.duplicate()
	lit_cells.fill(0)
	for c in circles:
		var r := c.z
		var x0 := maxi(0, floori((c.x - r - origin.x) / cell))
		var x1 := mini(w - 1, floori((c.x + r - origin.x) / cell))
		var y0 := maxi(0, floori((c.y - r - origin.y) / cell))
		var y1 := mini(h - 1, floori((c.y + r - origin.y) / cell))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := origin + Vector2(x + 0.5, y + 0.5) * cell
				if p.distance_to(Vector2(c.x, c.y)) <= r:
					lit_cells[y * w + x] = 1


func lit(p: Vector2) -> bool:
	if circles.is_empty():
		return false
	var x := floori((p.x - origin.x) / cell)
	var y := floori((p.y - origin.y) / cell)
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return lit_cells[y * w + x] != 0
