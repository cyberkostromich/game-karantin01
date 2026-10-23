extends GutTest
## M0-7: пути вокруг препятствий, недостижимая цель — ближайшая точка.


func test_path_around_block() -> void:
	var g := TestHelpers.grid(80)
	for y in range(10, 70):
		g.terrain[y * g.w + 40] = 0
		g.terrain[y * g.w + 41] = 0
	var p := Pathfinder.new()
	p.setup(g, 2, 12)
	var path := p.find_path(Vector2(-30, 0), Vector2(30, 0))
	assert_false(path.is_empty())
	var cur := Vector2(-30, 0)
	for q in path:
		assert_true(g.line_walkable(cur, q), "отрезок пути проходим")
		cur = q
	assert_almost_eq(cur.x, 30.0, 4.0)
