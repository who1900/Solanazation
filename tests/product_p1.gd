extends SceneTree
## Focused acceptance for first-turn composition and compact city feedback.

var failures := 0
var game: Node
var map_view_script: GDScript
var game_ui_script: GDScript


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	map_view_script = load("res://scripts/ui/MapView.gd")
	game_ui_script = load("res://scripts/ui/GameUI.gd")
	_static_contracts()
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _run_size(size)
	print("PRODUCT_P1_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _run_size(size: Vector2i) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 91000 + size.x, "rust_tech")
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	scene.add_child(camera)
	var map = map_view_script.new()
	map.name = "MapView"
	scene.add_child(map)
	var ui = game_ui_script.new()
	ui.name = "UI"
	scene.add_child(ui)
	await process_frame
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await process_frame
	map._focus_player_start()
	await process_frame

	var playable: Rect2 = ui.playable_map_rect()
	_check(playable.position.y >= ui.get_node("TopHUD").get_global_rect().end.y,
		"%s playable map starts below HUD" % size.x)
	_check(playable.end.y <= ui.get_node("BottomNav").get_global_rect().position.y,
		"%s playable map ends above bottom rail" % size.x)
	var focus_objects: Array = []
	var city: City = null
	for candidate in game.cities:
		if candidate.faction_id == game.faction_id and candidate.is_capital:
			city = candidate
			focus_objects.append(candidate)
			break
	for unit in game.units:
		if unit.faction_id == game.faction_id:
			focus_objects.append(unit)
	for object in focus_objects:
		_check(playable.grow(20.0).has_point(_cell_screen(camera, size, object.cell)),
			"%s initial frame contains %s" % [size.x, object.get_class()])
	_check(camera.zoom.x >= map_view_script.MIN_ZOOM and camera.zoom.x <= map_view_script.MAX_ZOOM,
		"%s initial zoom respects camera clamps" % size.x)
	_check(_cell_screen(camera, size, city.cell).y < playable.position.y + playable.size.y * 0.62,
		"%s capital avoids dead upper composition" % size.x)

	game.select(city)
	await process_frame
	var sheet := ui.get_node("SelectionPanel") as Control
	_check(sheet.size.y < 280.0, "%s selected-city sheet is content-sized" % size.x)
	game.resources.sol = 0
	city.build_queue.clear()
	city.add_to_queue("archio_archive")
	city.scrap_stock = 7
	ui._update_selection(city)
	await process_frame
	var queue := sheet.find_child("QueueFeedback", true, false) as Control
	var queue_label := sheet.find_child("QueueLabel", true, false) as Label
	_check(queue.visible and queue_label.text.contains("7/")
		and queue_label.text.contains("NEEDS 5 SOL") and not queue_label.text.contains("TURN"),
		"%s SOL-blocked queue never promises completion" % size.x)
	game.resources.sol = 5
	ui._update_selection(city)
	await process_frame
	_check(queue_label.text.contains("TURN") and not queue_label.text.contains("NEEDS"),
		"%s affordable queue restores ETA" % size.x)
	city.build_queue.clear()
	city.scrap_stock = 0
	game.grid.terrain[city.cell.x][city.cell.y] = "wasteland"
	var build_id := _first_build(city)
	_check(build_id != "", "%s city has a production candidate" % size.x)
	if build_id != "":
		game.resources.sol = 100
		city.add_to_queue(build_id)
		city.scrap_stock = 7
		ui._update_selection(city)
		await process_frame
		_check(queue.visible and queue_label.text.contains("7/") and queue_label.text.contains("TURN"),
			"%s selected city exposes queue progress and ETA" % size.x)
	city.build_queue.clear()
	city.scrap_stock = 0

	game.resources.sol = 0
	ui.build_city_actions(city)
	await process_frame
	var production := ui.get_node("CityActions") as Control
	var choices := production.find_children("ProductionChoice*", "Button", true, false)
	var blocked_archio := _production_choice(choices, "Archio-Archive")
	_check(blocked_archio != null and blocked_archio.text.contains("NEEDS 5 SOL")
		and not blocked_archio.text.contains("TURN"),
		"%s SOL-blocked production row has requirement instead of ETA" % size.x)
	_check(choices.size() <= 5 and choices.size() > 0,
		"%s production chooser contains at most five actionable rows" % size.x)
	for choice in choices:
		_check(choice.custom_minimum_size.y >= 72.0 and choice.text.contains("\n")
			and (choice.text.contains("TURN") or choice.text.contains("NEEDS")),
			"%s production row is scannable with effect/cost/status" % size.x)
	_check(production.size.y <= float(size.y) * 0.58 + 1.0,
		"%s production chooser is content-bounded" % size.x)
	ui._close_overlay("CityActions")
	await process_frame
	game.resources.sol = 5
	ui.build_city_actions(city)
	await process_frame
	production = ui.get_node("CityActions") as Control
	choices = production.find_children("ProductionChoice*", "Button", true, false)
	var affordable_archio := _production_choice(choices, "Archio-Archive")
	_check(affordable_archio != null and affordable_archio.text.contains("TURN")
		and not affordable_archio.text.contains("NEEDS"),
		"%s affordable production row exposes ETA" % size.x)
	ui._close_overlay("CityActions")
	await process_frame
	game.resources.scrap = 100
	for unit in game.units:
		if game.unit_requires_orders(unit):
			game.complete_unit_orders(unit)
	if city.build_queue.is_empty():
		city.add_to_queue(_first_build(city))
	var old_turn: int = game.turn
	ui._commit_end_turn()
	await process_frame
	var cue := ui.get_node("TurnDeltaCue") as Control
	_check(game.turn == old_turn + 1, "%s end turn advances once" % size.x)
	_check(cue.visible, "%s end turn shows non-modal delta cue" % size.x)
	ui._show_turn_delta(
		{"scrap": 10, "biomass": 5, "energy": 4, "sol": 0},
		{"scrap": 12, "biomass": 5, "energy": 4, "sol": 0}, {}, {})
	_check(ui._turn_cue_row.get_child_count() > 1,
		"%s delta cue contains derived resource/progress feedback" % size.x)
	viewport.queue_free()
	await process_frame


func _first_build(city: City) -> String:
	for building_id in Data.BUILDINGS:
		if building_id not in ["nuclear_plant", "fusion_plant"] \
				and city.can_queue_build(building_id, game.tech):
			return building_id
	return ""


func _production_choice(choices: Array, title: String) -> Button:
	for choice in choices:
		if (choice as Button).text.begins_with(title):
			return choice as Button
	return null


func _cell_screen(camera: Camera2D, viewport_size: Vector2i, cell: Vector2i) -> Vector2:
	var tile_size: float = float(map_view_script.TILE_SIZE)
	var world: Vector2 = Vector2(cell) * tile_size + Vector2.ONE * tile_size * 0.5
	return (world - camera.position) * camera.zoom.x + Vector2(viewport_size) * 0.5


func _static_contracts() -> void:
	var map_source := FileAccess.get_file_as_string("res://scripts/ui/MapView.gd")
	_check(not map_source.contains("(x + y) % 2"), "shroud has no checkerboard parity")
	var unexplored := map_source.get_slice("if not Game.is_explored(cell):", 1).get_slice("continue", 0)
	_check(not unexplored.contains("terrain_data"), "unexplored shroud never samples terrain")
	var a: Color = map_view_script.shroud_color(Vector2i(2, 2), 41)
	var b: Color = map_view_script.shroud_color(Vector2i(3, 2), 41)
	var color_delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	_check(color_delta < 0.05, "shroud grain remains one coherent neutral material")
	var reachable := FileAccess.get_file_as_string("res://assets/icons/actions/reachable.svg")
	_check(reachable.contains("stroke-opacity=\".34\"") and reachable.contains("r=\"15\""),
		"reachable marker is reduced in opacity and density")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  ok: %s" % description)
		return
	failures += 1
	push_error("Product P1: %s" % description)
