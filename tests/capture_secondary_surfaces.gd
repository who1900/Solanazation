extends Node
## Deterministic real-GL capture matrix for the seven secondary surfaces.

const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")


func _ready() -> void:
	MotionFeedback.test_reduced_motion = true
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var output_dir := args[1] if args.size() > 1 else "res://docs/captures/secondary/%d" % width
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await get_tree().process_frame
	var main := preload("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94521,
		"rust_tech", ["rust_tech", "global_net", "dao"])
	Game.resources.sol = 1000
	Game.resources.scrap = 1000
	Game.tech.researched["primitive_coding"] = true
	var ui := main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await get_tree().process_frame
	var failed := false
	for surface in ["unit", "diplomacy", "glossary", "network", "protocols", "wonders", "game-over"]:
		_close_surfaces(ui)
		await _open_surface(ui, surface)
		for _frame in 3:
			await get_tree().process_frame
		var image := get_tree().root.get_texture().get_image()
		var path := "%s/%s.png" % [output_dir, surface]
		var error := image.save_png(ProjectSettings.globalize_path(path))
		failed = failed or error != OK
		print("SECONDARY_CAPTURE width=%d surface=%s size=%s error=%d path=%s" % [
			width, surface, image.get_size(), error, path])
	get_tree().quit(1 if failed else 0)


func _open_surface(ui: Node, surface: String) -> void:
	match surface:
		"unit":
			Game.select(_player_unit())
		"diplomacy":
			Game.set_relation_ping(0, 1, 68)
			ui._toggle_diplomacy_panel()
		"glossary":
			ui._show_glossary()
		"network":
			ui._show_network_status()
		"protocols", "wonders":
			ui._toggle_tech_panel()
			await get_tree().process_frame
			var label := surface.to_upper()
			for node in ui.get_node("TechPanel").find_children("*", "Button", true, false):
				if (node as Button).text == label:
					(node as Button).emit_signal("pressed")
					break
		"game-over":
			ui.show_game_over(Game.factions[0].name, "all validators controlled")


func _close_surfaces(ui: Node) -> void:
	for panel_name in ["DipPanel", "GlossaryPanel", "NetworkStatusPanel", "TechPanel", "GameOverPanel"]:
		var panel := ui.get_node_or_null(panel_name)
		if panel != null:
			panel.free()
	Game.select(null)


func _player_unit() -> Unit:
	for unit in Game.units:
		if unit.faction_id == Game.faction_id:
			return unit
	return null
