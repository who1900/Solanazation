extends Node
## Real OpenGL acceptance capture for the compact SECURED city state.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var output := args[1] if args.size() > 1 else \
		"res://docs/concepts/strategic-arc-%d.png" % width
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await get_tree().process_frame
	var main := preload("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 99280,
		"rust_tech", ["rust_tech", "global_net", "steel"])
	var ui := main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await get_tree().process_frame
	_prepare_state()
	var capital: City = _city_of(0)
	var camera := main.get_node("Camera") as Camera2D
	camera.zoom = Vector2.ONE * (3.0 if width <= 575 else 3.35)
	camera.position = Game.cell_to_pixel(capital.cell) + Vector2(0, 34)
	camera.enabled = true
	Game.select(capital)
	UnitsView.sync()
	main.get_node("MapView")._redraw()
	for _frame in 4:
		await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	print("STRATEGIC_ARC_CAPTURE width=%d size=%s error=%d path=%s" % [
		width, image.get_size(), error, output])
	get_tree().quit(0 if error == OK else 1)


func _prepare_state() -> void:
	var capital: City = _city_of(0)
	var rival: City = _city_of(1)
	var center := capital.cell
	for x in range(maxi(0, center.x - 6), mini(Game.grid.w, center.x + 7)):
		for y in range(maxi(0, center.y - 5), mini(Game.grid.h, center.y + 6)):
			Game.grid.terrain[x][y] = "wasteland"
			Game.explored[Vector2i(x, y)] = true
			Game.visible[Vector2i(x, y)] = true
	capital.occupation_until_turn = Game.turn + 2
	capital.build_queue = ["assembly_forge"]
	capital.scrap_stock = 7
	if rival != null:
		Game.grid.clear_occupant(rival.cell.x, rival.cell.y, rival)
		rival.cell = center + Vector2i(4, 1)
		Game.grid.place_occupant(rival.cell.x, rival.cell.y, rival)
		rival.occupation_until_turn = Game.turn + 2
		rival.dos_turns = 2
	Game.update_visibility()
	for x in range(maxi(0, center.x - 6), mini(Game.grid.w, center.x + 7)):
		for y in range(maxi(0, center.y - 5), mini(Game.grid.h, center.y + 6)):
			Game.explored[Vector2i(x, y)] = true
			Game.visible[Vector2i(x, y)] = true


func _city_of(owner: int) -> City:
	for city in Game.cities:
		if city.faction_id == owner:
			return city
	return null
