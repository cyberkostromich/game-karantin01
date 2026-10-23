class_name TrainingSystem
extends RefCounted
## Обучение (GDD §6.3, M3-1): каждый юнит стоит N рекрутов — свободных взрослых мирных.

var world: World


func setup(w: World) -> void:
	world = w


func free_recruits() -> int:
	var n := 0
	for a in world.agents.list:
		if a.is_free_adult() and a.rescued:
			n += 1
	return n


## "" — можно, иначе ключ для tr() (кнопка серая + подсказка, GDD §6.3).
func check(b: Building, unit: String, owner: int) -> String:
	if b == null or not b.complete():
		return "TRAIN_ERR_BUILDING"
	if not b.data().get("trains", []).has(unit):
		return "TRAIN_ERR_BUILDING"
	if not b.powered:
		return "TRAIN_ERR_POWER"
	var req := Config.d("units.%s.requires" % unit)
	var tech: Variant = req.get("tech")
	if tech != null and not world.tech.has(String(tech)):
		return "TRAIN_ERR_TECH"
	var also: Variant = req.get("also_building")
	if also != null and world.buildings.count_of(String(also)) == 0:
		return "TRAIN_ERR_ALSO_" + String(also).to_upper()
	if world.economy.morale_effect("recruitment_blocked", false):
		return "TRAIN_ERR_MORALE"
	if free_recruits() < int(Config.f("units.%s.recruits" % unit)):
		return "TRAIN_ERR_RECRUITS"
	if not world.economy.can_afford(world.mods.unit_cost(unit, owner)):
		return "TRAIN_ERR_COST"
	return ""


func enqueue(b: Building, unit: String, owner: int) -> bool:
	var err := check(b, unit, owner)
	if err != "":
		world.emit("recruit_failed", [err])
		return false
	world.economy.spend(world.mods.unit_cost(unit, owner))
	var recruits: Array[int] = []
	var trait_id := ""
	for _k in int(Config.f("units.%s.recruits" % unit)):
		var a := world.agents.nearest_free_adult(b.pos)
		world.civilians.start_training(a, b)
		recruits.append(a.id)
		if trait_id == "" and a.trait_id != "":
			trait_id = a.trait_id
		var mc := float(Config.opt("civilians.traits.%s.effects.recruit_morale_cost" % a.trait_id, 0.0)) if a.trait_id != "" else 0.0
		if mc > 0.0:
			world.economy.morale_event("coward_recruited", -mc)
	var total := Config.f("units.%s.train_s" % unit) * world.mods.train_time_mult(trait_id)
	b.queue.append({"unit": unit, "t": total, "total": total, "owner": owner, "recruits": recruits, "trait": trait_id})
	return true


func cancel_last(b: Building) -> void:
	if b.queue.is_empty():
		return
	var q: Dictionary = b.queue.pop_back()
	world.economy.refund(world.mods.unit_cost(String(q["unit"]), int(q["owner"])), 1.0)
	for id: int in q["recruits"]:
		var a := world.agents.get_agent(id)
		if a != null:
			world.civilians.release(a)


func update(dt: float) -> void:
	for b in world.buildings.list:
		if b.queue.is_empty() or not b.working():
			continue
		var q: Dictionary = b.queue[0]
		q["t"] = float(q["t"]) - dt
		if float(q["t"]) > 0.0:
			continue
		b.queue.pop_front()
		_complete(b, q)


func _complete(b: Building, q: Dictionary) -> void:
	for id: int in q["recruits"]:
		var a := world.agents.get_agent(id)
		if a != null:
			world.agents.remove(a)  # мирный стал солдатом/экипажем
	var u := world.agents.spawn_unit(String(q["unit"]), int(q["owner"]), b.door, String(q["trait"]))
	if b.rally.distance_to(b.door) > 2.0:
		world.agents.move_to(u, b.rally)
	world.emit("unit_trained", [u.id, u.type, u.owner])
