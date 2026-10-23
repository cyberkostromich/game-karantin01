extends SceneTree
## Headless-проверка: мир на реальной карте, N тиков. TICKS=400 godot --headless -s tools/dev/smoke.gd
## Классы sim грузим динамически: при статической ссылке main-скрипт компилируется раньше автолоадов.

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var w: Object = load("res://src/sim/World.gd").new()
	w.setup({"seed": 7})
	print("setup ms ", Time.get_ticks_msec() - t0, " zombies ", w.zombies.alive_n, " agents ", w.agents.list.size(), " pois ", w.map.pois.size(), " nests ", w.map.nests.size())
	t0 = Time.get_ticks_msec()
	var n := int(OS.get_environment("TICKS")) if OS.get_environment("TICKS") != "" else 400
	var worst := 0
	for k in n:
		var t1 := Time.get_ticks_usec()
		w.step()
		worst = maxi(worst, Time.get_ticks_usec() - t1)
	var ms := Time.get_ticks_msec() - t0
	print("ticks ", n, " ms ", ms, " per tick ", float(ms) / n, " worst us ", worst, " day ", w.clock.day, " ", w.clock.phase_name(), " zombies ", w.zombies.alive_n)
	print("res ", w.economy.res, " morale ", w.economy.morale, " people ", w.economy.people())
	quit()
