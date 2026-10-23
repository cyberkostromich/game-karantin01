class_name BotPlayer
extends RefCounted
## Простой бот-командир для headless-прогонов баланса (M6-4) и как ИИ-удержание отключившегося игрока.
## Играет только через Commands (контракт tech spec §4.2) — тем же путём, что и люди.

const BUILD_ORDER := ["sawmill", "barracks", "scrapyard", "generator", "kitchen", "greenhouse", "tower", "checkpoint",
	"tent", "floodlight", "quarantine", "tower", "house", "storage", "medpost", "workshop", "generator", "greenhouse",
	"house", "floodlight", "house", "sawmill", "motorpool", "house", "storage", "tower", "house", "solar", "greenhouse"]
const WORK_PRIORITY := ["generator", "greenhouse", "kitchen", "sawmill", "scrapyard", "workshop", "medpost"]
const TECH_ORDER := ["concrete_walls", "silencers", "field_medicine", "solar", "heavy_armor", "hydroponics",
	"body_armor", "thermal_optics", "batteries", "vaccine", "aviation", "radio_intercept", "napalm"]

var world: World
var pid: int = 1
var think_cd: float = 0.0
var build_i: int = 0
var walls_done: bool = false
var rescue_target: Dictionary = {}   # scout id → Vector2
var log_lines: PackedStringArray = []
var stall_t: float = 0.0


func setup(w: World, player: int) -> void:
	world = w
	pid = player


func cmd(c: Dictionary) -> void:
	c["pid"] = pid
	world.commands.push(c)


func update(dt: float) -> void:
	think_cd -= dt
	if think_cd > 0.0:
		return
	think_cd = 2.0
	_build()
	_assign()
	_train()
	_research()
	_army()
	_walls()


# ------------------------------------------------------------------ стройка
func _anchor_for(type: String) -> Vector2:
	var m := world.map
	match type:
		"sawmill":
			return _near_resource(0)
		"scrapyard":
			return _near_resource(1)
		"checkpoint", "floodlight", "tower":
			return _wall_line() + Vector2(0, -10)
		_:
			return m.hq_pos


## Горловина чаши: стена поперёк прохода у внутреннего края трибун.
func _wall_line() -> Vector2:
	var m := world.map
	return m.gate_pos.lerp(m.hq_pos, 0.25)


## Точка в зоне стройки, у которой в радиусе работы больше всего узлов ресурса.
func _near_resource(kind: int) -> Vector2:
	var m := world.map
	var best := m.gate_outer
	var best_n := -1
	var work_r := Config.f("buildings.%s.work_radius" % ("sawmill" if kind == 0 else "scrapyard"))
	for k in 60:
		var a := TAU * k / 60.0
		for r: float in [20.0, 50.0, 80.0, 105.0]:
			var p := m.gate_outer + Vector2(cos(a), sin(a)) * r
			if not world.in_build_zone(p) or not world.grid.walkable(p):
				continue
			var n := 0
			for i in m.node_pos.size():
				if m.node_kind[i] == kind and m.node_alive[i] == 1 and m.node_pos[i].distance_to(p) < work_r * 0.8:
					n += 1
			if n > best_n:
				best_n = n
				best = p
	return best


func find_spot(type: String, around: Vector2) -> Vector2i:
	var g := world.grid
	var c := g.cell_of(around)
	for r in range(0, 40):
		for k in maxi(1, r * 6):
			var a := TAU * float(k) / maxf(1.0, r * 6.0)
			var cc := c + Vector2i(roundi(cos(a) * r * 2.0), roundi(sin(a) * r * 2.0))
			if world.buildings.check_place(type, cc, 0, false) == "" and _clear_of_paths(type, cc):
				return cc
	return Vector2i(-99999, -99999)


## Не застраиваем проход к воротам арены и путь Штаб–выход.
func _clear_of_paths(type: String, cc: Vector2i) -> bool:
	var r := world.buildings.rect_for(type, cc, 0)
	var rm := Rect2(world.grid.origin + Vector2(r.position) * world.grid.cell, Vector2(r.size) * world.grid.cell).grow(3.0)
	var a := world.map.hq_pos
	var b := world.map.gate_outer
	for k in 12:
		if rm.has_point(a.lerp(b, k / 11.0)):
			return false
	return true


func _build() -> void:
	if build_i >= BUILD_ORDER.size():
		return
	for b in world.buildings.list:
		if b.state == Building.State.CONSTRUCTING:
			if b.builders.is_empty():
				stall_t += 2.0
				if stall_t > 60.0:
					cmd({"t": "cancel_build", "building_id": b.id})
					stall_t = 0.0
			return  # одна стройка за раз — строителей мало
	stall_t = 0.0
	var t: String = BUILD_ORDER[build_i]
	var food_days := float(world.economy.res["food"]) / maxf(1.0, world.economy.daily_food_need())
	if world.economy.power_balance() < 0.0 and t != "generator" and world.buildings.count_of("generator") < 4:
		t = "generator"
		build_i -= 1
	elif food_days < 2.0 and t != "greenhouse" and world.buildings.count_of("greenhouse") < 5 and world.economy.power_balance() >= 2.0:
		t = "greenhouse"
		build_i -= 1
	if not world.economy.can_afford(Config.d("buildings.%s.cost" % t)):
		return
	var spot := find_spot(t, _anchor_for(t))
	if spot.x == -99999:
		build_i += 1
		return
	cmd({"t": "build", "building": t, "cells": [[spot.x, spot.y]], "rot": 0})
	build_i += 1


func _walls() -> void:
	if walls_done or build_i < 2 or not world.economy.can_afford({"wood": 90, "iron": 10}):
		return
	# стена поперёк горловины чаши с воротами посередине: стены ставим, пока упираются в трибуны
	var c := world.grid.cell_of(_wall_line())
	cmd({"t": "build", "building": "gate", "cells": [[c.x - 1, c.y]], "rot": 0})
	var cells: Array = []
	for side: int in [-1, 1]:
		var x := c.x - 3 if side < 0 else c.x + 2
		for k in 10:
			var cc := Vector2i(x, c.y)
			if not world.grid.terrain_walkable(cc) and not world.grid.terrain_walkable(cc + Vector2i(1, 0)):
				break
			cells.append([cc.x, cc.y])
			x += 2 * side
	cmd({"t": "build", "building": "wall_wood", "cells": cells, "rot": 0})
	# второй рубеж в 6 м позади первого
	var c2 := c + Vector2i(0, -3)
	var cells2: Array = []
	for side: int in [-1, 1]:
		var x := c2.x - 1 if side < 0 else c2.x + 1
		for k in 10:
			var cc := Vector2i(x, c2.y)
			if not world.grid.terrain_walkable(cc) and not world.grid.terrain_walkable(cc + Vector2i(1, 0)):
				break
			cells2.append([cc.x, cc.y])
			x += 2 * side
	cmd({"t": "build", "building": "gate", "cells": [[c2.x - 1, c2.y]], "rot": 0})
	cmd({"t": "build", "building": "wall_wood", "cells": cells2, "rot": 0})
	walls_done = true


func _assign() -> void:
	var free: Array[Agent] = []
	for a in world.agents.list:
		if a.is_free_adult() and a.rescued:
			free.append(a)
	var building_now := false
	for b in world.buildings.list:
		if world.buildings.needs_builders(b):
			building_now = true
	var keep := 3 if building_now or build_i < BUILD_ORDER.size() else 1
	for t: String in WORK_PRIORITY:
		for b in world.buildings.all_of(t):
			while b.workers.size() < b.worker_slots and free.size() > keep:
				var a: Agent = free.pop_back()
				cmd({"t": "assign", "civilians": [a.id], "building_id": b.id})


func _train() -> void:
	var bar := world.buildings.all_of("barracks")
	if bar.is_empty() or world.training.free_recruits() < 3 or bar[0].queue.size() > 1:
		return
	if float(world.economy.res["food"]) < world.economy.daily_food_need() + 30.0:
		return
	var soldiers := world.agents.units_of(pid).size()
	var scouts := 0
	for u in world.agents.units_of(pid):
		if u.type == "scout":
			scouts += 1
	var t := "assault"
	if scouts < 2:
		t = "scout"
	elif soldiers % 4 == 3:
		t = "sniper"
	elif soldiers % 6 == 5 and world.buildings.count_of("medpost") > 0:
		t = "medic"
	if world.training.check(bar[0], t, pid) == "":
		cmd({"t": "train", "building_id": bar[0].id, "unit": t, "count": 1})


func _research() -> void:
	for ws in world.buildings.all_of("workshop"):
		if not ws.research.is_empty():
			continue
		for t: String in TECH_ORDER:
			if world.tech.check(t) == "":
				cmd({"t": "research", "building_id": ws.id, "tech": t})
				return


# ------------------------------------------------------------------ армия
func _army() -> void:
	var m := world.map
	var night := world.clock.phase >= 2
	var hold := _wall_line() + Vector2(0, -14) if walls_done else m.gate_pos
	var raid := _raid_target() if not night and world.clock.frac() < 0.7 else null
	var raiders := 0
	for u in world.agents.units_of(pid):
		if u.hidden:
			continue
		if u.type == "scout" and not night:
			_scout(u)
			continue
		if raid != null and u.type == "assault" and raiders < 3 and world.agents.units_of(pid).size() >= 3:
			raiders += 1
			if u.pos.distance_to(raid.pos) > 8.0 and (not u.moving or u.dest.distance_to(raid.pos) > 10.0):
				cmd({"t": "move", "units": [u.id], "pos": raid.pos, "amove": true})
			continue
		var tower := _free_tower()
		if night and tower != null and u.kind == Agent.Kind.INFANTRY and u.order != Agent.Order.ENTER:
			cmd({"t": "enter", "units": [u.id], "target": tower.id})
			continue
		if u.pos.distance_to(hold) > 12.0 and not u.moving:
			cmd({"t": "move", "units": [u.id], "pos": hold + Vector2(world.rng.randf_range(-10, 10), world.rng.randf_range(-4, 4)), "amove": true})


func _free_tower() -> Building:
	for b in world.buildings.all_of("tower"):
		var pending := 0
		for u in world.agents.units_of(pid):
			if u.order == Agent.Order.ENTER and u.order_target == b.id:
				pending += 1
		if b.garrison.size() + pending < int(b.data()["garrison"]):
			return b
	return null


func _raid_target() -> MapPoi:
	var best: MapPoi = null
	var bd := 450.0
	for p in world.map.pois:
		if p.done or not (p.type in ["grocery", "pharmacy", "hardware", "car_service"]):
			continue
		var d := p.pos.distance_to(world.map.hq_pos)
		if d < bd:
			bd = d
			best = p
	return best


func _scout(u: Agent) -> void:
	var m := world.map
	var followers := world.civilians.follower_count(u)
	if followers >= 6 or (followers > 0 and _nearest_unaware(u.pos, 60.0) == null):
		if u.pos.distance_to(m.hq_pos) > 30.0 and (not u.moving or u.dest.distance_to(m.hq_pos) > 20.0):
			cmd({"t": "move", "units": [u.id], "pos": m.hq_pos})
		return
	var c := _nearest_unaware(u.pos, 700.0)
	if c == null:
		return
	if not u.moving or u.dest.distance_to(c.pos) > 10.0:
		cmd({"t": "move", "units": [u.id], "pos": c.pos})


func _nearest_unaware(p: Vector2, r: float) -> Agent:
	var best: Agent = null
	var bd := r
	for a in world.agents.list:
		if a.alive and a.kind == Agent.Kind.CIVILIAN and a.civ == Agent.Civ.UNAWARE and not a.rescued:
			var d := a.pos.distance_to(p)
			if d < bd:
				bd = d
				best = a
	return best
