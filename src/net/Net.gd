extends Node
## Сеть (M5): пока заглушка с интерфейсом, который зовёт Game.

func attach_host(_game: Node) -> void:
	pass


func attach_client(_game: Node) -> void:
	pass


func send_command(_cmd: Dictionary) -> void:
	pass


func after_tick() -> void:
	pass


func interp_alpha() -> float:
	return 1.0


func leave() -> void:
	pass
