extends SceneTree
## Real OpenGL before/after capture for permanent explored terrain memory.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var mode := str(args[1]) if args.size() > 1 else "memory"
	var output := str(args[2]) if args.size() > 2 else \
		"res://docs/captures/exploration/exploration-%s-%d.png" % [mode, width]
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await process_frame
	var game := root.get_node("Game")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var main = load("res://scenes/Main.tscn").instantiate()
	viewport.add_child(main)
	await process_frame
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 290825, "rust_tech")
	game.units.clear()
	game.cities.clear()
	game.grid.clear_occupants()
	game.explored.clear()
	game.visible.clear()
	var left := _passable_near(game, Vector2i(12, game.grid.h / 2))
	var right := _passable_at_distance(game, left, 16)
	var scout: Variant = game._spawn_unit("miner_quad", left, game.faction_id)
	game.update_visibility()
	if mode == "memory":
		game.grid.clear_occupant(scout.cell.x, scout.cell.y, scout)
		scout.cell = right
		game.grid.place_occupant(right.x, right.y, scout)
		game.update_visibility()
	var ui: Node = main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	# Let the match-ready start framing finish before fixing the comparison frame.
	await process_frame
	await process_frame
	var camera := main.get_node("Camera") as Camera2D
	camera.zoom = Vector2.ONE * 1.15
	camera.position = Vector2(left + right) * 8.0
	camera.enabled = true
	main.get_node("UnitsView")._sync()
	var map: Node = main.get_node("MapView")
	map._redraw()
	var water: Node = map.get_node("WaterSurface")
	water.phase_step = 19
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	print("EXPLORATION_CAPTURE width=%d mode=%s explored=%d visible=%d water=%d error=%d path=%s" % [
		width, mode, game.explored.size(), game.visible.size(),
		water.last_drawn_water_cells, error, output])
	quit(0 if error == OK else 1)


func _passable_near(game: Node, origin: Vector2i) -> Vector2i:
	for radius in range(0, 16):
		for x in range(origin.x - radius, origin.x + radius + 1):
			for y in range(origin.y - radius, origin.y + radius + 1):
				if game.grid.in_bounds(x, y) and game.grid.is_passable(x, y):
					return Vector2i(x, y)
	return Vector2i.ZERO


func _passable_at_distance(game: Node, origin: Vector2i, minimum: int) -> Vector2i:
	for distance in range(minimum, minimum + 10):
		for x in game.grid.w:
			for y in game.grid.h:
				if absi(x - origin.x) + absi(y - origin.y) == distance \
						and game.grid.is_passable(x, y):
					return Vector2i(x, y)
	return origin
