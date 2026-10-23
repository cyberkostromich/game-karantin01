class_name HumanAnim
extends RefCounted
## Процедурная анимация гуманоида по узлам модели (арт-библия §5, §7): ходьба и бег со сгибом колен
## и локтей, дыхание и осмотр в покое, работа (стройка/сбор), паника, отдача при выстреле, шатание
## заражённого и падение при смерти. Только вид: читает состояние агента, sim не трогает.
## Узлы shin_*/forearm_* есть у моделей v3; у старых их нет — тогда сгибов просто не будет.

const NODES: PackedStringArray = ["body", "head", "leg_l", "leg_r", "shin_l", "shin_r", "arm_l", "arm_r",
	"forearm_l", "forearm_r", "weapon"]
const SMOOTH := 10.0       # скорость перехода между позами, 1/с

var parts: Dictionary = {}  # имя → Node3D
var rest: Dictionary = {}   # имя → Transform3D позы покоя
var cur: Dictionary = {}    # имя → Vector3 текущие углы (рад) поверх позы покоя
var body_y: float = 0.0
var t: float = 0.0
var phase: float = 0.0
var seed: float = 0.0
var armed: bool = false
var civilian: bool = false
var recoil: float = 0.0
var _last_cd: float = 0.0
var dying: float = -1.0     # ≥ 0 — секунды с момента смерти


func setup(model: Node3D, is_armed: bool, is_civilian: bool, id: int) -> void:
	armed = is_armed
	civilian = is_civilian
	seed = fmod(float(id) * 1.37, TAU)
	phase = seed
	for pn in NODES:
		var n := Look.find(model, pn)
		if n != null:
			parts[pn] = n
			rest[pn] = n.transform
			cur[pn] = Vector3.ZERO


func update(a: Agent, delta: float) -> void:
	t += delta
	var pose := {}
	var spd := a.vel.length()
	if a.atk_cd > _last_cd + 0.01:
		recoil = 1.0
	_last_cd = a.atk_cd
	recoil = maxf(0.0, recoil - delta * 7.0)
	if spd > 0.15:
		_gait(pose, spd, delta, civilian and a.civ == Agent.Civ.FLEEING)
	elif civilian and a.civ in [Agent.Civ.WORKING, Agent.Civ.BUILDING]:
		_work(pose)
	elif civilian and a.civ == Agent.Civ.TRAINING:
		_drill(pose)
	else:
		_idle(pose)
	if a.infected and a.infect_detected:
		_add(pose, "body", Vector3(0.12, 0.0, sin(t * 2.3 + seed) * 0.09))
		_add(pose, "head", Vector3(0.25 + sin(t * 1.7) * 0.1, 0.0, 0.0))
	if recoil > 0.0 and armed:
		_add(pose, "body", Vector3(-0.07 * recoil, 0.0, 0.0))
		_add(pose, "head", Vector3(-0.04 * recoil, 0.0, 0.0))
	_apply(pose, delta)


func _add(pose: Dictionary, pn: String, v: Vector3) -> void:
	pose[pn] = (pose.get(pn, Vector3.ZERO) as Vector3) + v


## Ходьба/бег: бедро качается, колено сгибается на выносе ноги, руки в противофазе, корпус
## подпрыгивает дважды за шаг и наклоняется вперёд тем сильнее, чем быстрее.
func _gait(pose: Dictionary, spd: float, delta: float, panic: bool) -> void:
	var g := clampf(spd / 6.0, 0.25, 1.3)
	phase += delta * (2.0 + spd * 1.35)
	var s := sin(phase)
	var c := cos(phase)
	pose["leg_l"] = Vector3(-s * 0.62 * g, 0.0, 0.0)
	pose["leg_r"] = Vector3(s * 0.62 * g, 0.0, 0.0)
	pose["shin_l"] = Vector3((0.12 + 1.0 * maxf(0.0, c)) * g, 0.0, 0.0)
	pose["shin_r"] = Vector3((0.12 + 1.0 * maxf(0.0, -c)) * g, 0.0, 0.0)
	pose["body"] = Vector3(0.05 + 0.1 * g, s * 0.07 * g, 0.0)
	pose["head"] = Vector3(-0.05 * g, -s * 0.06 * g, 0.0)
	body_y = (absf(s) - 0.6) * 0.06 * g
	if panic:  # бегут, вскинув руки
		pose["arm_l"] = Vector3(-2.4 + sin(phase * 2.0) * 0.35, 0.0, -0.35)
		pose["arm_r"] = Vector3(-2.4 - sin(phase * 2.0) * 0.35, 0.0, 0.35)
		pose["forearm_l"] = Vector3(-0.6, 0.0, 0.0)
		pose["forearm_r"] = Vector3(-0.6, 0.0, 0.0)
	elif armed:  # оружие у плеча — руки почти не качаются
		pose["arm_l"] = Vector3(s * 0.05, 0.0, 0.0)
		pose["arm_r"] = Vector3(-s * 0.05, 0.0, 0.0)
	else:
		pose["arm_l"] = Vector3(s * 0.55 * g, 0.0, 0.0)
		pose["arm_r"] = Vector3(-s * 0.55 * g, 0.0, 0.0)
		pose["forearm_l"] = Vector3(-(0.2 + 0.45 * g) - maxf(0.0, -s) * 0.3, 0.0, 0.0)
		pose["forearm_r"] = Vector3(-(0.2 + 0.45 * g) - maxf(0.0, s) * 0.3, 0.0, 0.0)


## Покой: дыхание, перенос веса, неторопливый осмотр по сторонам с паузами.
func _idle(pose: Dictionary) -> void:
	var br := sin(t * 1.6 + seed)
	var look := sin(t * 0.31 + seed) * sin(t * 0.17 + seed * 2.0)
	pose["body"] = Vector3(br * 0.012, 0.0, sin(t * 0.4 + seed) * 0.015)
	pose["head"] = Vector3(0.04 + sin(t * 0.23 + seed) * 0.05, look * 0.7, 0.0)
	body_y = br * 0.006
	if not armed:
		pose["arm_l"] = Vector3(br * 0.03, 0.0, -0.02)
		pose["arm_r"] = Vector3(-br * 0.03, 0.0, 0.02)
		pose["forearm_l"] = Vector3(-0.12, 0.0, 0.0)
		pose["forearm_r"] = Vector3(-0.12, 0.0, 0.0)


## Работа на стройке/добыче: наклон, правая рука бьёт «молотком», левая придерживает.
func _work(pose: Dictionary) -> void:
	var w := sin(t * 5.5 + seed)
	pose["body"] = Vector3(0.38 + w * 0.05, 0.0, 0.0)
	pose["head"] = Vector3(0.25, 0.0, 0.0)
	pose["arm_r"] = Vector3(-1.35 - w * 0.55, 0.0, 0.1)
	pose["forearm_r"] = Vector3(-0.7 + w * 0.35, 0.0, 0.0)
	pose["arm_l"] = Vector3(-0.85, 0.0, -0.15)
	pose["forearm_l"] = Vector3(-0.6, 0.0, 0.0)
	pose["leg_l"] = Vector3(-0.25, 0.0, 0.0)
	pose["shin_l"] = Vector3(0.45, 0.0, 0.0)
	pose["shin_r"] = Vector3(0.2, 0.0, 0.0)
	body_y = -0.06


## Обучение рекрута: махи руками и приседания.
func _drill(pose: Dictionary) -> void:
	var d := 0.5 - 0.5 * cos(t * 3.2 + seed)
	pose["arm_l"] = Vector3(0.0, 0.0, -2.6 * d)
	pose["arm_r"] = Vector3(0.0, 0.0, 2.6 * d)
	pose["leg_l"] = Vector3(-0.5 * d, 0.0, -0.12 * d)
	pose["leg_r"] = Vector3(-0.5 * d, 0.0, 0.12 * d)
	pose["shin_l"] = Vector3(0.9 * d, 0.0, 0.0)
	pose["shin_r"] = Vector3(0.9 * d, 0.0, 0.0)
	body_y = -0.12 * d


func _apply(pose: Dictionary, delta: float) -> void:
	var k := minf(1.0, delta * SMOOTH)
	for pn: String in parts:
		var target: Vector3 = pose.get(pn, Vector3.ZERO)
		var v: Vector3 = (cur[pn] as Vector3).lerp(target, k)
		cur[pn] = v
		var n: Node3D = parts[pn]
		var r: Transform3D = rest[pn]
		n.transform = Transform3D(Basis.from_euler(v) * r.basis, r.origin)
	if parts.has("body"):
		var b: Node3D = parts["body"]
		b.position.y = (rest["body"] as Transform3D).origin.y + body_y
	if parts.has("weapon") and armed:
		var wpn: Node3D = parts["weapon"]
		wpn.position.z = (rest["weapon"] as Transform3D).origin.z - recoil * 0.06


## Смерть: обмякшие конечности, падение навзничь (или ничком — по сиду) и уход под землю.
## Возвращает false, когда анимация доиграна и вид можно удалять.
func die(model: Node3D, delta: float) -> bool:
	dying = maxf(dying, 0.0) + delta
	var f := ease(minf(1.0, dying / 0.55), 2.4)
	var dir := -1.0 if fmod(seed, 2.0) < 1.0 else 1.0
	model.rotation.x = dir * PI * 0.48 * f
	model.position.y = -maxf(0.0, dying - 1.6) * 0.8
	var limp := {"arm_l": Vector3(-1.2 * dir, 0.0, -0.6), "arm_r": Vector3(-1.0 * dir, 0.0, 0.7),
		"forearm_l": Vector3(-0.5, 0.0, 0.0), "head": Vector3(0.4 * dir, 0.6, 0.0), "shin_l": Vector3(0.6, 0.0, 0.0),
		"weapon": Vector3(1.4 * dir, 0.0, 0.5)}  # оружие выпадает из рук и ложится вдоль тела
	_apply(limp, delta * 0.6)
	return dying < 2.8
