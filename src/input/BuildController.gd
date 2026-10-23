class_name BuildController
extends Node3D
## Призрак постройки (M2-3): снап к сетке 2 м, R — поворот, зелёный/красный по проверке клеток,
## стены и мешки — протяжкой (сначала по главной оси, затем по второй — «Г»). Shift — строить ещё.

var game: Node
var type: String = ""
var rot: int = 0
var ghosts: Array[Node3D] = []
var _drag_from := Vector2i(-99999, -99999)
var _dragging := false
var _cells: Array[Vector2i] = []
var _radius_ring: MeshInstance3D


func active() -> bool:
	return type != ""


func begin(t: String) -> void:
	cancel()
	type = t
	rot = 0
	_radius_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	var r := Config.f("rules.base.build_radius_m")
	tm.inner_radius = r - 0.6
	tm.outer_radius = r
	tm.rings = 96
	tm.ring_segments = 3
	_radius_ring.mesh = tm
	_radius_ring.scale = Vector3(1, 0.02, 1)
	_radius_ring.material_override = Look.unlit(Color(1.0, 0.42, 0.12, 0.6))
	var hq: Vector2 = game.world.map.hq_pos
	_radius_ring.position = Vector3(hq.x, 0.3, hq.y)
	add_child(_radius_ring)


func cancel() -> void:
	type = ""
	_dragging = false
	for g in ghosts:
		g.queue_free()
	ghosts.clear()
	if _radius_ring != null:
		_radius_ring.queue_free()
		_radius_ring = null


func _drag_build() -> bool:
	return bool(Config.opt("buildings.%s.drag_build" % type, false))


func _origin_for(p: Vector2) -> Vector2i:
	var g: Grid = game.world.grid
	var f: Array = Config.a("buildings.%s.footprint" % type)
	var sz := Vector2i(int(f[0]), int(f[1])) if rot % 2 == 0 else Vector2i(int(f[1]), int(f[0]))
	return g.cell_of(p) - sz / 2


func _unhandled_input(ev: InputEvent) -> void:
	if not active():
		return
	if ev is InputEventMouseMotion:
		_update(game.cam.ground_at((ev as InputEventMouseMotion).position))
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if _drag_build():
				_dragging = true
				_drag_from = _origin_for(game.cam.ground_at(mb.position))
				_update(game.cam.ground_at(mb.position))
			else:
				_place(mb.shift_pressed)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and not (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and _dragging:
			_place(mb.shift_pressed)
			_dragging = false
			get_viewport().set_input_as_handled()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		if k.physical_keycode == KEY_R:
			rot = (rot + 1) % 2
			_update(game.cam.ground_at(get_viewport().get_mouse_position()))
			get_viewport().set_input_as_handled()
		elif k.physical_keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()


func _segment_cells(to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _dragging:
		out.append(to)
		return out
	var f: Array = Config.a("buildings.%s.footprint" % type)
	var len_cells := int(f[0])
	var a := _drag_from
	var d := to - a
	# сначала по главной оси, затем по второй
	var horiz := absi(d.x) >= absi(d.y)
	var n1 := absi(d.x if horiz else d.y) / len_cells
	var s1 := signi(d.x if horiz else d.y)
	for k in n1 + 1:
		out.append(a + (Vector2i(k * len_cells * s1, 0) if horiz else Vector2i(0, k * len_cells * s1)))
	var corner := out[-1]
	var rest := (to.y - corner.y) if horiz else (to.x - corner.x)
	var n2 := absi(rest) / len_cells
	var s2 := signi(rest)
	for k in range(1, n2 + 1):
		out.append(corner + (Vector2i(0, k * len_cells * s2) if horiz else Vector2i(k * len_cells * s2, 0)))
	return out.slice(0, 60)


func _rot_for(i: int) -> int:
	if not _dragging or _cells.size() < 2:
		return rot
	# сегмент вдоль Z — повёрнут на 90°
	var d := (_cells[mini(i + 1, _cells.size() - 1)] - _cells[maxi(i - 1, 0)])
	return 1 if absi(d.y) > absi(d.x) else 0


func _update(p: Vector2) -> void:
	_cells = _segment_cells(_origin_for(p))
	while ghosts.size() < _cells.size():
		var gnode := Look.instance(String(Config.g("buildings.%s.model" % type)), Look.palette_ghost())
		add_child(gnode)
		ghosts.append(gnode)
	while ghosts.size() > _cells.size():
		ghosts.pop_back().queue_free()
	var w: World = game.world
	var spent := {}
	for i in _cells.size():
		var r := _rot_for(i)
		var c := _cells[i]
		var rect := w.buildings.rect_for(type, c, r)
		var center := w.grid.origin + (Vector2(rect.position) + Vector2(rect.size) * 0.5) * w.grid.cell
		var g := ghosts[i]
		g.position = Vector3(center.x, 0.05, center.y)
		g.rotation.y = PI * 0.5 * r
		var err := w.buildings.check_place(type, c, r, false)
		if err == "" and not _affordable(spent, i + 1):
			err = "BUILD_ERR_COST"
		_set_ghost(g, 2.0 if err != "" else 1.0)
		if i == 0:
			game.hud.set_hint(tr(err) if err != "" else "")


func _affordable(_spent: Dictionary, n: int) -> bool:
	var cost: Dictionary = Config.d("buildings.%s.cost" % type)
	var total := {}
	for r: String in cost:
		total[r] = float(cost[r]) * n
	return game.world.economy.can_afford(total)


func _set_ghost(n: Node, v: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("ghost", v)
	for c in n.get_children():
		_set_ghost(c, v)


func _place(keep: bool) -> void:
	if _cells.is_empty():
		return
	if _cells.size() == 1:
		game.send({"t": "build", "building": type, "cells": [[_cells[0].x, _cells[0].y]], "rot": _rot_for(0)})
	else:
		# сегменты одной ориентации — одной командой (контракт tech spec §4.2)
		var by_rot := {0: [], 1: []}
		for i in _cells.size():
			(by_rot[_rot_for(i)] as Array).append([_cells[i].x, _cells[i].y])
		for r: int in by_rot:
			if not (by_rot[r] as Array).is_empty():
				game.send({"t": "build", "building": type, "cells": by_rot[r], "rot": r})
	Sfx.play("ui_build")
	if not keep:
		cancel()
		game.hud.set_hint("")
	else:
		_cells.clear()
