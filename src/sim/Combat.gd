class_name Combat
extends RefCounted
## Урон × броня (combat.json), заражение при укусе (GDD §8.2), смерти агентов, AoE.

var world: World
var mult: Dictionary
var tmp := PackedInt32Array()


func setup(w: World) -> void:
	world = w
	mult = Config.d("combat.damage_types")


func k(damage_type: String, armor: String) -> float:
	var row: Dictionary = mult.get(damage_type, {})
	return float(row.get(armor, 1.0))


# ------------------------------------------------------------------ по зомби
func hit_zombie(i: int, dmg: float, damage_type: String, from: Vector2) -> bool:
	var z := world.zombies
	if z.alive[i] == 0:
		return false
	var d := z.pos[i] - from
	var killed := z.damage(i, dmg * k(damage_type, z.armor_of(i)), atan2(d.x, d.y))
	if killed:
		world.economy.stats["kills"] = int(world.economy.stats["kills"]) + 1
		world.score_add("kills", 1)
	elif z.state[i] == ZombieSystem.S.IDLE or z.state[i] == ZombieSystem.S.INVESTIGATE:
		z.state[i] = ZombieSystem.S.INVESTIGATE  # подстреленный идёт на стрелка
		z.goal[i] = from
		z.timer[i] = Config.f("zombies.ai.investigate_timeout_s")
	return killed


func aoe(center: Vector2, radius: float, dmg: float, damage_type: String, kind: String) -> int:
	var z := world.zombies
	z.hash.query(center, radius, tmp)
	var kills := 0
	for i in tmp:
		if hit_zombie(i, dmg, damage_type, center):
			kills += 1
	for n in world.map.nests:
		if n.alive and n.pos.distance_to(center) <= radius + n.radius:
			world.map.damage_nest(n, dmg * k(damage_type, "structure"))
	world.emit("explosion", [center, radius, kind])
	return kills


# ------------------------------------------------------------------ по агентам
func zombie_hits_agent(zi: int, a: Agent, atk: Dictionary) -> bool:
	if a == null or not a.alive:
		return false
	var z := world.zombies
	var dtype := String(atk["damage_type"])
	var dmg := float(atk["damage"]) * k(dtype, a.armor)
	if a.kind == Agent.Kind.INFANTRY and world.units.in_cover(a):
		dmg *= Config.f("buildings.sandbags.cover_damage_mult")
	if atk.has("dot_dps"):
		a.dot_dps = float(atk["dot_dps"]) * k(dtype, a.armor)
		a.dot_t = float(atk["dot_s"])
	if atk.has("knockback") and a.kind != Agent.Kind.AIR:
		var push := (a.pos - z.pos[zi]).normalized() * float(atk["knockback"])
		var np := a.pos + push
		if world.grid.walkable(np):
			a.pos = np
	if dtype != "acid":
		_maybe_infect(a, z.t_infect[z.type_id[zi]])
	return damage_agent(a, dmg)


func _maybe_infect(a: Agent, zombie_chance: float) -> void:
	if a.infected or a.kind == Agent.Kind.VEHICLE or a.kind == Agent.Kind.AIR:
		return
	var inf := "rules.infection."
	var chance: float
	var inc: String
	if a.kind == Agent.Kind.CIVILIAN:
		chance = world.mods.civilian_infect_chance(a)
		inc = inf + "incubation_civilian_s"
	else:
		chance = zombie_chance * world.mods.infect_chance_mult(a)
		inc = inf + "incubation_soldier_s"
	if a.temp_life >= 0.0 or world.rng.randf() >= chance:
		return
	a.infected = true
	a.infect_t = Config.range_roll(inc, world.rng)
	a.infect_detected = false
	var inside := world.in_base(a.pos)
	world.emit("civilian_infected", [a.id, a.pos, inside])


func damage_agent(a: Agent, dmg: float) -> bool:
	if not a.alive:
		return false
	a.hp -= dmg
	if a.hp <= 0.0:
		kill_agent(a)
		return true
	return false


func kill_agent(a: Agent) -> void:
	if not a.alive:
		return
	var p := a.pos
	world.units.eject_passengers(a, true)
	world.agents.remove(a)
	if a.kind == Agent.Kind.CIVILIAN:
		world.civilians.on_died(a)
		if a.rescued:
			world.economy.stats["civ_lost"] = int(world.economy.stats["civ_lost"]) + 1
			world.economy.morale_event("deaths", Config.f("rules.morale.modifiers.civilian_death_each"))
		world.emit("civilian_died", [a.id, p])
		return
	if a.temp_life < 0.0:
		world.economy.stats["soldiers_lost"] = int(world.economy.stats["soldiers_lost"]) + 1
	world.emit("unit_died", [a.id, a.type, p])
	if a.kind != Agent.Kind.INFANTRY:
		_eject_crew(a, p)


## Экипаж катапультируется штурмовиками с 50% HP (GDD §6.3).
func _eject_crew(a: Agent, p: Vector2) -> void:
	var chance := Config.f("units.%s.crew_eject_chance" % a.type)
	for _n in int(Config.f("units.%s.recruits" % a.type)):
		if world.rng.randf() < chance:
			var s := world.agents.spawn_unit("assault", a.owner, p + Vector2(world.rng.randf_range(-3, 3), world.rng.randf_range(-3, 3)))
			s.hp = s.max_hp * Config.f("rules.sim_tuning.ejected_crew_hp_frac")


## Таймеры инкубации и кислоты; по истечении — зомби на месте (tech spec §3.4).
func update_agents(dt: float) -> void:
	var symptoms := Config.f("rules.infection.symptoms_visible_last_s")
	for a in world.agents.list.duplicate():
		if not a.alive:
			continue
		if a.dot_t > 0.0:
			a.dot_t -= dt
			if damage_agent(a, a.dot_dps * dt):
				continue
		if not a.infected:
			continue
		a.infect_t -= dt
		if a.infect_t <= symptoms and not a.infect_detected:
			a.infect_detected = true
			world.emit("infection_detected", [a.id, a.pos, "symptoms"])
		if a.infect_t <= 0.0:
			turn(a)


func turn(a: Agent) -> void:
	var p := a.pos
	if a.hidden and a.container >= 0:
		var b := world.buildings.get_building(a.container)
		if b != null:
			p = b.door
	var inside := world.in_base(p)
	var quarantined := a.civ == Agent.Civ.QUARANTINED
	var key := "turned_civilian_becomes" if a.kind == Agent.Kind.CIVILIAN else "turned_soldier_becomes"
	var ztype := world.zombies.type_index(String(Config.g("rules.infection." + key)))
	a.infected = false
	kill_agent(a)
	if quarantined:
		return  # в карантине обращаются и умирают без вспышки (GDD §8.2)
	world.zombies.spawn(ztype, world.grid.nearest_walkable(p, 10.0, true))
	world.emit("civilian_turned", [a.id, p, inside])
	if inside:
		world.economy.morale_event("outbreak", Config.f("rules.morale.modifiers.outbreak_inside_base"))
		world.outbreaks += 1
		world.emit("outbreak_in_base", [p])


func cure(a: Agent) -> void:
	a.infected = false
	a.infect_t = 0.0
	a.infect_detected = false
	if a.civ == Agent.Civ.QUARANTINED:
		world.civilians.release(a)


# ------------------------------------------------------------------ по постройкам
func zombie_hits_building(zi: int, b: Building, atk: Dictionary) -> void:
	if b == null or not b.alive:
		return
	var dmg := float(atk["damage"]) * k(String(atk["damage_type"]), "structure")
	world.buildings.damage(b, dmg)
	if not b.alive:
		world.zombies.target[zi] = ZombieSystem.NO_TARGET
