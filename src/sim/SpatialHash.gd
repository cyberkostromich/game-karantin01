class_name SpatialHash
extends RefCounted
## Равномерная сетка-хеш для поиска соседей (tech spec §2.2). Перестраивается целиком каждый тик:
## связные списки head/next в Packed-массивах — без аллокаций и без узлов.

var cell: float = 8.0
var inv_cell: float = 0.125
var origin: Vector2
var cw: int = 0
var ch: int = 0
var head: PackedInt32Array
var next: PackedInt32Array
var _pos: PackedVector2Array


func setup(org: Vector2, size: Vector2, cell_m: float) -> void:
	cell = cell_m
	inv_cell = 1.0 / cell_m
	origin = org
	cw = maxi(1, ceili(size.x / cell_m))
	ch = maxi(1, ceili(size.y / cell_m))
	head = PackedInt32Array()
	head.resize(cw * ch)
	head.fill(-1)


## positions[i] участвует, если alive[i] != 0. count — сколько первых слотов смотреть.
func rebuild(positions: PackedVector2Array, alive: PackedByteArray, count: int) -> void:
	_pos = positions
	head.fill(-1)
	if next.size() < count:
		next.resize(count)
	for i in count:
		if alive[i] == 0:
			continue
		var p := positions[i]
		var cx := clampi(int((p.x - origin.x) * inv_cell), 0, cw - 1)
		var cy := clampi(int((p.y - origin.y) * inv_cell), 0, ch - 1)
		var c := cy * cw + cx
		next[i] = head[c]
		head[c] = i


## Индексы в радиусе r вокруг p (дописываются в out, out очищается). max_n ограничивает выдачу.
func query(p: Vector2, r: float, out: PackedInt32Array, max_n: int = 1 << 30) -> void:
	out.clear()
	var r2 := r * r
	var x0 := clampi(int((p.x - r - origin.x) * inv_cell), 0, cw - 1)
	var x1 := clampi(int((p.x + r - origin.x) * inv_cell), 0, cw - 1)
	var y0 := clampi(int((p.y - r - origin.y) * inv_cell), 0, ch - 1)
	var y1 := clampi(int((p.y + r - origin.y) * inv_cell), 0, ch - 1)
	for cy in range(y0, y1 + 1):
		var row := cy * cw
		for cx in range(x0, x1 + 1):
			var i := head[row + cx]
			while i != -1:
				if _pos[i].distance_squared_to(p) <= r2:
					out.append(i)
					if out.size() >= max_n:
						return
				i = next[i]


## Ближайший индекс в радиусе r (или -1).
func nearest(p: Vector2, r: float) -> int:
	var best := -1
	var best_d := r * r
	var x0 := clampi(int((p.x - r - origin.x) * inv_cell), 0, cw - 1)
	var x1 := clampi(int((p.x + r - origin.x) * inv_cell), 0, cw - 1)
	var y0 := clampi(int((p.y - r - origin.y) * inv_cell), 0, ch - 1)
	var y1 := clampi(int((p.y + r - origin.y) * inv_cell), 0, ch - 1)
	for cy in range(y0, y1 + 1):
		var row := cy * cw
		for cx in range(x0, x1 + 1):
			var i := head[row + cx]
			while i != -1:
				var d := _pos[i].distance_squared_to(p)
				if d <= best_d:
					best_d = d
					best = i
				i = next[i]
	return best


## k ближайших (простая вставка — k маленькое).
func k_nearest(p: Vector2, r: float, k: int, out: PackedInt32Array) -> void:
	query(p, r, out)
	if out.size() <= k:
		return
	var arr: Array = Array(out)
	arr.sort_custom(func(a: int, b: int) -> bool: return _pos[a].distance_squared_to(p) < _pos[b].distance_squared_to(p))
	out.clear()
	for j in k:
		out.append(arr[j])
