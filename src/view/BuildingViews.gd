class_name BuildingViews
extends Node3D
## Постройки: модель по buildings.json, стройплощадка — полупрозрачная с «плёнкой» выше прогресса,
## прожекторы — свет ночью, ворота открываются для своих, над обесточенными — значок ⚡✕ (docs/07 §4).

var world: World
var views: Dictionary = {}   # id → Node3D
var lights: Dictionary = {}  # id → SpotLight3D
var icons: Dictionary = {}   # id → Sprite3D
var tmp := PackedInt32Array()


func setup(w: World) -> void:
	world = w


func _create(b: Building) -> Node3D:
	var root := Node3D.new()
	# готовые постройки — без параметров экземпляра (их сотни: стены), подсветка подменяет материал
	var model := Look.instance(String(b.data()["model"]), Look.palette_ghost() if not b.complete() else Look.palette_static())
	model.name = "Model"
	root.add_child(model)
	root.position = Vector3(b.pos.x, 0, b.pos.y)
	root.rotation.y = PI * 0.5 * b.rot
	root.set_meta("complete", b.complete())
	root.set_meta("type", b.type)
	add_child(root)
	if b.type == "floodlight":
		var l := SpotLight3D.new()
		l.light_color = Color("ffe3a3")
		l.light_energy = 6.0
		l.spot_range = Config.f("buildings.floodlight.light_radius") * 1.6
		l.spot_angle = 55.0
		l.position = Vector3(0, 5.2, 0)
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.shadow_enabled = false
		l.visible = false
		root.add_child(l)
		lights[b.id] = l
	var ic := Sprite3D.new()
	ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ic.pixel_size = 0.03
	ic.no_depth_test = true
	ic.render_priority = 10
	ic.position.y = 8.0
	ic.texture = Look.icon("st_low_power")
	ic.visible = false
	root.add_child(ic)
	icons[b.id] = ic
	views[b.id] = root
	return root


func render(delta: float) -> void:
	var seen := {}
	var night := world.clock.is_dark()
	for b in world.buildings.list:
		if not b.alive:
			continue
		seen[b.id] = true
		var v: Node3D = views.get(b.id)
		if v != null and (bool(v.get_meta("complete")) != b.complete() or String(v.get_meta("type")) != b.type):
			_drop(b.id)
			v = null
		if v == null:
			v = _create(b)
		_update(b, v, night, delta)
	for id: int in views.keys():
		if not seen.has(id):
			_drop(id)


func _drop(id: int) -> void:
	(views[id] as Node3D).queue_free()
	views.erase(id)
	lights.erase(id)
	icons.erase(id)


func _update(b: Building, v: Node3D, night: bool, delta: float) -> void:
	var model := v.get_node("Model") as Node3D
	if not b.complete():
		_set_param(model, "build_progress", b.progress)
	if lights.has(b.id):
		(lights[b.id] as SpotLight3D).visible = night and b.powered and b.enabled
	var ic: Sprite3D = icons[b.id]
	ic.visible = b.complete() and (not b.powered or not b.enabled) and b.power_need > 0.0
	match b.type:
		"gate":
			_gate(b, model, delta)
		"scrapyard":
			var arm := Look.find(model, "crane_arm")
			if arm != null and b.working() and not b.workers.is_empty():
				arm.rotate_y(delta * 0.4)
		"siren":
			var sp := Look.find(model, "speakers")
			if sp != null and b.ability_cd > 0.0:
				sp.rotate_y(delta * 3.0)
		"checkpoint":
			var bar := Look.find(model, "barrier")
			if bar != null:
				bar.rotation.z = lerpf(bar.rotation.z, 1.3 if _civ_near(b.door, 6.0) else 0.0, minf(1.0, delta * 4.0))


func _gate(b: Building, model: Node3D, delta: float) -> void:
	var open := _ally_near(b.pos, 7.0)
	for pn: String in ["door_l", "door_r"]:
		var d := Look.find(model, pn)
		if d != null:
			var target := (1.4 if pn == "door_l" else -1.4) if open else 0.0
			d.rotation.y = lerpf(d.rotation.y, target, minf(1.0, delta * 4.0))


func _ally_near(p: Vector2, r: float) -> bool:
	world.agents.hash.query(p, r, tmp, 1)
	return not tmp.is_empty()


func _civ_near(p: Vector2, r: float) -> bool:
	world.agents.hash.query(p, r, tmp, 4)
	for k in tmp:
		if world.agents.hash_list[k].civ == Agent.Civ.CHECKPOINT:
			return true
	return false


## Состояние постройки для шейдера — один vec4 bstate = (подсветка, призрак, прогресс, —).
func _set_param(n: Node, key: String, v: float) -> void:
	var st: Vector4 = n.get_meta("bstate", Vector4(0, 0, 1, 0))
	match key:
		"highlight": st.x = v
		"ghost": st.y = v
		"build_progress": st.z = v
	n.set_meta("bstate", st)
	_apply_bstate(n, st)


func _apply_bstate(n: Node, st: Vector4) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("bstate", st)
	for c in n.get_children():
		_apply_bstate(c, st)


func set_highlight(id: int, v: float) -> void:
	if not views.has(id):
		return
	var model: Node = views[id].get_node("Model")
	var ghost := model.has_meta("bstate") and (model.get_meta("bstate") as Vector4).z < 1.0
	if not ghost:
		Look.apply_material(model, Look.palette() if v > 0.0 else Look.palette_static())
	if v > 0.0 or ghost:
		_set_param(model, "highlight", v)
