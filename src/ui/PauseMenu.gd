class_name PauseMenu
extends PanelContainer
## Пауза/меню (Esc): продолжить, настройки, выход в главное меню. В коопе пауза не останавливает хост.

var game: Node
var settings := SettingsPanel.new()


func setup(g: Node) -> void:
	game = g
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(360, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UiTheme.label(tr("MENU_PAUSE"), 22, UiTheme.TEXT, true))
	v.add_child(UiTheme.button(tr("MENU_CONTINUE"), toggle))
	v.add_child(UiTheme.button(tr("MENU_SETTINGS"), func() -> void: settings.visible = not settings.visible))
	v.add_child(settings)
	settings.build()
	settings.visible = false
	v.add_child(UiTheme.button(tr("MENU_HELP"), func() -> void: game.hud.tutorial.show_help()))
	v.add_child(UiTheme.button(tr("MENU_TO_MAIN"), func() -> void: game.exit_to_menu()))


func toggle() -> void:
	visible = not visible
	position = (get_viewport_rect().size - get_combined_minimum_size()) * 0.5
	game.set_menu_pause(visible)
