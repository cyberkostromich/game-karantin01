class_name GameClock
extends RefCounted
## Фазы дня (GDD §2.2): рассвет → день → сумерки → ночь. День 1 начинается сразу с дня.
## В tech spec — автолоад; здесь — часть World, чтобы симуляцию можно было крутить headless в тестах (D-4).

const PHASES: PackedStringArray = ["dawn", "day", "dusk", "night"]

var world: World
var day: int = 1
var phase: int = 1
var t: float = 0.0           # время внутри фазы
var durations := PackedFloat32Array()
var total_days: int = 12
var finished: bool = false


func setup(w: World) -> void:
	world = w
	var dc := "rules.day_cycle."
	durations = PackedFloat32Array([Config.f(dc + "dawn_s"), Config.f(dc + "day_s"),
		Config.f(dc + "dusk_s"), Config.f(dc + "night_s")])
	total_days = Config.i(dc + "days_total")


func phase_name() -> String:
	return PHASES[phase]


func is_night() -> bool:
	return phase == 3


func is_dark() -> bool:
	return phase == 3 or (phase == 2 and t > durations[2] * 0.5)


func left() -> float:
	return durations[phase] - t


func frac() -> float:
	return t / maxf(0.001, durations[phase])


func day_length() -> float:
	var s := 0.0
	for d in durations:
		s += d
	return s


## 0..1 «темноты» для освещения (плавные сумерки и рассвет).
func darkness() -> float:
	match phase:
		0: return 1.0 - frac()
		1: return 0.0
		2: return frac()
		_: return 1.0


func advance(dt: float) -> void:
	if finished:
		return
	t += dt
	while t >= durations[phase]:
		t -= durations[phase]
		_next_phase()
		if finished:
			return


func _next_phase() -> void:
	phase = (phase + 1) % 4
	if phase == 0:
		if day >= total_days:
			finished = true  # рассвет после ночи 12 — эвакуация (GDD §14)
			world.on_final_dawn()
			return
		day += 1
		world.on_dawn()
	elif phase == 1:
		world.on_day_start()
	elif phase == 2:
		world.on_dusk()
	else:
		world.on_night()
	world.emit("phase_changed", [day, phase_name()])


## Сколько секунд от начала текущей ночи (или -1 не ночью).
func night_elapsed() -> float:
	return t if phase == 3 else -1.0
