class_name Lobby
extends VBoxContainer
## Лобби коопа (M5-1): заглушка до реализации сети.

signal start_requested(opts: Dictionary)
signal back_requested


func open(_host: bool) -> void:
	for c in get_children():
		c.queue_free()
	position = Vector2(80, 290)
	add_child(UiTheme.label(tr("LOBBY_SOON"), 16))
	add_child(UiTheme.button(tr("MENU_BACK"), func() -> void: back_requested.emit()))
