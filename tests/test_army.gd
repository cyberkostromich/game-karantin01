extends GutTest
## M3-1, M1-7: обучение расходует рекрутов, бой убивает зомби, шум выстрелов.


func test_training_consumes_recruits() -> void:
	var w := TestHelpers.world(160)
	w.economy.res["food"] = 500.0
	w.economy.res["iron"] = 500.0
	w.economy.res["wood"] = 500.0
	var bar := w.buildings.place("barracks", Vector2i(60, 60), 0, 1, true)
	assert_eq(w.training.check(bar, "assault", 1), "TRAIN_ERR_RECRUITS")
	var c := TestHelpers.civ(w, Vector2(10, 10))
	assert_eq(w.training.check(bar, "assault", 1), "")
	assert_eq(w.training.check(bar, "medic", 1), "TRAIN_ERR_ALSO_MEDPOST")
	assert_true(w.training.enqueue(bar, "assault", 1))
	TestHelpers.steps(w, int(Config.f("units.assault.train_s") / w.dt) + 40)
	assert_false(c.alive, "мирный стал солдатом")
	var n := 0
	for a in w.agents.list:
		if a.type == "assault":
			n += 1
	assert_eq(n, 1)


func test_doctrine_discount() -> void:
	var w := TestHelpers.world(120)
	var base := Config.d("units.assault.cost")
	var c := w.mods.unit_cost("assault", 1)
	assert_eq(float(c["iron"]), ceilf(float(base["iron"]) * 0.8), "Мотострелки: −20% цены штурмовика")


func test_soldiers_kill_walkers() -> void:
	var w := TestHelpers.world(160)
	for k in 3:
		w.agents.spawn_unit("assault", 1, Vector2(k * 2, 0))
	for k in 6:
		w.zombies.spawn(0, Vector2(k * 2 - 5, 14), ZombieSystem.S.HORDE)
	TestHelpers.steps(w, 20 * 15)
	assert_eq(w.zombies.alive_n, 0, "6 ходоков против 3 штурмовиков")
	assert_false(w.noise.recent.is_empty(), "выстрелы шумят")


func test_tank_needs_tech() -> void:
	var w := TestHelpers.world(160)
	w.economy.res["food"] = 500.0
	w.economy.res["iron"] = 500.0
	var mp := w.buildings.place("motorpool", Vector2i(50, 50), 0, 1, true)
	for k in 3:
		TestHelpers.civ(w, Vector2(10 + k, 10))
	assert_eq(w.training.check(mp, "tank", 1), "TRAIN_ERR_TECH")
	w.tech.done.append("heavy_armor")
	assert_eq(w.training.check(mp, "tank", 1), "")
