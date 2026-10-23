class_name Agent
extends RefCounted
## Военный юнит или мирный (GDD §6–7). Агентов ≤ ~300 — это объекты, не SoA (в отличие от зомби).

enum Kind { INFANTRY, VEHICLE, AIR, CIVILIAN }
## Приказы военных
enum Order { NONE, MOVE, AMOVE, ATTACK, HOLD, PATROL, ENTER, UNLOAD, REFUEL, FOLLOW }
## Состояния мирных (civilians.json/adult/states)
enum Civ { UNAWARE, FOLLOWING, FLEEING, HEADING_TO_BASE, CHECKPOINT, IDLE, WORKING, BUILDING, TRAINING, QUARANTINED, ROOFTOP }

var id: int = 0
var kind: int = Kind.INFANTRY
var type: String = ""
var owner: int = 0            # pid игрока; мирные — -1
var pos: Vector2 = Vector2.ZERO
var facing: float = 0.0       # рад, 0 = +Z (модели смотрят в +Z)
var vel: Vector2 = Vector2.ZERO
var hp: float = 1.0
var max_hp: float = 1.0
var armor: String = "light"
var speed: float = 5.0
var vision: float = 25.0
var radius: float = 0.4
var alive: bool = true
var hidden: bool = false      # в гарнизоне/транспорте/на крыше — не цель для зомби
var container: int = -1       # id постройки (гарнизон) или агента (транспорт)
var passengers: Array[int] = []

# --- движение
var path := PackedVector2Array()
var path_i: int = 0
var dest: Vector2 = Vector2.ZERO
var moving: bool = false
var stuck_t: float = 0.0
var repath_cd: float = 0.0
var speed_mult: float = 1.0

# --- приказы и бой
var order: int = Order.NONE
var order_target: int = -1    # агент/постройка в зависимости от приказа
var order_target_unit: bool = false  # ENTER: true — транспорт (id агента), false — постройка
var order_pos: Vector2 = Vector2.ZERO
var patrol_a: Vector2 = Vector2.ZERO
var patrol_b: Vector2 = Vector2.ZERO
var target_z: int = -1        # индекс зомби
var target_nest: int = -1
var atk_cd: float = 0.0
var atk2_cd: float = 0.0
var scan_cd: float = 0.0
var ability_cd: Dictionary = {}
var camo_t: float = 0.0
var ram_t: float = 0.0
var dot_dps: float = 0.0
var dot_t: float = 0.0
var fuel: float = 0.0
var noise_cd: float = 0.0
var hp_mult: float = 1.0
var dmg_mult: float = 1.0
var temp_life: float = -1.0   # временные бойцы «Штурмовой группы»
var heal_cd: float = 0.0

# --- заражение (GDD §8.2)
var infected: bool = false
var infect_t: float = 0.0
var infect_detected: bool = false

# --- мирные
var civ: int = Civ.IDLE
var leader: int = -1
var work_b: int = -1          # постройка, где работает/строит
var job_t: float = 0.0
var job_phase: int = 0
var job_node: int = -1        # ресурсный узел
var carry: Dictionary = {}
var trait_id: String = ""
var is_child: bool = false
var age_days: float = 0.0
var home_b: int = -1
var spawn_kind: String = ""
var rescued: bool = false
var flee_t: float = 0.0
var revealed: bool = false    # «?» — видели разведчиком или в поле зрения


func is_unit() -> bool:
	return kind != Kind.CIVILIAN


func targetable() -> bool:
	return alive and not hidden


## Класс для combat.target_priority.zombie_vs
func priority_class() -> String:
	match kind:
		Kind.CIVILIAN:
			return "child" if is_child else "civilian"
		Kind.INFANTRY:
			return "infantry"
		_:
			return "vehicle"


func is_free_adult() -> bool:
	return kind == Kind.CIVILIAN and alive and not is_child and civ == Civ.IDLE and not hidden


func in_base_state() -> bool:
	return civ in [Civ.IDLE, Civ.WORKING, Civ.BUILDING, Civ.TRAINING, Civ.QUARANTINED, Civ.CHECKPOINT]


func stop() -> void:
	path = PackedVector2Array()
	path_i = 0
	moving = false
	vel = Vector2.ZERO
