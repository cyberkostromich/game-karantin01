class_name TechSystem
extends RefCounted
## Дерево технологий (GDD §11): одна Мастерская = одно исследование; скорость ∝ работникам на слотах.

var world: World
var done: PackedStringArray = []


func setup(w: World) -> void:
	world = w


func has(tech: String) -> bool:
	return done.has(tech)


func in_progress(tech: String) -> bool:
	for b in world.buildings.all_of("workshop"):
		if String(b.research.get("tech", "")) == tech:
			return true
	return false


## "" — можно, иначе ключ причины для tr().
func check(tech: String) -> String:
	if not Config.has("tech." + tech):
		return "TECH_ERR_UNKNOWN"
	if has(tech) or in_progress(tech):
		return "TECH_ERR_DONE"
	if not world.mods.tech_ignores_requires(tech):
		for r: String in Config.a("tech.%s.requires" % tech):
			if not has(r):
				return "TECH_ERR_REQUIRES"
	if not world.economy.can_afford(Config.d("tech.%s.cost" % tech)):
		return "TECH_ERR_COST"
	return ""


func start(b: Building, tech: String) -> bool:
	if b == null or b.type != "workshop" or not b.complete() or not b.research.is_empty():
		return false
	if check(tech) != "":
		return false
	world.economy.spend(Config.d("tech.%s.cost" % tech))
	var total := world.mods.tech_time(tech)
	b.research = {"tech": tech, "t": total, "total": total}
	return true


func cancel(b: Building) -> void:
	if b.research.is_empty():
		return
	world.economy.refund(Config.d("tech.%s.cost" % String(b.research["tech"])), 1.0)
	b.research = {}


func update(dt: float) -> void:
	for b in world.buildings.all_of("workshop"):
		if b.research.is_empty() or not b.working():
			continue
		var rate := 0.0
		for cid in b.workers:
			var a := world.agents.get_agent(cid)
			if a != null and a.civ == Agent.Civ.WORKING:
				rate += world.mods.research_rate(a)
		# research_s задан при полном штате (workers = 2, tech.json/_doc)
		rate /= maxf(1.0, float(b.worker_slots))
		b.research["t"] = float(b.research["t"]) - dt * rate
		if float(b.research["t"]) <= 0.0:
			var tech := String(b.research["tech"])
			b.research = {}
			done.append(tech)
			world.economy.mark_dirty()
			world.emit("research_completed", [tech])
