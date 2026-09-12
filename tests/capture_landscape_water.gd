extends Node
## Real OpenGL acceptance capture for terrain, coasts, and animated water.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var zoom := float(args[1]) if args.size() > 1 else 2.0
	var output := args[2] if args.size() > 2 else \
		"res://docs/captures/landscape/landscape-%d-%.1f.png" % [width, zoom]
	var water_phase := int(args[3]) if args.size() > 3 else 7
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await get_tree().process_frame
	var main := preload("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 882501, "rust_tech")
	_prepare_landscape()
	# Let the match-ready camera framing finish before applying the acceptance zoom.
	await get_tree().process_frame
	var ui := main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	var camera := main.get_node("Camera") as Camera2D
	camera.zoom = Vector2.ONE * zoom
	camera.position = Vector2(Game.grid.w, Game.grid.h) * 8.0
	camera.enabled = true
	UnitsView.sync()
	var map := main.get_node("MapView")
	map._redraw()
	var water := map.get_node("WaterSurface") as WaterSurfaceView
	water.set_process(false)
	var effective_phase := 0 if zoom < WaterSurfaceView.ANIMATED_MIN_ZOOM else water_phase
	water.phase_step = effective_phase
	water.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	print("LANDSCAPE_CAPTURE width=%d zoom=%.2f phase=%d water_cells=%d draw_usec=%d error=%d path=%s" % [
		width, zoom, effective_phase, water.last_drawn_water_cells, water.last_draw_usec, error, output])
	get_tree().quit(0 if error == OK else 1)


func _prepare_landscape() -> void:
	Game.units.clear()
	Game.cities.clear()
	Game.terminals.clear()
	Game.lairs.clear()
	Game.explored.clear()
	Game.visible.clear()
	var center := Vector2(Game.grid.w, Game.grid.h) * 0.5
	for x in Game.grid.w:
		for y in Game.grid.h:
			var cell := Vector2i(x, y)
			var normalized := (Vector2(x, y) - center) / Vector2(18.0, 13.0)
			var coast_noise := sin(float(x) * 0.57) * 0.09 + cos(float(y) * 0.73) * 0.07
			if normalized.length() > 1.0 + coast_noise:
				Game.grid.terrain[x][y] = "ocean"
			elif y > int(center.y) + 3 and x < int(center.x) - 2:
				Game.grid.terrain[x][y] = "swamp"
			elif x > int(center.x) + 5 and y < int(center.y) + 4:
				Game.grid.terrain[x][y] = "node_zone"
			elif posmod(x * 3 + y * 5, 13) < 3:
				Game.grid.terrain[x][y] = "ruins"
			else:
				Game.grid.terrain[x][y] = "wasteland"
			Game.grid.infra[x][y] = 0
			Game.grid.improvements[x][y] = ""
			Game.explored[cell] = true
			Game.visible[cell] = true
	var focus := Vector2i(Game.grid.w / 2, Game.grid.h / 2)
	var city := Game._found_city_at(focus + Vector2i(-2, 2), Game.faction_id)
	city.build_queue = ["assembly_forge"]
	var guard := Game._spawn_unit("rust_guard", focus + Vector2i(-1, -1), Game.faction_id)
	Game._spawn_unit("virus_pickup", focus + Vector2i(0, -1), Game.BARB_FACTION)
	Game._spawn_unit("founder", focus + Vector2i(-3, 0), Game.faction_id)
	Game._spawn_unit("steam_cruiser", _nearest_ocean(focus), Game.faction_id)
	Game.select(guard)


func _nearest_ocean(origin: Vector2i) -> Vector2i:
	for radius in range(1, 20):
		for x in range(origin.x - radius, origin.x + radius + 1):
			for y in [origin.y - radius, origin.y + radius]:
				if Game.grid.in_bounds(x, y) and Game.grid.terrain[x][y] == "ocean":
					return Vector2i(x, y)
		for y in range(origin.y - radius + 1, origin.y + radius):
			for x in [origin.x - radius, origin.x + radius]:
				if Game.grid.in_bounds(x, y) and Game.grid.terrain[x][y] == "ocean":
					return Vector2i(x, y)
	return Vector2i.ZERO
