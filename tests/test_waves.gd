extends GutTest
## M2-7: формулы waves.json, множители игроков, направления.


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
	assert_eq(w.waves.count_for("walker", 1), int(round(32 * 2.6)))
	assert_eq(w.waves.count_for("giant", 12), 1)


func test_directions_per_night() -> void:
	var w := TestHelpers.world(120)
	assert_eq(w.waves.directions_for(1), 1)
	assert_eq(w.waves.directions_for(5), 2)
	assert_eq(w.waves.directions_for(9), 3)
	assert_eq(w.waves.directions_for(12), 4)


func test_wave_spawns_at_night() -> void:
	var w := TestHelpers.world(200)
	w.clock.phase = 2
	w.clock.t = 0.0
	w.on_dusk()
	assert_false(w.waves.directions.is_empty())
	w.clock.phase = 3
	w.clock.t = w.clock.durations[3] * 0.3
	var before := w.zombies.alive_n
	TestHelpers.steps(w, 5)
	assert_gt(w.zombies.alive_n, before)
	var horde := 0
	for i in w.zombies.count:
		if w.zombies.alive[i] == 1 and w.zombies.state[i] == ZombieSystem.S.HORDE:
			horde += 1
	assert_gt(horde, 0)
