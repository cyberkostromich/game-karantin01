class_name FogRenderer
extends MeshInstance3D
## Туман войны поверх сцены: полноэкранный квад, шейдер восстанавливает XZ из глубины (fog.gdshader).

var world: World
var img: Image
var tex: ImageTexture
var mat: ShaderMaterial
var _ver: int = -1


func setup(w: World) -> void:
	world = w
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.flip_faces = true
	mesh = q
	mat = ShaderMaterial.new()
	mat.shader = load("res://src/view/shaders/fog.gdshader")
	mat.render_priority = 5
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	var f := w.fog
	img = Image.create_from_data(f.w, f.h, false, Image.FORMAT_L8, f.display)
	tex = ImageTexture.create_from_image(img)
	mat.set_shader_parameter("fog_tex", tex)
	mat.set_shader_parameter("fog_origin", f.origin)
	mat.set_shader_parameter("fog_size", Vector2(f.w, f.h) * f.cell)
	mat.set_shader_parameter("unexplored", Config.f("rules.view.fog_unexplored_brightness"))


func render() -> void:
	var f := world.fog
	if f.version == _ver:
		return
	_ver = f.version
	img.set_data(f.w, f.h, false, Image.FORMAT_L8, f.display)
	tex.update(img)
	mat.set_shader_parameter("enabled", 1.0 if f.enabled else 0.0)
