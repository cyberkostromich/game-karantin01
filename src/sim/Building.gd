class_name Building
extends RefCounted
## Наша постройка (GDD §10). Объекты карты (подстанция, лут, метро) — это MapPoi, не Building.

enum State { CONSTRUCTING, COMPLETE }

var id: int = 0
var type: String = ""
var owner: int = 0
var cells := Rect2i()
var rect_m := Rect2()
var pos: Vector2 = Vector2.ZERO
var rot: int = 0
var hp: float = 1.0
var max_hp: float = 1.0
var alive: bool = true
var state: int = State.CONSTRUCTING
var progress: float = 0.0
var workers: Array[int] = []       # мирные на слотах (добыча/кухня/медпункт/мастерская)
var worker_slots: int = 0
var builders: Array[int] = []      # строители/ремонтники, назначенные сейчас
var powered: bool = true
var enabled: bool = true           # ручное выключение игроком (команда power)
var power_need: float = 0.0        # сколько потребляет (>0) в текущей фазе
var repairing: bool = false
var upgrading_to: String = ""
var upgrade_progress: float = 0.0
var queue: Array[Dictionary] = []  # обучение: {unit, t, total, owner}
var research: Dictionary = {}      # {tech, t, total}
var garrison: Array[int] = []
var ability_cd: float = 0.0
var noise_cd: float = 0.0
var patients: Array[int] = []      # медпункт/карантин
var door: Vector2 = Vector2.ZERO        # точка выхода юнитов / входа мирных
var rally: Vector2 = Vector2.ZERO
var hits_taken_t: float = 0.0


func data() -> Dictionary:
	return Config.d("buildings." + type)


func complete() -> bool:
	return state == State.COMPLETE and alive


func working() -> bool:
	return complete() and enabled and powered


func is_wall_like() -> bool:
	return bool(data().get("drag_build", false))


func footprint() -> Vector2i:
	var f: Array = data()["footprint"]
	return Vector2i(int(f[0]), int(f[1])) if rot % 2 == 0 else Vector2i(int(f[1]), int(f[0]))


func half_extent() -> float:
	return maxf(rect_m.size.x, rect_m.size.y) * 0.5
