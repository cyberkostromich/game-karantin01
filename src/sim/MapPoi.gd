class_name MapPoi
extends RefCounted
## Объект карты (не строится игроком): лут-здание, подстанция, радиовышка, форт, гнездо в метро.

var id: int = 0
var key: String = ""
var type: String = ""
var name: String = ""
var pos: Vector2 = Vector2.ZERO      # проходимая точка взаимодействия
var anchor: Vector2 = Vector2.ZERO   # реальная точка объекта (центр здания/станции)
var alive: bool = true
var hp: float = 0.0
var max_hp: float = 0.0
var radius: float = 6.0
var progress: float = 0.0            # рейд/ремонт/захват 0..1
var done: bool = false               # разграблен / починен / захвачен / уничтожен
var paid: bool = false               # оплачен ремонт
var timer: float = 0.0
var spawned: Array[int] = []         # зомби гнезда (для ambient_cap)
