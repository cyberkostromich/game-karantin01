extends GutTest
## M3-2..M3-6: способности, транспорт, вертолёт, гарнизон.


func test_garrison_tower_range_bonus() -> void:
	var w := TestHelpers.world(160)
	var t := w.buildings.place("tower", Vector2i(80, 70), 0, 1, true)
	var u := w.agents.spawn_unit("assault", 1, t.door)
	w.commands.push({"t": "enter", "pid": 1, "units": [u.id], "target": t.id})
	TestHelpers.steps(w, 40)
	assert_true(u.hidden, "боец в вышке")
	assert_eq(t.garrison.size(), 1)
	assert_almost_eq(w.units._range(u), Config.f("units.assault.attack.range") + Config.f("buildings.tower.garrison_range_bonus"), 0.01)
	var z := w.zombies.spawn(0, t.pos + Vector2(0, 21), ZombieSystem.S.IDLE)
	TestHelpers.steps(w, 20 * 6)
	assert_eq(w.zombies.alive[z], 0, "из вышки достаёт дальше")


func test_bmp_transport_board_unload() -> void:
	var w := TestHelpers.world(160)
	var bmp := w.agents.spawn_unit("bmp", 1, Vector2(0, 0))
	var a := w.agents.spawn_unit("assault", 1, Vector2(4, 0))
	w.commands.push({"t": "enter", "pid": 1, "units": [a.id], "target": bmp.id, "kind": "unit"})
	TestHelpers.steps(w, 40)
	assert_true(a.hidden)
	assert_eq(bmp.passengers.size(), 1)
	w.commands.push({"t": "unload", "pid": 1, "units": [bmp.id]})
	w.step()
	assert_false(a.hidden)
	assert_eq(bmp.passengers.size(), 0)


func test_vehicle_death_ejects_crew() -> void:
	var w := TestHelpers.world(160, 1, 3)
	var tank := w.agents.spawn_unit("tank", 1, Vector2(0, 0))
	var before := w.agents.units_of(1).size()
	var ejected := 0
	for k in 10:
		var t2 := w.agents.spawn_unit("tank", 1, Vector2(k * 8.0, 20))
		var n0 := w.agents.units_of(1).size()
		w.combat.kill_agent(t2)
		ejected += w.agents.units_of(1).size() - (n0 - 1)
	assert_gt(ejected, 0, "экипаж катапультируется с шансом crew_eject_chance")
	assert_true(tank.alive)
	assert_eq(before, 1)


func test_grenade_and_flare_and_smoke() -> void:
	var w := TestHelpers.world(160)
	var a := w.agents.spawn_unit("assault", 1, Vector2(0, 0))
	var zs: Array[int] = []
	for k in 5:
		zs.append(w.zombies.spawn(0, Vector2(10 + k * 0.5, 0)))
	w.zombies.rebuild_hash()
	assert_true(w.abilities.use(a, "grenade", Vector2(11, 0)))
	var dead := 0
	for i in zs:
		if w.zombies.alive[i] == 0:
			dead += 1
	assert_eq(dead, 5, "граната 80 × explosive 1.5 убивает ходоков в 4 м")
	assert_false(w.abilities.use(a, "grenade", Vector2(11, 0)), "кулдаун")
	var s := w.agents.spawn_unit("scout", 1, Vector2(-50, -50))
	assert_true(w.abilities.use(s, "flare", Vector2(-20, -50)))
	var z := w.zombies.spawn(0, Vector2(30, -50))
	TestHelpers.steps(w, 25)
	assert_eq(w.zombies.state[z], ZombieSystem.S.INVESTIGATE, "ракета приманивает шумом")
	var b := w.agents.spawn_unit("bmp", 1, Vector2(60, 60))
	var c := w.zombies.spawn(0, Vector2(63, 60))
	w.zombies.rebuild_hash()
	w.zombies.state[c] = ZombieSystem.S.CHASE
	w.zombies.target[c] = b.id
	assert_true(w.abilities.use(b, "smoke", b.pos))
	assert_ne(w.zombies.state[c], ZombieSystem.S.CHASE, "дым — зомби теряют цель")


func test_heli_fuel_and_rooftop_rescue() -> void:
	var w := TestHelpers.world(200)
	var pad := w.buildings.place("helipad", Vector2i(110, 110), 0, 1, true)
	var h := w.agents.spawn_unit("heli", 1, pad.pos)
	var c := w.civilians.spawn(Vector2(-150, -150), Agent.Civ.ROOFTOP, false)
	c.hidden = true
	w.commands.push({"t": "move", "pid": 1, "units": [h.id], "pos": [-150.0, -150.0]})
	TestHelpers.steps(w, 20 * 25)
	assert_true(c.hidden and c.container == h.id, "мирный с крыши в вертолёте")
	w.commands.push({"t": "move", "pid": 1, "units": [h.id], "pos": [pad.pos.x, pad.pos.y]})
	var fuel_before := h.fuel
	TestHelpers.steps(w, 20 * 25)
	assert_true(c.rescued or c.civ == Agent.Civ.CHECKPOINT or c.civ == Agent.Civ.IDLE, "высажен на базе")
	assert_lt(fuel_before, w.mods.heli_flight_time(1))


func test_heli_crashes_without_fuel() -> void:
	var w := TestHelpers.world(160)
	var h := w.agents.spawn_unit("heli", 1, Vector2(50, 50))
	h.fuel = 0.1
	TestHelpers.steps(w, 5)
	assert_false(h.alive)


func test_tank_crushes_walkers() -> void:
	var w := TestHelpers.world(160)
	var t := w.agents.spawn_unit("tank", 1, Vector2(0, 0))
	for k in 6:
		w.zombies.spawn(0, Vector2(k * 3.0 + 6.0, 0))
	w.commands.push({"t": "move", "pid": 1, "units": [t.id], "pos": [40.0, 0.0]})
	TestHelpers.steps(w, 20 * 8)
	assert_lt(w.zombies.alive_n, 6, "давка мелких зомби")
