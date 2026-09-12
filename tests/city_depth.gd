extends SceneTree
## Acceptance for finite automatic city work, focus, founding and save v9.

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_capacity_and_focus()
	_test_tile_sol_economy()
	_test_overlap_and_reassignment()
	_test_mutation_reassignment()
	_test_founding_contract()
	await _test_save_and_migration()
	_test_ai_contract_and_edge_city()
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _test_ui(size)
	print("=== CITY DEPTH %s (failures: %d) ===" % [
		"PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_capacity_and_focus() -> void:
	_reset(83001)
	var city := _add_city("Focus", 0, Vector2i(20, 20))
	_set_ring(city.cell, "wasteland")
	game.grid.terrain[20][19] = "swamp"
	game.grid.terrain[21][20] = "ruins"
	game.grid.terrain[19][20] = "rift"
	game.grid.terrain[20][21] = "crater"
	game.recompute_city_worked_tiles()
	_check(City.WORKED_SECTOR_MULT == 2, "worked sectors expose the bounded productivity factor")
	_check(city.worked_cells.size() == 2, "POP 1 works center plus exactly one tile")
	_check(city.gather_total() != _old_nine_tile_total(city), "city no longer harvests its full 3x3 ring")
	var expected := {
		"biomass": Vector2i(20, 19), "scrap": Vector2i(21, 20),
		"energy": Vector2i(19, 20), "sol": Vector2i(20, 21),
	}
	for focus_id in expected:
		city.focus = focus_id
		game.recompute_city_worked_tiles()
		_check(city.worked_cells[1] == expected[focus_id], "%s focus deterministically picks its yield" % focus_id)
	city.population = 3
	game.recompute_city_worked_tiles()
	_check(city.worked_cells.size() == 4, "finite work capacity grows with population")
	var first := city.worked_cells.duplicate()
	game.recompute_city_worked_tiles()
	_check(city.worked_cells == first, "assignment tie-break is deterministic")


func _test_tile_sol_economy() -> void:
	_reset(83006)
	var city := _add_city("SOL Focus", 0, Vector2i(20, 20))
	_set_ring(city.cell, "wasteland")
	game.grid.terrain[20][21] = "crater"
	city.focus = "sol"
	game.protocol = "central"
	game.resources.sol = 0
	game.recompute_city_worked_tiles()
	var expected := int(city.gather_total().sol) + city.sol_production()
	game.end_turn()
	_check(int(game.resources.sol) == expected and expected > city.sol_production(),
		"worked terrain SOL reaches the real player economy")


func _test_overlap_and_reassignment() -> void:
	_reset(83002)
	var left := _add_city("Left", 0, Vector2i(10, 10))
	var right := _add_city("Right", 1, Vector2i(12, 10))
	_set_ring(left.cell, "wasteland")
	_set_ring(right.cell, "wasteland")
	game.grid.terrain[11][10] = "rift"
	left.focus = "energy"
	right.focus = "energy"
	game.recompute_city_worked_tiles()
	_check(left.worked_cells.has(Vector2i(11, 10)) and not right.worked_cells.has(Vector2i(11, 10)),
		"legacy overlap yields a tile once by stable coordinate priority")
	_check(_all_worked_cells_unique(), "every worked tile is globally unique")
	game.cities.reverse()
	game.recompute_city_worked_tiles()
	_check(left.worked_cells.has(Vector2i(11, 10)) and not right.worked_cells.has(Vector2i(11, 10)),
		"claim priority does not depend on city array order")
	game.cities.erase(left)
	game.grid.clear_occupant(left.cell.x, left.cell.y, left)
	game.recompute_city_worked_tiles()
	_check(right.worked_cells.has(Vector2i(11, 10)), "removed city releases its worked tile")
	var before_focus := right.focus
	_check(game.capture_city(right, 0), "city capture uses shared reassignment path")
	_check(right.focus == before_focus and right.worked_cells.size() == 2,
		"capture preserves focus and valid finite assignment")


func _test_mutation_reassignment() -> void:
	_reset(83007)
	var left := _add_city("Damaged", 0, Vector2i(10, 10))
	var right := _add_city("Neighbor", 1, Vector2i(12, 10))
	_set_ring(left.cell, "wasteland")
	_set_ring(right.cell, "wasteland")
	game.grid.terrain[9][10] = "rift"
	game.grid.terrain[11][10] = "rift"
	left.focus = "energy"
	right.focus = "energy"
	left.population = 2
	game.recompute_city_worked_tiles()
	_check(left.worked_cells.has(Vector2i(11, 10)),
		"POP 2 overlap fixture initially owns the shared sector")
	var bot := _add_unit("auto_mech", game.BARB_FACTION, Vector2i(10, 9))
	game._barbarian_attack(bot, left.cell)
	_check(left.population == 1 and not left.worked_cells.has(Vector2i(11, 10)) \
		and right.worked_cells.has(Vector2i(11, 10)),
		"botnet population loss immediately shrinks and releases a claim")

	_reset(83008)
	var revolt_city := _add_city("Revolt", 1, Vector2i(20, 20))
	_set_ring(revolt_city.cell, "wasteland")
	revolt_city.population = 2
	game.recompute_city_worked_tiles()
	var broker := _add_unit("net_broker", 0, Vector2i(19, 20))
	var map_view = load("res://scripts/ui/MapView.gd").new()
	map_view._hack(broker, revolt_city, "revolt")
	map_view.free()
	_check(revolt_city.population == 1 and revolt_city.worked_cells.size() == 2,
		"broker revolt immediately shrinks worked capacity")

	_reset(83009)
	var improved := _add_city("Improved", 0, Vector2i(20, 20))
	_set_ring(improved.cell, "wasteland")
	improved.focus = "balanced"
	game.recompute_city_worked_tiles()
	var improvement_cell := Vector2i(21, 20)
	_check(not improved.worked_cells.has(improvement_cell),
		"improvement fixture starts on an unworked tied sector")
	var founder := _add_unit("founder", 0, improvement_cell)
	_check(game.build_improvement(founder, "tower") \
		and improved.worked_cells.has(improvement_cell),
		"successful improvement immediately updates automatic assignment")

	_reset(83010)
	var linked := _add_city("Linked", 0, Vector2i(20, 20))
	_set_ring(linked.cell, "wasteland")
	linked.focus = "sol"
	game.recompute_city_worked_tiles()
	var monorail_cell := Vector2i(21, 20)
	_check(not linked.worked_cells.has(monorail_cell),
		"monorail fixture starts on an unworked tied sector")
	var engineer := _add_unit("rust_guard", 0, monorail_cell)
	_check(game.build_monorail(engineer) and linked.worked_cells.has(monorail_cell) \
		and int(linked.gather_total().sol) > 0,
		"successful monorail immediately updates SOL assignment and yield")


func _test_founding_contract() -> void:
	_reset(83003)
	_add_city("Anchor", 0, Vector2i(10, 10))
	var player := _add_unit("founder", 0, Vector2i(15, 10))
	var ai_founder := _add_unit("founder", 1, Vector2i(25, 10))
	_check(game.can_found_site(player.cell, 0, player), "player founder may found on its own occupied legal cell")
	_check(game.can_found_site(ai_founder.cell, 1, ai_founder), "AI founder uses the same own-cell legality")
	player.cell = Vector2i(14, 10)
	_check(not game.can_found_site(player.cell, 0, player), "minimum founding distance is five Manhattan tiles")
	player.cell = Vector2i(15, 10)
	var before_preview := _preview_state()
	var preview: Dictionary = game.founding_site_preview(player.cell, 0, player)
	_check(bool(preview.legal) and preview.worked.size() == 2, "legal site previews finite POP 1 work")
	_check(_preview_state() == before_preview, "founding preview is a pure read of game state")
	game.resources.scrap = Data.SCRAP_PER_CITY
	_check(game.found_city(player), "player founds through common legality")
	var founded: City = game.city_at(Vector2i(15, 10))
	_check(founded != null and founded.gather_total() == preview.yields,
		"founding preview exactly matches post-found yield allocation")
	var blocked := Vector2i(25, 10)
	game.grid.terrain[blocked.x][blocked.y] = "mountains"
	_check(not game.can_found_site(blocked, 1, ai_founder), "mountains are invalid for both founders")


func _test_save_and_migration() -> void:
	_reset(83004)
	var city := _add_city("Saved", 0, Vector2i(20, 20))
	_set_ring(city.cell, "wasteland")
	game.grid.terrain[21][20] = "ruins"
	city.focus = "scrap"
	game.recompute_city_worked_tiles()
	var expected_cells := city.worked_cells.duplicate()
	var path := "user://city_depth_v9.json"
	_check(game.save_to_file(path), "v9 city focus save writes")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(int(saved.version) == 9 and str(saved.cities[0].focus) == "scrap",
		"v9 serializes focus, not derived claims")
	_check(not saved.cities[0].has("worked_cells"), "worked cells remain deterministic derived state")
	_check(game.load_from_file(path), "v9 city focus save loads")
	city = game.city_at(Vector2i(20, 20))
	_check(city.focus == "scrap" and city.worked_cells == expected_cells,
		"save/load restores exact focus and derived allocation")
	for city_data in saved.cities:
		city_data.erase("focus")
	saved.version = 8
	var legacy_path := "user://city_depth_v8.json"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	_check(game.load_from_file(legacy_path), "v8 save migrates")
	_check(game.city_at(Vector2i(20, 20)).focus == "balanced", "v8 focus migrates to Balanced")
	await process_frame


func _test_ai_contract_and_edge_city() -> void:
	_reset(83005)
	var ai_city := _add_city("AI", 1, Vector2i(20, 20))
	_set_ring(ai_city.cell, "wasteland")
	game.ai._run_economy(1, [ai_city], game.ai._resources(1), game)
	_check(ai_city.focus in game.CITY_FOCUSES and ai_city.worked_cells.size() == 2,
		"AI economy uses the same finite focus allocator")
	var edge := _add_city("Edge", 0, Vector2i(0, 0))
	game.grid.terrain[0][0] = "wasteland"
	edge.population = 8
	game.recompute_city_worked_tiles()
	_check(not edge.worked_cells.is_empty() and edge.worked_cells[0] == edge.cell,
		"edge city always works its center without deadlock")


func _test_ui(size: Vector2i) -> void:
	_reset(83100 + size.x)
	var city := _add_city("Focus UI", 0, Vector2i(20, 20))
	_set_ring(city.cell, "wasteland")
	game.grid.terrain[20][19] = "swamp"
	game.grid.terrain[21][20] = "ruins"
	game.grid.terrain[19][20] = "rift"
	game.recompute_city_worked_tiles()
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var ui = load("res://scripts/ui/GameUI.gd").new()
	ui.name = "UI"
	scene.add_child(ui)
	await process_frame
	ui._set_match_chrome_visible(true)
	game.select(city)
	ui.build_city_actions(city)
	await process_frame
	var workspace: Control = ui.get_node("CityActions")
	var city_tab: Button = workspace.find_child("CityTabOverview", true, false)
	city_tab.emit_signal("pressed")
	await process_frame
	var focus_button: Button = workspace.find_child("CityFocus", true, false)
	_check(focus_button != null and focus_button.size.y >= 44.0 and not focus_button.disabled,
		"%dpx focus is one touch-safe effective control" % size.x)
	_check(focus_button.text.contains("→") and (focus_button.text.contains("+") \
		or focus_button.text.contains("-")), "%dpx focus previews a real yield delta" % size.x)
	_check(workspace.get_global_rect().end.y <= ui.get_node("BottomNav").get_global_rect().position.y,
		"%dpx city focus workspace stays above navigation" % size.x)
	var before := city.gather_total()
	focus_button.emit_signal("pressed")
	await process_frame
	_check(city.gather_total() != before, "%dpx one focus tap changes immediate yields" % size.x)
	ui._close_overlay("CityActions")
	var founder := _add_unit("founder", 0, Vector2i(25, 20))
	game.grid.terrain[25][20] = "wasteland"
	game.select(founder)
	await process_frame
	_check(ui._selection_summary_text.contains("SITE  BIO") and ui._selection_actions.visible,
		"%dpx legal founder selection shows concise site yields and action" % size.x)
	game.grid.clear_occupant(founder.cell.x, founder.cell.y, founder)
	founder.cell = Vector2i(24, 20)
	game.grid.place_occupant(founder.cell.x, founder.cell.y, founder)
	game.select(founder)
	await process_frame
	_check(ui._selection_summary_text.contains("CITY TOO CLOSE") and not ui._selection_actions.visible,
		"%dpx illegal founder selection shows one concise reason" % size.x)
	viewport.queue_free()
	await process_frame


func _reset(seed_value: int) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed_value, "rust_tech",
		["rust_tech", "global_net"])
	game.grid.clear_occupants()
	game.units.clear()
	game.cities.clear()
	game.city_name_counter = 1


func _add_city(city_name: String, owner: int, cell: Vector2i) -> City:
	var city := City.new(city_name, owner, game.factions[owner], cell, game.grid)
	city.buildings["genesis_node"] = true
	game.cities.append(city)
	game.grid.place_occupant(cell.x, cell.y, city)
	return city


func _add_unit(type_id: String, owner: int, cell: Vector2i) -> Unit:
	var unit := Unit.new(type_id, owner, cell, game.grid)
	game.units.append(unit)
	game.grid.place_occupant(cell.x, cell.y, unit)
	return unit


func _set_ring(center: Vector2i, terrain_id: String) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			game.grid.terrain[center.x + dx][center.y + dy] = terrain_id


func _old_nine_tile_total(city: City) -> Dictionary:
	var totals := {"food": 0, "scrap": 0, "energy": 0, "sol": 0}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var tile := city.gather_tile(city.cell.x + dx, city.cell.y + dy)
			for key in totals:
				totals[key] += int(tile[key])
	return totals


func _all_worked_cells_unique() -> bool:
	var seen: Dictionary = {}
	for city in game.cities:
		for worked_cell in city.worked_cells:
			if seen.has(worked_cell):
				return false
			seen[worked_cell] = true
	return true


func _preview_state() -> Array:
	var city_state: Array = []
	for city in game.cities:
		city_state.append([city, city.focus, city.worked_cells.duplicate()])
	var occupancy: Array = []
	for city in game.cities:
		occupancy.append(game.grid.occupant_at(city.cell.x, city.cell.y))
	for unit in game.units:
		occupancy.append(game.grid.occupant_at(unit.cell.x, unit.cell.y))
	return [game.cities.duplicate(), city_state, occupancy, game.resources.duplicate(true), str(game._rng.state)]


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)
