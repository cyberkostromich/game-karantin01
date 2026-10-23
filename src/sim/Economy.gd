class_name Economy
extends RefCounted
## Склад, энергосеть, мораль, рассвет: еда, рождения, взросление (GDD §5, §6.2, §12; tech spec §3.5).

const RES: PackedStringArray = ["food", "wood", "iron"]

var world: World
var res: Dictionary = {"food": 0.0, "wood": 0.0, "iron": 0.0}
var power_prod: float = 0.0
var power_use: float = 0.0
var battery: float = 0.0
var battery_cap: float = 0.0
var morale: float = 50.0
var morale_mods: Dictionary = {}       # текущие модификаторы (для подсказки в HUD)
var event_morale: Dictionary = {}      # накопленные событийные (смерти, вспышки) — затухают
var antidote_charges: int = 0
var zero_food_days: int = 0
var _power_cd: float = 0.0
var _morale_cd: float = 0.0
var _dirty: bool = true
var _last_off := PackedInt32Array()
var stats: Dictionary = {}             # счётчики для отчёта рассвета и финала
var history: Array[Dictionary] = []    # численность по дням (график финала, бот-прогон)


func setup(w: World) -> void:
	world = w
	morale = Config.f("rules.morale.base")
	reset_stats()


func reset_stats() -> void:
	stats = {"kills": 0, "civ_lost": 0, "soldiers_lost": 0, "births": 0, "rescued": 0, "food_before": res["food"]}


func mark_dirty() -> void:
	_dirty = true


# ------------------------------------------------------------------ склад
func cap() -> float:
	return Config.f("rules.start.storage_cap_hq") + Config.f("buildings.storage.storage_cap") * world.buildings.count_of("storage")


func can_afford(cost: Dictionary) -> bool:
	for r: String in cost:
		if float(res.get(r, 0.0)) + 0.0001 < float(cost[r]):
			return false
	return true


func spend(cost: Dictionary) -> void:
	for r: String in cost:
		res[r] = float(res.get(r, 0.0)) - float(cost[r])


func refund(cost: Dictionary, frac: float) -> void:
	for r: String in cost:
		add(r, float(cost[r]) * frac)


func add(r: String, amount: float) -> float:
	var before := float(res.get(r, 0.0))
	res[r] = clampf(before + amount, 0.0, cap())
	return float(res[r]) - before


# ------------------------------------------------------------------ люди
func people() -> Dictionary:
	var adults := 0
	var children := 0
	var soldiers := 0
	for a in world.agents.list:
		if not a.alive:
			continue
		if a.kind == Agent.Kind.CIVILIAN:
			if a.rescued:
				if a.is_child:
					children += 1
				else:
					adults += 1
		elif a.temp_life < 0.0:
			soldiers += int(Config.f("units.%s.recruits" % a.type))
	return {"adults": adults, "children": children, "soldiers": soldiers, "total": adults + children + soldiers}


func housing() -> int:
	var h := 0
	for b in world.buildings.list:
		if b.complete():
			h += int(b.data().get("housing", 0))
	return h


func daily_food_need() -> float:
	var p := people()
	var c := "rules.consumption_per_day."
	var need: float = float(p["adults"]) * Config.f(c + "civilian_adult") + float(p["children"]) * Config.f(c + "child") \
		+ float(p["soldiers"]) * Config.f(c + "soldier")
	if kitchen_staffed():
		need *= Config.f(c + "kitchen_mult")
	return need


func kitchen_staffed() -> bool:
	var need := ceilf(float(people()["total"]) / Config.f("rules.consumption_per_day.cooks_per_people"))
	var cooks := 0.0
	for b in world.buildings.all_of("kitchen"):
		if b.working():
			for cid in b.workers:
				var a := world.agents.get_agent(cid)
				if a != null and a.civ == Agent.Civ.WORKING:
					cooks += world.mods.cook_value(a)
	return need > 0.0 and cooks >= need


# ------------------------------------------------------------------ тик
func update(dt: float) -> void:
	_power_cd -= dt
	if _power_cd <= 0.0 or _dirty:
		_power_cd = Config.f("rules.power.update_interval_s")
		_update_power(Config.f("rules.power.update_interval_s"))
		_dirty = false
	_continuous(dt)
	_morale_cd -= dt
	if _morale_cd <= 0.0:
		_morale_cd = Config.f("rules.economy.morale_update_s")
		_update_morale()


func _continuous(dt: float) -> void:
	var day_len := world.clock.day_length()
	for b in world.buildings.list:
		if not b.working():
			continue
		if b.type == "greenhouse":
			var y := Config.f("buildings.greenhouse.yield_per_worker_per_day.food")
			for cid in b.workers:
				var a := world.agents.get_agent(cid)
				if a != null and a.civ == Agent.Civ.WORKING:
					add("food", y * world.mods.greenhouse_mult(a) * dt / day_len)
		elif b.type == "generator" and _generator_running(b):
			add("wood", -Config.f("buildings.generator.upkeep_per_day.wood") * dt / day_len)


func _generator_running(b: Building) -> bool:
	return b.complete() and b.enabled and not b.workers.is_empty() and float(res["wood"]) > 0.0


## Баланс сети; дефицит → отключаем по приоритету (GDD §5). Аккумулятор сглаживает ночь.
func _update_power(step_s: float) -> void:
	var night := world.clock.is_night() or world.clock.is_dark()
	var prod := 0.0
	var consumers: Array[Building] = []
	battery_cap = 0.0
	for b in world.buildings.list:
		if not b.complete():
			continue
		var d := b.data()
		battery_cap += float(d.get("power_storage", 0.0))
		if b.type == "generator":
			prod += float(d["power"]) if _generator_running(b) else 0.0
			continue
		var p := float(d.get("power", 0.0))
		if d.has("power_day"):
			p = float(d["power_night"] if night else d["power_day"])
		elif d.has("power_night"):
			p = float(d["power_night"]) if night else 0.0
		if p > 0.0 and b.enabled:
			prod += p
		elif p < 0.0:
			b.power_need = -p
			if b.enabled:
				consumers.append(b)
			else:
				b.powered = false
		else:
			b.powered = true
	prod += world.map.power_bonus()
	var use := 0.0
	for b in consumers:
		use += b.power_need
	var balance := prod - use
	var rate := Config.f("rules.power.battery_rate_per_min") * step_s / 60.0
	battery = minf(battery, battery_cap)
	if balance > 0.0:
		battery = minf(battery_cap, battery + balance * rate)
	elif balance < 0.0 and battery > 0.0:
		var cover := minf(-balance, battery / maxf(rate, 0.0001))
		battery -= cover * rate
		balance += cover
	_shutdown(consumers, balance)
	power_prod = prod
	power_use = use


func _shutdown(consumers: Array[Building], balance: float) -> void:
	var order: Array = Config.a("rules.power.shutdown_priority")
	consumers.sort_custom(func(a: Building, b: Building) -> bool:
		var ia := order.find(a.type)
		var ib := order.find(b.type)
		return (ia if ia >= 0 else -1) < (ib if ib >= 0 else -1))
	var off := PackedInt32Array()
	for b in consumers:
		var was := b.powered
		if balance < 0.0:
			b.powered = false
			balance += b.power_need
			off.append(b.id)
		else:
			b.powered = true
		if was != b.powered:
			world.on_power_changed(b)
	# алерт — только когда меняется набор отключённых, а не каждые 0.5 с
	if off != _last_off:
		_last_off = off
		if not off.is_empty():
			world.emit("power_deficit", [off])


func power_balance() -> float:
	return power_prod - power_use


# ------------------------------------------------------------------ мораль
func _update_morale() -> void:
	var m := Config.d("rules.morale.modifiers")
	var p := people()
	morale_mods = {}
	if housing() >= p["total"] and p["total"] > 0:
		morale_mods["housing_ok"] = float(m["housing_ok"])
	if _tents_dominate():
		morale_mods["tents"] = Config.f("buildings.tent.morale_if_over_half_housing")
	if kitchen_staffed():
		morale_mods["kitchen_staffed"] = float(m["kitchen_staffed"])
	if world.clock.is_night() and _lights_ok():
		morale_mods["power_ok_at_night"] = float(m["power_ok_at_night"])
	for b in world.buildings.all_of("medpost"):
		if b.working() and not b.workers.is_empty():
			morale_mods["medpost_staffed"] = float(m["medpost_staffed"])
			break
	if float(res["food"]) < daily_food_need():
		morale_mods["food_shortage"] = float(m["food_shortage"])
	var total := Config.f("rules.morale.base")
	for k: String in morale_mods:
		total += float(morale_mods[k])
	for k: String in event_morale:
		total += float(event_morale[k])
	morale = clampf(total, Config.f("rules.morale.min"), Config.f("rules.morale.max"))


func _tents_dominate() -> bool:
	var tents := 0
	for b in world.buildings.all_of("tent"):
		tents += int(b.data().get("housing", 0))
	var h := housing()
	return h > 0 and tents * 2 > h


func _lights_ok() -> bool:
	for b in world.buildings.all_of("floodlight"):
		if not b.powered:
			return false
	return true


func morale_event(kind: String, amount: float) -> void:
	event_morale[kind] = float(event_morale.get(kind, 0.0)) + amount
	_update_morale()


func morale_effect(key: String, default: Variant) -> Variant:
	for e: Dictionary in Config.a("rules.morale.effects"):
		if morale >= float(e["min"]):
			return e.get(key, default)
	return default


# ------------------------------------------------------------------ рассвет
func on_dawn() -> Dictionary:
	var report := stats.duplicate()
	report["day"] = world.clock.day
	var need := daily_food_need()
	var had := float(res["food"])
	res["food"] = maxf(0.0, had - need)
	report["food_delta"] = float(res["food"]) - float(stats["food_before"])
	if need > had:
		morale_event("starvation", (need - had) * Config.f("rules.starvation.morale_per_missing_food"))
		zero_food_days += 1
		if zero_food_days >= Config.i("rules.starvation.deaths_if_zero_food_days"):
			report["starved"] = world.civilians.starve(Config.f("rules.starvation.death_fraction_per_day"))
	else:
		zero_food_days = 0
	_decay_events()
	report["births"] = _births()
	world.civilians.grow_children()
	var p := people()
	history.append({"day": world.clock.day, "adults": p["adults"], "children": p["children"],
		"soldiers": p["soldiers"], "food": res["food"], "wood": res["wood"], "iron": res["iron"], "morale": morale})
	reset_stats()
	return report


func _decay_events() -> void:
	var dec := Config.f("rules.economy.event_morale_decay_per_day")
	for k: String in event_morale.keys():
		var v := float(event_morale[k])
		v = minf(0.0, v + dec) if v < 0.0 else maxf(0.0, v - dec)
		if absf(v) < 0.01:
			event_morale.erase(k)
		else:
			event_morale[k] = v


## Рождения: блоки жилья с ≥2 взрослыми, мораль ≥ порога, запас еды ≥ N дней (GDD §6.2).
func _births() -> int:
	var b_cfg := Config.d("rules.birth")
	if morale < float(b_cfg["min_morale"]) or not morale_effect("birth_enabled", false):
		return 0
	if float(res["food"]) < daily_food_need() * float(b_cfg["min_food_days_reserve"]):
		return 0
	var adults_left: int = people()["adults"]
	var born := 0
	for b in world.buildings.list:
		var hcap := int(b.data().get("housing", 0))
		if not b.complete() or hcap <= 0:
			continue
		var here := mini(adults_left, hcap)
		adults_left -= here
		if here >= int(b_cfg["min_adults_in_house"]) and world.rng.randf() < world.mods.birth_chance():
			world.civilians.spawn_child(b.pos)
			born += 1
	return born
