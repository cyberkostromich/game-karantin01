class_name CivilianSystem
extends RefCounted
## Мирные (GDD §6.1): прячутся → прилипают к юниту (15 м) → идут на базу → КПП → свободные/работа.
## Работа в зданиях и добыча — CivilianJobs.gd.

const C := Agent.Civ

var world: World
var jobs: CivilianJobs
var tmp := PackedInt32Array()
var ztmp := PackedInt32Array()
var last_group_t: float = -999.0
var trait_ids: PackedStringArray = []
var trait_weights := PackedFloat32Array()


func setup(w: World) -> void:
	world = w
	jobs = CivilianJobs.new()
	jobs.setup(w, self)
	for t in Config.keys_of("civilians.traits"):
		trait_ids.append(t)
		trait_weights.append(Config.f("civilians.traits.%s.weight" % t))


func roll_trait() -> String:
	if world.rng.randf() >= Config.f("rules.trait_chance"):
		return ""
	return trait_ids[world.rng.rand_weighted(trait_weights)]


func spawn(p: Vector2, st: int, rescued: bool) -> Agent:
	var a := world.agents.spawn_civilian(p, false, st)
	a.trait_id = roll_trait()
	a.rescued = rescued
	a.revealed = rescued
	return a


func spawn_child(p: Vector2) -> Agent:
	var a := world.agents.spawn_civilian(world.grid.nearest_walkable(p), true, C.IDLE)
	a.rescued = true
	a.revealed = true
	world.economy.stats["births"] = int(world.economy.stats["births"]) + 1
	world.emit("child_born", [a.id, a.pos])
	return a


func grow_children() -> void:
	var days := Config.f("rules.birth.child_grows_up_days")
	for a in world.agents.list:
		if a.alive and a.is_child:
			a.age_days += 1.0
			if a.age_days >= days:
				a.is_child = false
				a.type = "adult"
				a.max_hp = Config.f("civilians.adult.hp")
				a.hp = a.max_hp
				a.speed = Config.f("civilians.adult.speed")
				a.trait_id = roll_trait()


# ------------------------------------------------------------------ тик
func update(dt: float) -> void:
	var tick := world.tick
	for a in world.agents.list.duplicate():
		if not a.alive or a.kind != Agent.Kind.CIVILIAN or a.hidden and a.civ != C.ROOFTOP:
			continue
		match a.civ:
			C.UNAWARE: _unaware(a, tick)
			C.FOLLOWING: _following(a, dt)
			C.FLEEING: _fleeing(a, dt)
			C.HEADING_TO_BASE: _heading(a)
			C.CHECKPOINT: _checkpoint(a, dt)
			C.IDLE: _idle(a, dt, tick)
			C.WORKING: jobs.work(a, dt)
			C.BUILDING: jobs.build(a)
			C.TRAINING: jobs.training(a)
		if a.civ != C.UNAWARE and a.civ != C.ROOFTOP and (a.id + tick) % 5 == 0:
			_panic_check(a)
	jobs.update_buildings(dt)


func _unaware(a: Agent, tick: int) -> void:
	if (a.id + tick) % 5 != 0:
		return
	_panic_check(a)
	if a.civ != C.UNAWARE:
		return
	var r := Config.f("rules.civilian_ai.contact_radius_m")
	world.agents.hash.query(a.pos, r, tmp, 16)
	for k in tmp:
		var u: Agent = world.agents.hash_list[k]
		if u.is_unit() and u.alive and u.temp_life < 0.0 and follower_count(u) < Config.i("rules.civilian_ai.max_followers_per_unit"):
			_start_follow(a, u)
			return


func _start_follow(a: Agent, u: Agent) -> void:
	a.civ = C.FOLLOWING
	a.leader = u.id
	if not a.revealed:
		a.revealed = true
		world.emit("civilian_found", [a.id, a.pos])


func follower_count(u: Agent) -> int:
	var n := 0
	for a in world.agents.list:
		if a.alive and a.kind == Agent.Kind.CIVILIAN and a.civ == C.FOLLOWING and a.leader == u.id:
			n += 1
	return n


func _following(a: Agent, _dt: float) -> void:
	var u := world.agents.get_agent(a.leader)
	if u == null or not u.alive:
		_panic(a)  # ведущий погиб — паника (GDD §6.1)
		return
	if world.in_base(u.pos) and world.in_base(a.pos):
		_arrive(a)
		return
	if u.hidden:
		return
	var cap := world.units.transport_cap(u, true)
	if cap > 0 and a.pos.distance_to(u.pos) < u.radius + Config.f("rules.sim_tuning.transport_enter_radius_m"):
		if world.units.board(a, u):
			return
	var fd := Config.f("rules.civilian_ai.follow_distance_m") + u.radius
	a.speed_mult = Config.f("units.scout.passive.followers_speed_mult") if u.type == "scout" else 1.0
	if a.pos.distance_to(u.pos) > fd * 1.6:
		if not a.moving or a.dest.distance_to(u.pos) > fd * 2.0:
			world.agents.move_to(a, u.pos + (a.pos - u.pos).normalized() * fd)
	elif a.moving and a.pos.distance_to(u.pos) < fd:
		a.stop()


func _panic_check(a: Agent) -> void:
	if a.civ in [C.FLEEING, C.QUARANTINED, C.TRAINING, C.ROOFTOP]:
		return
	var r := Config.f("rules.civilian_ai.flee_radius_m")
	if a.trait_id != "":
		r *= float(Config.opt("civilians.traits.%s.effects.flee_radius_mult" % a.trait_id, 1.0))
	var zi := world.zombies.hash.nearest(a.pos, r)
	if zi == -1:
		return
	if a.civ == C.FOLLOWING:
		var u := world.agents.get_agent(a.leader)
		if u != null and u.pos.distance_to(a.pos) < 6.0:
			return  # рядом с бойцом не разбегаются
	_panic(a, world.zombies.pos[zi])


func _panic(a: Agent, from: Vector2 = Vector2.INF) -> void:
	if a.civ == C.WORKING or a.civ == C.BUILDING:
		release(a)
	a.civ = C.FLEEING
	a.leader = -1
	a.flee_t = Config.f("rules.civilian_ai.panic_hide_s")
	a.speed_mult = Config.f("rules.civilian_ai.panic_speed_mult")
	var to: Vector2
	if a.rescued:
		to = world.map.hq_pos
	elif from != Vector2.INF:
		to = a.pos + (a.pos - from).normalized() * 25.0
	else:
		to = a.pos + Vector2(world.rng.randf_range(-20, 20), world.rng.randf_range(-20, 20))
	world.agents.move_to(a, world.grid.nearest_walkable(to, 30.0))


func _fleeing(a: Agent, dt: float) -> void:
	a.flee_t -= dt
	if a.flee_t > 0.0 and a.moving:
		return
	a.speed_mult = 1.0
	if a.rescued:
		a.civ = C.IDLE
	else:
		a.civ = C.UNAWARE  # спрятался в ближайшем укрытии и ждёт следующего бойца


## Сирена / «Сирена спасения»: мирные сами идут на базу — без охраны, через зомби.
func call_to_base(p: Vector2, r: float, speed_mult: float) -> void:
	for a in world.agents.list:
		if a.alive and a.kind == Agent.Kind.CIVILIAN and not a.rescued and not a.hidden and a.pos.distance_to(p) <= r:
			if a.civ in [C.UNAWARE, C.FLEEING, C.FOLLOWING]:
				a.civ = C.HEADING_TO_BASE
				a.leader = -1
				a.speed_mult = speed_mult * Config.f("rules.civilian_ai.panic_speed_mult")
				a.revealed = true
				world.agents.move_to(a, world.map.gate_outer)


func _heading(a: Agent) -> void:
	if world.in_base(a.pos):
		_arrive(a)
	elif not a.moving:
		world.agents.move_to(a, world.map.hq_pos)


## Мирный дошёл до базы: на КПП (если есть) или сразу в свободные.
func _arrive(a: Agent) -> void:
	a.leader = -1
	a.speed_mult = 1.0
	var kpp := _nearest_checkpoint(a.pos)
	if kpp != null and Config.opt("rules.infection.checkpoint_detects_infected", true):
		a.civ = C.CHECKPOINT
		a.job_t = Config.f("rules.civilian_ai.checkpoint_scan_s")
		a.work_b = kpp.id
		world.agents.move_to(a, kpp.door)
	else:
		_admit(a)


func _nearest_checkpoint(p: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for b in world.buildings.all_of("checkpoint"):
		if b.working() and b.pos.distance_to(p) < bd:
			bd = b.pos.distance_to(p)
			best = b
	return best


func _checkpoint(a: Agent, dt: float) -> void:
	var b := world.buildings.get_building(a.work_b)
	if b == null or not b.working():
		_admit(a)
		return
	if a.pos.distance_to(b.door) > Config.f("buildings.checkpoint.scan_radius"):
		if not a.moving:
			world.agents.move_to(a, b.door)
		return
	a.job_t -= dt
	if a.job_t > 0.0:
		return
	if a.infected and not a.infect_detected:
		a.infect_detected = true
		world.emit("infection_detected", [a.id, a.pos, "checkpoint"])
	_admit(a)
	if a.infected:
		jobs.send_to_quarantine(a)


func _admit(a: Agent) -> void:
	a.civ = C.IDLE
	a.work_b = -1
	if not a.rescued:
		a.rescued = true
		world.economy.stats["rescued"] = int(world.economy.stats["rescued"]) + 1
		world.emit("civilian_rescued", [a.id, a.pos])
		if world.time - last_group_t > Config.f("rules.sim_tuning.rescue_group_window_s"):
			world.economy.morale_event("rescued", Config.f("rules.morale.modifiers.rescued_group_arrives"))
		last_group_t = world.time


func after_unload(a: Agent) -> void:
	if world.in_base(a.pos):
		_arrive(a)
	else:
		a.civ = C.UNAWARE if not a.rescued else C.IDLE


func _idle(a: Agent, dt: float, tick: int) -> void:
	if not a.rescued:
		a.civ = C.UNAWARE
		return
	if a.moving or (a.id + tick) % 40 != 0:
		return
	if not world.in_base(a.pos) or world.rng.randf() < 0.3:
		var r := Config.f("rules.civilian_ai.idle_wander_m")
		var c := world.map.hq_pos + Vector2(world.rng.randf_range(-r, r) * 3.0, world.rng.randf_range(-r, r) * 3.0)
		world.agents.move_to(a, world.grid.nearest_walkable(c, 20.0))


# ------------------------------------------------------------------ назначения
func release(a: Agent) -> void:
	var b := world.buildings.get_building(a.work_b)
	if b != null:
		b.workers.erase(a.id)
		b.builders.erase(a.id)
	jobs.unclaim(a)
	a.work_b = -1
	a.carry = {}
	a.hidden = false
	a.container = -1
	if a.civ != C.FLEEING:
		a.civ = C.IDLE if a.rescued else C.UNAWARE


func assign_builder(a: Agent, b: Building) -> void:
	release(a)
	a.civ = C.BUILDING
	a.work_b = b.id
	world.agents.move_to(a, world.grid.nearest_walkable(b.door, 20.0))


func start_training(a: Agent, b: Building) -> void:
	release(a)
	a.civ = C.TRAINING
	a.work_b = b.id
	world.agents.move_to(a, b.door)


func reveal_around(p: Vector2, r: float) -> void:
	for a in world.agents.list:
		if a.alive and a.kind == Agent.Kind.CIVILIAN and not a.revealed and a.pos.distance_to(p) <= r:
			a.revealed = true
			world.emit("civilian_found", [a.id, a.pos])


func on_died(a: Agent) -> void:
	var b := world.buildings.get_building(a.work_b)
	if b != null:
		b.workers.erase(a.id)
		b.builders.erase(a.id)
		b.patients.erase(a.id)
	jobs.unclaim(a)


## Голод: умирает доля мирных (rules.starvation).
func starve(frac: float) -> int:
	var cands: Array[Agent] = []
	for a in world.agents.list:
		if a.alive and a.kind == Agent.Kind.CIVILIAN and a.rescued:
			cands.append(a)
	var n := int(ceil(cands.size() * frac))
	for k in n:
		world.combat.kill_agent(cands[world.rng.randi() % cands.size()])
		cands = cands.filter(func(x: Agent) -> bool: return x.alive)
		if cands.is_empty():
			break
	return n
