class_name SnapshotCodec
extends RefCounted
## Снапшоты хоста (tech spec §4.3): «быстрый» 10 Гц — время, ресурсы, зомби в зоне интереса, агенты;
## «медленный» 2 Гц — постройки, объекты карты, наука, волна, эффекты способностей.
## Формат — словарь Packed-массивов → var_to_bytes → zstd. Клиент накладывает их на мир-реплику.

var agent_types: PackedStringArray = []
var bld_types: PackedStringArray = []
var techs: PackedStringArray = []
var traits: PackedStringArray = [""]


func _init() -> void:
	for k in Config.keys_of("units"):
		if k != "abilities":
			agent_types.append(k)
	agent_types.append_array(["adult", "child"])
	for k in Config.keys_of("buildings"):
		if k != "map_poi":
			bld_types.append(k)
	techs = Config.keys_of("tech")
	traits.append_array(Config.keys_of("civilians.traits"))


static func pack(d: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(d)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func unpack(b: PackedByteArray) -> Dictionary:
	if b.size() < 4:
		return {}
	var n := b.decode_u32(0)
	var raw := b.slice(4).decompress(n, FileAccess.COMPRESSION_ZSTD)
	var v: Variant = bytes_to_var(raw)
	return v if v is Dictionary else {}


# ------------------------------------------------------------------ быстрый снапшот
func encode_fast(w: World, interest: Vector2, radius: float) -> PackedByteArray:
	var z := w.zombies
	var zi := PackedInt32Array()
	var zp := PackedVector2Array()
	var zv := PackedVector2Array()
	var zt := PackedByteArray()
	var zh := PackedByteArray()
	var r2 := radius * radius
	for i in z.count:
		if z.alive[i] == 0 or z.pos[i].distance_squared_to(interest) > r2:
			continue
		zi.append(i)
		zp.append(z.pos[i])
		zv.append(z.vel[i])
		zt.append(z.type_id[i] | (z.state[i] << 4))
		zh.append(clampi(int(255.0 * z.hp[i] / maxf(1.0, z.t_hp[z.type_id[i]])), 0, 255))
	var e := w.economy
	return pack({"tick": w.tick, "time": w.time, "day": w.clock.day, "phase": w.clock.phase, "pt": w.clock.t,
		"res": [e.res["food"], e.res["wood"], e.res["iron"]], "pw": [e.power_prod, e.power_use, e.battery, e.battery_cap],
		"mor": e.morale, "mm": e.morale_mods, "me": e.event_morale, "anti": e.antidote_charges,
		"zc": z.count, "zk": z.kills_total, "zn": z.alive_n, "zi": zi, "zp": zp, "zv": zv, "zt": zt, "zh": zh,
		"ag": _agents(w), "dcd": w.doctrine_cds})


func _agents(w: World) -> Dictionary:
	var n := w.agents.list.size()
	var ids := PackedInt32Array()
	var f := PackedFloat32Array()   # 11 float на агента
	var b := PackedByteArray()      # 6 байт на агента
	var ints := PackedInt32Array()  # контейнер, лидер, work_b, order_target
	ids.resize(n)
	for k in n:
		var a := w.agents.list[k]
		ids[k] = a.id
		f.append_array([a.pos.x, a.pos.y, a.vel.x, a.vel.y, a.facing, a.hp, a.max_hp, a.fuel, a.temp_life, a.infect_t, a.camo_t])
		var flags := (1 if a.hidden else 0) | (2 if a.moving else 0) | (4 if a.infected and a.infect_detected else 0) \
			| (8 if a.rescued else 0) | (16 if a.revealed else 0) | (32 if a.is_child else 0) | (64 if a.infected else 0)
		b.append_array([a.kind, agent_types.find(a.type), a.owner + 1, flags, a.civ, maxi(0, traits.find(a.trait_id))])
		ints.append_array([a.container, a.leader, a.work_b, a.passengers.size()])
	return {"id": ids, "f": f, "b": b, "i": ints}


func apply_fast(w: World, d: Dictionary) -> void:
	if d.is_empty():
		return
	w.tick = int(d["tick"])
	w.time = float(d["time"])
	_clock(w, int(d["day"]), int(d["phase"]), float(d["pt"]))
	var e := w.economy
	var res: Array = d["res"]
	e.res["food"] = res[0]
	e.res["wood"] = res[1]
	e.res["iron"] = res[2]
	var pw: Array = d["pw"]
	e.power_prod = pw[0]
	e.power_use = pw[1]
	e.battery = pw[2]
	e.battery_cap = pw[3]
	e.morale = float(d["mor"])
	e.morale_mods = d["mm"]
	e.event_morale = d["me"]
	e.antidote_charges = int(d["anti"])
	w.doctrine_cds = d["dcd"]
	_zombies(w, d)
	_apply_agents(w, d["ag"])


func _clock(w: World, day: int, phase: int, t: float) -> void:
	var c := w.clock
	var changed := c.phase != phase or c.day != day
	c.day = day
	c.phase = phase
	c.t = t
	if changed:
		w._update_lights()


func _zombies(w: World, d: Dictionary) -> void:
	var z := w.zombies
	var cnt := int(d["zc"])
	if z.pos.size() < cnt:
		z._grow(cnt + 64)
	var was := z.alive.duplicate()
	z.count = maxi(z.count, cnt)
	z.alive.fill(0)
	var zi: PackedInt32Array = d["zi"]
	var zp: PackedVector2Array = d["zp"]
	var zv: PackedVector2Array = d["zv"]
	var zt: PackedByteArray = d["zt"]
	var zh: PackedByteArray = d["zh"]
	for k in zi.size():
		var i := zi[k]
		z.prev[i] = z.pos[i] if was[i] != 0 else zp[k]
		z.pos[i] = zp[k]
		z.vel[i] = zv[k]
		z.type_id[i] = zt[k] & 15
		z.state[i] = zt[k] >> 4
		z.hp[i] = float(zh[k]) / 255.0 * z.t_hp[z.type_id[i]]
		z.alive[i] = 1
	z.alive_n = int(d["zn"])
	z.kills_total = int(d["zk"])
	z.rebuild_hash()


func _apply_agents(w: World, ag: Dictionary) -> void:
	var ids: PackedInt32Array = ag["id"]
	var f: PackedFloat32Array = ag["f"]
	var b: PackedByteArray = ag["b"]
	var ints: PackedInt32Array = ag["i"]
	var seen := {}
	for k in ids.size():
		var id := ids[k]
		seen[id] = true
		var a: Agent = w.agents.by_id.get(id)
		if a == null:
			a = Agent.new()
			a.id = id
			w.agents.list.append(a)
			w.agents.by_id[id] = a
		var o := k * 11
		a.pos = Vector2(f[o], f[o + 1])
		a.vel = Vector2(f[o + 2], f[o + 3])
		a.facing = f[o + 4]
		a.hp = f[o + 5]
		a.max_hp = f[o + 6]
		a.fuel = f[o + 7]
		a.temp_life = f[o + 8]
		a.infect_t = f[o + 9]
		a.camo_t = f[o + 10]
		var p := k * 6
		a.kind = b[p]
		a.type = agent_types[b[p + 1]]
		a.owner = int(b[p + 2]) - 1
		var fl := b[p + 3]
		a.hidden = (fl & 1) != 0
		a.moving = (fl & 2) != 0
		a.infected = (fl & 64) != 0
		a.infect_detected = (fl & 4) != 0
		a.rescued = (fl & 8) != 0
		a.revealed = (fl & 16) != 0
		a.is_child = (fl & 32) != 0
		a.civ = b[p + 4]
		a.trait_id = traits[b[p + 5]]
		var q := k * 4
		a.container = ints[q]
		a.leader = ints[q + 1]
		a.work_b = ints[q + 2]
		a.passengers.resize(ints[q + 3])
		a.radius = Config.f("rules.sim_tuning.unit_radius.%s" % ("civilian" if a.kind == Agent.Kind.CIVILIAN else String(Config.g("units.%s.category" % a.type))))
	for a in w.agents.list.duplicate():
		if not seen.has(a.id):
			w.agents.by_id.erase(a.id)
			w.agents.list.erase(a)
	w.agents.rebuild_hash()


# ------------------------------------------------------------------ медленный снапшот
func encode_slow(w: World) -> PackedByteArray:
	var blds: Array = []
	for b in w.buildings.list:
		var q: Array = []
		for item: Dictionary in b.queue:
			q.append([agent_types.find(String(item["unit"])), item["t"], item["total"]])
		blds.append([b.id, bld_types.find(b.type), b.rot, b.cells.position.x, b.cells.position.y, b.owner, b.hp, b.max_hp,
			b.state, b.progress, int(b.powered) | int(b.enabled) << 1 | int(b.repairing) << 2, b.power_need,
			bld_types.find(b.upgrading_to), b.upgrade_progress, PackedInt32Array(b.workers), q,
			[techs.find(String(b.research.get("tech", ""))), b.research.get("t", 0.0), b.research.get("total", 0.0)],
			b.garrison.size(), b.patients.size(), b.ability_cd, b.rally, PackedInt32Array(b.builders)])
	var pois: Array = []
	for p in w.map.pois:
		pois.append([p.alive, p.done, p.paid, p.progress, p.hp])
	var ab := w.abilities
	var dead := PackedInt32Array()
	for i in w.map.node_alive.size():
		if w.map.node_alive[i] == 0:
			dead.append(i)
	return pack({"b": blds, "p": pois, "tech": w.tech.done, "wd": w.waves.directions, "wc": w.waves.composition,
		"sm": ab.smokes, "fi": ab.fires, "lu": ab.lures, "rv": ab.reveals, "dead": dead, "fort": w.fortress_captured,
		"score": w.score, "out": w.outbreaks})


func apply_slow(w: World, d: Dictionary) -> void:
	if d.is_empty():
		return
	var seen := {}
	for row: Array in d["b"]:
		seen[int(row[0])] = true
		_building(w, row)
	for b in w.buildings.list.duplicate():
		if not seen.has(b.id):
			w.grid.clear_rect(b.cells, b.id)
			w.buildings.list.erase(b)
			w.buildings.by_id.erase(b.id)
	var pois: Array = d["p"]
	for k in mini(pois.size(), w.map.pois.size()):
		var p := w.map.pois[k]
		var r: Array = pois[k]
		p.alive = r[0]
		p.done = r[1]
		p.paid = r[2]
		p.progress = r[3]
		p.hp = r[4]
	w.tech.done = d["tech"]
	w.waves.directions = d["wd"]
	w.waves.composition = d["wc"]
	var ab := w.abilities
	ab.smokes.assign(d["sm"])
	ab.fires.assign(d["fi"])
	ab.lures.assign(d["lu"])
	ab.reveals.assign(d["rv"])
	var dead: PackedInt32Array = d["dead"]
	for i in dead:
		if i < w.map.node_alive.size() and w.map.node_alive[i] != 0:
			w.map.node_alive[i] = 0
			w.map.nodes_dirty = true
	w.fortress_captured = d["fort"]
	w.score = d["score"]
	w.outbreaks = int(d["out"])
	w.economy.mark_dirty()


func _building(w: World, row: Array) -> void:
	var id := int(row[0])
	var b: Building = w.buildings.by_id.get(id)
	var type := bld_types[int(row[1])]
	if b == null:
		b = Building.new()
		b.id = id
		b.type = type
		b.rot = int(row[2])
		b.cells = w.buildings.rect_for(type, Vector2i(int(row[3]), int(row[4])), b.rot)
		var g := w.grid
		b.rect_m = Rect2(g.origin + Vector2(b.cells.position) * g.cell, Vector2(b.cells.size) * g.cell)
		b.pos = b.rect_m.get_center()
		b.door = g.nearest_walkable(b.pos + Vector2(0, b.rect_m.size.y * 0.5 + 2.0), 30.0)
		b.worker_slots = int(b.data().get("workers", 0))
		w.buildings.list.append(b)
		w.buildings.by_id[id] = b
		if type == "hq":
			w.buildings.hq = b
	b.type = type
	b.owner = int(row[5])
	b.hp = row[6]
	b.max_hp = row[7]
	var st := int(row[8])
	if st != b.state or not b.has_meta("placed"):
		b.set_meta("placed", true)
		w.grid.set_rect(b.cells, b.id, w.buildings._block_kind(type) if st == Building.State.COMPLETE else Grid.BLOCK_NONE)
	b.state = st
	b.progress = row[9]
	var fl := int(row[10])
	b.powered = (fl & 1) != 0
	b.enabled = (fl & 2) != 0
	b.repairing = (fl & 4) != 0
	b.power_need = row[11]
	b.upgrading_to = bld_types[int(row[12])] if int(row[12]) >= 0 else ""
	b.upgrade_progress = row[13]
	b.workers.assign(Array(row[14]))
	b.queue.clear()
	for q: Array in row[15]:
		b.queue.append({"unit": agent_types[int(q[0])], "t": q[1], "total": q[2]})
	var r: Array = row[16]
	b.research = {} if int(r[0]) < 0 else {"tech": techs[int(r[0])], "t": r[1], "total": r[2]}
	b.garrison.resize(int(row[17]))
	b.patients.resize(int(row[18]))
	b.ability_cd = row[19]
	b.rally = row[20]
	b.builders.assign(Array(row[21]))
