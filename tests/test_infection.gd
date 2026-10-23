extends GutTest
## M1-8: заражение — таймер инкубации → ходок на месте; флаг скрыт до детекта; карантин гасит вспышку.


func test_civilian_turns_into_walker_in_place() -> void:
	var w := TestHelpers.world(120)
	var c := TestHelpers.civ(w, Vector2(40, 40))
	w.combat._maybe_infect(c, 1.0)
	assert_true(c.infected)
	assert_false(c.infect_detected, "до КПП/медика/симптомов заражение скрыто")
	var lo: float = Config.a("rules.infection.incubation_civilian_s")[0]
	var hi: float = Config.a("rules.infection.incubation_civilian_s")[1]
	assert_between(c.infect_t, lo, hi)
	var before := w.zombies.alive_n
	var ticks := int(ceil(c.infect_t / w.dt)) + 2
	var last := c.pos
	for _k in ticks:
		if c.alive:
			last = c.pos
		w.step()
	assert_false(c.alive)
	assert_eq(w.zombies.alive_n, before + 1)
	var found := false
	for k in w.zombies.count:
		if w.zombies.alive[k] == 1 and w.zombies.pos[k].distance_to(last) < 4.0:
			found = true
	assert_true(found, "зомби появился на месте мирного")


func test_symptoms_reveal_last_seconds() -> void:
	var w := TestHelpers.world(120)
	var c := TestHelpers.civ(w, Vector2(30, 30))
	w.combat._maybe_infect(c, 1.0)
	c.infect_t = Config.f("rules.infection.symptoms_visible_last_s") + 0.5
	TestHelpers.steps(w, 20)
	assert_true(c.infect_detected)


func test_quarantine_turn_has_no_outbreak() -> void:
	var w := TestHelpers.world(120)
	w.buildings.place("quarantine", Vector2i(90, 90), 0, 1, true)
	var c := TestHelpers.civ(w, Vector2(30, 30))
	w.combat._maybe_infect(c, 1.0)
	assert_true(w.civilians.jobs.send_to_quarantine(c))
	var before := w.zombies.alive_n
	c.infect_t = 0.01
	TestHelpers.steps(w, 3)
	assert_false(c.alive)
	assert_eq(w.zombies.alive_n, before, "в карантине обращаются и умирают без вспышки")


func test_vehicles_never_infected() -> void:
	var w := TestHelpers.world(120)
	var t := w.agents.spawn_unit("tank", 1, Vector2(20, 20))
	w.combat._maybe_infect(t, 1.0)
	assert_false(t.infected)


func test_antidote_cures() -> void:
	var w := TestHelpers.world(120)
	var m := w.agents.spawn_unit("medic", 1, Vector2(10, 10))
	var c := TestHelpers.civ(w, Vector2(12, 10))
	w.combat._maybe_infect(c, 1.0)
	w.agents.rebuild_hash()
	assert_true(w.abilities.use(m, "antidote", c.pos))
	assert_false(c.infected)


func test_medic_detects_and_auto_cures() -> void:
	var w := TestHelpers.world(120)
	w.agents.spawn_unit("medic", 1, Vector2(10, 10))
	var c := TestHelpers.civ(w, Vector2(12, 10))
	w.combat._maybe_infect(c, 1.0)
	w.step()
	assert_false(c.infected, "медик осматривает соседей и сам колет антидот")
