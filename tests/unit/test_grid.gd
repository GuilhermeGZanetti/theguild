extends GutTest
## Line of sight and cover on hand-built grids.


func _grid() -> BattleGrid:
	return BattleGrid.new(12, 12)


func _prop(g: BattleGrid, p: Vector2i, id: String) -> void:
	var d: Array = MapGen.PROPS[id]
	var tl := g.t(p)
	tl["prop"] = id
	tl["cover"] = d[0]
	tl["solid"] = d[1]
	tl["block"] = d[2]


func test_full_cover_between_two_units_blocks_sight():
	var g := _grid()
	_prop(g, Vector2i(5, 5), "rock_l")
	assert_false(g.los(Vector2i(1, 5), Vector2i(9, 5)))
	assert_false(g.los(Vector2i(9, 5), Vector2i(1, 5)), "both ways")


func test_cover_next_to_either_end_is_peeked_around():
	var g := _grid()
	_prop(g, Vector2i(8, 5), "rock_l")
	_prop(g, Vector2i(2, 5), "boulder")
	assert_true(g.los(Vector2i(1, 5), Vector2i(9, 5)))


func test_full_cover_below_the_viewer_does_not_block():
	var g := _grid()
	_prop(g, Vector2i(5, 5), "tree")
	g.t(Vector2i(1, 5))["h"] = 1
	assert_true(g.los(Vector2i(1, 5), Vector2i(9, 5)), "a level up, you see over the tree")
	assert_true(g.los(Vector2i(9, 5), Vector2i(1, 5)), "and are seen over it")
	g.t(Vector2i(5, 5))["h"] = 1
	assert_false(g.los(Vector2i(1, 5), Vector2i(9, 5)), "a tree on your own level still hides")


func test_buildings_need_real_height_to_see_over():
	var g := _grid()
	_prop(g, Vector2i(5, 5), "house_part")
	g.t(Vector2i(1, 5))["h"] = 1
	assert_false(g.los(Vector2i(1, 5), Vector2i(9, 5)))
	g.t(Vector2i(1, 5))["h"] = 4
	assert_true(g.los(Vector2i(1, 5), Vector2i(9, 5)))


func test_grazing_a_corner_does_not_block():
	var g := _grid()
	# the line from (0,0) to (8,4) runs along the edge of (3,2)
	_prop(g, Vector2i(3, 2), "rock_l")
	assert_true(g.los(Vector2i(0, 0), Vector2i(8, 4)))
	assert_true(g.los(Vector2i(8, 4), Vector2i(0, 0)))
	# a wall across the whole line does
	_prop(g, Vector2i(3, 1), "rock_l")
	assert_false(g.los(Vector2i(0, 0), Vector2i(8, 4)))


func test_ridges_still_block_sight():
	var g := _grid()
	for y in 12:
		g.t(Vector2i(5, y))["h"] = 3
	assert_false(g.los(Vector2i(1, 5), Vector2i(9, 5)))


func test_sight_is_the_same_both_ways_on_real_maps():
	for region in ["carrow", "coast", "ember", "dunes", "stilts"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(region)
		var g: BattleGrid = MapGen.new().generate({"region": region, "objective": "defense", "seed": 77}, rng, 4)["grid"]
		for k in 400:
			var a := Vector2i(rng.randi() % g.w, rng.randi() % g.h)
			var b := Vector2i(rng.randi() % g.w, rng.randi() % g.h)
			assert_eq(g.los(a, b), g.los(b, a), "%s %s-%s" % [region, str(a), str(b)])


func test_palms_are_full_cover():
	var d: Array = MapGen.PROPS["palm"]
	assert_eq(int(d[0]), 2)
	assert_true(d[1] and d[2], "solid and tall enough to hide behind")
