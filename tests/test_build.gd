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
