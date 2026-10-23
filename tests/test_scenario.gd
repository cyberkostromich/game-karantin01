extends GutTest
## M4-3..M4-5: рейды, гнёзда, события дней, победа/поражение/счёт.


func test_raid_loot_without_combat() -> void:
	var w := TestHelpers.world(160)
	var p := MapPoi.new()
	p.type = "grocery"
	p.pos = Vector2(40, 40)
	w.map._add_poi(p)
	w.agents.spawn_unit("assault", 1, Vector2(41, 40))
	var food := float(w.economy.res["food"])
	TestHelpers.steps(w, int(Config.f("buildings.map_poi.grocery.search_s") / w.dt) + 30)
	assert_true(p.done)
	assert_gt(float(w.economy.res["food"]), food)


func test_raid_blocked_by_zombie_nearby() -> void:
	var w := TestHelpers.world(160)
	var p := MapPoi.new()
	p.type = "pharmacy"
	p.pos = Vector2(40, 40)
	w.map._add_poi(p)
	w.agents.spawn_unit("assault", 1, Vector2(41, 40))
	var z := w.zombies.spawn(0, Vector2(44, 40))
	w.zombies.hp[z] = 1e9  # не убить
	TestHelpers.steps(w, 20 * 15)
	assert_false(p.done, "рейд только «без боя»")


func test_nest_spawns_and_dies() -> void:
	var w := TestHelpers.world(200)
	var n := MapPoi.new()
	n.type = "nest"
	n.key = "metro_test"
	n.pos = Vector2(-80, -80)
	n.hp = Config.f("zombies.nest.hp")
	n.max_hp = n.hp
	n.radius = 5.0
	w.map._add_poi(n)
	w.map.nests.append(n)
	TestHelpers.steps(w, int(Config.f("zombies.nest.spawn.interval_s") / w.dt) + 5)
	assert_gt(w.zombies.alive_n, 0, "гнездо спавнит ходоков")
	w.map.damage_nest(n, 1e9)
	assert_false(n.alive)
	assert_eq(int(w.score.get("nests", 0)), 1)


func test_victory_requires_quota() -> void:
	var w := TestHelpers.world(160)
	for k in Config.i("rules.victory.evacuation_quota_people"):
		TestHelpers.civ(w, Vector2(k * 0.5, 5))
	w.scenario.on_final_dawn()
	assert_true(w.scenario.over)
	assert_true(w.scenario.victory)
	assert_gt(int(w.scenario.final_score["total"]), 0)


func test_defeat_without_quota() -> void:
	var w := TestHelpers.world(160)
	TestHelpers.civ(w, Vector2(0, 5))
	w.scenario.on_final_dawn()
	assert_false(w.scenario.victory)
	assert_eq(String(w.scenario.final_score["reason"]), "DEFEAT_QUOTA")


func test_hq_destroyed_is_defeat() -> void:
	var w := TestHelpers.world(160)
	w.scenario.checks_enabled = true
	TestHelpers.civ(w, Vector2(0, 5))
	w.buildings.destroy(w.buildings.hq)
	TestHelpers.steps(w, 25)
	assert_true(w.scenario.over)
	assert_eq(String(w.scenario.final_score["reason"]), "DEFEAT_HQ")


func test_clock_cycles_and_finishes() -> void:
	var w := TestHelpers.world(120)
	w.clock.total_days = 2
	TestHelpers.civ(w, Vector2(0, 5))
	var total := int(w.clock.day_length() * 2.5 / w.dt)
	for k in total:
		w.step()
		if w.scenario.over:
			break
	assert_true(w.clock.finished, "рассвет после последней ночи — эвакуация")
	assert_true(w.scenario.over)


func test_migration_night_from_events() -> void:
	var w := TestHelpers.world(120)
	assert_eq(w.scenario.migration_night, 7)
