class_name AgentViews
extends Node3D
## Узлы для всех агентов sim: создаёт/удаляет AgentView, интерполирует позиции между тиками,
## прячет мирных в тумане (найденных показывает знаком «?»).

const CIV_MODELS: PackedStringArray = ["models/civilians/civ_adult_a.glb", "models/civilians/civ_adult_b.glb",
	"models/civilians/civ_adult_c.glb", "models/civilians/civ_adult_d.glb", "models/civilians/civ_adult_e.glb"]

var world: World
var views: Dictionary = {}      # id → AgentView
var prev: Dictionary = {}       # id → Vector2 (позиция на прошлом тике)
var selected: Dictionary = {}   # id → true
var heli_alt: float = 25.0


func setup(w: World) -> void:
	world = w
	heli_alt = Config.f("rules.sim_tuning.heli_altitude_m")


func on_tick() -> void:
	for a in world.agents.list:
		prev[a.id] = a.pos


func _model_for(a: Agent) -> String:
	if a.kind == Agent.Kind.CIVILIAN:
		if a.is_child:
			return String(Config.g("civilians.child.model"))
		return CIV_MODELS[a.id % CIV_MODELS.size()]
	return String(Config.g("units.%s.model" % a.type))


func render(alpha: float, delta: float) -> void:
	var seen := {}
	for a in world.agents.list:
		if not a.alive:
			continue
		seen[a.id] = true
		var v: AgentView = views.get(a.id)
		if v == null or v.kind != a.kind or (a.kind == Agent.Kind.CIVILIAN and v.has_meta("child") != a.is_child):
			if v != null:
				v.queue_free()
			v = _create(a)
		var p: Vector2 = (prev.get(a.id, a.pos) as Vector2).lerp(a.pos, alpha)
		var show := _visible(a)
		v.visible = show
		if not show:
			continue
		var alt := 0.0
		if a.kind == Agent.Kind.AIR:
			alt = heli_alt if a.moving or world.heli.nearest_pad(a.pos) == null or a.pos.distance_to(world.heli.nearest_pad(a.pos).pos) > 8.0 else 0.0
			alt = lerpf(v.position.y, alt, minf(1.0, delta * 1.5))
		v.animate(a, p, delta, alt)
		v.set_status(_status(a))
		v.model.visible = a.kind != Agent.Kind.CIVILIAN or a.rescued or world.fog.visible(a.pos)
	for id: int in views.keys():
		if not seen.has(id):
			(views[id] as AgentView).queue_free()
			views.erase(id)
			prev.erase(id)
			selected.erase(id)


func _create(a: Agent) -> AgentView:
	var v := AgentView.new()
	v.build(a, _model_for(a), Look.team_color(a.owner))
	if a.is_child:
		v.set_meta("child", true)
	add_child(v)
	views[a.id] = v
	v.set_selected(selected.has(a.id))
	return v


func _visible(a: Agent) -> bool:
	if a.hidden:
		return false
	if a.kind != Agent.Kind.CIVILIAN or a.rescued:
		return true
	return a.revealed or world.fog.visible(a.pos)


func _status(a: Agent) -> String:
	if a.infected and a.infect_detected:
		return "st_infected"
	if a.kind == Agent.Kind.CIVILIAN:
		if not a.rescued:
			return "st_follow" if a.civ == Agent.Civ.FOLLOWING else ("st_unknown" if a.revealed and not world.fog.visible(a.pos) else "")
		if a.civ == Agent.Civ.FLEEING:
			return "st_noise"
	elif a.camo_t > 0.0:
		return "abl_camo"
	elif a.kind == Agent.Kind.AIR and a.fuel < world.mods.heli_flight_time(a.owner) * 0.25:
		return "st_low_power"
	return ""


func set_selection(ids: Array) -> void:
	for id: int in selected:
		if views.has(id):
			(views[id] as AgentView).set_selected(false)
	selected.clear()
	for id: int in ids:
		selected[id] = true
		if views.has(id):
			(views[id] as AgentView).set_selected(true)


## Экранная позиция агента (для рамки выделения).
func screen_pos(cam: Camera3D, a: Agent) -> Vector2:
	var y := heli_alt if a.kind == Agent.Kind.AIR else 1.0
	return cam.unproject_position(Vector3(a.pos.x, y, a.pos.y))
