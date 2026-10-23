extends GutTest
## M1-4: поле ведёт к цели в обход стены мира; закрытая нашей стеной цель — через стену (ломать).


func _field(g: Grid, target: Vector2) -> FlowField:
	var f := FlowField.new()
	f.setup(g, target, 60.0, 8.0)
	f.compute_now()
	return f


func test_detour_around_world_wall() -> void:
	var g := TestHelpers.grid(80)
	# стена мира (дом) от x=-20 до x=20 на z=10, цель в (0,0), старт в (0,30)
	for x in range(-10, 11):
		g.terrain[g.idx_of(Vector2(x * 2, 10))] = 0
	var f := _field(g, Vector2.ZERO)
	var p := Vector2(0, 30)
	for k in 600:
		var d := f.dir_at(p)
		if d == Vector2.ZERO:
			break
		# шаг как у ZombieSystem.step: в непроходимую клетку не входим, скользим
		var np := p + d * 0.5
		if g.zombie_walkable(np):
			p = np
		elif g.zombie_walkable(Vector2(np.x, p.y)):
			p.x = np.x
		elif g.zombie_walkable(Vector2(p.x, np.y)):
			p.y = np.y
		assert_true(g.zombie_walkable(p), "путь не проходит сквозь стену мира: %s" % p)
	assert_lt(p.length(), 3.0, "дошли до цели: %s" % p)


func test_closed_base_leads_to_our_wall() -> void:
	var g := TestHelpers.grid(80)
	for x in range(-8, 9):
		for y in range(-8, 9):
			if absi(x) == 8 or absi(y) == 8:
				var i := g.idx_of(Vector2(x * 2, y * 2))
				g.occ[i] = 99
				g.block[i] = Grid.BLOCK_ALL
	var f := _field(g, Vector2.ZERO)
	var d := f.dir_at(Vector2(0, 40))
	assert_ne(d, Vector2.ZERO, "при закрытой базе поле всё равно ведёт к стене")
	assert_gt(f.distance_at(Vector2(0, 40)), 0.0)
