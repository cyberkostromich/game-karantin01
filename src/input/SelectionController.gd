class_name SelectionController
extends Control
## Выделение и приказы мышью (M0-6, docs/07_ui_hud.md §3): ЛКМ/рамка/Shift/двойной клик, ПКМ — приказ
## по контексту (земля — движение, гнездо — атака, вышка/техника — посадка, здание со слотами — работа).
## Режимы: A-move, патруль, цель способности, пинг. Стройка — BuildController.

enum Mode { NORMAL, AMOVE, PATROL, ABILITY, DOCTRINE, PING }

var game: Node   # Game.gd
var mode: int = Mode.NORMAL
var ability_id: String = ""
var ability_unit: int = -1
var doctrine_id: String = ""
var _press := Vector2.ZERO
var _dragging := false
var _box := Rect2()
var _last_click_t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func world() -> World:
	return game.world


func sel() -> Selection:
	return game.selection


func set_mode(m: int) -> void:
	mode = m
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if m != Mode.NORMAL else Input.CURSOR_ARROW)


func _draw() -> void:
	if _dragging:
		draw_rect(_box, Color(0.35, 1.0, 0.45, 0.12), true)
		draw_rect(_box, Color(0.35, 1.0, 0.45, 0.8), false, 1.0)


func _unhandled_input(ev: InputEvent) -> void:
	if game.build.active():
		return
	if ev is InputEventMouseButton:
		_mouse_button(ev as InputEventMouseButton)
	elif ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and mode == Mode.NORMAL:
		var m := (ev as InputEventMouseMotion).position
		if _press.distance_to(m) > 6.0:
			_dragging = true
			_box = Rect2(_press, m - _press).abs()
			queue_redraw()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev as InputEventKey)


func _mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press = mb.position
			if mb.alt_pressed:
				game.send({"t": "ping", "kind": "attention", "pos": _ground(mb.position)})
				return
			if mode != Mode.NORMAL:
				_target_click(mb.position, mb.shift_pressed)
		else:
			if mode != Mode.NORMAL:
				return
			if _dragging:
				_box_select(mb.shift_pressed)
			else:
				_click_select(mb.position, mb.shift_pressed, mb.double_click)
			_dragging = false
			queue_redraw()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if mode != Mode.NORMAL:
			set_mode(Mode.NORMAL)
			return
		_right_click(mb.position, mb.shift_pressed)


func _ground(sp: Vector2) -> Vector2:
	return game.cam.ground_at(sp)


# ------------------------------------------------------------------ выделение
func _box_select(add: bool) -> void:
	var w := world()
	var units: Array[int] = []
	var civs: Array[int] = []
	for a in w.agents.list:
		if not a.alive or a.hidden:
			continue
		if not _box.has_point(game.agents_view.screen_pos(game.cam, a)):
			continue
		if a.is_unit() and (a.owner == game.pid or w.is_shared_control()):
			units.append(a.id)
		elif a.kind == Agent.Kind.CIVILIAN and a.rescued:
			civs.append(a.id)
	if not units.is_empty():
		civs.clear()  # рамка по смешанной толпе берёт бойцов
	sel().set_agents(units, civs, add)


func pick_agent(p: Vector2) -> Agent:
	var w := world()
	var best: Agent = null
	var bd := 2.2
	for a in w.agents.list:
		if not a.alive or a.hidden:
			continue
		if a.kind == Agent.Kind.CIVILIAN and not a.rescued and not w.fog.visible(a.pos):
			continue
		var d := a.pos.distance_to(p) - a.radius  # вертолёт — по тени на земле
		if d < bd:
			bd = d
			best = a
	return best


func pick_poi(p: Vector2) -> MapPoi:
	for poi in world().map.pois:
		if poi.alive and not poi.done and poi.pos.distance_to(p) < maxf(8.0, poi.radius + 3.0) and world().fog.explored(poi.pos):
			return poi
	return null


func _click_select(sp: Vector2, add: bool, double: bool) -> void:
	var p := _ground(sp)
	var a := pick_agent(p)
	var w := world()
	if a != null:
		if double:
			_select_type_on_screen(a)
			return
		if a.is_unit() and (a.owner == game.pid or w.is_shared_control()):
			sel().set_agents([a.id], [], add)
		elif a.kind == Agent.Kind.CIVILIAN:
			sel().set_agents([], [a.id], add)
		return
	var b := w.buildings.building_near(p, 0.5)
	if b != null:
		sel().set_building(b.id)
		return
	var poi := pick_poi(p)
	if poi != null:
		sel().set_poi(poi.id)
		return
	if not add:
		sel().clear()


func _select_type_on_screen(a: Agent) -> void:
	var rect := get_viewport_rect()
	var units: Array[int] = []
	var civs: Array[int] = []
	for b in world().agents.list:
		if b.alive and not b.hidden and b.type == a.type and b.kind == a.kind and rect.has_point(game.agents_view.screen_pos(game.cam, b)):
			if b.is_unit() and (b.owner == game.pid or world().is_shared_control()):
				units.append(b.id)
			elif b.kind == Agent.Kind.CIVILIAN and b.rescued:
				civs.append(b.id)
	sel().set_agents(units, civs)


# ------------------------------------------------------------------ приказы
func _right_click(sp: Vector2, queue: bool) -> void:
	var p := _ground(sp)
	var w := world()
	var s := sel()
	if not s.units.is_empty():
		for n in w.map.nests:
			if n.alive and n.pos.distance_to(p) < n.radius + 4.0 and w.fog.explored(n.pos):
				game.send({"t": "attack", "units": s.units, "target": n.id})
				game.marker(p, Color(1, 0.3, 0.2))
				return
		var b := w.buildings.building_near(p, 0.5)
		if b != null and b.data().has("garrison"):
			game.send({"t": "enter", "units": s.units, "target": b.id})
			game.marker(p, Color(0.4, 0.8, 1))
			return
		var v := pick_agent(p)
		if v != null and v.is_unit() and world().units.transport_cap(v, false) > 0 and not s.units.has(v.id):
			game.send({"t": "enter", "units": s.units, "target": v.id})
			game.marker(p, Color(0.4, 0.8, 1))
			return
		game.send({"t": "move", "units": s.units, "pos": p, "queue": queue, "amove": false})
		game.marker(p, Color(0.35, 1.0, 0.45))
	elif not s.civs.is_empty():
		var b := w.buildings.building_near(p, 0.5)
		if b != null and b.worker_slots > 0:
			game.send({"t": "assign", "civilians": s.civs, "building_id": b.id})
			game.marker(p, Color(1.0, 0.8, 0.3))
	elif s.building >= 0:
		game.send({"t": "rally", "building_id": s.building, "pos": p})
		game.marker(p, Color(1.0, 0.8, 0.3))


func _target_click(sp: Vector2, shift: bool) -> void:
	var p := _ground(sp)
	var s := sel()
	match mode:
		Mode.AMOVE:
			game.send({"t": "move", "units": s.units, "pos": p, "queue": false, "amove": true})
			game.marker(p, Color(1, 0.35, 0.25))
		Mode.PATROL:
			game.send({"t": "patrol", "units": s.units, "pos": p})
			game.marker(p, Color(0.4, 0.8, 1))
		Mode.ABILITY:
			game.send({"t": "ability", "unit": ability_unit, "ability": ability_id, "pos": p})
			game.marker(p, Color(1, 0.55, 0.2))
		Mode.DOCTRINE:
			game.send({"t": "doctrine", "doctrine": doctrine_id, "pos": p})
			game.marker(p, Color(1, 0.55, 0.2))
		Mode.PING:
			game.send({"t": "ping", "kind": "attention", "pos": p})
	if not shift:
		set_mode(Mode.NORMAL)


func _key(k: InputEventKey) -> void:
	var s := sel()
	var code := k.physical_keycode
	if code >= KEY_1 and code <= KEY_9:
		var g := code - KEY_0
		if k.ctrl_pressed:
			s.groups[g] = s.units.duplicate()
		elif s.groups.has(g):
			var ids: Array[int] = []
			ids.assign((s.groups[g] as Array).filter(func(id: int) -> bool: return world().agents.get_agent(id) != null))
			var same: bool = ids == s.units
			s.set_agents(ids, [])
			if same and not ids.is_empty():
				game.cam.focus(world().agents.get_agent(ids[0]).pos)
		return
	if s.units.is_empty():
		return
	if k.is_action("cmd_amove"):
		set_mode(Mode.AMOVE)
	elif k.is_action("cmd_stop"):
		game.send({"t": "stop", "units": s.units})
	elif k.is_action("cmd_hold"):
		game.send({"t": "hold", "units": s.units})
	elif k.is_action("cmd_patrol"):
		set_mode(Mode.PATROL)
	elif k.is_action("unload"):
		game.send({"t": "unload", "units": s.units})
	else:
		for i in 4:
			if k.is_action("ab_%d" % (i + 1)):
				game.hud.command_card.press_ability(i)


## Способность выбранной группы: берём первого юнита, у которого она готова.
func begin_ability(id: String) -> void:
	var w := world()
	for uid in sel().units:
		var a := w.agents.get_agent(uid)
		if a != null and w.abilities.check(a, id) == "":
			ability_unit = a.id
			ability_id = id
			if id in ["aimed_shot", "camo", "smoke", "ram"]:
				game.send({"t": "ability", "unit": a.id, "ability": id, "pos": a.pos})
				return
			set_mode(Mode.ABILITY)
			return


func begin_doctrine(id: String) -> void:
	doctrine_id = id
	set_mode(Mode.DOCTRINE)
