class_name NoiseSystem
extends RefCounted
## Буфер событий шума (GDD §9, tech spec §3.3). Раз в тик: idle-зомби в радиусе × hearing_mult → investigate.

var events: Array[Vector3] = []   # x, z, radius
## Отладка/«Радиоперехват»: последние шумы для визуализации.
var recent: Array[Vector3] = []
var recent_max: int = 32


func emit(pos: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	events.append(Vector3(pos.x, pos.y, radius))


func take() -> Array[Vector3]:
	var out := events
	events = []
	for e in out:
		recent.append(e)
	if recent.size() > recent_max:
		recent = recent.slice(recent.size() - recent_max)
	return out
