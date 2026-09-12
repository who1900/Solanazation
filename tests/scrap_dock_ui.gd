extends SceneTree
## Regression: faction replacement building IDs remain readable in city UI refreshes.

var failures := 0


func _init() -> void:
	await process_frame
	var game := root.get_node("Game")
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94721, "rust_tech")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(575, 1280)
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var ui = load("res://scripts/ui/GameUI.gd").new()
	ui.name = "UI"
	scene.add_child(ui)
	await process_frame
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await process_frame

	var city: City = null
	for candidate in game.cities:
		if candidate.faction_id == game.faction_id:
			city = candidate
			break
	_check(city != null, "Rust-Tech city exists")
	if city != null:
		var dock_data: Dictionary = city.building_data("scrap_dock")
		_check(str(dock_data.name) == "Scrap Dock" and int(dock_data.scrap_gen) == 2,
			"Scrap Dock resolves faction building data")
		city.buildings["scrap_dock"] = true
		ui._update_selection(city)
		await process_frame
		_check(ui._selection_full_text.contains("Scrap Dock"),
			"selected-city refresh labels the built Scrap Dock")

		city.buildings.erase("scrap_dock")
		city.build_queue.clear()
		city.scrap_stock = 0
		city.add_to_queue("assembly_forge")
		var resources := {"scrap": 1, "sol": 0}
		city.process_build(resources)
		_check(not city.build_queue.is_empty() and city.build_queue[0] == "scrap_dock",
			"Rust-Tech production converts Assembly Forge to Scrap Dock")
		ui._update_selection(city)
		await process_frame
		var queue_label := ui.get_node("SelectionPanel").find_child(
			"QueueLabel", true, false) as Label
		_check(queue_label != null and queue_label.text.contains("Scrap Dock")
			and queue_label.text.contains("1/20 SCRAP"),
			"production refresh shows Scrap Dock label and faction-adjusted cost")

	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94722, "global_net")
	var global_city: City = null
	for candidate in game.cities:
		if candidate.faction_id == game.faction_id:
			global_city = candidate
			break
	_check(global_city != null, "Global-Net city exists")
	if global_city != null:
		global_city.buildings["server_altar"] = true
		ui._show_network_status()
		await process_frame
		var network_panel: Node = ui.get_node_or_null("NetworkStatusPanel")
		var found_altar_label := false
		if network_panel != null:
			for label in network_panel.find_children("*", "Label", true, false):
				if (label as Label).text.contains("Server Altar"):
					found_altar_label = true
					break
		_check(found_altar_label,
			"network status resolves the Global-Net Server Altar label")
		ui._close_overlay("NetworkStatusPanel")

	viewport.queue_free()
	await process_frame
	print("SCRAP_DOCK_UI_%s failures=%d" % [
		"PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok: %s" % description)
		return
	failures += 1
	push_error("Scrap Dock UI: %s" % description)
