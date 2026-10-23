extends GutTest
## M1-1, M1-3, M1-5, M1-6: SoA зомби, пространственный хеш, FSM, шум.


func test_spawn_and_free_2000_no_leak() -> void:
	var w := TestHelpers.world(120)
	var z := w.zombies
	for round in 3:
		var ids := PackedInt32Array()
		for k in 2000:
			ids.append(z.spawn(0, Vector2(randf_range(-100, 100), randf_range(-100, 100))))
		assert_eq(z.alive_n, 2000)
		for i in ids:
			z.kill(i)
		assert_eq(z.alive_n, 0)
	assert_eq(z.count, 2000, "слоты переиспользуются через free-list")


func test_spatial_hash_matches_bruteforce() -> void:
	var h := SpatialHash.new()
	h.setup(Vector2(-100, -100), Vector2(200, 200), 8.0)
	var pos := PackedVector2Array()
	var alive := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 500:
		pos.append(Vector2(rng.randf_range(-99, 99), rng.randf_range(-99, 99)))
		alive.append(1 if k % 7 != 0 else 0)
	h.rebuild(pos, alive, pos.size())
	var out := PackedInt32Array()
	for q in 20:
		var c := Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90))
		h.query(c, 15.0, out)
		var expect := 0
		for k in pos.size():
			if alive[k] == 1 and pos[k].distance_to(c) <= 15.0:
				expect += 1
				assert_true(out.has(k))
		assert_eq(out.size(), expect)
	var n := h.nearest(Vector2.ZERO, 50.0)
	var best := -1
	var bd := INF
	for k in pos.size():
		if alive[k] == 1 and pos[k].length() < bd:
			bd = pos[k].length()
			best = k
	assert_eq(n, best)


func test_noise_wakes_idle_zombie() -> void:
	var w := TestHelpers.world(120)
	var i := w.zombies.spawn(0, Vector2(80, 80))
	w.noise.emit(Vector2(60, 60), 40.0)
	w.step()
	assert_eq(w.zombies.state[i], ZombieSystem.S.INVESTIGATE)
	var far := w.zombies.spawn(0, Vector2(-100, -100))
	w.noise.emit(Vector2(60, 60), 40.0)
	w.step()
	assert_eq(w.zombies.state[far], ZombieSystem.S.IDLE, "за радиусом шума не слышно")


func test_zombie_chases_and_bites_civilian() -> void:
	var w := TestHelpers.world(120)
	var c := TestHelpers.civ(w, Vector2(50, 50))
	c.rescued = false
	c.civ = Agent.Civ.UNAWARE
	var i := w.zombies.spawn(w.zombies.type_index("runner"), Vector2(56, 50))  # от ходока мирный убегает
	TestHelpers.steps(w, 200)
	assert_true(c.infected or not c.alive, "мирный укушен (заражение = любое попадание, GDD §8.2)")
	assert_true(w.zombies.state[i] != ZombieSystem.S.IDLE or not c.alive)
