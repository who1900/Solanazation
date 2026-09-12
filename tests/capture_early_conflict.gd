extends Node
## Manual acceptance capture. Run without --headless so the image comes from
## the Windows OpenGL Compatibility renderer.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var output := args[1] if args.size() > 1 else "res://docs/concepts/early-conflict-%d.png" % width
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await get_tree().process_frame
	var main := preload("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 8252026, "rust_tech")
	var ui := main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await get_tree().process_frame
	_prepare_encounter()
	var camera := main.get_node("Camera") as Camera2D
	var center: Vector2i = _player_capital().cell
	camera.zoom = Vector2.ONE * (3.0 if width <= 575 else 3.35)
	camera.position = Game.cell_to_pixel(center) + Vector2(0, 36)
	camera.enabled = true
	UnitsView.sync()
	main.get_node("MapView")._redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	print("EARLY_CONFLICT_CAPTURE width=%d size=%s error=%d path=%s" % [width, image.get_size(), error, output])
	get_tree().quit(0 if error == OK else 1)


func _prepare_encounter() -> void:
	var capital := _player_capital()
	var center: Vector2i = capital.cell
	for x in range(maxi(0, center.x - 7), mini(Game.grid.w, center.x + 8)):
		for y in range(maxi(0, center.y - 5), mini(Game.grid.h, center.y + 6)):
			Game.grid.terrain[x][y] = "wasteland"
			Game.grid.infra[x][y] = 0
	capital.build_queue.clear()
	capital.dos_turns = 0
	capital.offline_turns = 0

	var construction := Game._found_city_at(center + Vector2i(-4, 1), Game.faction_id)
	construction.build_queue = ["assembly_forge"]
	construction.scrap_stock = 9
	var powered := Game._found_city_at(center + Vector2i(0, 3), Game.faction_id)
	powered.buildings["steam_turbine"] = true

	var rival: City = null
	for city in Game.cities:
		if city.faction_id != Game.faction_id:
			rival = city
			break
	if rival != null:
		rival.cell = center + Vector2i(4, 2)
		rival.dos_turns = 3
		rival.offline_turns = 0

	Game.units.clear()
	Game._spawn_unit("founder", center + Vector2i(-4, -2), Game.faction_id)
	Game._spawn_unit("rust_guard", center + Vector2i(-2, -2), Game.faction_id)
	Game._spawn_unit("miner_quad", center + Vector2i(-1, -2), Game.faction_id)
	Game._spawn_unit("miner_quad", center + Vector2i(1, -2), 1)
	Game._spawn_unit("virus_pickup", center + Vector2i(3, -2), Game.BARB_FACTION)
	Game._spawn_unit("raider_walker", center + Vector2i(-4, 0), Game.faction_id)
	Game._spawn_unit("heavy_mech", center + Vector2i(-2, 0), 1)
	Game._spawn_unit("net_broker", center + Vector2i(2, 0), Game.faction_id)
	Game._spawn_unit("auto_mech", center + Vector2i(4, 0), Game.BARB_FACTION)
	Game._spawn_unit("steam_cruiser", center + Vector2i(2, 2), Game.faction_id)
	Game.lairs.clear()
	Game.lairs.append(center + Vector2i(0, -3))
	Game.terminals.clear()
	Game.update_visibility()
	for x in range(center.x - 5, center.x + 6):
		for y in range(center.y - 5, center.y + 5):
			if Game.grid.in_bounds(x, y):
				Game.explored[Vector2i(x, y)] = true
				Game.visible[Vector2i(x, y)] = true
	Game.select(Game.units[2])


func _player_capital() -> City:
	for city in Game.cities:
		if city.faction_id == Game.faction_id and city.is_capital:
			return city
	return Game.cities[0]
