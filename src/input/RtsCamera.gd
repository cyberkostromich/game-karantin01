class_name RtsCamera
extends Camera3D
## Камера RTS (M0-4): WASD/край экрана/СКМ, колесо — зум с двумя уровнями наклона (55° → 65°),
## без свободного вращения (GDD §17). Ограничена рамкой карты.

var target := Vector3.ZERO       # точка на земле, куда смотрим
var zoom: float = 0.45           # 0 — близко, 1 — далеко
var zoom_target: float = 0.45
var bounds := Rect2(-1000, -1000, 2000, 2000)
var min_h: float = 22.0
var max_h: float = 150.0
var pan_speed: float = 1.0
var edge_px: int = 6
var edge_scroll: bool = true
var wasd_enabled: bool = true
var _drag := false
var _drag_from := Vector2.ZERO
var _shake: float = 0.0


func _ready() -> void:
	zoom = Config.f("rules.view.camera_default_zoom")
	zoom_target = zoom
	fov = 50.0
	near = 0.5
	far = 3500.0
	current = true


func focus(p: Vector2) -> void:
	target = Vector3(p.x, 0, p.y)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func height() -> float:
	return lerpf(min_h, max_h, zoom)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_target = clampf(zoom_target - 0.08, 0.0, 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_target = clampf(zoom_target + 0.08, 0.0, 1.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
			_drag_from = mb.position
	elif ev is InputEventMouseMotion and _drag:
		var mm := ev as InputEventMouseMotion
		var k := height() / 400.0
		target.x -= mm.relative.x * k
		target.z -= mm.relative.y * k


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("cam_left"): dir.x -= 1
	if Input.is_action_pressed("cam_right"): dir.x += 1
	if Input.is_action_pressed("cam_up"): dir.y -= 1
	if Input.is_action_pressed("cam_down"): dir.y += 1
	if wasd_enabled and not Input.is_key_pressed(KEY_CTRL):
		dir += Keys.wasd_dir()
	if edge_scroll and DisplayServer.window_is_focused():
		var m := get_viewport().get_mouse_position()
		var s := get_viewport().get_visible_rect().size
		if m.x >= 0 and m.y >= 0 and m.x <= s.x and m.y <= s.y:
			if m.x < edge_px: dir.x -= 1
			if m.x > s.x - edge_px: dir.x += 1
			if m.y < edge_px: dir.y -= 1
			if m.y > s.y - edge_px: dir.y += 1
	var spd := (40.0 + height() * 2.2) * pan_speed
	target.x += dir.x * spd * delta
	target.z += dir.y * spd * delta
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	zoom = lerpf(zoom, zoom_target, minf(1.0, delta * 8.0))
	var pitch := deg_to_rad(lerpf(55.0, 65.0, smoothstep(0.35, 0.9, zoom)))
	var h := height()
	var back := h / tan(pitch)
	var off := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
	position = target + Vector3(0, h, back) + off
	rotation = Vector3(-pitch, 0, 0)


## Луч из экранной точки на плоскость земли y=0.
func ground_at(screen: Vector2) -> Vector2:
	var o := project_ray_origin(screen)
	var d := project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector2(target.x, target.z)
	var t := -o.y / d.y
	var p := o + d * t
	return Vector2(p.x, p.z)
