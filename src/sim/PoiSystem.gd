class_name PoiSystem
extends RefCounted
## Взаимодействие с объектами карты (GDD §10, §13): рейд лут-зданий «отряд стоит рядом без боя»,
## ремонт подстанции и радиовышки, захват Новодевичьего (расширяет зону стройки).

var world: World
var tick_cd: float = 0.0
var step_s: float = 0.5
var tmp := PackedInt32Array()


func setup(w: World) -> void:
	world = w


func update(dt: float) -> void:
	tick_cd -= dt
	if tick_cd > 0.0:
		return
	tick_cd = step_s
	for p in world.map.pois:
		if p.done or not p.alive:
			continue
		match p.type:
			"grocery", "car_service", "hardware", "pharmacy":
				_raid(p, Config.f("buildings.map_poi.%s.search_s" % p.type), _loot.bind(p))
			"substation", "radio_tower":
				if p.paid:
					var rs := float(Config.opt("buildings.map_poi.%s.repair_s" % p.type, Config.f("rules.sim_tuning.default_repair_s")))
					_raid(p, rs, _repaired.bind(p))
			"fortress":
				_raid(p, Config.f("rules.base.fortress_capture_s"), _captured.bind(p), Config.f("rules.base.fortress_capture_radius_m"))


## Прогресс, пока рядом есть наш юнит и нет зомби (рейд «без боя»).
func _raid(p: MapPoi, need_s: float, done_cb: Callable, radius := -1.0) -> void:
	var r := radius if radius > 0.0 else Config.f("rules.sim_tuning.raid_radius_m")
	if world.zombies.hash.nearest(p.pos, r) != -1:
		return
	var present := false
	world.agents.hash.query(p.pos, r, tmp, 8)
	for k in tmp:
		if world.agents.hash_list[k].is_unit():
			present = true
			break
	if not present:
		return
	p.progress = minf(1.0, p.progress + step_s / maxf(0.1, need_s))
	if p.progress >= 1.0:
		p.done = true
		done_cb.call()


func _loot(p: MapPoi) -> void:
	var loot := Config.d("buildings.map_poi.%s.loot" % p.type)
	var got := {}
	for r: String in loot:
		if r == "effect":
			var eff := String(loot[r])
			if eff.begins_with("antidote_charges_+"):
				var n := int(eff.trim_prefix("antidote_charges_+"))
				world.economy.antidote_charges += n
				got["antidote"] = n
			continue
		var rng: Array = loot[r]
		var v := world.rng.randi_range(int(rng[0]), int(rng[1]))
		got[r] = world.economy.add(r, v)
	world.noise.emit(p.pos, Config.f("combat.noise_events.door_breach"))
	world.emit("loot_collected", [p.type, got, p.pos])


func _repaired(p: MapPoi) -> void:
	world.score_add("objectives", 1)
	world.economy.mark_dirty()
	world.emit("objective_updated", [p.key, "done"])
	world.emit("alert", ["objective", "ALERT_REPAIRED_" + p.type.to_upper(), p.pos])


func _captured(p: MapPoi) -> void:
	world.fortress_captured = true
	world.score_add("objectives", 1)
	world.emit("objective_updated", [p.key, "done"])
	world.emit("alert", ["objective", "ALERT_FORTRESS", p.pos])


## Команда «починить»: оплатить ремонт; дальше прогресс идёт, пока рядом стоит юнит.
func pay_repair(p: MapPoi) -> bool:
	if p == null or p.done or p.paid or not (p.type in ["substation", "radio_tower"]):
		return false
	var cost := Config.d("buildings.map_poi.%s.repair_cost" % p.type)
	if not world.economy.can_afford(cost):
		return false
	world.economy.spend(cost)
	p.paid = true
	return true


func wave_info_known() -> bool:
	var r := world.map.poi("radio_tower")
	return (r != null and r.done) or world.mods.wave_info_early()
