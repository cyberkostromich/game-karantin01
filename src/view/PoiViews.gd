class_name PoiViews
extends Node3D
## Объекты карты: гнёзда у станций метро (пульсируют), павильоны метро, значки лута/целей над зданиями.
## Значки видны, только когда место открыто туманом (не раскрываем карту даром).

const LOOT_ICON := {"grocery": "res_food", "pharmacy": "abl_antidote", "car_service": "res_iron",
	"hardware": "res_wood", "substation": "res_power", "radio_tower": "st_wave", "fortress": "bld_tower"}

var world: World
var nests: Dictionary = {}    # poi id → Node3D
var markers: Dictionary = {}  # poi id → Sprite3D
var t: float = 0.0


func setup(w: World) -> void:
	world = w
	for p in w.map.pois:
		if p.type == "nest":
			var root := Node3D.new()
			root.position = Vector3(p.pos.x, 0, p.pos.y)
			var ent := Look.instance("models/city/city_metro_entrance.glb")
			ent.position = Vector3(p.anchor.x - p.pos.x, 0, p.anchor.y - p.pos.y)
			root.add_child(ent)
			var nest := Look.instance(String(Config.g("zombies.nest.model")))
			nest.name = "Nest"
			root.add_child(nest)
			add_child(root)
			nests[p.id] = root
		elif LOOT_ICON.has(p.type):
			var s := Sprite3D.new()
			s.texture = Look.icon(LOOT_ICON[p.type], 128)
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.pixel_size = 0.04 if p.type in ["substation", "radio_tower", "fortress"] else 0.025
			s.no_depth_test = true
			s.render_priority = 9
			s.position = Vector3(p.pos.x, 9.0 if s.pixel_size > 0.03 else 6.0, p.pos.y)
			s.visible = false
			add_child(s)
			markers[p.id] = s


func render(delta: float) -> void:
	t += delta
	for id: int in nests:
		var p := world.map.pois[id]
		var n: Node3D = nests[id]
		var nest := n.get_node("Nest") as Node3D
		nest.visible = p.alive
		var pulse := Look.find(nest, "pulse")
		if pulse != null and p.alive:
			var s := 1.0 + 0.08 * sin(t * (5.0 if world.clock.is_night() else 2.0))
			pulse.scale = Vector3(s, s, s)
	for id: int in markers:
		var p := world.map.pois[id]
		var m: Sprite3D = markers[id]
		m.visible = not p.done and world.fog.explored(p.pos)
		if m.visible and p.progress > 0.0:
			m.modulate = Color(1, 1, 1, 0.5 + 0.5 * absf(sin(t * 4.0)))
