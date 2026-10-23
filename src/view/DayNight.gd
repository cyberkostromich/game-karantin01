class_name DayNight
extends Node3D
## Освещение по фазе дня (арт-библия §1): холодный рассеянный день, синяя ночь ×0.35,
## тёплые прожекторы. Пишет глобальный uniform qm_night для эмиссии палитры.

var world: World
var sun := DirectionalLight3D.new()
var env := WorldEnvironment.new()
var e := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
var night: float = 0.0


func setup(w: World, shadows: bool) -> void:
	world = w
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color("f1ede4")
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_blur = 1.5
	add_child(sun)
	var sky := Sky.new()
	sky_mat.sky_top_color = Color("8e9aa6")
	sky_mat.sky_horizon_color = Color("b9bec2")
	sky_mat.ground_horizon_color = Color("9a9c9e")
	sky_mat.ground_bottom_color = Color("4a4f57")
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.ssao_enabled = shadows
	e.ssao_radius = 2.0
	e.ssao_intensity = 1.4
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.fog_enabled = true
	e.fog_light_color = Color("aab2b9")
	e.fog_density = 0.0009
	e.fog_aerial_perspective = 0.4
	env.environment = e
	add_child(env)


func render(delta: float) -> void:
	var target := world.clock.darkness()
	night = move_toward(night, target, delta * 0.6)
	RenderingServer.global_shader_parameter_set("qm_night", night)
	var day_sun := Color("f1ede4")
	var night_sun := Color("6f86b8")
	sun.light_color = day_sun.lerp(night_sun, night)
	sun.light_energy = lerpf(1.1, 0.22, night)
	sun.rotation_degrees.x = lerpf(-52.0, -70.0, night)
	e.ambient_light_energy = lerpf(0.9, 0.28, night)
	e.ambient_light_color = Color("1b2a44")
	sky_mat.sky_top_color = Color("8e9aa6").lerp(Color("0c1424"), night)
	sky_mat.sky_horizon_color = Color("b9bec2").lerp(Color("1b2a44"), night)
	e.fog_light_color = Color("aab2b9").lerp(Color("141e30"), night)
	e.adjustment_enabled = true
	e.adjustment_saturation = lerpf(0.92, 0.7, night)
