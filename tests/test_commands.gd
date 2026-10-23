extends GutTest
## M5-2 / tech spec §7: одинаковые команды с одинаковым сидом дают одинаковое состояние (хост-детерминизм).


func _run(seed_v: int) -> Array:
	var w := TestHelpers.world(160, 1, seed_v)
	w.economy.res["wood"] = 500.0
	var u := w.agents.spawn_unit("assault", 1, Vector2(0, 10))
	for k in 30:
		w.zombies.spawn(0, Vector2(randi_range(-60, 60) if false else k * 3 - 45, 60))
	w.commands.push({"t": "move", "pid": 1, "units": [u.id], "pos": [20.0, 40.0], "amove": true})
	w.commands.push({"t": "build", "pid": 1, "building": "wall_wood", "cells": [[60, 60], [62, 60]], "rot": 0})
	TestHelpers.steps(w, 400)
	var zs := PackedVector2Array()
	for i in w.zombies.count:
		if w.zombies.alive[i] == 1:
			zs.append(w.zombies.pos[i].snapped(Vector2(0.001, 0.001)))
	return [u.pos.snapped(Vector2(0.001, 0.001)), zs, w.buildings.list.size(), w.zombies.alive_n]


func test_deterministic_host_apply() -> void:
	var a := _run(42)
	var b := _run(42)
	assert_eq(a[0], b[0])
	assert_eq(a[2], b[2])
	assert_eq(a[3], b[3])
	assert_eq(a[1], b[1])


func test_foreign_units_ignored_in_coop() -> void:
	var w := TestHelpers.world(160, 2)
	var u := w.agents.spawn_unit("assault", 2, Vector2(0, 10))
	w.commands.push({"t": "move", "pid": 1, "units": [u.id], "pos": [30.0, 30.0]})
	w.step()
	assert_false(u.moving, "игрок 1 не командует юнитом игрока 2")
