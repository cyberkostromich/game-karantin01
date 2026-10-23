class_name BuildSystem
extends RefCounted
## Размещение, стройка мирными, ремонт, улучшение стен, разрушение (GDD §10, tech spec M2-3).

var world: World
var list: Array[Building] = []
var by_id: Dictionary = {}
var next_id: int = 1
var assign_cd: float = 0.0
var hq: Building = null


func setup(w: World) -> void:
	world = w


func get_building(id: int) -> Building:
	return by_id.get(id)


func all_of(type: String, only_complete := true) -> Array[Building]:
	var out: Array[Building] = []
	for b in list:
		if b.alive and b.type == type and (not only_complete or b.complete()):
			out.append(b)
	return out


func count_of(type: String) -> int:
	return all_of(type).size()


func rect_for(type: String, origin_cell: Vector2i, rot: int) -> Rect2i:
	var f: Array = Config.a("buildings.%s.footprint" % type)
	var sz := Vector2i(int(f[0]), int(f[1])) if rot % 2 == 0 else Vector2i(int(f[1]), int(f[0]))
	return Rect2i(origin_cell, sz)


## Почему нельзя построить ("" — можно). Ключи — для tr() в UI.
func check_place(type: String, origin_cell: Vector2i, rot: int, check_cost := true) -> String:
	var d := Config.d("buildings." + type)
	if d.is_empty() or type == "map_poi" or bool(d.get("prebuilt", false)):
		return "BUILD_ERR_TYPE"
	if bool(d.get("unique", false)) and not all_of(type, false).is_empty():
		return "BUILD_ERR_UNIQUE"
	var tech: Variant = d.get("requires_tech")
	if tech != null and not world.tech.has(String(tech)):
		return "BUILD_ERR_TECH"
	var r := rect_for(type, origin_cell, rot)
	if not world.grid.rect_free(r):
		return "BUILD_ERR_BLOCKED"
	var c := world.grid.center_of(r.position) + Vector2(r.size - Vector2i.ONE) * world.grid.cell * 0.5
	if not world.in_build_zone(c):
		return "BUILD_ERR_ZONE"
	if check_cost and not world.economy.can_afford(d.get("cost", {})):
		return "BUILD_ERR_COST"
	return ""


func place(type: String, origin_cell: Vector2i, rot: int, owner: int, instant := false) -> Building:
	var d := Config.d("buildings." + type)
	if not instant:
		if check_place(type, origin_cell, rot) != "":
			return null
		world.economy.spend(d.get("cost", {}))
	var b := Building.new()
	b.id = next_id
	next_id += 1
	b.type = type
	b.owner = owner
	b.rot = rot
	b.cells = rect_for(type, origin_cell, rot)
	var g := world.grid
	b.rect_m = Rect2(g.origin + Vector2(b.cells.position) * g.cell, Vector2(b.cells.size) * g.cell)
	b.pos = b.rect_m.get_center()
	b.max_hp = float(d["hp"])
	b.worker_slots = int(d.get("workers", 0))
	b.door = g.nearest_walkable(b.pos + Vector2(0, b.rect_m.size.y * 0.5 + 2.0), 30.0)
	b.rally = b.door
	list.append(b)
	by_id[b.id] = b
	# стройплощадка занимает клетки сразу, но блокирует проход только готовая постройка
	g.set_rect(b.cells, b.id, Grid.BLOCK_NONE)
	if instant:
		b.hp = b.max_hp
		_finish(b)
	else:
		b.hp = b.max_hp * Config.f("rules.build.site_start_hp_frac")
		world.emit("building_placed", [b.id, type])
	return b


func _block_kind(type: String) -> int:
	var d := Config.d("buildings." + type)
	if bool(d.get("auto_open_for_allies", false)):
		return Grid.BLOCK_ZOMBIE
	if d.has("blocks_zombies") and not bool(d["blocks_zombies"]):
		return Grid.BLOCK_NONE
	return Grid.BLOCK_ALL


func _finish(b: Building) -> void:
	b.state = Building.State.COMPLETE
	b.progress = 1.0
	world.grid.set_rect(b.cells, b.id, _block_kind(b.type))
	world.paths.update_rect(b.cells.grow(1))
	_release_builders(b)
	if b.type == "hq":
		hq = b
	world.economy.mark_dirty()
	world.emit("building_completed", [b.id, b.type])


func cancel(b: Building) -> void:
	if b.state == Building.State.CONSTRUCTING:
		var cost: Dictionary = b.data().get("cost", {})
		world.economy.refund(cost, Config.f("rules.build.cancel_refund_frac"))
	destroy(b, false)


func destroy(b: Building, by_enemy := true) -> void:
	if not b.alive:
		return
	b.alive = false
	world.grid.clear_rect(b.cells, b.id)
	world.paths.update_rect(b.cells.grow(1))
	_release_builders(b)
	for cid in b.workers:
		var a := world.agents.get_agent(cid)
		if a != null:
			world.civilians.release(a)
	b.workers.clear()
	world.units.eject_garrison(b)
	list.erase(b)
	by_id.erase(b.id)
	world.economy.mark_dirty()
	if by_enemy:
		world.noise.emit(b.pos, Config.f("combat.noise_events.building_destroyed"))
	world.emit("building_destroyed", [b.id, b.type, b.pos])


func damage(b: Building, amount: float) -> void:
	if not b.alive:
		return
	b.hp -= amount
	if b.hits_taken_t <= 0.0:
		world.emit("building_attacked", [b.id, b.pos])
		b.hits_taken_t = Config.f("rules.sim_tuning.building_attack_alert_s")
	if b.hp <= 0.0:
		destroy(b)


func building_near(p: Vector2, r: float) -> Building:
	var g := world.grid
	var c := g.cell_of(p)
	var k := ceili(r / g.cell)
	var best: Building = null
	var bd := INF
	for dy in range(-k, k + 1):
		for dx in range(-k, k + 1):
			var cc := c + Vector2i(dx, dy)
			if not g.in_bounds(cc):
				continue
			var id := g.occ[cc.y * g.w + cc.x]
			if id < 0:
				continue
			var dd := float(dx * dx + dy * dy)
			if dd < bd:
				var b := get_building(id)
				if b != null and b.alive:
					bd = dd
					best = b
	return best


# ------------------------------------------------------------------ тик
func update(dt: float) -> void:
	assign_cd -= dt
	if assign_cd <= 0.0:
		assign_cd = Config.f("rules.build.assign_interval_s")
		_auto_assign()
	for b in list:
		if b.hits_taken_t > 0.0:
			b.hits_taken_t -= dt
		if b.state == Building.State.CONSTRUCTING:
			_progress_build(b, dt)
		elif b.repairing or b.upgrading_to != "":
			_progress_repair(b, dt)


func needs_builders(b: Building) -> bool:
	return b.alive and (b.state == Building.State.CONSTRUCTING or b.repairing or b.upgrading_to != "")


## Эффективные строители на месте: сумма скоростей (черты, мораль, доктрина) → N^0.8 (GDD §6.2).
func _effective_builders(b: Building) -> float:
	var n := 0.0
	var reach := Config.f("rules.build.builder_reach_m") + b.half_extent()
	for cid in b.builders:
		var a := world.agents.get_agent(cid)
		if a == null or a.civ != Agent.Civ.BUILDING or a.pos.distance_to(b.pos) > reach:
			continue
		n += world.mods.build_rate(a, b.owner)
	return n


func _progress_build(b: Building, dt: float) -> void:
	var n := _effective_builders(b)
	if n <= 0.0:
		return
	var build_s := maxf(0.1, float(b.data()["build_s"]))
	var dp := pow(n, Config.f("rules.build.builders_exponent")) / build_s * dt
	b.progress = minf(1.0, b.progress + dp)
	b.hp = minf(b.max_hp, b.hp + b.max_hp * dp)
	_construction_noise(b, dt)
	if b.progress >= 1.0:
		_finish(b)


func _progress_repair(b: Building, dt: float) -> void:
	var n := _effective_builders(b)
	if n <= 0.0:
		return
	_construction_noise(b, dt)
	var build_s := maxf(0.1, float(b.data()["build_s"]))
	var rate := pow(n, Config.f("rules.build.builders_exponent")) / build_s * dt
	if b.upgrading_to != "":
		b.upgrade_progress += rate * float(b.data()["build_s"]) / float(Config.f("buildings.%s.build_s" % b.upgrading_to))
		if b.upgrade_progress >= 1.0:
			_apply_upgrade(b)
		return
	b.hp = minf(b.max_hp, b.hp + b.max_hp * rate * Config.f("rules.build.repair_speed_mult"))
	if b.hp >= b.max_hp:
		b.repairing = false
		_release_builders(b)


func _construction_noise(b: Building, dt: float) -> void:
	b.noise_cd -= dt
	if b.noise_cd <= 0.0:
		b.noise_cd = Config.f("rules.sim_tuning.continuous_noise_interval_s")
		world.noise.emit(b.pos, Config.f("combat.noise_events.construction"))


func start_repair(b: Building) -> bool:
	if not b.complete() or b.hp >= b.max_hp or b.repairing:
		return false
	var frac := (1.0 - b.hp / b.max_hp) * Config.f("rules.build.repair_cost_frac")
	var cost := _scaled(b.data().get("cost", {}), frac)
	if not world.economy.can_afford(cost):
		return false
	world.economy.spend(cost)
	b.repairing = true
	return true


func start_upgrade(b: Building) -> bool:
	var to: Variant = b.data().get("upgrade_to")
	if to == null or not b.complete() or b.upgrading_to != "":
		return false
	var td := Config.d("buildings." + String(to))
	var tech: Variant = td.get("requires_tech")
	if tech != null and not world.tech.has(String(tech)):
		return false
	if not world.economy.can_afford(td.get("cost", {})):
		return false
	world.economy.spend(td.get("cost", {}))
	b.upgrading_to = String(to)
	b.upgrade_progress = 0.0
	return true


func _apply_upgrade(b: Building) -> void:
	var frac := b.hp / b.max_hp
	b.type = b.upgrading_to
	b.upgrading_to = ""
	b.max_hp = float(b.data()["hp"])
	b.hp = b.max_hp * maxf(frac, 1.0)
	_release_builders(b)
	world.emit("building_completed", [b.id, b.type])


func _scaled(cost: Dictionary, k: float) -> Dictionary:
	var out := {}
	for r: String in cost:
		out[r] = ceilf(float(cost[r]) * k)
	return out


func _release_builders(b: Building) -> void:
	for cid in b.builders:
		var a := world.agents.get_agent(cid)
		if a != null and a.civ == Agent.Civ.BUILDING and a.work_b == b.id:
			world.civilians.release(a)
	b.builders.clear()


## Свободные взрослые сами идут на ближайшие стройплощадки (GDD §6.2 «Строить»).
func _auto_assign() -> void:
	var cap := Config.i("rules.build.max_builders_per_site")
	for b in list:
		if not needs_builders(b):
			continue
		b.builders = b.builders.filter(func(cid: int) -> bool:
			var a := world.agents.get_agent(cid)
			return a != null and a.alive and a.civ == Agent.Civ.BUILDING and a.work_b == b.id)
		while b.builders.size() < cap:
			var a := world.agents.nearest_free_adult(b.pos)
			if a == null or a.pos.distance_to(b.pos) > Config.f("rules.build.auto_assign_radius_m"):
				break
			world.civilians.assign_builder(a, b)
			b.builders.append(a.id)
