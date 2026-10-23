class_name CivilianJobs
extends RefCounted
## Работа мирных (GDD §6.2, M2-4): слоты в зданиях, рейсы добытчиков к деревьям и остовам,
## медпункт (аура + лечение заражения), карантин, сбор рекрутов.

const C := Agent.Civ
enum Phase { TO_NODE, GATHER, TO_BUILDING }

var world: World
var civ: CivilianSystem
var tmp := PackedInt32Array()


func setup(w: World, c: CivilianSystem) -> void:
	world = w
	civ = c


## Команда assign: свободные взрослые → слоты здания. Возвращает число назначенных.
func assign(ids: Array, b: Building) -> int:
	if b == null or not b.complete() or b.worker_slots <= 0:
		return 0
	var n := 0
	for id: int in ids:
		if b.workers.size() >= b.worker_slots:
			break
		var a := world.agents.get_agent(id)
		if a == null or a.is_child or not a.rescued or a.kind != Agent.Kind.CIVILIAN:
			continue
		if not (a.civ in [C.IDLE, C.WORKING, C.BUILDING]):
			continue
		civ.release(a)
		a.civ = C.WORKING
		a.work_b = b.id
		a.job_phase = Phase.TO_BUILDING
		b.workers.append(a.id)
		world.agents.move_to(a, b.door)
		n += 1
	return n


## «+» в карточке здания: ближайший свободный взрослый.
func assign_nearest(b: Building) -> bool:
	var a := world.agents.nearest_free_adult(b.pos)
	return a != null and assign([a.id], b) == 1


func unassign_one(b: Building) -> void:
	if b.workers.is_empty():
		return
	var a := world.agents.get_agent(b.workers[-1])
	if a != null:
		civ.release(a)
	else:
		b.workers.pop_back()


func unclaim(a: Agent) -> void:
	if a.job_node >= 0 and a.job_node < world.map.node_claims.size():
		world.map.node_claims[a.job_node] = maxi(0, world.map.node_claims[a.job_node] - 1)
	a.job_node = -1


func work(a: Agent, dt: float) -> void:
	var b := world.buildings.get_building(a.work_b)
	if b == null or not b.alive:
		civ.release(a)
		return
	var d := b.data()
	if d.has("gathers_from"):
		_gather(a, b, d, dt)
	elif not a.moving and a.pos.distance_to(b.door) > 3.0:
		world.agents.move_to(a, b.door)
	elif not a.moving:
		# работники цехов (генератор, кухня, теплица…) — внутри здания, а не толпой в дверях
		a.hidden = true
		a.container = b.id


func _gather(a: Agent, b: Building, d: Dictionary, dt: float) -> void:
	var kind := 0 if String(d["gathers_from"]) == "tree" else 1
	var res := "wood" if kind == 0 else "iron"
	var shelter := bool(Config.opt("rules.civilian_ai.workers_shelter_at_night", false)) and world.clock.is_dark()
	if shelter and a.job_phase != Phase.TO_BUILDING:
		unclaim(a)
		a.job_phase = Phase.TO_BUILDING
		world.agents.move_to(a, b.door)
	match a.job_phase:
		Phase.TO_BUILDING:
			if a.moving:
				return
			if a.pos.distance_to(b.door) > 3.0:
				world.agents.move_to(a, b.door)
				return
			if a.carry.has(res):
				var got := world.economy.add(res, float(a.carry[res]))
				world.emit("resource_delivered", [res, got, b.door])
				a.carry = {}
			if shelter or not b.working():
				return
			_pick_node(a, b, kind, float(d["work_radius"]))
		Phase.TO_NODE:
			if a.job_node < 0 or world.map.node_alive[a.job_node] == 0:
				_pick_node(a, b, kind, float(d["work_radius"]))
				return
			if not a.moving:
				if a.pos.distance_to(world.map.node_pos[a.job_node]) <= 3.5:
					a.job_phase = Phase.GATHER
					a.job_t = _gather_time(a, b, res)
				else:
					world.agents.move_to(a, world.grid.nearest_walkable(world.map.node_pos[a.job_node], 6.0))
		Phase.GATHER:
			a.job_t -= dt
			a.noise_cd -= dt
			if a.noise_cd <= 0.0:
				a.noise_cd = Config.f("rules.sim_tuning.continuous_noise_interval_s")
				world.noise.emit(a.pos, Config.f("combat.noise_events.gather_" + res))
			if a.job_t <= 0.0:
				var cap := Config.f("civilians.adult.carry_capacity." + res)
				var got := world.map.take_from_node(a.job_node, cap)
				a.carry = {res: got}
				unclaim(a)
				a.job_phase = Phase.TO_BUILDING
				world.agents.move_to(a, b.door)


## Время у узла так, чтобы в среднем выйти на yield_per_worker_per_day (tech spec §3.5).
func _gather_time(a: Agent, b: Building, res: String) -> float:
	var y := Config.f("buildings.%s.yield_per_worker_per_day.%s" % [b.type, res])
	var per_s := y / world.clock.day_length() * world.mods.gather_rate(a, b.owner)
	var cap := Config.f("civilians.adult.carry_capacity." + res)
	return cap / maxf(per_s, 0.0001) * Config.f("rules.civilian_ai.gather_trip_efficiency")


func _pick_node(a: Agent, b: Building, kind: int, radius: float) -> void:
	var i := world.map.nearest_node(kind, a.pos, b.pos, radius)
	if i < 0:
		a.job_phase = Phase.TO_BUILDING
		return
	a.job_node = i
	world.map.node_claims[i] += 1
	a.job_phase = Phase.TO_NODE
	world.agents.move_to(a, world.grid.nearest_walkable(world.map.node_pos[i], 6.0))


func build(a: Agent) -> void:
	var b := world.buildings.get_building(a.work_b)
	if b == null or not world.buildings.needs_builders(b):
		civ.release(a)
		return
	var reach := Config.f("rules.build.builder_reach_m") + b.half_extent()
	if not a.moving and a.pos.distance_to(b.pos) > reach:
		world.agents.move_to(a, world.grid.nearest_walkable(b.door, 20.0))


func training(a: Agent) -> void:
	var b := world.buildings.get_building(a.work_b)
	if b == null:
		civ.release(a)
		return
	if not a.moving and a.pos.distance_to(b.door) <= 3.0:
		a.hidden = true
		a.container = b.id
	elif not a.moving:
		world.agents.move_to(a, b.door)


# ------------------------------------------------------------------ медицина
func send_to_quarantine(a: Agent) -> bool:
	for q in world.buildings.all_of("quarantine"):
		if q.patients.size() < int(q.data()["capacity"]):
			civ.release(a)
			q.patients.append(a.id)
			a.civ = C.QUARANTINED
			a.work_b = q.id
			a.hidden = true
			a.container = q.id
			a.pos = q.door
			return true
	world.emit("alert", ["infected", "ALERT_NO_QUARANTINE", a.pos])
	return false


func update_buildings(dt: float) -> void:
	for b in world.buildings.list:
		if b.type == "medpost" and b.working():
			_medpost(b, dt)
		elif b.type == "quarantine":
			b.patients = b.patients.filter(func(id: int) -> bool:
				var p := world.agents.get_agent(id)
				return p != null and p.alive and p.civ == C.QUARANTINED)


func _medpost(b: Building, dt: float) -> void:
	var aura := Config.d("buildings.medpost.heal_aura")
	var heal_mult := 1.0
	var doctors: Array[Agent] = []
	for id in b.workers:
		var w := world.agents.get_agent(id)
		if w != null and w.civ == C.WORKING and w.pos.distance_to(b.door) < 4.0:
			doctors.append(w)
			heal_mult = maxf(heal_mult, world.mods.medpost_heal_mult(w))
	if doctors.is_empty():
		return
	world.agents.hash.query(b.pos, float(aura["radius"]) + b.half_extent(), tmp)
	for k in tmp:
		var p: Agent = world.agents.hash_list[k]
		if p.kind != Agent.Kind.VEHICLE and p.kind != Agent.Kind.AIR:
			p.hp = minf(p.max_hp, p.hp + float(aura["hps"]) * heal_mult * dt)
	# лечение заражения: один пациент на врача, cure_time × черта (GDD §8.2)
	for doc in doctors:
		var pat := world.agents.get_agent(doc.order_target)
		if pat == null or not pat.alive or not pat.infected:
			pat = _next_patient(b)
			doc.order_target = pat.id if pat != null else -1
			doc.job_t = Config.f("rules.infection.medpost_cure_time_s") * world.mods.cure_time_mult(doc)
			continue
		doc.job_t -= dt
		if doc.job_t <= 0.0:
			world.combat.cure(pat)
			doc.order_target = -1


func _next_patient(b: Building) -> Agent:
	var taken: Array[int] = []
	for id in b.workers:
		var w := world.agents.get_agent(id)
		if w != null:
			taken.append(w.order_target)
	var best: Agent = null
	var bd := INF
	for a in world.agents.list:
		if a.alive and a.infected and a.infect_detected and not taken.has(a.id) and world.in_base(a.pos if not a.hidden else b.pos):
			var d := a.pos.distance_to(b.pos) - (1000.0 if a.civ == C.QUARANTINED else 0.0)
			if d < bd:
				bd = d
				best = a
	return best
