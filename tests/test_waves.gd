extends GutTest
## M2-7 / D-15: формулы waves.json, множители игроков, поток орды по дням.


func test_formula_values() -> void:
	var w := TestHelpers.world(120)
	var wd := w.waves
	# walker: a + b * n^p = 20 + 12 * 1^1.35 = 32
	assert_eq(wd.base_count("walker", 1), 32)
	assert_eq(wd.base_count("walker", 12), int(round(20 + 12 * pow(12, 1.35))))
	assert_eq(wd.base_count("runner", 1), 0)
	assert_eq(wd.base_count("runner", 2), int(round(2 * pow(1, 1.3))))
	assert_eq(wd.base_count("screamer", 6), 2)
	assert_eq(wd.base_count("brute", 4), 1)
	assert_eq(wd.base_count("spitter", 5), 1)
	assert_eq(wd.base_count("giant", 11), 0)
	assert_eq(wd.base_count("giant", 12), 1)


func test_player_scaling_and_giant_not_scaled() -> void:
	var w := TestHelpers.world(120, 4)
	assert_eq(w.waves.count_for("walker", 1), int(round(32 * 2.6 * Config.f("waves.stream.day_mult"))))
	assert_eq(w.waves.count_for("giant", 12), 1)


func test_stream_spawns_far_packs_heading_to_base() -> void:
	var w := TestHelpers.world(800)
	w.waves.stream_on = true
	var before := w.zombies.alive_n
	TestHelpers.steps(w, 40 * 60)   # минута дня 1
	var n := w.zombies.alive_n - before
	assert_gt(n, 0, "поток идёт и днём, без ожидания ночи")
	var near := 0
	for i in w.zombies.count:
		if w.zombies.alive[i] == 1:
			assert_eq(w.zombies.state[i], ZombieSystem.S.HORDE, "сразу идут на базу")
			if w.zombies.pos[i].length() < Config.f("waves.stream.spawn_distance_m") * 0.6:
				near += 1
	assert_eq(near, 0, "появляются далеко от Штаба")


func test_stream_grows_each_day() -> void:
	var w := TestHelpers.world(200)
	var prev := 0
	for d in [1, 4, 8, 12]:
		var total := 0
		for t: String in Config.keys_of("waves.formulas"):
			total += w.waves.count_for(t, d)
		assert_gt(total, prev, "день %d — больше, чем раньше" % d)
		prev = total
