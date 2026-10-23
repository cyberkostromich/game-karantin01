class_name Portrait
extends SubViewportContainer
## Живой 3D-портрет выбранного (как в SC2/CoH): своя маленькая сцена с моделью, светом и камерой
## на голову и плечи; модель чуть покачивается. Один на панель выделения — меняется только модель.

var vp := SubViewport.new()
var cam := Camera3D.new()
var holder := Node3D.new()
var model_path: String = ""
var _t: float = 0.0


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(96, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(192, 192)
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.64, 0.7)
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()   # контровой свет — силуэт отделяется от тёмного слота
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.78, 0.55)
	vp.add_child(rim)
	vp.add_child(holder)
	cam.fov = 26.0
	vp.add_child(cam)


## path — модель (как в data/*.json); vehicle — кадр шире и ниже.
func show_model(path: String, vehicle := false) -> void:
	if path == model_path:
		return
	model_path = path
	for c in holder.get_children():
		c.queue_free()
	var m := Look.instance(path)
	holder.add_child(m)
	var aabb := _aabb(m)
	var h := aabb.size.y
	var target := aabb.get_center() + Vector3(0, h * (0.0 if vehicle else 0.2), 0)
	var dist := (maxf(aabb.size.x, aabb.size.z) * 1.6 if vehicle else h * 1.45)
	cam.position = target + Vector3(0.0, dist * 0.18, dist)
	cam.look_at(target)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _process(delta: float) -> void:
	_t += delta
	holder.rotation.y = 0.45 + sin(_t * 0.6) * 0.25
