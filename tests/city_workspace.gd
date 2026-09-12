extends SceneTree
## Focused acceptance for the compact, non-mutating city workspace.

var failures := 0
var game: Node
var game_ui_script: GDScript


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	game_ui_script = load("res://scripts/ui/GameUI.gd")
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _run_size(size)
	print("CITY_WORKSPACE_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _run_size(size: Vector2i) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 93500 + size.x,
		"rust_tech")
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var ui = game_ui_script.new()
	ui.name = "UI"
	scene.add_child(ui)
	await process_frame
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await process_frame
	var city: City = _player_city()
	game.select(city)
	var before := _snapshot(city)
	ui.build_city_actions(city)
	await process_frame
	await process_frame
	var workspace := ui.get_node("CityActions") as Control
	_check(workspace != null and workspace.is_visible_in_tree(),
		"%s city opens one workspace" % size.x)
	_check(workspace.size.y <= float(size.y) * 0.58 + 1.0,
		"%s workspace remains a bounded bottom sheet" % size.x)
	for node_name in ["CityWorkspaceHeader", "CityIllustration", "CurrentProduction",
			"CityYieldRow", "CityTabProduction", "CityTabOverview", "CityActionsScroll"]:
		_check(workspace.find_child(node_name, true, false) != null,
			"%s workspace exposes %s" % [size.x, node_name])
	var production_tab := workspace.find_child("CityTabProduction", true, false) as Button
	var overview_tab := workspace.find_child("CityTabOverview", true, false) as Button
	_check(production_tab.size.y >= 48.0 and overview_tab.size.y >= 48.0,
		"%s city tabs meet touch target" % size.x)
	var choices := workspace.find_children("ProductionChoice*", "Button", true, false)
	_check(choices.size() > 0 and choices.size() <= 5,
		"%s production is a one-level list of at most five choices" % size.x)
	for choice in choices:
		var button := choice as Button
		_check(button.text.count("\n") == 1 and button.text.length() < 105
			and (button.text.contains("TURN") or button.text.contains("NEEDS")),
			"%s production row stays concise and actionable" % size.x)
	overview_tab.emit_signal("pressed")
	await process_frame
	_check(not (workspace.find_child("CityProductionContent", true, false) as Control).visible
		and (workspace.find_child("CityOverviewContent", true, false) as Control).visible,
		"%s CITY tab replaces rather than stacks content" % size.x)
	production_tab.emit_signal("pressed")
	await process_frame
	ui._close_overlay("CityActions")
	await process_frame
	_check(_snapshot(city) == before, "%s open, tabs and close never mutate game state" % size.x)
	_check(ui.get_node("SelectionPanel").visible,
		"%s close restores the selected-city sheet" % size.x)

	city.build_queue = ["assembly_forge"]
	city.scrap_stock = 5
	city.offline_turns = 2
	ui.build_city_actions(city)
	await process_frame
	var state := ui.get_node("CityActions").find_child(
		"CityOperationalState", true, false) as Label
	_check(state.text == "OFFLINE · 2T", "%s offline state is immediately visible" % size.x)
	var current := ui.get_node("CityActions").find_child(
		"CurrentProductionLabel", true, false) as Label
	_check(current.text.contains("HALTED"), "%s offline queue never promises an ETA" % size.x)
	ui._close_overlay("CityActions")
	city.offline_turns = 0
	city.build_queue.clear()
	city.scrap_stock = 0
	city.dos_turns = 2
	ui.build_city_actions(city)
	await process_frame
	state = ui.get_node("CityActions").find_child("CityOperationalState", true, false) as Label
	_check(state.text == "DoS · 2T", "%s DoS state is immediately visible" % size.x)
	ui._close_overlay("CityActions")
	city.dos_turns = 0
	city.occupation_until_turn = game.turn + 2
	ui.build_city_actions(city)
	await process_frame
	var secured := ui.get_node("CityActions").find_child("CitySecuredState", true, false) as Label
	_check(secured != null and secured.text == "SECURED 2T",
		"%s secured state remains visible" % size.x)
	ui._close_overlay("CityActions")
	city.occupation_until_turn = 0

	city.build_queue.clear()
	city.scrap_stock = 0
	ui.build_city_actions(city)
	await process_frame
	workspace = ui.get_node("CityActions")
	var build_button := workspace.find_child("ProductionChoice_*", true, false) as Button
	_check(build_button != null, "%s first-turn city has a production action" % size.x)
	if build_button != null:
		build_button.emit_signal("pressed")
		await process_frame
	_check(not city.build_queue.is_empty(), "%s production tap queues exactly one project" % size.x)
	workspace = ui.get_node("CityActions")
	var refreshed_current := workspace.find_child(
		"CurrentProductionLabel", true, false) as Label
	_check(refreshed_current != null and refreshed_current.text.contains("Assembly Forge")
		and not refreshed_current.text.contains("NO PRODUCTION"),
		"%s queued project refreshes current production immediately" % size.x)
	_check(workspace.find_child("ProductionChoice_assembly_forge", true, false) == null,
		"%s queued project leaves the choice list immediately" % size.x)
	ui._close_overlay("CityActions")
	viewport.queue_free()
	await process_frame


func _player_city() -> City:
	for city in game.cities:
		if city.faction_id == game.faction_id:
			return city
	return null


func _snapshot(city: City) -> Dictionary:
	return {
		"turn": game.turn,
		"resources": game.resources.duplicate(true),
		"population": city.population,
		"queue": city.build_queue.duplicate(true),
		"stock": city.scrap_stock,
		"buildings": city.buildings.duplicate(true),
		"fatigue": city.fatigue,
		"offline": city.offline_turns,
		"dos": city.dos_turns,
		"occupation": city.occupation_until_turn,
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok: " + message)
	else:
		failures += 1
		print("  FAIL: " + message)
