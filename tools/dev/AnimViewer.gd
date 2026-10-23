extends Node3D
## Стенд моделей и анимаций в движке (не входит в игру): ряды бойцов, мирных и зомби в разных
## состояниях, снимки кадров в PNG. Запуск (нужен экран или xvfb):
##   godot --resolution 1600x900 res://tools/dev/anim_viewer.tscn -- --out=/tmp/anim [--frames=4]
## Кадры: <out>_0.png … — по одному на каждые 0.3 с анимации.

const ROWS := [
	[["models/units/unit_assault.glb", "idle"], ["models/units/unit_assault.glb", "walk"],
		["models/units/unit_scout.glb", "run"], ["models/units/unit_medic.glb", "walk"],
		["models/units/unit_sniper.glb", "idle"], ["models/units/unit_assault.glb", "death"]],
	[["models/civilians/civ_adult_a.glb", "idle"], ["models/civilians/civ_adult_b.glb", "walk"],
		["models/civilians/civ_adult_c.glb", "work"], ["models/civilians/civ_adult_e.glb", "panic"],
		["models/civilians/civ_adult_d.glb", "drill"], ["models/civilians/civ_child.glb", "run"]],
	[["walker", "walk"], ["runner", "run"], ["brute", "attack"], ["walker_armored", "feed"],
		["screamer", "idle"], ["spitter", "death"]],
]

var views: Array = []      # [AgentView, Agent]
var mms: Array = []        # [MultiMesh, state, spd, die_rate]
var t: float = 0.0
var out := ""
var frames := 4
var shot := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--frames="):
			frames = int(arg.substr(9))
	_stage()
	for r in ROWS.size():
		for c in (ROWS[r] as Array).size():
			var e: Array = ROWS[r][c]
			var p := Vector2(c * 2.6 - 6.5, r * 4.2 - 4.2)
			if r < 2:
				_human(String(e[0]), String(e[1]), p, r * 10 + c)
			else:
				_zombie(String(e[0]), String(e[1]), p)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.84, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_energy = 0.9
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = Look.unlit(Color(0.56, 0.62, 0.45))
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 8.0, 17.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.2))


func _human(path: String, mode: String, p: Vector2, id: int) -> void:
	var a := Agent.new()
	a.id = id
	a.kind = Agent.Kind.CIVILIAN if path.contains("civilians") else Agent.Kind.INFANTRY
	a.rescued = true
	a.hp = 1.0
	a.max_hp = 1.0
	a.civ = {"work": Agent.Civ.WORKING, "panic": Agent.Civ.FLEEING, "drill": Agent.Civ.TRAINING}.get(mode, Agent.Civ.IDLE)
	var spd: float = {"walk": 2.5, "run": 6.0, "panic": 6.5}.get(mode, 0.0)
	a.vel = Vector2(0.0, spd)
	a.facing = 0.85
	var v := AgentView.new()
	add_child(v)
	v.build(a, path, Color(0.18, 0.5, 0.93))
	v.set_meta("mode", mode)
	v.set_meta("pos", p)
	views.append([v, a])


func _zombie(type: String, mode: String, p: Vector2) -> void:
	var m := Look.merged(String(Config.g("zombies.%s.model" % type)))
	var piv: Dictionary = m["pivots"]
	var mesh: ArrayMesh = m["mesh"]
	for si in mesh.get_surface_count():
		var mat := Look.zombie(type, m["textures"][si])
		for pn: String in piv:
			mat.set_shader_parameter("piv_" + pn, piv[pn])
		mat.set_shader_parameter("stride", Config.f("zombies.%s.speed" % type) * 2.2 + 2.0)
		mesh.surface_set_material(si, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = m["mesh"]
	mm.instance_count = 1
	var k := Config.f("rules.view.zombie_scale")
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.85).scaled(Vector3.ONE * k), Vector3(p.x, 0.0, p.y)))
	var st: float = {"attack": 3.0, "feed": 5.0, "run": 2.0, "walk": 2.0}.get(mode, 0.0)
	var spd: float = {"walk": 0.45, "run": 1.0}.get(mode, 0.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	mms.append([mm, st, spd, 1.0 if mode == "death" else 0.0])


func _process(delta: float) -> void:
	t += delta
	for e in views:
		var v: AgentView = e[0]
		var a: Agent = e[1]
		if v.get_meta("mode") == "death" and t > 0.4:
			v.dying(delta)
			continue
		v.animate(a, v.get_meta("pos"), delta, 0.0)
		a.atk_cd = 0.6 if fmod(t, 0.7) < 0.05 else maxf(0.0, a.atk_cd - delta)
	for e in mms:
		var die: float = clampf((t - 0.4) * 0.35, 0.0, 0.99) * float(e[3])
		(e[0] as MultiMesh).set_instance_custom_data(0, Color(0.2, float(e[1]) / 255.0, float(e[2]), die))
	if out != "" and t > 1.0 + shot * 0.3:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, shot])
		shot += 1
		if shot >= frames:
			get_tree().quit()
