extends SceneTree
## Real OpenGL captures for the next-required-decision turn flow.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var output_dir := str(args[1]) if args.size() > 1 else \
		"res://docs/captures/turn-guidance/%d" % width
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
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 83120 + width, "rust_tech")
	var ui: Node = main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await process_frame
	var first: Unit = game.next_required_action().target
	game.select(first)
	var camera := main.get_node("Camera") as Camera2D
	camera.position = game.cell_to_pixel(first.cell)
	camera.zoom = Vector2.ONE * (3.0 if width <= 575 else 3.35)
	main.get_node("UnitsView")._sync()
	await _save(viewport, "%s/orders.png" % output_dir)

	for unit in game.units:
		if game.unit_requires_orders(unit):
			game.complete_unit_orders(unit)
	game.tech.current = "steam_synthesis"
	for city in game.cities:
		if city.faction_id == game.faction_id:
			city.add_to_queue("steam_turbine")
	ui._refresh_next_action()
	game.select(null)
	main.get_node("UnitsView")._sync()
	await _save(viewport, "%s/ready.png" % output_dir)
	quit(0)


func _save(viewport: SubViewport, path: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	print("TURN_GUIDANCE_CAPTURE %dx%d error=%d path=%s" % [
		image.get_width(), image.get_height(), error, path])
