class_name Scenario
extends RefCounted
## Сценарий «Лужники» (GDD §14–15): события дней, цели, победа/поражение, счёт и медали.

var world: World
var migration_night: int = -1
var evac_announced: bool = false
var over: bool = false
var victory: bool = false
var final_score: Dictionary = {}
var _check_cd: float = 0.0


func setup(w: World) -> void:
	world = w
	for k: String in Config.keys_of("waves.events"):
		if String(Config.g("waves.events.%s.type" % k)) == "horde_migration":
			migration_night = int(k.trim_prefix("day_"))


func on_day_start(day: int) -> void:
	var key := "waves.events.day_%d" % day
	if not Config.has(key):
		return
	var e := Config.d(key)
	var kind := String(e["type"])
	var pos := Vector2.ZERO
	if e.has("poi"):
		var p := world.map.poi(String(e["poi"]))
		if p != null:
			pos = p.anchor
	match kind:
		"radio":
			_spawn_group(pos, int(e.get("spawn_civilians", 0)))
		"objective":
			world.emit("objective_updated", [String(e.get("poi", "")), "active"])
		"evacuation":
			evac_announced = true
			world.emit("objective_updated", ["evacuation", "active"])
		"final":
			_spawn_giant()
	world.emit("scenario_event", [day, kind, String(e.get("text_ru", "")), pos])


func _spawn_group(p: Vector2, n: int) -> void:
	for k in n:
		var q := world.grid.nearest_walkable(p + Vector2(world.rng.randf_range(-12, 12), world.rng.randf_range(-12, 12)), 40.0)
		var a := world.civilians.spawn(q, Agent.Civ.UNAWARE, false)
		a.spawn_kind = "event"
		a.revealed = true


## Великан идёт в финальную ночь вместе с волной (waves.json/formulas/giant) — его спавнит WaveDirector;
## здесь только убеждаемся, что он есть в составе.
func _spawn_giant() -> void:
	pass


func update(dt: float) -> void:
	if over:
		return
	_check_cd -= dt
	if _check_cd > 0.0:
		return
	_check_cd = 1.0
	if bool(Config.g("rules.defeat.hq_destroyed")) and (world.buildings.hq == null or not world.buildings.hq.alive):
		finish(false, "DEFEAT_HQ")
	elif bool(Config.g("rules.defeat.population_zero")) and world.economy.people()["total"] == 0:
		finish(false, "DEFEAT_PEOPLE")


## Люди на арене (мирные + экипажи, включая сидящих в технике и вышках).
func people_on_arena() -> Dictionary:
	var out := {"civilians": 0, "children": 0, "soldiers": 0}
	for a in world.agents.list:
		if not a.alive:
			continue
		var p := a.pos
		if a.hidden and a.container >= 0:
			var b := world.buildings.get_building(a.container)
			if b != null:
				p = b.pos
			var v := world.agents.get_agent(a.container)
			if v != null:
				p = v.pos
		if not world.in_base(p):
			continue
		if a.kind == Agent.Kind.CIVILIAN:
			if a.rescued:
				out["children" if a.is_child else "civilians"] += 1
		elif a.temp_life < 0.0:
			out["soldiers"] += int(Config.f("units.%s.recruits" % a.type))
	return out


func on_final_dawn() -> void:
	var p := people_on_arena()
	var total: int = p["civilians"] + p["children"] + p["soldiers"]
	finish(total >= Config.i("rules.victory.evacuation_quota_people"), "VICTORY" if total >= Config.i("rules.victory.evacuation_quota_people") else "DEFEAT_QUOTA")


func finish(win: bool, reason: String) -> void:
	if over:
		return
	over = true
	victory = win
	final_score = compute_score(win)
	final_score["reason"] = reason
	world.emit("game_over", [win, final_score])


func compute_score(win: bool) -> Dictionary:
	var s := Config.d("rules.victory.score")
	var p := people_on_arena()
	var sc := {
		"civilians": p["civilians"] * int(s["per_civilian_evacuated"]) if win else 0,
		"children": p["children"] * int(s["per_child_evacuated"]) if win else 0,
		"soldiers": p["soldiers"] * int(s["per_soldier_alive"]),
		"nests": int(world.score.get("nests", 0)) * int(s["per_nest_cleared"]),
		"objectives": int(world.score.get("objectives", 0)) * int(s["per_objective"]),
	}
	var total := 0
	for k: String in sc:
		total += int(sc[k])
	var medals: Array[String] = []
	if world.outbreaks == 0:
		medals.append("MEDAL_NO_OUTBREAK")
	if world.score.get("tanks_built", 0) == 0:
		medals.append("MEDAL_NO_TANKS")
	if not world.map.nests.is_empty() and world.map.nests.all(func(n: MapPoi) -> bool: return not n.alive):
		medals.append("MEDAL_ALL_NESTS")
	return {"parts": sc, "total": total, "medals": medals, "people": p, "kills": world.zombies.kills_total,
		"day": world.clock.day, "history": world.economy.history}
