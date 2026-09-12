extends Node
## Real OpenGL captures for the production-first city workspace.

const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")


func _ready() -> void:
	MotionFeedback.test_reduced_motion = true
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var output_dir := args[1] if args.size() > 1 else "res://docs/captures/city/%d" % width
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await get_tree().process_frame
	var main := preload("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 93611,
		"rust_tech", ["rust_tech"])
	var ui := main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await get_tree().process_frame
	var city := _player_city()
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			Game.grid.terrain[city.cell.x + dx][city.cell.y + dy] = "wasteland"
	Game.grid.terrain[city.cell.x][city.cell.y - 1] = "swamp"
	Game.grid.terrain[city.cell.x + 1][city.cell.y] = "ruins"
	Game.grid.terrain[city.cell.x - 1][city.cell.y] = "rift"
	Game.recompute_city_worked_tiles()
	var states := ["empty", "focus", "queued", "offline", "dos", "secured"]
	var failed := false
	for state in states:
		_prepare(city, state)
		Game.select(city)
		ui.build_city_actions(city)
		await get_tree().process_frame
		if state != "empty":
			var city_tab := ui.get_node("CityActions").find_child(
				"CityTabOverview", true, false) as Button
			city_tab.emit_signal("pressed")
			await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var image := get_tree().root.get_texture().get_image()
		var path := "%s/city-%s.png" % [output_dir, state]
		var error := image.save_png(ProjectSettings.globalize_path(path))
		failed = failed or error != OK
		print("CITY_CAPTURE width=%d state=%s size=%s error=%d path=%s" % [
			width, state, image.get_size(), error, path])
		ui._close_overlay("CityActions")
		await get_tree().process_frame
	get_tree().quit(1 if failed else 0)


func _prepare(city: City, state: String) -> void:
	city.build_queue.clear()
	city.scrap_stock = 0
	city.offline_turns = 0
	city.dos_turns = 0
	city.occupation_until_turn = 0
	match state:
		"focus":
			city.population = 2
		"queued":
			city.build_queue = ["assembly_forge"]
			city.scrap_stock = 11
		"offline":
			city.build_queue = ["assembly_forge"]
			city.scrap_stock = 5
			city.offline_turns = 2
		"dos":
			city.dos_turns = 2
		"secured":
			city.occupation_until_turn = Game.turn + 2


func _player_city() -> City:
	for city in Game.cities:
		if city.faction_id == Game.faction_id:
			return city
	return null
