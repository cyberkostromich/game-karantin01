extends GutTest
## M2-5: склад, энергосеть с приоритетом отключения, рассвет (еда, мораль, рождения, взросление).


func test_dawn_consumes_food() -> void:
	var w := TestHelpers.world(120)
	for k in 10:
		TestHelpers.civ(w, Vector2(k * 2, 10))
	w.agents.spawn_unit("assault", 1, Vector2(0, 20))
	w.economy.res["food"] = 100.0
	var need := w.economy.daily_food_need()
	assert_almost_eq(need, 10 * 1.0 + 1 * 1.5, 0.001)
	w.economy.on_dawn()
	assert_almost_eq(float(w.economy.res["food"]), 100.0 - need, 0.001)


func test_storage_cap() -> void:
	var w := TestHelpers.world(120)
	w.economy.res["wood"] = 0.0
	w.economy.add("wood", 99999.0)
	assert_eq(float(w.economy.res["wood"]), Config.f("rules.start.storage_cap_hq"))
	w.buildings.place("storage", Vector2i(70, 70), 0, 1, true)
	w.economy.add("wood", 99999.0)
	assert_eq(float(w.economy.res["wood"]), Config.f("rules.start.storage_cap_hq") + Config.f("buildings.storage.storage_cap"))


func test_power_shutdown_by_priority() -> void:
	var w := TestHelpers.world(160)
	# Штаб даёт +5. Мастерская (−3) и Медпункт (−2) и Казарма (−2) = −7 → дефицит 2.
	var ws := w.buildings.place("workshop", Vector2i(60, 60), 0, 1, true)
	var med := w.buildings.place("medpost", Vector2i(100, 60), 0, 1, true)
	var bar := w.buildings.place("barracks", Vector2i(60, 100), 0, 1, true)
	w.economy._update_power(0.5)
	assert_false(ws.powered, "Мастерская отключается первой (GDD §5)")
	assert_true(med.powered)
	assert_true(bar.powered)


func test_morale_housing_and_shortage() -> void:
	var w := TestHelpers.world(120)
	for k in 4:
		TestHelpers.civ(w, Vector2(k * 2, 10))
	w.economy.res["food"] = 1000.0
	w.economy._update_morale()
	assert_true(w.economy.morale_mods.has("housing_ok"), "Штаб даёт жильё на 6")
	w.economy.res["food"] = 0.0
	w.economy._update_morale()
	assert_true(w.economy.morale_mods.has("food_shortage"))


func test_birth_requires_morale_and_food() -> void:
	var w := TestHelpers.world(120)
	w.buildings.place("house", Vector2i(70, 70), 0, 1, true)
	for k in 6:
		TestHelpers.civ(w, Vector2(k * 2, 10))
	w.economy.res["food"] = 400.0
	w.economy.event_morale["test"] = 30.0
	w.economy._update_morale()
	assert_true(w.economy.morale >= 60.0)
	var born := 0
	for k in 40:
		born += w.economy._births()
	assert_gt(born, 0)
	w.economy.event_morale["test"] = -40.0
	w.economy._update_morale()
	assert_eq(w.economy._births(), 0, "при морали < 60 рождений нет")


func test_child_grows_up() -> void:
	var w := TestHelpers.world(120)
	var ch := w.civilians.spawn_child(Vector2(5, 5))
	for k in int(Config.f("rules.birth.child_grows_up_days")):
		w.civilians.grow_children()
	assert_false(ch.is_child)
