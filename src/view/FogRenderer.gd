class_name FogRenderer
extends Node
## Туман войны: растр FogOfWar → глобальные параметры шейдеров (fog.gdshaderinc). Каждый материал мира
## сам затемняет себя по мировой позиции — одинаково в Forward+ и в WebGL, без пост-эффекта.

var world: World
var img: Image
var tex: ImageTexture
var _ver: int = -1


func setup(w: World) -> void:
	world = w
	var f := w.fog
	img = Image.create_from_data(f.w, f.h, false, Image.FORMAT_L8, f.display)
	tex = ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("qm_fog", tex)
	RenderingServer.global_shader_parameter_set("qm_fog_rect", Vector4(f.origin.x, f.origin.y, f.w * f.cell, f.h * f.cell))
	_set_k()


func _set_k() -> void:
	var f := world.fog
	RenderingServer.global_shader_parameter_set("qm_fog_k",
		Vector4(1.0 if f.enabled else 0.0, Config.f("rules.view.fog_unexplored_brightness"), 1.0 / maxf(f.w, 1), 0.0))


func render() -> void:
	var f := world.fog
	if f.version == _ver:
		return
	_ver = f.version
	img.set_data(f.w, f.h, false, Image.FORMAT_L8, f.display)
	tex.update(img)
	_set_k()


func _exit_tree() -> void:
	# меню и следующая партия — без тумана
	RenderingServer.global_shader_parameter_set("qm_fog_k", Vector4.ZERO)
