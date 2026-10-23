extends SceneTree
## Headless бот-прогон (M6-4): DAYS=12 SEED=7 PLAYERS=1 godot --headless -s tools/bot_run.gd
## Пишет tools/bot_runs/run_<seed>.csv (ресурсы и численность по дням) и итог в stdout.

func _initialize() -> void:
	var days := int(OS.get_environment("DAYS")) if OS.get_environment("DAYS") != "" else 12
	var seed_v := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	var np := int(OS.get_environment("PLAYERS")) if OS.get_environment("PLAYERS") != "" else 1
	var players: Array = []
	for k in np:
		players.append({"pid": k + 1, "name": "BOT%d" % (k + 1), "doctrines": ["infantry", "civil_defense"] if np == 1 else [["infantry", "armor", "aviation", "civil_defense"][k % 4]]})
	var w: Object = load("res://src/sim/World.gd").new()
	w.setup({"seed": seed_v, "players": players})
	w.silent = true
	w.clock.total_days = days
	var ev := {}
	w.event_sink = func(n: String, _a: Array) -> void: ev[n] = int(ev.get(n, 0)) + 1
	var bots: Array = []
	for p: Dictionary in players:
		var b: Object = load("res://src/sim/BotPlayer.gd").new()
		b.setup(w, int(p["pid"]))
		bots.append(b)
	var csv := PackedStringArray(["day,food,wood,iron,adults,children,soldiers,morale,zombies,kills,buildings,power,ms_per_tick"])
	var t0 := Time.get_ticks_msec()
	var last_day := 1
	var ticks := 0
	var tick_t0 := Time.get_ticks_usec()
	while not w.scenario.over and w.clock.day <= days and not w.clock.finished:
		for b: Object in bots:
			b.update(w.dt)
		w.step()
		ticks += 1
		if w.clock.day != last_day:
			var ms := float(Time.get_ticks_usec() - tick_t0) / 1000.0 / maxf(1.0, ticks)
			csv.append(_row(w, last_day, ms))
			print(csv[csv.size() - 1])
			last_day = w.clock.day
			ticks = 0
			tick_t0 = Time.get_ticks_usec()
	csv.append(_row(w, w.clock.day, 0.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/bot_runs"))
	var f := FileAccess.open("res://tools/bot_runs/run_%d_p%d.csv" % [seed_v, np], FileAccess.WRITE)
	f.store_string("\n".join(csv) + "\n")
	print("EVENTS ", ev)
	print("RESULT over=", w.scenario.over, " victory=", w.scenario.victory, " day=", w.clock.day, " reason=", w.scenario.final_score.get("reason", "-"),
		" score=", w.scenario.final_score.get("total", 0), " people_on_arena=", w.scenario.people_on_arena(), " wall_s=", (Time.get_ticks_msec() - t0) / 1000.0)
	quit()


func _row(w: Object, day: int, ms: float) -> String:
	var p: Dictionary = w.economy.people()
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f" % [day, int(w.economy.res["food"]), int(w.economy.res["wood"]), int(w.economy.res["iron"]),
		p["adults"], p["children"], p["soldiers"], int(w.economy.morale), w.zombies.alive_n, w.zombies.kills_total,
		w.buildings.list.size(), int(w.economy.power_balance()), ms]
