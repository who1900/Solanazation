extends SceneTree
## Earth map diagnostics.

func _init() -> void:
	await process_frame
	var g = root.get_node_or_null("Game")
	if g == null:
		g = load("res://scripts/GameRoot.gd").new()
		root.add_child(g)
	await process_frame
	g.start_game(Data.MapSize.LARGE, Data.MapType.EARTH, 983)
	await process_frame
	print("units: %d, cities: %d" % [g.units.size(), g.cities.size()])
	for i in g.cities.size():
		var c: City = g.cities[i]
		print("  city %d: faction=%d cell=%s" % [i, c.faction_id, c.cell])
	var spawns: Array = g.grid.find_spawn_points(2)
	print("spawns: %s" % str(spawns))
	quit(0)
