class_name CommandCard
extends PanelContainer
## Командная карта 4×3 (docs/07 §1): кнопки по выделению, горячие клавиши в углу, кулдаун — затемнение с секундами.
## Без выделения — меню стройки (B) и кнопки науки/мирных.

const BUILD_GROUPS := [
	["core", ["tent", "house", "storage", "kitchen", "greenhouse"]],
	["prod", ["sawmill", "scrapyard", "generator", "solar", "battery"]],
	["med", ["medpost", "quarantine", "checkpoint", "barracks", "motorpool", "helipad", "workshop"]],
	["def", ["wall_wood", "wall_concrete", "gate", "tower", "floodlight", "siren", "sandbags"]],
]
const BUILD_KEYS := "QWERTYUIASDFGHJKZXCVBNM"

var game: Node
var grid := GridContainer.new()
var title: Label
var build_mode: bool = false
var ability_ids: Array[String] = []
var _sig: String = ""
var _acc: float = 0.0


func setup(g: Node) -> void:
	game = g
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	custom_minimum_size = Vector2(360, 196)
	var v := VBoxContainer.new()
	add_child(v)
	title = UiTheme.caps("", 11)
	v.add_child(title)
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	game.selection.changed.connect(func() -> void:
		build_mode = false
		_sig = "")


func toggle_build() -> void:
	build_mode = not build_mode
	_sig = ""


func _process(delta: float) -> void:
	_acc -= delta
	if _acc > 0.0:
		return
	_acc = 0.15
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
	else:
		_refresh()


func _signature() -> String:
	var s: Selection = game.selection
	var w: World = game.world
	var parts: PackedStringArray = [str(build_mode), str(s.units.size()), str(s.civs.size()), str(s.building), str(s.poi)]
	if s.building >= 0:
		var b := w.buildings.get_building(s.building)
		if b != null:
			parts.append("%s%d%d" % [b.type, b.state, b.workers.size()])
	return "|".join(parts)


func _clear() -> void:
	for c in grid.get_children():
		c.queue_free()
	ability_ids.clear()


func _btn(text: String, icon_id: String, key: String, cb: Callable, tip: String, err: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(84, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 11)
	if icon_id != "":
		b.icon = Look.icon(icon_id, 64)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.tooltip_text = tip + ("\n" + tr(err) if err != "" else "")
	b.disabled = err != ""
	b.pressed.connect(cb)
	if key != "":
		var k := UiTheme.label(key, 10, UiTheme.ACCENT, true)
		k.position = Vector2(4, 1)
		b.add_child(k)
	var cd := UiTheme.label("", 13, Color.WHITE, true)
	cd.name = "CD"
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(cd)
	grid.add_child(b)
	return b


func _rebuild() -> void:
	_clear()
	var s: Selection = game.selection
	var w: World = game.world
	if build_mode:
		title.text = tr("CMD_BUILD_MENU").to_upper()
		_build_menu()
	elif not s.units.is_empty():
		title.text = tr("CMD_UNITS").to_upper()
		_units()
	elif s.building >= 0 and w.buildings.get_building(s.building) != null:
		title.text = String(w.buildings.get_building(s.building).data()["name_ru"]).to_upper()
		_building(w.buildings.get_building(s.building))
	elif s.poi >= 0:
		title.text = w.map.pois[s.poi].name.to_upper() if w.map.pois[s.poi].name != "" else tr("POI_" + w.map.pois[s.poi].type.to_upper()).to_upper()
		_poi(w.map.pois[s.poi])
	else:
		title.text = tr("CMD_COMMAND").to_upper()
		_btn(tr("CMD_BUILD"), "bld_hq", "B", toggle_build, tr("CMD_BUILD_TIP"))
		_btn(tr("CMD_TECH"), "bld_workshop", "T", func() -> void: game.hud.toggle_tech(), tr("CMD_TECH_TIP"))
		_btn(tr("CMD_IDLE_CIVS"), "civ_adult", ".", func() -> void: game.select_idle_civilians(), tr("CMD_IDLE_TIP"))
		_btn(tr("CMD_TO_BASE"), "bld_hq", "Home", func() -> void: game.cam.focus(w.map.hq_pos), "")
		_doctrine_buttons()


func _build_menu() -> void:
	var w: World = game.world
	var ki := 0
	for grp: Array in BUILD_GROUPS:
		for t: String in grp[1]:
			var d := Config.d("buildings." + t)
			var err := ""
			if d.get("requires_tech") != null and not w.tech.has(String(d["requires_tech"])):
				err = "BUILD_ERR_TECH"
			elif not w.economy.can_afford(d.get("cost", {})):
				err = "BUILD_ERR_COST"
			var key := BUILD_KEYS[ki] if ki < BUILD_KEYS.length() else ""
			ki += 1
			var b := _btn(String(d["name_ru"]).get_slice(" ", 0), String(d["icon"]).get_file().get_basename(), key,
				func() -> void: game.begin_build(t), _cost_tip(String(d["name_ru"]), d.get("cost", {}), d), err)
			b.set_meta("build", t)
	grid.columns = 6
	custom_minimum_size.x = 540


func _units() -> void:
	grid.columns = 4
	custom_minimum_size.x = 360
	var sel: SelectionController = game.select_ctl
	_btn(tr("CMD_AMOVE"), "st_wave", "A", func() -> void: sel.set_mode(SelectionController.Mode.AMOVE), tr("CMD_AMOVE_TIP"))
	_btn(tr("CMD_STOP"), "st_day", "S", func() -> void: game.send({"t": "stop", "units": game.selection.units}), "")
	_btn(tr("CMD_HOLD"), "bld_sandbags", "H", func() -> void: game.send({"t": "hold", "units": game.selection.units}), tr("CMD_HOLD_TIP"))
	_btn(tr("CMD_PATROL"), "st_follow", "P", func() -> void: sel.set_mode(SelectionController.Mode.PATROL), "")
	var w: World = game.world
	for id in game.selection.units:
		var a := w.agents.get_agent(id)
		if a == null:
			continue
		for ab: String in Config.a("units.%s.abilities" % a.type):
			if not ability_ids.has(ab) and ability_ids.size() < 4:
				ability_ids.append(ab)
	var keys := ["Q", "W", "E", "R"]
	for i in ability_ids.size():
		var ab := ability_ids[i]
		var d := Config.d("units.abilities." + ab)
		var err := ""
		if d.get("requires_tech") != null and not w.tech.has(String(d["requires_tech"])):
			err = "ABIL_ERR_TECH"
		var b := _btn(String(d["name_ru"]), "abl_" + ab, keys[i], func() -> void: press_ability(i), tr("ABIL_" + ab.to_upper() + "_TIP"), err)
		b.set_meta("ability", ab)
	var has_pass := false
	for id in game.selection.units:
		var a := w.agents.get_agent(id)
		if a != null and (not a.passengers.is_empty() or a.hidden):
			has_pass = true
	if has_pass:
		_btn(tr("CMD_UNLOAD"), "st_follow", "U", func() -> void: game.send({"t": "unload", "units": game.selection.units}), "")
	_doctrine_buttons()


func press_ability(i: int) -> void:
	if i < ability_ids.size():
		game.select_ctl.begin_ability(ability_ids[i])


func _doctrine_buttons() -> void:
	var w: World = game.world
	for d: String in w.player_doctrines(game.pid):
		var ab := Config.d("doctrines.%s.ability" % d)
		var b := _btn(String(ab["name_ru"]), "doc_" + d, "", func() -> void: game.select_ctl.begin_doctrine(d), String(ab["effect"]))
		b.set_meta("doctrine", d)


func _building(b: Building) -> void:
	grid.columns = 4
	custom_minimum_size.x = 360
	var w: World = game.world
	var d := b.data()
	if not b.complete():
		_btn(tr("CMD_CANCEL"), "st_hungry", "", func() -> void: game.send({"t": "cancel_build", "building_id": b.id}), tr("CMD_CANCEL_TIP"))
		return
	for u: String in d.get("trains", []):
		var cost := w.mods.unit_cost(u, game.pid)
		var err := w.training.check(b, u, game.pid)
		var tip := _cost_tip(String(Config.g("units.%s.name_ru" % u)), cost, {}) + "\n" + tr("HUD_RECRUITS") + ": %d\n%s" % [int(Config.f("units.%s.recruits" % u)), String(Config.g("units.%s.role" % u))]
		var bt := _btn(String(Config.g("units.%s.name_ru" % u)), "unit_" + u, "", func() -> void: game.send({"t": "train", "building_id": b.id, "unit": u, "count": 1}), tip, err)
		bt.set_meta("train", u)
	if not b.queue.is_empty():
		_btn(tr("CMD_CANCEL_TRAIN"), "st_hungry", "", func() -> void: game.send({"t": "cancel_train", "building_id": b.id}), "")
	if b.worker_slots > 0:
		_btn("−", "civ_adult", "", func() -> void: game.send({"t": "assign_one", "building_id": b.id, "delta": -1}), tr("CMD_WORKER_MINUS"))
		_btn("+", "civ_adult", "", func() -> void: game.send({"t": "assign_one", "building_id": b.id, "delta": 1}), tr("CMD_WORKER_PLUS"))
	if bool(d.get("research", false)):
		_btn(tr("CMD_TECH"), "bld_workshop", "T", func() -> void: game.hud.toggle_tech(b.id), tr("CMD_TECH_TIP"))
	if b.type == "siren":
		_btn(tr("CMD_SIREN"), "bld_siren", "", func() -> void: game.send({"t": "siren", "building_id": b.id}), tr("CMD_SIREN_TIP"))
	if d.get("upgrade_to") != null:
		var to := String(d["upgrade_to"])
		var err := "" if w.tech.has(String(Config.opt("buildings.%s.requires_tech" % to, ""))) else "BUILD_ERR_TECH"
		_btn(tr("CMD_UPGRADE"), "bld_wall", "", func() -> void: _upgrade_all(b), _cost_tip(String(Config.g("buildings.%s.name_ru" % to)), Config.d("buildings.%s.cost" % to), {}), err)
	if b.hp < b.max_hp:
		_btn(tr("CMD_REPAIR"), "st_healing", "", func() -> void: game.send({"t": "repair", "building_id": b.id}), tr("CMD_REPAIR_TIP"))
	if b.power_need > 0.0:
		_btn(tr("CMD_POWER_OFF") if b.enabled else tr("CMD_POWER_ON"), "res_power", "", func() -> void: game.send({"t": "power", "building_id": b.id, "on": not b.enabled}), tr("CMD_POWER_TIP"))
	if b.type != "hq":
		_btn(tr("CMD_DEMOLISH"), "st_hungry", "", func() -> void: game.send({"t": "demolish", "building_id": b.id}), tr("CMD_DEMOLISH_TIP"))


## Улучшить все выделенные стены этого типа рядом (протяжкой их ставят десятками).
func _upgrade_all(b: Building) -> void:
	game.send({"t": "upgrade", "building_id": b.id})


func _poi(p: MapPoi) -> void:
	var w: World = game.world
	if p.type in ["substation", "radio_tower"] and not p.paid and not p.done:
		var cost := Config.d("buildings.map_poi.%s.repair_cost" % p.type)
		_btn(tr("CMD_POI_REPAIR"), "st_healing", "", func() -> void: game.send({"t": "poi_repair", "poi": p.id}),
			_cost_tip(tr("CMD_POI_REPAIR"), cost, {}), "" if w.economy.can_afford(cost) else "BUILD_ERR_COST")


func _cost_tip(name: String, cost: Dictionary, d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in cost:
		parts.append("%d %s" % [int(cost[r]), tr("RES_" + r.to_upper())])
	var s := name + ("\n" + ", ".join(parts) if not parts.is_empty() else "")
	if d.has("power") and float(d["power"]) != 0.0:
		s += "\n%s %+d" % [tr("RES_POWER"), int(d["power"])]
	if d.has("workers"):
		s += "\n%s: %d" % [tr("HUD_WORKERS"), int(d["workers"])]
	if d.has("housing"):
		s += "\n%s: %d" % [tr("HUD_HOUSING"), int(d["housing"])]
	return s


## Кулдауны и доступность без пересборки кнопок.
func _refresh() -> void:
	var w: World = game.world
	for c in grid.get_children():
		var b := c as Button
		if b == null:
			continue
		var cd := b.get_node_or_null("CD") as Label
		if b.has_meta("ability"):
			var left := 999.0
			for id in game.selection.units:
				var a := w.agents.get_agent(id)
				if a != null and Config.a("units.%s.abilities" % a.type).has(b.get_meta("ability")):
					left = minf(left, w.abilities.cooldown_left(a, String(b.get_meta("ability"))))
			cd.text = "%d" % ceili(left) if left > 0.0 and left < 999.0 else ""
			b.modulate = Color(0.6, 0.6, 0.6) if left > 0.0 else Color.WHITE
		elif b.has_meta("doctrine"):
			var left := w.doctrine_cd(game.pid, String(b.get_meta("doctrine")))
			cd.text = "%d" % ceili(left) if left > 0.0 else ""
			b.modulate = Color(0.6, 0.6, 0.6) if left > 0.0 else Color.WHITE
		elif b.has_meta("train") and game.selection.building >= 0:
			var bl := w.buildings.get_building(game.selection.building)
			if bl != null:
				var err := w.training.check(bl, String(b.get_meta("train")), game.pid)
				b.disabled = err != ""
		elif b.has_meta("build"):
			var t := String(b.get_meta("build"))
			var d := Config.d("buildings." + t)
			b.disabled = (d.get("requires_tech") != null and not w.tech.has(String(d["requires_tech"]))) or not w.economy.can_afford(d.get("cost", {}))


func build_hotkey(k: int) -> bool:
	if not build_mode:
		return false
	var ch := OS.get_keycode_string(k)
	var i := BUILD_KEYS.find(ch)
	if i < 0 or i >= grid.get_child_count():
		return false
	var b := grid.get_child(i) as Button
	if b != null and not b.disabled:
		b.pressed.emit()
		return true
	return false
