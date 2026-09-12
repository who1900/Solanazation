extends SceneTree
## Fair Rival v1 contracts and certified Small/Pangaea soak.

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_peace_and_war_gate()
	_test_economy_and_research()
	_test_faction_effect_parity()
	_test_obstacle_pathing()
	_test_capture_and_victory()
	_test_save_continuation()
	_test_small_pangaea_soak()
	print("FAIR_RIVAL_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_peace_and_war_gate() -> void:
	_prepare_fixture(7101)
	_add_city(0, Vector2i(3, 3))
	_add_city(1, Vector2i(20, 20))
	var ai_unit := _add_unit("heavy_mech", 1, Vector2i(10, 10))
	var player_unit := _add_unit("rust_guard", 0, Vector2i(11, 10))
	ai_unit.moves_left = 0
	game.diplomacy[1] = "peace"
	game.ping[1] = 50
	game.ai.take_turn(1, game)
	check(game.units.has(ai_unit) and game.units.has(player_unit),
		"peace blocks AI combat")
	check(ai_unit.has_moved_this_turn and ai_unit.moves_left < ai_unit.max_moves(),
		"AI movement points reset before its peaceful exploration action")
	check(int(game.ping[1]) == 49, "peaceful rivalry advances toward the existing hostility threshold")
	game.diplomacy[1] = "war"
	game.ai.take_turn(1, game)
	check(not (game.units.has(ai_unit) and game.units.has(player_unit)),
		"war permits one seeded adjacent combat resolution")


func _test_economy_and_research() -> void:
	_prepare_fixture(7102)
	var city := _add_city(1, Vector2i(12, 12))
	city.buildings["steam_turbine"] = true
	game.ai.ai_resources[1] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 0}
	game.ai.take_turn(1, game)
	var treasury: Dictionary = game.ai.ai_resources[1]
	check(int(treasury.scrap) > 0 and int(treasury.biomass) > 0 and int(treasury.energy) > 0,
		"AI credits deterministic powered city yields")
	check(int(treasury.energy) == 23,
		"AI energy accounting includes the Genesis bootstrap and turbine exactly once")
	var expected_sol := int(round(int(round(5.0 * 0.5)) * 1.25))
	check(int(treasury.sol) == expected_sol,
		"AI applies Peer-to-Peer SOL and its faction validator modifier in player order")
	check(game.ai.ai_tech.has(1), "AI owns independent research state")
	city.build_queue.clear()
	city.buildings["assembly_forge"] = true
	game.ai._queue_legal_production([city], game.ai._tech(1))
	check(city.build_queue.is_empty(), "AI cannot queue a technology-locked building")
	game.ai._tech(1).researched["block_encryption"] = true
	game.ai._queue_legal_production([city], game.ai._tech(1))
	check(city.build_queue == ["sol_exchange"], "AI queues the building after legal research")
	city.offline_turns = 2
	city.build_queue.clear()
	game.ai.ai_resources[1] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 0}
	game.ai.take_turn(1, game)
	check(game.ai.ai_resources[1] == {"scrap": 0, "biomass": 0, "energy": 0, "sol": 0},
		"offline AI city produces nothing")
	_prepare_fixture(7106)
	_add_city(1, Vector2i(5, 5))
	var founder := _add_unit("founder", 1, Vector2i(12, 12))
	game.ai.ai_resources[1] = {"scrap": Data.SCRAP_PER_CITY, "biomass": 0, "energy": 0, "sol": 0}
	game.ai._founder_action(game, founder, 1)
	check(not game.units.has(founder) and game.cities.size() == 2 \
			and int(game.ai.ai_resources[1].scrap) == 0,
		"AI expansion consumes one Founder and the same 25 Scrap city cost")


func _test_obstacle_pathing() -> void:
	_prepare_fixture(7103)
	var attacker := _add_unit("heavy_mech", 1, Vector2i(5, 5))
	_add_unit("rust_guard", 0, Vector2i(10, 5))
	for y in range(3, 6):
		game.grid.terrain[6][y] = "mountains"
	game.diplomacy[1] = "war"
	game.ai.take_turn(1, game)
	check(game.units.has(attacker) and attacker.cell.y >= 6 and attacker.cell.x >= 6,
		"deterministic land pathing routes around an obstacle")


func _test_faction_effect_parity() -> void:
	_prepare_fixture(7107)
	var city := _add_city(1, Vector2i(12, 12))
	city.buildings["steam_turbine"] = true
	city.buildings["assembly_forge"] = true
	game.grid.terrain[11][12] = "ruins"
	game.ai.ai_resources[1] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 0}
	var manager: TechManager = game.ai._tech(1)
	manager.researched["steam_synthesis"] = true
	game.recompute_city_worked_tiles()
	var expected_scrap := int(city.gather_total().scrap) + city.count_terrain_near("ruins")
	game.ai._run_economy(1, [city], game.ai.ai_resources[1], game)
	check(int(game.ai.ai_resources[1].scrap) == expected_scrap,
		"AI Steam Synthesis adds one Scrap for a nearby Ruins tile")
	game.ai.ai_resources[1].scrap = 10
	game.ai._train_units(1, [city], game.ai.ai_resources[1], manager, game)
	var trained_veteran := false
	for unit in game.units:
		if unit.faction_id == 1 and unit.veteran:
			trained_veteran = true
	check(trained_veteran, "AI Assembly Forge grants veteran status to a trained unit")
	city.fatigue = 0
	game.diplomacy[1] = "war"
	_add_unit("rust_guard", 0, Vector2i(30, 30))
	game.ai._run_economy(1, [city], game.ai.ai_resources[1], game)
	check(city.fatigue == 0, "declared war alone does not add AI city fatigue")
	_add_unit("rust_guard", 0, Vector2i(16, 12))
	game.ai._run_economy(1, [city], game.ai.ai_resources[1], game)
	check(city.fatigue == 3, "nearby enemy adds the same +5 minus recovery AI city fatigue")


func _test_capture_and_victory() -> void:
	_prepare_fixture(7104)
	var player_capital := _add_city(0, Vector2i(8, 8))
	var ai_capital := _add_city(1, Vector2i(20, 8))
	check(player_capital.is_capital and ai_capital.is_capital, "fixture has two original capitals")
	check(game.capture_city(player_capital, 1)
		and player_capital.faction_id == 1 and player_capital.faction == game.factions[1],
		"city capture updates both faction index and faction object")
	var winner := [""]
	game.game_over.connect(func(name: String, _reason: String): winner[0] = name, CONNECT_ONE_SHOT)
	check(game.update_victories() and winner[0] == game.factions[1].name,
		"domination recognizes the faction controlling every original capital")
	game.capture_city(player_capital, 0)
	var captured_by_combat := false
	for combat_seed in range(7110, 7120):
		_prepare_fixture(combat_seed)
		var target_city := _add_city(0, Vector2i(11, 10))
		_add_unit("heavy_mech", 1, Vector2i(10, 10))
		game.diplomacy[1] = "war"
		game.ai.take_turn(1, game)
		if target_city.faction_id == 1 and target_city.faction == game.factions[1]:
			captured_by_combat = true
			break
	check(captured_by_combat, "seeded AI combat can legally capture and transfer a city")
	_prepare_fixture(7121)
	player_capital = _add_city(0, Vector2i(8, 8))
	ai_capital = _add_city(1, Vector2i(20, 8))
	game.resources.sol = 81
	game.ai.ai_resources[1] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 19}
	game.network_sol_generated = {0: 81, 1: 19}
	game.monopoly_turns = 0
	for i in range(9):
		check(not game.update_victories(), "monopoly does not finish before ten turns")
	check(game.monopoly_turns == 9, "monopoly counter accumulates exact qualifying turns")
	var monopoly_winner := [""]
	game.game_over.connect(func(name: String, _reason: String): monopoly_winner[0] = name, CONNECT_ONE_SHOT)
	check(game.update_victories() and monopoly_winner[0] == game.factions[0].name,
		"monopoly triggers exactly on the tenth qualifying turn")
	game.resources.sol = 1
	game.ai.ai_resources[1].sol = 99
	game.network_sol_generated = {0: 1, 1: 99}
	game.update_victories()
	check(game.monopoly_turns == 0, "monopoly progress resets when share falls to 80% or below")


func _test_save_continuation() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 7105, "rust_tech")
	game.diplomacy[1] = "war"
	for i in range(4):
		game.end_turn()
	var path := "user://fair_rival_continuation.json"
	check(game.save_to_file(path), "Fair Rival v4 save writes")
	var saved_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved_data is Dictionary and game._validate_save_data(saved_data),
		"Fair Rival v4 save validates before load")
	for i in range(6):
		game.end_turn()
	var expected := _snapshot()
	check(game.load_from_file(path), "Fair Rival v4 save loads")
	for i in range(6):
		game.end_turn()
	var actual := _snapshot()
	for key in expected:
		check(actual[key] == expected[key],
			"save/load resumes exact %s continuation" % key)


func _test_small_pangaea_soak() -> void:
	var started := Time.get_ticks_msec()
	var threatening_seeds := 0
	for seed in range(7200, 7210):
		game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, "rust_tech")
		var previous_positions := _ai_positions()
		var moved_turns := 0
		var rivalry_reached_war := false
		var initial_activity := _ai_activity_signature()
		var initial_distance := _closest_ai_to_player_city()
		var closest_distance := initial_distance
		for step in range(50):
			game.end_turn()
			var positions := _ai_positions()
			if positions != previous_positions:
				moved_turns += 1
			previous_positions = positions
			rivalry_reached_war = rivalry_reached_war or game.diplomatic_status(1) == "war"
			closest_distance = mini(closest_distance, _closest_ai_to_player_city())
			var state_error := _state_error()
			if state_error != "":
				check(false, "soak seed %d turn %d: %s" % [seed, step + 1, state_error])
				break
		check(moved_turns >= 2, "soak seed %d has repeated AI movement" % seed)
		check(_ai_activity_signature() != initial_activity,
			"soak seed %d has real economy/production/research change" % seed)
		check(rivalry_reached_war, "soak seed %d reaches autonomous hostility" % seed)
		if closest_distance < initial_distance:
			threatening_seeds += 1
	check(threatening_seeds >= 5,
		"at least half of certified seeds produce a measurable AI threat (%d/10)" % threatening_seeds)
	var elapsed := Time.get_ticks_msec() - started
	check(elapsed < 20000, "10-seed x 50-turn soak stays below 20s (actual %dms)" % elapsed)
	print("FAIR_RIVAL_SOAK_MS=%d" % elapsed)


func _prepare_fixture(seed: int) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, "rust_tech")
	game.units.clear()
	game.cities.clear()
	game.grid.clear_occupants()
	for x in game.grid.w:
		for y in game.grid.h:
			game.grid.terrain[x][y] = "wasteland"
	game.ai.ai_resources.clear()
	game.ai.ai_tech.clear()
	game.event_active = ""
	game.next_event_turn = 1000000


func _add_city(faction_idx: int, cell: Vector2i) -> City:
	return game._found_city_at(cell, faction_idx)


func _add_unit(type_id: String, faction_idx: int, cell: Vector2i) -> Unit:
	var unit := Unit.new(type_id, faction_idx, cell, game.grid)
	game.units.append(unit)
	game.grid.place_occupant(cell.x, cell.y, unit)
	return unit


func _state_error() -> String:
	var expected := {}
	for unit in game.units:
		if expected.has(unit.cell):
			return "duplicate unit cell %s" % unit.cell
		if game.grid.occupant_at(unit.cell.x, unit.cell.y) != unit:
			return "unit occupancy mismatch at %s" % unit.cell
		expected[unit.cell] = true
		if unit.faction_id != game.BARB_FACTION and (unit.faction_id < 0 or unit.faction_id >= game.factions.size()):
			return "invalid unit faction %d" % unit.faction_id
	for city in game.cities:
		if expected.has(city.cell):
			return "duplicate city cell %s" % city.cell
		if game.grid.occupant_at(city.cell.x, city.cell.y) != city:
			return "city occupancy mismatch at %s" % city.cell
		expected[city.cell] = true
		if city.faction_id < 0 or city.faction_id >= game.factions.size() \
				or city.faction != game.factions[city.faction_id]:
			return "invalid city faction at %s idx=%d actual=%s expected=%s" % [
				city.cell, city.faction_id,
				city.faction.id if city.faction != null else "null",
				game.factions[city.faction_id].id if city.faction_id >= 0 \
						and city.faction_id < game.factions.size() else "invalid"]
	for treasury in game.ai.ai_resources.values():
		for key in Data.START_RESOURCES:
			if not treasury.has(key) or not (treasury[key] is int or treasury[key] is float):
				return "invalid treasury field %s" % key
	return ""


func _snapshot() -> Dictionary:
	return {
		"turn": game.turn,
		"rng": str(game._rng.state),
		"units": game._serialize_units(),
		"cities": game._serialize_cities(),
		"ai": game._serialize_ai(),
		"ai_tech": game.ai.serialize_tech(),
		"diplomacy": game.diplomacy,
		"ping": game.ping,
	}


func _ai_positions() -> Array:
	var positions := []
	for unit in game.units:
		if unit.faction_id == 1:
			positions.append([unit.type_id, unit.cell.x, unit.cell.y])
	return positions


func _ai_activity_signature() -> String:
	var treasury: Dictionary = game.ai.ai_resources.get(1, Data.START_RESOURCES)
	var build_progress := 0
	for city in game.cities:
		if city.faction_id == 1:
			build_progress += city.scrap_stock + city.buildings.size() * 100
	var manager: TechManager = game.ai._tech(1)
	return "%s|%d|%d|%d|%d" % [
		JSON.stringify(treasury), build_progress, manager.points,
		manager.researched.size(), game.units_of_faction(1).size()]


func _closest_ai_to_player_city() -> int:
	var best := 1 << 30
	for unit in game.units:
		if unit.faction_id != 1:
			continue
		for city in game.cities:
			if city.faction_id == 0:
				best = mini(best, absi(unit.cell.x - city.cell.x) + absi(unit.cell.y - city.cell.y))
	return best


func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIR_RIVAL_FAIL: " + message)
