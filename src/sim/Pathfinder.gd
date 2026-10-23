class_name Pathfinder
extends RefCounted
## Пути для военных и мирных: AStarGrid2D (нативный A*) на грубой сетке 2×2 клетки (4 м)
## + сглаживание по мелкой сетке. Отклонение от tech spec §3.2 (NavigationServer3D) — см. docs/decisions.md D-3:
## sim должен работать headless и детерминированно, а навмеш города на 3.4 км печётся слишком долго.

var grid: Grid
var astar := AStarGrid2D.new()
var scale: int = 2
var cw: int = 0
var ch: int = 0
var smooth_lookahead: int = 12


func setup(g: Grid, coarse_scale: int, lookahead: int) -> void:
	grid = g
	scale = coarse_scale
	smooth_lookahead = lookahead
	cw = ceili(float(g.w) / scale)
	ch = ceili(float(g.h) / scale)
	astar.region = Rect2i(0, 0, cw, ch)
	astar.cell_size = Vector2.ONE * g.cell * scale
	astar.offset = g.origin + astar.cell_size * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	update_rect(Rect2i(0, 0, g.w, g.h))


## Пересчитать грубые клетки, покрывающие прямоугольник мелких (после стройки/сноса).
func update_rect(fine: Rect2i) -> void:
	var c0 := Vector2i(floori(float(fine.position.x) / scale), floori(float(fine.position.y) / scale))
	var c1 := Vector2i(ceili(float(fine.end.x) / scale), ceili(float(fine.end.y) / scale))
	for cy in range(maxi(c0.y, 0), mini(c1.y, ch)):
		for cx in range(maxi(c0.x, 0), mini(c1.x, cw)):
			astar.set_point_solid(Vector2i(cx, cy), not _coarse_walkable(cx, cy))


func _coarse_walkable(cx: int, cy: int) -> bool:
	var ok := 0
	var total := 0
	for dy in scale:
		for dx in scale:
			var x := cx * scale + dx
			var y := cy * scale + dy
			if x >= grid.w or y >= grid.h:
				continue
			total += 1
			var i := y * grid.w + x
			if grid.block[i] == Grid.BLOCK_ALL:
				return false  # стены тонкие (1 клетка) — не даём путям «просачиваться» сквозь них
			if grid.terrain[i] >= Grid.WALKABLE_MIN:
				ok += 1
	return ok * 4 >= total * 3


func coarse_of(p: Vector2) -> Vector2i:
	var c := grid.cell_of(p)
	return Vector2i(clampi(c.x / scale, 0, cw - 1), clampi(c.y / scale, 0, ch - 1))


func _nearest_open(c: Vector2i, max_k: int = 12) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for k in range(1, max_k + 1):
		for dy in range(-k, k + 1):
			for dx in range(-k, k + 1):
				if absi(dx) != k and absi(dy) != k:
					continue
				var cc := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(cc) and not astar.is_point_solid(cc):
					return cc
	return c


## Путь из точек в метрах (без стартовой точки). Пусто — пути нет. Недостижимая цель → ближайшая достижимая.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if grid.line_walkable(from, to):
		out.append(to)
		return out
	var a := _nearest_open(coarse_of(from))
	var b := _nearest_open(coarse_of(to))
	if astar.is_point_solid(a) or astar.is_point_solid(b):
		return out
	var ids := astar.get_id_path(a, b, true)
	if ids.is_empty():
		return out
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(astar.get_point_position(id))
	if ids[-1] == b and grid.walkable(to):
		pts[-1] = to
	return _smooth(from, pts)


## Строковое «натягивание»: из текущей точки прыгаем к самой дальней видимой (не дальше lookahead).
func _smooth(from: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cur := from
	var i := 0
	var n := pts.size()
	while i < n:
		var best := i
		var j := mini(n - 1, i + smooth_lookahead)
		while j > i:
			if grid.line_walkable(cur, pts[j]):
				best = j
				break
			j -= 1
		if best == i and not grid.line_walkable(cur, pts[i]):
			# первый узел грубой сетки не виден напрямую: идём через ближайшую проходимую точку
			var mid := grid.nearest_walkable(cur.lerp(pts[i], 0.5), 6.0)
			if grid.line_walkable(cur, mid):
				out.append(mid)
				cur = mid
		cur = pts[best]
		out.append(cur)
		i = best + 1
	return out
