class_name Abilities
extends RefCounted
## Способности юнитов (units.json/abilities) и доктрин (doctrines.json/ability). GDD §4, §7.

var world: World
var lures: Array[Dictionary] = []    # сигнальные ракеты: {pos, t, cd}
var smokes: Array[Dictionary] = []   # {pos, r, t}
var fires: Array[Dictionary] = []    # напалм: {a, b, w, dps, t}
var reveals: Array[Dictionary] = []  # воздушная разведка: {pos, r, t}
var repairs: Array[Dictionary] = []  # ремкомплект: {id, hps, t}
var tmp := PackedInt32Array()


func setup(w: World) -> void:
	world = w


func ab(id: String) -> Dictionary:
	return Config.d("units.abilities." + id)


func cooldown_left(a: Agent, id: String) -> float:
	return float(a.ability_cd.get(id, 0.0))


## "" — можно, иначе ключ причины.
func check(a: Agent, id: String) -> String:
	if not Config.a("units.%s.abilities" % a.type).has(id):
		return "ABIL_ERR_NONE"
	if cooldown_left(a, id) > 0.0:
		return "ABIL_ERR_CD"
	var tech: Variant = ab(id).get("requires_tech")
	if tech != null and not world.tech.has(String(tech)):
		return "ABIL_ERR_TECH"
	return ""


func use(a: Agent, id: String, p: Vector2) -> bool:
	if a == null or not a.alive or check(a, id) != "":
		return false
	var d := ab(id)
	var rng := float(d.get("range", 0.0))
	if rng > 0.0 and a.pos.distance_to(p) > rng:
		p = a.pos + (p - a.pos).normalized() * rng
	var cd := float(d["cooldown_s"])
	match id:
		"grenade":
			world.combat.aoe(p, float(d["aoe"]), float(d["damage"]) * a.dmg_mult, String(d["damage_type"]), "grenade")
			world.noise.emit(p, float(d["noise"]))
		"aimed_shot":
			a.ability_cd["_aimed"] = cd  # следующий выстрел по особому ×3
		"antidote":
			if not _antidote(a, p, float(d["range"])):
				return false
			cd *= world.mods.antidote_cd_mult()
		"flare":
			lures.append({"pos": p, "t": float(d["duration_s"]), "cd": 0.0, "noise": float(d["noise"])})
		"camo":
			a.camo_t = float(d["duration_s"])
		"smoke":
			smokes.append({"pos": a.pos, "r": float(d["aoe"]), "t": float(d["duration_s"])})
			_smoke_pulse(smokes[-1])
		"ram":
			a.ram_t = float(d["duration_s"])
			a.speed_mult = float(d["speed_mult"])
		"napalm":
			var dir := (p - a.pos).normalized() if p.distance_to(a.pos) > 1.0 else Vector2(sin(a.facing), cos(a.facing))
			var start := a.pos
			fires.append({"a": start, "b": start + dir * float(d["length"]), "w": float(d["width"]),
				"dps": float(d["dps"]), "t": float(d["duration_s"])})
			world.noise.emit(a.pos, float(d["noise"]))
	a.ability_cd[id] = cd
	world.emit("ability_used", [a.id, id, p])
	return true


func _antidote(a: Agent, p: Vector2, rng: float) -> bool:
	var best: Agent = null
	var bd := INF
	world.agents.hash.query(a.pos, rng, tmp)
	for k in tmp:
		var b: Agent = world.agents.hash_list[k]
		if b.infected and b.pos.distance_to(p) < bd:
			bd = b.pos.distance_to(p)
			best = b
	if best == null:
		return false
	world.combat.cure(best)
	return true


## Медик сам колет антидот выявленным заражённым рядом (экономит микроконтроль).
func auto_antidote(a: Agent) -> void:
	if cooldown_left(a, "antidote") > 0.0:
		return
	var r := Config.f("units.abilities.antidote.range")
	world.agents.hash.query(a.pos, r, tmp)
	for k in tmp:
		var b: Agent = world.agents.hash_list[k]
		if b.infected and b.infect_detected:
			use(a, "antidote", b.pos)
			return


# ------------------------------------------------------------------ доктрины
func doctrine_check(pid: int, doctrine: String) -> String:
	if not world.player_doctrines(pid).has(doctrine):
		return "ABIL_ERR_NONE"
	if world.doctrine_cd(pid, doctrine) > 0.0:
		return "ABIL_ERR_CD"
	return ""


func use_doctrine(pid: int, doctrine: String, p: Vector2) -> bool:
	if doctrine_check(pid, doctrine) != "":
		return false
	var d := Config.d("doctrines.%s.ability" % doctrine)
	match String(d["id"]):
		"assault_squad":
			for k in int(d["count"]):
				var u := world.agents.spawn_unit(String(d["unit"]), pid, p + Vector2(k * 1.5 - 1.5, 0))
				u.temp_life = float(d["life_s"])
		"field_repair":
			for a in world.agents.list:
				if a.alive and a.kind == Agent.Kind.VEHICLE and a.pos.distance_to(p) <= float(d["radius"]):
					repairs.append({"id": a.id, "hps": a.max_hp * float(d["heal_frac"]) / float(d["duration_s"]), "t": float(d["duration_s"])})
		"air_recon":
			reveals.append({"pos": p, "r": float(d["radius"]), "t": float(d["duration_s"])})
			world.civilians.reveal_around(p, float(d["radius"]))
		"rescue_siren":
			world.civilians.call_to_base(p, float(d["radius"]), float(d["speed_mult"]))
			world.noise.emit(p, float(d["noise"]))
	world.set_doctrine_cd(pid, doctrine, float(d["cooldown_s"]))
	world.emit("ability_used", [-pid, String(d["id"]), p])
	return true


## Громкоговоритель на базе: мирные в радиусе сами идут на базу (GDD §6.1).
func use_siren(b: Building) -> bool:
	if b == null or b.type != "siren" or not b.working() or b.ability_cd > 0.0:
		return false
	var s := Config.d("buildings.siren.active_ability")
	world.civilians.call_to_base(b.pos, float(s["call_civilians_radius"]), 1.0)
	world.noise.emit(b.pos, float(s["noise"]))
	b.ability_cd = float(s["cooldown_s"])
	world.emit("ability_used", [0, "siren", b.pos])
	return true


# ------------------------------------------------------------------ тик эффектов
func update(dt: float) -> void:
	for l in lures:
		l["t"] = float(l["t"]) - dt
		l["cd"] = float(l["cd"]) - dt
		if float(l["cd"]) <= 0.0:
			l["cd"] = Config.f("rules.sim_tuning.continuous_noise_interval_s")
			world.noise.emit(l["pos"], float(l["noise"]))
	lures = lures.filter(func(l: Dictionary) -> bool: return float(l["t"]) > 0.0)
	for s in smokes:
		s["t"] = float(s["t"]) - dt
		_smoke_pulse(s)
	smokes = smokes.filter(func(s: Dictionary) -> bool: return float(s["t"]) > 0.0)
	for f in fires:
		f["t"] = float(f["t"]) - dt
		_burn(f, dt)
	fires = fires.filter(func(f: Dictionary) -> bool: return float(f["t"]) > 0.0)
	for r in reveals:
		r["t"] = float(r["t"]) - dt
	reveals = reveals.filter(func(r: Dictionary) -> bool: return float(r["t"]) > 0.0)
	for r in repairs:
		r["t"] = float(r["t"]) - dt
		var a := world.agents.get_agent(int(r["id"]))
		if a != null:
			a.hp = minf(a.max_hp, a.hp + float(r["hps"]) * dt)
	repairs = repairs.filter(func(r: Dictionary) -> bool: return float(r["t"]) > 0.0)
	for b in world.buildings.list:
		if b.ability_cd > 0.0:
			b.ability_cd -= dt


func _smoke_pulse(s: Dictionary) -> void:
	var z := world.zombies
	z.hash.query(s["pos"], float(s["r"]), tmp)
	for i in tmp:
		z.flags[i] |= ZombieSystem.F_BLIND
		if z.state[i] == ZombieSystem.S.CHASE or z.state[i] == ZombieSystem.S.ATTACK:
			world.zombie_brain.lose_target(i)


func in_smoke(p: Vector2) -> bool:
	for s in smokes:
		if p.distance_to(s["pos"]) <= float(s["r"]):
			return true
	return false


func _burn(f: Dictionary, dt: float) -> void:
	var a: Vector2 = f["a"]
	var b: Vector2 = f["b"]
	var mid := (a + b) * 0.5
	var z := world.zombies
	z.hash.query(mid, a.distance_to(b) * 0.5 + float(f["w"]), tmp)
	for i in tmp:
		var p := z.pos[i]
		var cp := Geometry2D.get_closest_point_to_segment(p, a, b)
		if cp.distance_to(p) <= float(f["w"]) * 0.5:
			world.combat.hit_zombie(i, float(f["dps"]) * dt, "explosive", cp)
