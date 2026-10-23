extends SceneTree
func _initialize() -> void:
	var w: Object = load("res://src/sim/World.gd").new()
	w.setup({"seed": 7})
	w.silent = true
	w.scenario.checks_enabled = false
	var bot: Object = load("res://src/sim/BotPlayer.gd").new()
	bot.setup(w, 1)
	var scout = null
	for u in w.agents.list:
		if u.type == "scout":
			scout = u
	var c = bot._nearest_unaware(scout.pos, 900.0)
	print("scout ", scout.pos, " target civ ", c.pos, " dist ", c.pos.distance_to(scout.pos), " kind ", c.spawn_kind)
	w.commands.push({"t": "move", "pid": 1, "units": [scout.id], "pos": c.pos})
	var phase := 0
	for t in 20 * 300:
		w.step()
		if phase == 0 and scout.pos.distance_to(c.pos) < 10.0:
			phase = 1
			print("t=%d arrived; civ state %d followers %d" % [t / 20, c.civ, w.civilians.follower_count(scout)])
			w.commands.push({"t": "move", "pid": 1, "units": [scout.id], "pos": w.map.hq_pos})
		if t % 200 == 0:
			var fs := ""
			for a in w.agents.list:
				if a.kind == 3 and a.leader == scout.id:
					fs += "[%d st%d %d,%d mv%s path%d] " % [a.id, a.civ, int(a.pos.x), int(a.pos.y), a.moving, a.path.size()]
			print("t=%d scout %d,%d mv%s hp%d | civ st%d resc%s %d,%d | %s" % [t / 20, int(scout.pos.x), int(scout.pos.y), scout.moving, int(scout.hp), c.civ, c.rescued, int(c.pos.x), int(c.pos.y), fs])
	quit()
