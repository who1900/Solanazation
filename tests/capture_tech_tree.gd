extends Node
## Real OpenGL captures for strategic tree, card states, and educational info.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var width := int(args[0]) if not args.is_empty() else 720
	var state := args[1] if args.size() > 1 else "tree"
	var output := args[2] if args.size() > 2 else \
		"res://docs/concepts/tech-%s-%d.png" % [state, width]
	DisplayServer.window_set_size(Vector2i(width, 1280))
	await get_tree().process_frame
	var main := preload("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	Game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88440 + width,
		"rust_tech", ["rust_tech", "global_net"])
	Game.resources.sol = 1000
	var ui = main.get_node("UI")
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	ui._toggle_tech_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = ui.get_node("TechPanel/Content").find_child("TechScroll", true, false)
	if state == "cards":
		Game.tech.researched = {
			"steam_synthesis": true, "primitive_coding": true, "hydroponics": true,
			"atomic_reactor": true, "block_encryption": true, "radiation_engineering": true,
			"quantum_computing": true, "smart_contracts": true, "cyber_implants": true,
			"satellite_uplink": true, "global_consensus": true,
		}
		Game.tech.current = "firedancer"
		Game.tech.points = 241
		var tree = scroll.find_child("DependencyTree", true, false)
		tree.refresh()
		scroll.scroll_horizontal = 1052
	elif state == "info":
		ui._show_tech_detail("smart_contracts")
	for _frame in 5:
		await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	print("TECH_TREE_CAPTURE width=%d state=%s size=%s error=%d path=%s" % [
		width, state, image.get_size(), error, output])
	get_tree().quit(0 if error == OK else 1)
