class_name TestHelpers
extends RefCounted
## Маленький мир для тестов: пустое поле N×N клеток, Штаб в центре, без населения.


static func grid(n: int = 160) -> Grid:
	var g := Grid.new()
	g.init_empty(n, n, 2.0, Vector2(-n, -n), 128)
	return g


static func world(n: int = 160, players: int = 1, seed_v: int = 1) -> World:
	var ps: Array = []
	for k in players:
		ps.append({"pid": k + 1, "name": "P%d" % (k + 1), "doctrines": ["infantry"]})
	var w := World.new()
	w.setup({"grid": grid(n), "empty": true, "seed": seed_v, "players": ps, "hq": Vector2.ZERO})
	w.silent = true
	w.scenario.checks_enabled = false
	return w


static func steps(w: World, n: int) -> void:
	for _k in n:
		w.step()


static func civ(w: World, p: Vector2) -> Agent:
	return w.civilians.spawn(p, Agent.Civ.IDLE, true)
