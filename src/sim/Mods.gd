class_name Mods
extends RefCounted
## Все множители в одном месте: доктрины (doctrines.json/effects), технологии (tech.json/mods),
## черты мирных (civilians.json/traits), мораль (rules.morale.effects). Остальные системы только спрашивают.

var world: World


func setup(w: World) -> void:
	world = w


func _doctrines(owner: int) -> Array:
	return world.player_doctrines(owner)


func _doc_eff(owner: int, key: String) -> Array:
	var out: Array = []
	for d: String in _doctrines(owner):
		var e: Dictionary = Config.opt("doctrines.%s.effects" % d, {})
		if e.has(key):
			out.append(e[key])
	return out


func _tech_mod(key: String) -> Variant:
	for t: String in world.tech.done:
		var m: Dictionary = Config.opt("tech.%s.mods" % t, {})
		if m.has(key):
			return m[key]
	return null


func _trait(trait_id: String, key: String, default: float) -> float:
	if trait_id == "":
		return default
	return float(Config.opt("civilians.traits.%s.effects.%s" % [trait_id, key], default))


func category(type: String) -> String:
	return String(Config.g("units.%s.category" % type))


# ------------------------------------------------------------------ юниты
func unit_cost(type: String, owner: int) -> Dictionary:
	var base: Dictionary = Config.d("units.%s.cost" % type).duplicate()
	for m: Dictionary in _doc_eff(owner, "cost_mult"):
		if m.has(type):
			for r: String in base:
				base[r] = ceilf(float(base[r]) * float(m[type]))
	for m: Dictionary in _doc_eff(owner, "iron_cost_mult"):
		if m.has(type) and base.has("iron"):
			base["iron"] = ceilf(float(base["iron"]) * float(m[type]))
	return base


func unit_hp_mult(type: String, owner: int, trait_id: String) -> float:
	var k := 1.0
	var cat := category(type)
	for m: Dictionary in _doc_eff(owner, "hp_mult_category"):
		k *= float(m.get(cat, 1.0))
	if cat == "infantry":
		var t: Variant = _tech_mod("infantry_hp_mult")
		if t != null:
			k *= float(t)
		k *= _trait(trait_id, "as_soldier_hp_mult", 1.0)
	else:
		k *= _trait(trait_id, "as_crew_vehicle_hp_mult", 1.0)
	return k


func unit_damage_mult(type: String, _owner: int, trait_id: String) -> float:
	return _trait(trait_id, "as_soldier_damage_mult", 1.0) if category(type) == "infantry" else 1.0


func unit_speed_mult(type: String, _owner: int, trait_id: String) -> float:
	return _trait(trait_id, "as_crew_vehicle_speed_mult", 1.0) if category(type) != "infantry" else 1.0


func train_time_mult(trait_id: String) -> float:
	return _trait(trait_id, "train_time_mult", 1.0)


func heli_flight_time(owner: int) -> float:
	var t := Config.f("units.heli.flight_time_s")
	for m: Variant in _doc_eff(owner, "heli_flight_time_mult"):
		t *= float(m)
	return t


func noise_attack(a: Agent) -> float:
	var n := Config.f("units.%s.noise_attack" % a.type)
	var m: Variant = _tech_mod("noise_attack_mult")
	if m is Dictionary and (m as Dictionary).has(a.type):
		n *= float(m[a.type])
	return n


func infect_chance_mult(a: Agent) -> float:
	var k := float(Config.opt("units.%s.infect_resist" % a.type, 1.0))
	if a.kind == Agent.Kind.INFANTRY:
		var t: Variant = _tech_mod("infect_chance_mult")
		if t != null:
			k *= float(t)
	return k


func civilian_infect_chance(a: Agent) -> float:
	var base := Config.f("rules.infection.civilian_hit_infect_chance")
	var v: Variant = _tech_mod("base_civilian_infect_chance")
	if v != null and world.in_base(a.pos):
		base = float(v)
	return base


func medic_heal_mult(a: Agent) -> float:
	var k := _trait(a.trait_id, "as_medic_heal_mult", 1.0)
	var t: Variant = _tech_mod("medic_heal_mult")
	return k * (float(t) if t != null else 1.0)


func antidote_cd_mult() -> float:
	var t: Variant = _tech_mod("antidote_cd_mult")
	return float(t) if t != null else 1.0


func ignores_night() -> bool:
	return _tech_mod("ignore_night_vision") == true


func wave_info_early() -> bool:
	return _tech_mod("wave_info_from_day_start") == true


## Видимость юнита с учётом ночи и света (GDD §9).
func vision_of(a: Agent) -> float:
	var v := a.vision
	if world.clock.is_night() and not ignores_night() and not world.light.lit(a.pos):
		v *= Config.f("combat.light.unit_vision_dark_mult")
	return v


func terrain_speed_mult(a: Agent) -> float:
	if a.kind != Agent.Kind.VEHICLE:
		var k := 1.0
		if a.camo_t > 0.0:
			k *= Config.f("units.abilities.camo.move_speed_mult")
		return k
	var road := world.grid.is_road(a.pos)
	var off := Config.f("units.%s.speed_offroad" % a.type)
	var on := Config.f("units.%s.speed" % a.type)
	return 1.0 if road else off / on


# ------------------------------------------------------------------ лагерь
func work_speed() -> float:
	return world.economy.morale_effect("work_speed_mult", 1.0)


func build_rate(a: Agent, owner: int) -> float:
	var k := Config.f("civilians.adult.build_rate") * _trait(a.trait_id, "build_rate_mult", 1.0) * work_speed()
	for m: Variant in _doc_eff(owner, "build_mult"):
		k *= float(m)
	return k


func gather_rate(a: Agent, owner: int) -> float:
	var k := _trait(a.trait_id, "gather_rate_mult", 1.0) * work_speed()
	for m: Variant in _doc_eff(owner, "gather_mult"):
		k *= float(m)
	return k


func greenhouse_mult(a: Agent) -> float:
	var k := _trait(a.trait_id, "greenhouse_yield_mult", 1.0) * work_speed()
	var t: Variant = _tech_mod("greenhouse_yield_mult")
	return k * (float(t) if t != null else 1.0)


func research_rate(a: Agent) -> float:
	return _trait(a.trait_id, "research_mult", 1.0) * work_speed()


func medpost_heal_mult(a: Agent) -> float:
	return _trait(a.trait_id, "medpost_heal_mult", 1.0)


func cure_time_mult(a: Agent) -> float:
	return _trait(a.trait_id, "cure_time_mult", 1.0)


func cook_value(a: Agent) -> float:
	return _trait(a.trait_id, "kitchen_counts_as", 1.0)


func birth_chance() -> float:
	var c := Config.f("rules.birth.chance_per_house_per_day")
	for p in world.players:
		for m: Variant in _doc_eff(int(p["pid"]), "birth_chance_add"):
			c += float(m)
	return c


func tech_time(tech: String) -> float:
	var t := Config.f("tech.%s.research_s" % tech)
	for p in world.players:
		for m: Dictionary in _doc_eff(int(p["pid"]), "tech_time_mult"):
			if m.has(tech):
				t *= float(m[tech])
	return t


func tech_ignores_requires(tech: String) -> bool:
	for p in world.players:
		for arr: Array in _doc_eff(int(p["pid"]), "tech_ignore_requires"):
			if arr.has(tech):
				return true
	return false
