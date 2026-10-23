class_name Grid
extends RefCounted
## Сетка 2 м (tech spec §2.2): рельеф из navgrid.png + занятость нашими постройками.
## terrain: 0 — непроходимо (дома, вода), 128 — бездорожье, 200 — тротуар, 255 — дорога.

const WALKABLE_MIN := 100
const ROAD := 255
## block: 0 — свободно, 1 — стоит постройка (блок для всех), 2 — ворота (блок только для зомби)
const BLOCK_NONE := 0
const BLOCK_ALL := 1
const BLOCK_ZOMBIE := 2

var w: int = 0
var h: int = 0
var cell: float = 2.0
var origin: Vector2 = Vector2.ZERO
var terrain: PackedByteArray
var occ: PackedInt32Array      # id постройки в клетке или -1 (для размещения и атак по стенам)
var block: PackedByteArray
## Версия: растёт при любом изменении проходимости — потребители (flow-field, пути) пересчитываются.
var version: int = 0


func init_empty(width: int, height: int, cell_m: float, org: Vector2, fill: int = 128) -> void:
	w = width
	h = height
	cell = cell_m
	origin = org
	terrain = PackedByteArray()
	terrain.resize(w * h)
	terrain.fill(fill)
	occ = PackedInt32Array()
	occ.resize(w * h)
	occ.fill(-1)
	block = PackedByteArray()
	block.resize(w * h)


func load_image(img: Image, cell_m: float, org: Vector2) -> void:
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	init_empty(img.get_width(), img.get_height(), cell_m, org)
	terrain = img.get_data()


func size_m() -> Vector2:
	return Vector2(w, h) * cell


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.y - origin.y) / cell))


func idx_of(p: Vector2) -> int:
	var cx := floori((p.x - origin.x) / cell)
	var cy := floori((p.y - origin.y) / cell)
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return -1
	return cy * w + cx


func center_of(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func clamp_pos(p: Vector2) -> Vector2:
	return p.clamp(origin + Vector2.ONE * cell, origin + size_m() - Vector2.ONE * cell)


## Проходимость для людей и техники (ворота пропускают своих).
func walkable_i(i: int) -> bool:
	return i >= 0 and terrain[i] >= WALKABLE_MIN and block[i] != BLOCK_ALL


func zombie_walkable_i(i: int) -> bool:
	return i >= 0 and terrain[i] >= WALKABLE_MIN and block[i] == BLOCK_NONE


func walkable(p: Vector2) -> bool:
	return walkable_i(idx_of(p))


func zombie_walkable(p: Vector2) -> bool:
	return zombie_walkable_i(idx_of(p))


func terrain_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and terrain[c.y * w + c.x] >= WALKABLE_MIN


func is_road(p: Vector2) -> bool:
	var i := idx_of(p)
	return i >= 0 and terrain[i] == ROAD


## Постройка занимает прямоугольник клеток. kind — BLOCK_* (мешки с песком не блокируют никого).
func set_rect(r: Rect2i, building_id: int, kind: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var i := y * w + x
			occ[i] = building_id
			block[i] = kind
	version += 1


func clear_rect(r: Rect2i, building_id: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var i := y * w + x
			if occ[i] == building_id:
				occ[i] = -1
				block[i] = BLOCK_NONE
	version += 1


## Прямоугольник свободен для стройки: рельеф проходим и нет наших построек.
func rect_free(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h:
				return false
			var i := y * w + x
			if terrain[i] < WALKABLE_MIN or occ[i] >= 0:
				return false
	return true


## Для стен протяжкой: клетки рельефа-препятствия (трибуны, дома) допускаются — иначе у края не закрыть щель в 1 клетку.
## Нужна хотя бы одна проходимая клетка и ни одной нашей постройки.
func rect_free_partial(r: Rect2i) -> bool:
	var any := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h:
				return false
			var i := y * w + x
			if occ[i] >= 0:
				return false
			if terrain[i] >= WALKABLE_MIN:
				any = true
	return any


## Прямая видимость/проходимость по клеткам (DDA), для сглаживания путей.
func line_walkable(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := ceili(d.length() / (cell * 0.5))
	if steps <= 0:
		return walkable(a)
	var s := d / steps
	var p := a
	for _k in steps + 1:
		if not walkable(p):
			return false
		p += s
	return true


## Ближайшая проходимая точка (спиралью по клеткам). Возвращает исходную, если она проходима.
func nearest_walkable(p: Vector2, max_r: float = 40.0, for_zombie: bool = false) -> Vector2:
	var c := cell_of(p)
	var max_k := ceili(max_r / cell)
	for k in max_k + 1:
		for dy in range(-k, k + 1):
			for dx in range(-k, k + 1):
				if absi(dx) != k and absi(dy) != k:
					continue
				var cc := c + Vector2i(dx, dy)
				if not in_bounds(cc):
					continue
				var i := cc.y * w + cc.x
				if (zombie_walkable_i(i) if for_zombie else walkable_i(i)):
					return center_of(cc) if k > 0 else p
	return p
