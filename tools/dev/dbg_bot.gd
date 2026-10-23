extends SceneTree
func _initialize() -> void:
	var w: Object = load("res://src/sim/World.gd").new()
	w.setup({"seed": 7})
	w.silent = true
	var b: Object = load("res://src/sim/BotPlayer.gd").new()
	b.setup(w, 1)
	var ev := {}
	w.event_sink = func(n: String, args: Array) -> void:
		ev[n] = int(ev.get(n, 0)) + 1
		if n in ["unit_died", "outbreak_in_base", "building_destroyed", "game_over", "wave_started", "wave_announced"]:
			print("t=%d %s %s %s" % [int(w.time), w.clock.phase_name(), n, str(args).left(80)])
	var t := 0
	while not w.scenario.over and w.time < 900:
		b.update(w.dt)
		w.step()
		t += 1
		if t % 100 == 0 and w.time > 700 or t % 2000 == 0:
			var near := 0
			for i in w.zombies.count:
				if w.zombies.alive[i] == 1 and w.zombies.pos[i].distance_to(w.map.hq_pos) < 150:
					near += 1
			var units = w.agents.units_of(1)
			var up := ""
			for u in units:
				up += "%s(%d,%d hp%d) " % [u.type.left(2), int(u.pos.x), int(u.pos.y), int(u.hp)]
			var walls := ""
			for bb in w.buildings.list:
				if bb.type in ["wall_wood", "gate", "hq"]:
					walls += "%s%d " % [bb.type.left(1), int(bb.hp)]
			up += " | " + walls
			print("t=%d %s z_near=%d people=%s kills=%d bld=%d units=%s" % [int(w.time), w.clock.phase_name(), near, w.economy.people(), w.zombies.kills_total, w.buildings.list.size(), up])
	print(ev)
	quit()
