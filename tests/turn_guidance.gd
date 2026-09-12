extends SceneTree
## Acceptance for the single next-required-decision turn guide.

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_priority_and_orders()
	await _test_save_and_legacy_load()
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _test_ui(size)
	print("=== TURN GUIDANCE %s (failures: %d) ===" % [
		"PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_priority_and_orders() -> void:
	var state := _guidance_state(81001)
	var first: Unit = state.first
	var second: Unit = state.second
	var city: City = state.city
	_check(game.next_required_action().kind == "unit"
		and game.next_required_action().target == first,
		"unit orders precede research and production")
	game.select(first)
	_check(game.unit_order_label(first) == "FORTIFY", "stationary guard offers FORTIFY")
	_check(game.complete_unit_orders(first) and first.fortified and first.orders_skipped,
		"FORTIFY consciously completes stationary guard orders")
	second.has_moved_this_turn = true
	_check(game.unit_order_label(second) == "WAIT", "partially moved guard offers WAIT")
	game.complete_unit_orders(second)
	_check(not second.fortified and second.orders_skipped,
		"WAIT does not grant fortification after partial movement")
	_check(game.next_required_action().kind == "research",
		"legal research follows completed unit orders")
	game.tech.current = "steam_synthesis"
	_check(game.next_required_action().kind == "production"
		and game.next_required_action().target == city,
		"idle city production follows active research")
	city.add_to_queue("steam_turbine")
	_check(game.next_required_action().kind == "end_turn",
		"end turn becomes ready only after required decisions")

	var founder := _add_unit("founder", Vector2i(24, 20))
	_check(game.unit_order_label(founder) == "WAIT", "founder uses WAIT, never FORTIFY")
	game.complete_unit_orders(founder)
	var transport_cell := Vector2i(25, 20)
	game.grid.terrain[transport_cell.x][transport_cell.y] = "ocean"
	var transport := _add_unit("steam_cruiser", transport_cell)
	_check(game.unit_order_label(transport) == "WAIT", "transport uses WAIT, never FORTIFY")
	game.complete_unit_orders(transport)
	var exhausted := _add_unit("rust_guard", Vector2i(26, 20))
	exhausted.moves_left = 0.0
	var fortified := _add_unit("rust_guard", Vector2i(27, 20))
	fortified.fortified = true
	var carrier_cell := Vector2i(28, 20)
	game.grid.terrain[carrier_cell.x][carrier_cell.y] = "ocean"
	var carrier := _add_unit("steam_cruiser", carrier_cell)
	carrier.orders_skipped = true
	var passenger := Unit.new("rust_guard", game.faction_id, carrier.cell, game.grid)
	carrier.cargo.append(passenger)
	_check(game.next_required_action().kind == "end_turn",
		"exhausted, fortified, skipped, and cargo units do not demand orders")


func _test_save_and_legacy_load() -> void:
	var state := _guidance_state(81002)
	var first: Unit = state.first
	game.complete_unit_orders(first)
	var save_path := "user://turn_guidance_v8.json"
	_check(game.save_to_file(save_path), "v8 turn-order state saves")
	_check(game.load_from_file(save_path), "v8 turn-order state loads")
	var loaded_first: Unit = game.units[0]
	_check(loaded_first.orders_skipped and loaded_first.moves_left <= 0.001,
		"v8 load preserves completed orders exactly")

	var file := FileAccess.open(save_path, FileAccess.READ)
	var legacy: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	legacy.version = 7
	for unit_data in legacy.units:
		unit_data.erase("orders_skipped")
	var legacy_path := "user://turn_guidance_v7.json"
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	_check(game.load_from_file(legacy_path), "v7 save migrates safely")
	_check(not game.units[0].orders_skipped, "v7 migration defaults orders to pending")
	game.units[0].orders_skipped = true
	game.units[0].reset_moves()
	_check(not game.units[0].orders_skipped, "new turn resets a conscious WAIT/FORTIFY order")


func _test_ui(size: Vector2i) -> void:
	var state := _guidance_state(82000 + size.x)
	var first: Unit = state.first
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var map: Node2D = load("res://scripts/ui/MapView.gd").new()
	map.name = "MapView"
	scene.add_child(map)
	var camera := Camera2D.new()
	camera.name = "Camera"
	scene.add_child(camera)
	var ui = load("res://scripts/ui/GameUI.gd").new()
	ui.name = "UI"
	scene.add_child(ui)
	await process_frame
	ui._set_match_chrome_visible(true)
	await process_frame
	var next := ui.get_node("BottomNav").find_child("NextActionButton", true, false) as Button
	var end_turn := ui.get_node("BottomNav").find_child("EndTurnButton", true, false) as Button
	_check(next.text == "UNIT NEEDS ORDERS" and next.size.y >= 48.0 and end_turn.disabled,
		"%dpx guide is touch-safe and locks End Turn while orders remain" % size.x)
	var before := [first.cell, first.moves_left, first.fortified, first.orders_skipped]
	next.emit_signal("pressed")
	await process_frame
	_check(game.selected_unit == first and before == [first.cell, first.moves_left,
		first.fortified, first.orders_skipped] and next.text == "FORTIFY",
		"%dpx first tap only focuses unit and reveals explicit order" % size.x)
	next.emit_signal("pressed")
	await process_frame
	_check(first.orders_skipped and game.next_required_action().target == state.second,
		"%dpx second tap consciously completes that unit" % size.x)
	var turn_before: int = game.turn
	ui._hold_start()
	ui._process(1.0)
	_check(game.turn == turn_before and not ui._holding_end,
		"%dpx locked End Turn ignores hold attempts" % size.x)
	for unit in game.units:
		if game.unit_requires_orders(unit):
			game.complete_unit_orders(unit)
	game.tech.current = "steam_synthesis"
	state.city.add_to_queue("steam_turbine")
	ui._refresh_next_action()
	_check(next.text == "TURN READY" and next.disabled and not end_turn.disabled
		and end_turn.text == "END TURN · HOLD",
		"%dpx resolved flow clearly hands off to hold-to-end-turn" % size.x)
	var broker := _add_unit("net_broker", Vector2i(24, 20))
	game.select(broker)
	ui._refresh_next_action()
	_check(next.text == "WAIT", "%dpx selected broker exposes WAIT" % size.x)
	var rival_city := City.new("Rival", 1, game.factions[1], Vector2i(29, 20), game.grid)
	game.cities.append(rival_city)
	game.grid.place_occupant(rival_city.cell.x, rival_city.cell.y, rival_city)
	game.shield_turns = 1
	map._hack(broker, rival_city, "dos")
	_check(broker.moves_left <= 0.001 and next.text == "TURN READY",
		"%dpx broker operation refreshes the next real decision immediately" % size.x)
	game.shield_turns = 0
	game.grid.clear_occupant(rival_city.cell.x, rival_city.cell.y, rival_city)
	game.cities.erase(rival_city)

	state.city.build_queue.clear()
	for building_id in Data.BUILDINGS:
		if building_id not in ["nuclear_plant", "fusion_plant"]:
			state.city.buildings[state.city.faction.building_for(str(building_id))] = true
	game.tech.researched["atomic_reactor"] = true
	game.resources.sol = 20
	ui._refresh_next_action()
	_check(game.next_required_action().kind == "production",
		"%dpx valid late-city upgrade remains a production decision" % size.x)
	next.emit_signal("pressed")
	await process_frame
	var city_actions: Node = ui.get_node_or_null("CityActions")
	var upgrade: Node = city_actions.find_child("ProductionChoice_upgrade", true, false) \
		if city_actions != null else null
	var has_empty_copy := false
	if city_actions != null:
		for label in city_actions.find_children("*", "Label", true, false):
			if label.text == "NO AFFORDABLE PRODUCTION":
				has_empty_copy = true
	_check(upgrade != null and not has_empty_copy,
		"%dpx guided late city opens a real upgrade, never an empty picker" % size.x)
	_check(city_actions != null and city_actions.get_global_rect().end.y <= \
		ui.get_node("BottomNav").get_global_rect().position.y,
		"%dpx city workspace stays above the taller navigation" % size.x)
	viewport.queue_free()
	await process_frame


func _guidance_state(seed: int) -> Dictionary:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, seed, "rust_tech")
	game.grid.clear_occupants()
	game.units.clear()
	game.cities.clear()
	game.tech.researched.clear()
	game.tech.current = ""
	game.resources.sol = 10
	for x in range(17, 31):
		for y in range(17, 24):
			game.grid.terrain[x][y] = "wasteland"
	var city := City.new("Guide", game.faction_id, game.factions[game.faction_id],
		Vector2i(20, 20), game.grid)
	city.buildings["genesis_node"] = true
	game.cities.append(city)
	game.grid.place_occupant(city.cell.x, city.cell.y, city)
	var first := _add_unit("rust_guard", Vector2i(22, 20))
	var second := _add_unit("rust_guard", Vector2i(23, 20))
	game.select(null)
	game.update_visibility()
	return {"city": city, "first": first, "second": second}


func _add_unit(type_id: String, cell: Vector2i) -> Unit:
	var unit := Unit.new(type_id, game.faction_id, cell, game.grid)
	game.units.append(unit)
	game.grid.place_occupant(cell.x, cell.y, unit)
	return unit


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)
