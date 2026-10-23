class_name FlowField
extends RefCounted
## Поле направлений орды к цели (Штаб) в окне вокруг цели (tech spec §3.2).
## Наши стены проходимы с «ценой атаки»: если путь закрыт, поле ведёт к стене — зомби её ломают.
## Пересчёт — целиком в фоновом потоке (WorkerThreadPool) при изменении сетки; старое поле живёт до замены.
## За пределами окна зомби идут напрямую к центру окна (ZombieSystem).

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const NONE := 255

var grid: Grid
var center: Vector2
var radius_cells: int = 0
var ww: int = 0
var x0: int = 0
var y0: int = 0
var wall_cost: int = 80
var dir: PackedByteArray        # направление для каждой клетки окна
var dist: PackedInt32Array
var built_version: int = -1
var _task: int = -1
var _pending: Dictionary = {}
var _dir_vec: PackedVector2Array


func setup(g: Grid, c: Vector2, radius_m: float, wall_cost_mult: float) -> void:
	grid = g
	center = c
	radius_cells = ceili(radius_m / g.cell)
	ww = radius_cells * 2 + 1
	var cc := g.cell_of(c)
	x0 = cc.x - radius_cells
	y0 = cc.y - radius_cells
	wall_cost = int(10.0 * wall_cost_mult)
	dir = PackedByteArray()
	dir.resize(ww * ww)
	dir.fill(NONE)
	_dir_vec = PackedVector2Array()
	for d in DIRS:
		_dir_vec.append(Vector2(d).normalized())


func is_ready() -> bool:
	return built_version >= 0


## Вызывать каждый тик: запускает пересчёт при изменении сетки и забирает готовый результат.
func poll(async: bool = true) -> void:
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply_pending()
	if built_version != grid.version:
		var job := _snapshot()
		if async:
			_task = WorkerThreadPool.add_task(_compute.bind(job))
		else:
			_compute(job)
			_apply_pending()


func compute_now() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply_pending()
	built_version = -2
	poll(false)


func _apply_pending() -> void:
	if _pending.is_empty():
		return
	dir = _pending["dir"]
	dist = _pending["dist"]
	built_version = _pending["version"]
	_pending = {}


## Копия входа для потока: стоимость клетки (0 — стена мира, 10 — проход, wall_cost — наша постройка).
func _snapshot() -> Dictionary:
	var cost := PackedByteArray()
	cost.resize(ww * ww)
	for wy in ww:
		var gy := y0 + wy
		for wx in ww:
			var gx := x0 + wx
			var c := 0
			if gx >= 0 and gy >= 0 and gx < grid.w and gy < grid.h:
				var i := gy * grid.w + gx
				if grid.terrain[i] >= Grid.WALKABLE_MIN:
					c = 1 if grid.block[i] == Grid.BLOCK_NONE else 2
			cost[wy * ww + wx] = c
	return {"cost": cost, "version": grid.version, "target": Vector2i(radius_cells, radius_cells)}


## Дейкстра с корзинами (Dial): веса целые — 10 прямо, 14 по диагонали, × цену атаки для постройки.
func _compute(job: Dictionary) -> void:
	var cost: PackedByteArray = job["cost"]
	var n := ww * ww
	var d := PackedInt32Array()
	d.resize(n)
	d.fill(0x3fffffff)
	var max_edge := 14 * maxi(wall_cost, 10) / 10 + 1
	var nb := max_edge + 1
	var buckets: Array[PackedInt32Array] = []
	for _k in nb:
		buckets.append(PackedInt32Array())
	var t: Vector2i = job["target"]
	var ti := t.y * ww + t.x
	d[ti] = 0
	buckets[0].append(ti)
	var cur := 0
	var pending := 1
	var empty_run := 0
	while pending > 0:
		var bi := cur % nb
		var b := buckets[bi]
		if b.is_empty():
			cur += 1
			empty_run += 1
			if empty_run > nb:
				break
			continue
		empty_run = 0
		buckets[bi] = PackedInt32Array()
		pending -= b.size()
		for idx in b:
			if d[idx] != cur:
				continue
			var cx := idx % ww
			var cy := idx / ww
			for k in 8:
				var nx := cx + DIRS[k].x
				var ny := cy + DIRS[k].y
				if nx < 0 or ny < 0 or nx >= ww or ny >= ww:
					continue
				var ni := ny * ww + nx
				var c := cost[ni]
				if c == 0:
					continue
				var step := 14 if (k & 1) == 1 else 10
				if c == 2:
					step = step * wall_cost / 10
				elif (k & 1) == 1 and (cost[cy * ww + nx] == 0 or cost[ny * ww + cx] == 0):
					continue  # не срезаем углы домов
				var nd := cur + step
				if nd < d[ni]:
					d[ni] = nd
					buckets[nd % nb].append(ni)
					pending += 1
		cur += 1
	_pending = {"dir": _directions(d, cost), "dist": d, "version": job["version"]}


func _directions(d: PackedInt32Array, cost: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(ww * ww)
	out.fill(NONE)
	for cy in ww:
		for cx in ww:
			var i := cy * ww + cx
			var best := d[i]
			var bk := NONE
			for k in 8:
				var nx := cx + DIRS[k].x
				var ny := cy + DIRS[k].y
				if nx < 0 or ny < 0 or nx >= ww or ny >= ww:
					continue
				var nd := d[ny * ww + nx]
				if nd < best:
					best = nd
					bk = k
			out[i] = bk
	return out


## Единичный вектор движения для точки или ZERO (вне окна / нет пути / в цели).
func dir_at(p: Vector2) -> Vector2:
	var c := grid.cell_of(p)
	var wx := c.x - x0
	var wy := c.y - y0
	if wx < 0 or wy < 0 or wx >= ww or wy >= ww:
		return Vector2.ZERO
	var k := dir[wy * ww + wx]
	return Vector2.ZERO if k == NONE else _dir_vec[k]


func in_window(p: Vector2) -> bool:
	var c := grid.cell_of(p)
	return c.x >= x0 and c.y >= y0 and c.x < x0 + ww and c.y < y0 + ww


## Расстояние по полю в метрах (для тестов и приоритизации) или -1.
func distance_at(p: Vector2) -> float:
	if dist.is_empty() or not in_window(p):
		return -1.0
	var c := grid.cell_of(p)
	var v := dist[(c.y - y0) * ww + (c.x - x0)]
	return -1.0 if v >= 0x3fffffff else v * grid.cell / 10.0
