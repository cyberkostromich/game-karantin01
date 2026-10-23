class_name Commands
extends RefCounted
## Приказы игроков — контракт tech spec §4.2. Клиенты шлют только эти словари; хост применяет их в тике.
## Любая проверка прав — здесь: юниты должны принадлежать pid, постройки общие (GDD §4).

var world: World
var queue: Array[Dictionary] = []


func setup(w: World) -> void:
	world = w


func push(cmd: Dictionary) -> void:
	queue.append(cmd)


func apply_all() -> void:
	var q := queue
	queue = []
	for c in q:
		apply(c)


func _units(c: Dictionary) -> Array[Agent]:
	var out: Array[Agent] = []
	var pid := int(c.get("pid", 0))
	for id: Variant in c.get("units", []):
		var a := world.agents.get_agent(int(id))
		if a != null and a.alive and a.is_unit() and (a.owner == pid or world.is_shared_control()):
			out.append(a)
	return out


func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	var a: Array = v
	return Vector2(float(a[0]), float(a[1]))


func _b(c: Dictionary) -> Building:
	return world.buildings.get_building(int(c.get("building_id", -1)))


func apply(c: Dictionary) -> void:
	var pid := int(c.get("pid", 0))
	var t := String(c.get("t", ""))
	var b := _b(c)
	match t:
		"move":
			_move(_units(c), _v2(c["pos"]), bool(c.get("amove", false)))
		"attack":
			_attack(_units(c), int(c.get("target", -1)))
		"stop", "hold":
			for a in _units(c):
				_stop(a, Agent.Order.HOLD if t == "hold" else Agent.Order.NONE)
		"patrol":
			_patrol(_units(c), _v2(c["pos"]))
		"enter":
			for a in _units(c):
				_enter(a, int(c.get("target", -1)), String(c.get("kind", "building")) == "unit")
		"unload":
			for a in _units(c):
				world.units.unload(a)
		"ability":
			world.abilities.use(_owned(pid, int(c.get("unit", -1))), String(c["ability"]), _v2(c["pos"]))
		"doctrine":
			world.abilities.use_doctrine(pid, String(c["doctrine"]), _v2(c["pos"]))
		"build":
			_build(c, pid)
		_:
			if b != null:
				_apply_building(t, b, c, pid)
			else:
				_apply_misc(t, c, pid)


func _apply_building(t: String, b: Building, c: Dictionary, pid: int) -> void:
	match t:
		"cancel_build":
			world.buildings.cancel(b)
		"demolish":
			_demolish(b)
		"repair":
			world.buildings.start_repair(b)
		"upgrade":
			world.buildings.start_upgrade(b)
		"train":
			for _k in int(c.get("count", 1)):
				world.training.enqueue(b, String(c["unit"]), pid)
		"cancel_train":
			world.training.cancel_last(b)
		"assign":
			world.civilians.jobs.assign(c.get("civilians", []), b)
		"assign_one":
			_assign_one(b, int(c.get("delta", 1)))
		"research":
			world.tech.start(b, String(c["tech"]))
		"cancel_research":
			world.tech.cancel(b)
		"power":
			b.enabled = bool(c.get("on", true))
			world.economy.mark_dirty()
		"siren":
			world.abilities.use_siren(b)
		"rally":
			b.rally = world.grid.nearest_walkable(_v2(c["pos"]), 20.0)


func _apply_misc(t: String, c: Dictionary, pid: int) -> void:
	match t:
		"transfer":
			for a in _units(c):
				a.owner = int(c.get("to_pid", a.owner))
		"ping":
			world.emit("ping_placed", [pid, String(c.get("kind", "attention")), _v2(c["pos"])])
		"poi_repair":
			var i := int(c.get("poi", -1))
			if i >= 0 and i < world.map.pois.size():
				world.pois.pay_repair(world.map.pois[i])


func _owned(pid: int, id: int) -> Agent:
	var a := world.agents.get_agent(id)
	return a if a != null and a.is_unit() and (a.owner == pid or world.is_shared_control()) else null


## Строй «коробкой»: каждому юниту — своя точка вокруг цели, чтобы не толпились (GDD §7 «построения»).
func _move(units: Array[Agent], p: Vector2, amove: bool) -> void:
	var slots := formation(p, units.size(), units)
	for k in units.size():
		var a := units[k]
		if a.hidden and a.container >= 0:
			_leave(a)
		a.order = Agent.Order.AMOVE if amove else Agent.Order.MOVE
		a.order_pos = slots[k]
		a.target_z = -1
		a.target_nest = -1
		world.agents.move_to(a, slots[k] if a.kind == Agent.Kind.AIR else world.grid.nearest_walkable(slots[k], 12.0))


func formation(p: Vector2, n: int, units: Array[Agent]) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cols := ceili(sqrt(float(n)))
	var sp := 2.4
	for a in units:
		if a.kind != Agent.Kind.INFANTRY:
			sp = 7.0
	for k in n:
		var r := k / cols
		var c := k % cols
		out.append(p + Vector2((c - (cols - 1) * 0.5) * sp, (r - (ceili(float(n) / cols) - 1) * 0.5) * sp))
	return out


func _attack(units: Array[Agent], target: int) -> void:
	for a in units:
		a.order = Agent.Order.ATTACK
		a.order_target = target
		a.target_nest = -1


func _stop(a: Agent, o: int) -> void:
	a.stop()
	a.order = o
	a.order_pos = a.pos
	world.agents.path_queue.erase(a.id)


func _patrol(units: Array[Agent], p: Vector2) -> void:
	for a in units:
		a.order = Agent.Order.PATROL
		a.patrol_a = a.pos
		a.patrol_b = p
		world.agents.move_to(a, p)


func _enter(a: Agent, target: int, is_unit: bool) -> void:
	if a.hidden or (is_unit and target == a.id):
		return
	a.order = Agent.Order.ENTER
	a.order_target = target
	a.order_target_unit = is_unit


func _leave(a: Agent) -> void:
	var b := world.buildings.get_building(a.container)
	if b != null:
		b.garrison.erase(a.id)
		a.pos = world.grid.nearest_walkable(b.door)
	var v := world.agents.get_agent(a.container)
	if v != null:
		v.passengers.erase(a.id)
		a.pos = world.grid.nearest_walkable(v.pos)
	a.hidden = false
	a.container = -1


func _build(c: Dictionary, pid: int) -> void:
	var type := String(c["building"])
	var rot := posmod(int(c.get("rot", 0)), roundi(360.0 / Config.f("rules.build.rotation_step_deg")))
	for cell: Variant in c.get("cells", []):
		var v := _v2(cell)
		world.buildings.place(type, Vector2i(int(v.x), int(v.y)), rot, pid)


func _demolish(b: Building) -> void:
	if b != null and b.type != "hq":
		world.economy.refund(b.data().get("cost", {}), Config.f("rules.build.demolish_refund_frac"))
		world.buildings.destroy(b, false)


func _assign_one(b: Building, delta: int) -> void:
	if b == null:
		return
	if delta > 0:
		world.civilians.jobs.assign_nearest(b)
	else:
		world.civilians.jobs.unassign_one(b)

