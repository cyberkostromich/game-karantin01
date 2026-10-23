class_name Keys
extends RefCounted
## Раскладка по docs/07_ui_hud.md §3. Действия регистрируются кодом (project.godot не правим руками).
## Конфликт WASD (камера) и A/S/Q/W/E/R (приказы) решён так: при выделенных юнитах буквы — приказы,
## камера — стрелки/край/СКМ; без выделения WASD двигает камеру (docs/decisions.md D-7).

const MAP := {
	"cam_left": [KEY_LEFT], "cam_right": [KEY_RIGHT], "cam_up": [KEY_UP], "cam_down": [KEY_DOWN],
	"cam_home": [KEY_HOME], "cam_event": [KEY_SPACE],
	"cmd_amove": [KEY_A], "cmd_stop": [KEY_S], "cmd_hold": [KEY_H], "cmd_patrol": [KEY_P],
	"ab_1": [KEY_Q], "ab_2": [KEY_W], "ab_3": [KEY_E], "ab_4": [KEY_R],
	"build_menu": [KEY_B], "tech_tree": [KEY_T], "idle_civs": [KEY_PERIOD],
	"speed_up": [KEY_EQUAL, KEY_KP_ADD], "speed_down": [KEY_MINUS, KEY_KP_SUBTRACT], "pause": [KEY_PAUSE, KEY_F3],
	"menu": [KEY_ESCAPE], "rotate": [KEY_R], "unload": [KEY_U], "toggle_fog": [KEY_F9],
}


static func setup() -> void:
	for action: String in MAP:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k: int in MAP[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)


static func wasd_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): d.x -= 1
	if Input.is_physical_key_pressed(KEY_D): d.x += 1
	if Input.is_physical_key_pressed(KEY_W): d.y -= 1
	if Input.is_physical_key_pressed(KEY_S): d.y += 1
	return d
