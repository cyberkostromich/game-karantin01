class_name HeliSystem
extends RefCounted
## Вертолёт (GDD §7, M3-5): топливо, возврат и дозаправка на площадке, спасение с крыш.

var world: World


func setup(w: World) -> void:
	world = w


func update_fuel(a: Agent, dt: float) -> void:
	var pad := nearest_pad(a.pos)
	var landed := pad != null and not a.moving and a.pos.distance_to(pad.pos) <= pad.half_extent()
	if landed:
		_refuel(a, pad, dt)
		return
	a.fuel -= dt
	var full := world.mods.heli_flight_time(a.owner)
	if a.fuel <= full * Config.f("rules.sim_tuning.heli_return_fuel_frac") and a.order != Agent.Order.REFUEL and pad != null:
		a.order = Agent.Order.REFUEL
		world.agents.move_to(a, pad.pos)
		world.emit("alert", ["fuel", "ALERT_HELI_FUEL", a.pos])
	if a.fuel <= 0.0:
		world.combat.kill_agent(a)  # без топлива — авария
		return
	_rooftop_pickup(a)
	if not a.moving and world.in_base(a.pos) and not a.passengers.is_empty():
		_unload_civilians(a)


func _refuel(a: Agent, pad: Building, dt: float) -> void:
	var full := world.mods.heli_flight_time(a.owner)
	if a.fuel >= full:
		if a.order == Agent.Order.REFUEL:
			a.order = Agent.Order.NONE
		_unload_civilians(a)
		return
	if a.job_t <= 0.0:
		var cost := Config.d("units.heli.refuel_cost")
		if not world.economy.can_afford(cost):
			return
		world.economy.spend(cost)
		a.job_t = Config.f("units.heli.refuel_s")
	a.job_t -= dt
	if a.job_t <= 0.0:
		a.fuel = full
	_unload_civilians(a)


func nearest_pad(p: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for b in world.buildings.all_of("helipad"):
		var d := b.pos.distance_to(p)
		if d < bd:
			bd = d
			best = b
	return best


## Мирные на крышах достаются только вертолётом (civilians.json/spawn_groups).
func _rooftop_pickup(a: Agent) -> void:
	if a.moving or (world.tick + a.id) % 10 != 0:
		return
	var r := Config.f("rules.civilian_ai.rooftop_pickup_radius_m")
	for c in world.agents.list:
		if c.alive and c.kind == Agent.Kind.CIVILIAN and c.civ == Agent.Civ.ROOFTOP and c.pos.distance_to(a.pos) <= r:
			if not world.units.board(c, a):
				break
			c.revealed = true
			world.emit("civilian_found", [c.id, c.pos])


func _unload_civilians(a: Agent) -> void:
	if not world.in_base(a.pos):
		return
	var keep: Array[int] = []
	for pid in a.passengers:
		var c := world.agents.get_agent(pid)
		if c == null:
			continue
		if c.kind != Agent.Kind.CIVILIAN:
			keep.append(pid)
			continue
		c.hidden = false
		c.container = -1
		c.pos = world.grid.nearest_walkable(a.pos + Vector2(world.rng.randf_range(-4, 4), world.rng.randf_range(-4, 4)))
		world.civilians.after_unload(c)
	a.passengers = keep
