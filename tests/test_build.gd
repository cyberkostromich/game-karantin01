extends GutTest
## M2-3: размещение, стройка N строителями, ремонт, улучшение стены, зона стройки.


func test_place_checks() -> void:
	var w := TestHelpers.world(160)
	w.economy.res["wood"] = 500.0
	w.economy.res["iron"] = 500.0
	assert_eq(w.buildings.check_place("hq", Vector2i(10, 10), 0), "BUILD_ERR_TYPE")
	assert_eq(w.buildings.check_place("wall_concrete", Vector2i(70, 70), 0), "BUILD_ERR_TECH")
	assert_eq(w.buildings.check_place("tent", Vector2i(78, 78), 0), "BUILD_ERR_BLOCKED", "клетки Штаба заняты")
	assert_eq(w.buildings.check_place("tent", Vector2i(60, 60), 0), "")


func test_builders_finish_construction() -> void:
	var w := TestHelpers.world(160)
	w.economy.res["wood"] = 500.0
	for k in 4:
		TestHelpers.civ(w, Vector2(10 + k, 20))
	var b := w.buildings.place("tent", Vector2i(85, 85), 0, 1)
	assert_not_null(b)
	assert_eq(b.state, Building.State.CONSTRUCTING)
	TestHelpers.steps(w, 20 * 40)
	assert_true(b.complete(), "палатка достроена 4 строителями (прогресс %f)" % b.progress)


func test_wall_blocks_zombies_but_gate_lets_allies() -> void:
	var w := TestHelpers.world(160)
	var wall := w.buildings.place("wall_wood", Vector2i(70, 60), 0, 1, true)
	var gate := w.buildings.place("gate", Vector2i(74, 60), 0, 1, true)
	var pw := wall.rect_m.get_center()
	var pg := gate.rect_m.get_center()
	assert_false(w.grid.zombie_walkable(pw))
	assert_false(w.grid.walkable(pw))
	assert_false(w.grid.zombie_walkable(pg))
	assert_true(w.grid.walkable(pg), "ворота открываются для своих")


func test_repair_and_upgrade() -> void:
	var w := TestHelpers.world(160)
	w.economy.res["wood"] = 500.0
	w.economy.res["iron"] = 500.0
	var wall := w.buildings.place("wall_wood", Vector2i(60, 60), 0, 1, true)
	wall.hp = wall.max_hp * 0.5
	assert_true(w.buildings.start_repair(wall))
	assert_false(w.buildings.start_upgrade(wall), "без технологии бетон недоступен")
	w.tech.done.append("concrete_walls")
	wall.repairing = false
	assert_true(w.buildings.start_upgrade(wall))
	for k in 3:
		TestHelpers.civ(w, Vector2(0, 30 + k))
	TestHelpers.steps(w, 20 * 30)
	assert_eq(wall.type, "wall_concrete")


func test_rotation_cells_and_door() -> void:
	var w := TestHelpers.world(160)
	var bs := w.buildings
	var n := roundi(360.0 / Config.f("rules.build.rotation_step_deg"))
	var f: Array = Config.a("buildings.house.footprint")
	assert_eq(bs.rect_for("house", Vector2i(0, 0), n / 4).size, Vector2i(int(f[1]), int(f[0])), "90° меняет стороны")
	assert_eq(bs.cells_for("house", Vector2i(0, 0), 0).size(), int(f[0]) * int(f[1]), "без поворота — весь прямоугольник")
	var diag := roundi(45.0 / Config.f("rules.build.rotation_step_deg"))
	var cs := bs.cells_for("house", Vector2i(0, 0), diag)
	var r := bs.rect_for("house", Vector2i(0, 0), diag)
	assert_lt(cs.size(), r.get_area(), "под 45° углы ограничивающего прямоугольника свободны")
	assert_almost_eq(float(cs.size()), float(f[0]) * float(f[1]), float(f[0]) + float(f[1]), "площадь ≈ площади контура")
	# дверь поворачивается с фасадом: 0 → юг (+Z), 90° → восток (+X), 180° → север, 270° → запад
	var dirs := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]
	for q in 4:
		var b := bs.place("house", Vector2i(40 + q * 20, 40), q * n / 4, 1, true)
		assert_gt((b.door - b.pos).normalized().dot(dirs[q]), 0.9, "дверь при повороте %d" % q)
