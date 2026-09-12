extends SceneTree
## Focused contracts for bounded war, capture stabilization, minted-SOL Monopoly,
## complete AI research, and current-schema deterministic save continuation.

const ROSTER := ["rust_tech", "global_net", "bio", "steel"]
var game: Node
var failures := 0


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_ceasefire_and_pair_isolation()
	_test_occupation_parity()
	_test_secured_target_filter()
	_test_nearest_war_enemy_equivalence()
	_test_cityless_diplomacy_filter()
	_test_single_search_path_orders()
	_test_minted_monopoly()
	_test_nonproduction_sol_excluded()
	_test_complete_ai_research()
	_test_v5_migration_and_current_continuation()
	print("STRATEGIC_ARC_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _start(seed: int = 99101) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, ROSTER[0], ROSTER)


func _test_ceasefire_and_pair_isolation() -> void:
	_start()
	game.set_relation(1, 2, "war")
	game.set_relation(2, 3, "war")
	game.war_exhaustion["1:2"] = game.WAR_EXHAUSTION_LIMIT - 1
	game.war_exhaustion["2:3"] = 4
	game._advance_strategic_state()
	check(game.relation_status(1, 2) == "peace" and game.war_exhaustion["1:2"] == -game.CEASEFIRE_TURNS,
		"war exhaustion creates an exact deterministic ceasefire")
	check(game.relation_status(2, 3) == "war" and game.war_exhaustion["2:3"] == 5,
		"ceasefire is isolated from an unrelated pair")
	check(not game.can_start_war(1, 2), "pair cannot restart war during secured ceasefire")
	for _turn in game.CEASEFIRE_TURNS:
		game._advance_strategic_state()
	check(game.can_start_war(1, 2), "same pair may restart war after exact cooldown")
	game.set_relation(1, 2, "war")
	check(game.are_factions_at_war(1, 2), "war can restart after exhaustion recovery")


func _test_occupation_parity() -> void:
	_start(99102)
	var player_city: City = _city_of(0)
	var rival_city: City = _city_of(1)
	check(game.capture_city(rival_city, 0) \
			and game.occupation_remaining(rival_city) == game.OCCUPATION_TURNS,
		"player capture receives the same visible stabilization")
	check(not game.capture_city(rival_city, 1), "rival cannot immediately recapture secured city")
	game._advance_strategic_state()
	check(game.capture_city(player_city, 2), "AI capture path accepts an unsecured player city")
	check(player_city.occupation_until_turn == rival_city.occupation_until_turn,
		"player and AI captures in one global turn share the same absolute expiry")
	check(not game.capture_city(player_city, 0), "player cannot bypass the same secured period")
	for expected in range(game.OCCUPATION_TURNS - 1, 0, -1):
		game.turn += 1
		game._advance_strategic_state()
		check(game.occupation_remaining(rival_city) == expected \
				and game.occupation_remaining(player_city) == expected,
			"both owners retain identical duration across action-phase processing")
	game.turn += 1
	check(game.occupation_remaining(rival_city) == 0 \
			and game.occupation_remaining(player_city) == 0,
		"both secured states expire on the same absolute turn")
	check(game.capture_city(rival_city, 1) and game.capture_city(player_city, 0),
		"both ownership directions reopen together after expiry")


func _test_secured_target_filter() -> void:
	_start(99107)
	game.grid.clear_occupants()
	game.units.clear()
	game.cities.clear()
	var near := City.new("Near Secured", 1, game.factions[1], Vector2i(10, 10), game.grid)
	var far := City.new("Far Open", 1, game.factions[1], Vector2i(20, 10), game.grid)
	near.occupation_until_turn = game.turn + 2
	game.cities.assign([near, far])
	game.grid.place_occupant(near.cell.x, near.cell.y, near)
	game.grid.place_occupant(far.cell.x, far.cell.y, far)
	check(game.ai._nearest_enemy_cell(game, Vector2i(9, 10), 1) == far.cell,
		"AI skips a nearer SECURED city for a farther legal target")
	game.grid.clear_occupant(far.cell.x, far.cell.y, far)
	game.cities.erase(far)
	check(game.ai._nearest_enemy_cell(game, Vector2i(9, 10), 1) == Vector2i(-1, -1),
		"AI has no target when every enemy city is SECURED")
	var defender := Unit.new("rust_guard", 1, Vector2i(14, 10), game.grid)
	game.units.append(defender)
	game.grid.place_occupant(defender.cell.x, defender.cell.y, defender)
	check(game.ai._nearest_enemy_cell(game, Vector2i(9, 10), 1) == defender.cell,
		"enemy units remain targetable while their city is SECURED")
	game.grid.clear_occupant(defender.cell.x, defender.cell.y, defender)
	game.units.erase(defender)
	game.turn = near.occupation_until_turn
	check(game.ai._nearest_enemy_cell(game, Vector2i(9, 10), 1) == near.cell,
		"SECURED city becomes targetable on its exact expiry turn")


func _test_nearest_war_enemy_equivalence() -> void:
	_start(99109)
	game.grid.clear_occupants()
	game.units.clear()
	game.cities.clear()
	var origin := Vector2i(10, 10)
	var lower_city := City.new("Lower", 1, game.factions[1], Vector2i(15, 10), game.grid)
	var higher_unit := Unit.new("rust_guard", 2, Vector2i(12, 10), game.grid)
	game.cities.append(lower_city)
	game.units.append(higher_unit)
	game.set_relation(0, 1, "war")
	game.set_relation(0, 2, "war")
	check(game.ai._nearest_war_enemy(game, origin, 0) == 2,
		"closer higher-ID hostile faction beats farther lower-ID faction")
	lower_city.cell = Vector2i(8, 10)
	game.cities.reverse()
	game.units.reverse()
	check(game.ai._nearest_war_enemy(game, origin, 0) == 1,
		"equal distance chooses lower faction across mixed targets and array order")
	game.set_relation(0, 1, "peace")
	check(game.ai._nearest_war_enemy(game, origin, 0) == 2,
		"peaceful nearer target is ignored")
	game.set_relation(0, 1, "war")
	lower_city.cell = Vector2i(11, 10)
	lower_city.occupation_until_turn = game.turn + 1
	higher_unit.faction_id = 1
	higher_unit.cell = Vector2i(14, 10)
	check(game.ai._nearest_war_enemy(game, origin, 0) == 1,
		"SECURED city is ignored while its faction unit remains eligible")
	game.set_relation(0, 1, "peace")
	check(game.ai._nearest_war_enemy(game, origin, 0) == -1,
		"one-pass hostile scan returns no target when none is at war")


func _test_cityless_diplomacy_filter() -> void:
	_start(99108)
	for city in game.cities.duplicate():
		if city.faction_id == 1:
			game.grid.clear_occupant(city.cell.x, city.cell.y, city)
			game.cities.erase(city)
	game.set_relation(1, 2, "peace")
	game.set_relation_ping(1, 2, 20)
	game.ai._update_relations(1, "Conqueror", game)
	check(game.relation_ping(1, 2) == 20 and game.relation_status(1, 2) == "peace",
		"cityless acting faction cannot restart diplomacy")
	game.ai._update_relations(2, "Conqueror", game)
	check(game.relation_ping(1, 2) == 20 and game.relation_status(1, 2) == "peace",
		"living faction skips a cityless diplomatic counterpart")
	game.set_relation(2, 3, "peace")
	game.set_relation_ping(2, 3, 50)
	game.ai._update_relations(2, "Conqueror", game)
	check(game.relation_ping(2, 3) == 49,
		"living factions still process their diplomacy normally")
	game.set_relation(1, 2, "war")
	var stranded: Unit = null
	for unit in game.units:
		if unit.faction_id == 1:
			stranded = unit
			break
	check(stranded != null and game.ai._nearest_war_enemy(game, stranded.cell, 1) == 2,
		"cityless units retain existing war orders against living enemies")
	if stranded != null:
		var before_cell := stranded.cell
		game.ai.take_turn(1, game)
		check(not game.units.has(stranded) or stranded.cell != before_cell \
				or stranded.moves_left < stranded.max_moves(),
			"cityless faction still executes its stranded unit turn")


func _test_single_search_path_orders() -> void:
	_start(99110)
	var original_grid: GridManager = game.grid
	var route_grid := GridManager.new(7, 7)
	for x in route_grid.w:
		for y in route_grid.h:
			route_grid.terrain[x][y] = "wasteland"
			route_grid.occupant[x][y] = null
	game.grid = route_grid
	var straight: Array[Vector2i] = game.ai._path_steps(game, Vector2i(1, 1), Vector2i(5, 1))
	check(straight == [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)],
		"one search reconstructs the exact straight route to target adjacency")
	check(game.ai._next_path_step(game, Vector2i(1, 1), Vector2i(5, 1)) == straight[0],
		"single-step path contract remains a wrapper over the same route")
	check(game.ai._path_steps(game, Vector2i(4, 1), Vector2i(5, 1)).is_empty(),
		"already adjacent attacker needs no movement route")
	var tied: Array[Vector2i] = game.ai._path_steps(game, Vector2i(1, 1), Vector2i(3, 3))
	check(tied == [Vector2i(2, 1), Vector2i(2, 2)],
		"equal routes retain the declared direction-order tie break")
	var blocker := RefCounted.new()
	route_grid.place_occupant(2, 1, blocker)
	var detour: Array[Vector2i] = game.ai._path_steps(game, Vector2i(1, 1), Vector2i(5, 1))
	check(detour == [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
		"occupied intermediate cells remain blockers for the complete route")
	route_grid.clear_occupant(2, 1, blocker)
	for cell in [Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1)]:
		route_grid.terrain[cell.x][cell.y] = "mountains"
	check(game.ai._path_steps(game, Vector2i(1, 1), Vector2i(5, 1)).is_empty(),
		"fully blocked origin produces no route")
	for cell in [Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1)]:
		route_grid.terrain[cell.x][cell.y] = "wasteland"
	for y in route_grid.h:
		route_grid.terrain[3][y] = "mountains"
	check(game.ai._path_steps(game, Vector2i(1, 1), Vector2i(5, 1)) == [Vector2i(2, 1)],
		"unreachable target preserves the closest-progress fallback")
	for y in route_grid.h:
		route_grid.terrain[3][y] = "wasteland"
	var mover := Unit.new("rust_guard", 1, Vector2i(1, 1), route_grid)
	route_grid.place_occupant(mover.cell.x, mover.cell.y, mover)
	game.ai._move_along_path(game, mover, Vector2i(5, 1))
	check(mover.cell == Vector2i(3, 1) and mover.moves_left <= 0.001,
		"multi-step order consumes movement without searching after every step")
	var long_grid := GridManager.new(270, 3)
	for x in long_grid.w:
		for y in long_grid.h:
			long_grid.terrain[x][y] = "wasteland" if y == 1 else "mountains"
			long_grid.occupant[x][y] = null
			long_grid.infra[x][y] = 2 if y == 1 else 0
	game.grid = long_grid
	var fast := Unit.new("miner_quad", 1, Vector2i(0, 1), long_grid)
	long_grid.place_occupant(fast.cell.x, fast.cell.y, fast)
	game.ai._move_along_path(game, fast, Vector2i(269, 1))
	check(fast.cell == Vector2i(268, 1),
		"movement continues in deterministic segments beyond one search limit")
	game.grid = original_grid


func _test_minted_monopoly() -> void:
	_start(99103)
	game.resources.sol = 10000
	game.ai._resources(1).sol = 1
	game.network_sol_generated = {0: 0, 1: 0, 2: 0, 3: 0}
	for _turn in 12:
		check(not game.update_victories(), "idle treasury hoard cannot certify Monopoly")
	check(game.monopoly_progress[0] == 0, "idle hoard makes no Monopoly progress")

	game.network_sol_generated = {0: 90, 1: 20, 2: 0, 3: 0}
	game.resources.sol = 0
	for _turn in 9:
		check(not game.update_victories(), "real minted share still holds for ten turns")
	# Spending treasury does not rewrite historical production share.
	game.resources.sol = -50
	var winner := [""]
	game.game_over.connect(func(name: String, _reason: String): winner[0] = name, CONNECT_ONE_SHOT)
	check(game.update_victories() and winner[0] == game.factions[0].name,
		"81% minted share wins on turn ten regardless of treasury spending")


func _test_nonproduction_sol_excluded() -> void:
	_start(99106)
	var before: Dictionary = game.network_sol_generated.duplicate(true)
	game.resources.scrap = 100
	check(game.trade_resources(1, false), "trade fixture creates treasury SOL")
	var lair: Vector2i = game.lairs[0]
	check(game.capture_lair(lair), "lair fixture grants treasury loot")
	var looter := Unit.new("armored_courier", 0, Vector2i.ZERO, game.grid)
	var killed := Unit.new("rust_guard", 1, Vector2i.ONE, game.grid)
	game.on_kill(looter, killed)
	var terminal_rng := RandomNumberGenerator.new()
	for candidate in 10000:
		terminal_rng.seed = candidate
		var roll := terminal_rng.randf()
		if roll >= 0.15 and roll < 0.40:
			game._rng.seed = candidate
			break
	var terminal := Vector2i(1, 1)
	game.terminals = [terminal]
	game.activate_terminal(looter, terminal)
	check(game.network_sol_generated == before,
		"trade, lair loot, kill loot, and terminal windfalls are not network production")


func _test_complete_ai_research() -> void:
	_start(99104)
	for agenda in game.ai.AGENDAS:
		var manager := TechManager.new()
		var res := {"scrap": 0, "biomass": 0, "energy": 0, "sol": 10000}
		for _step in Data.TECHS.size():
			game.ai._choose_research(manager, res, agenda)
			check(manager.current != "", "%s always chooses a legal remaining technology" % agenda)
			if manager.current == "":
				break
			manager.add_points(manager.research_cost(manager.current))
		check(manager.researched.size() == Data.TECHS.size(),
			"%s research order covers all %d technologies" % [agenda, Data.TECHS.size()])
		check(manager.current_era() == 4, "%s reaches Era IV without discounts" % agenda)


func _test_v5_migration_and_current_continuation() -> void:
	_start(99105)
	var path := "user://strategic_arc_current.json"
	game.network_sol_generated = {0: 40, 1: 70, 2: 2, 3: 1}
	game.war_exhaustion["0:1"] = 7
	_city_of(1).occupation_until_turn = game.turn + 2
	check(game.save_to_file(path), "current-schema fixture saves")
	var original := FileAccess.get_file_as_string(path)
	var v5: Dictionary = JSON.parse_string(original)
	v5.version = 5
	v5.erase("network_sol_generated")
	v5.erase("war_exhaustion")
	for city_data in v5.cities:
		city_data.erase("occupation_until")
	v5.monopoly_progress = {"0": 9, "1": 0, "2": 0, "3": 0}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v5))
	file.close()
	check(game.load_from_file(path), "v5 migrates into current schema")
	check(_sum_generated() == 0 and game.monopoly_progress[0] == 0,
		"legacy treasury history resets safely instead of granting false progress")
	check(game.occupation_remaining(_city_of(1)) == 0 and game.war_exhaustion["0:1"] == 0,
		"legacy strategic cooldowns migrate to neutral defaults")

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	check(game.load_from_file(path), "current-schema fixture reloads")
	var expected_state := [game.network_sol_generated.duplicate(true),
		game.war_exhaustion.duplicate(true), _city_of(1).occupation_until_turn]
	game.end_turn()
	var expected_continuation := _signature()
	check(game.load_from_file(path), "current-schema fixture reloads for deterministic continuation")
	check([game.network_sol_generated, game.war_exhaustion, _city_of(1).occupation_until_turn] == expected_state,
		"current schema restores exact minted, exhaustion, and occupation state")
	game.end_turn()
	check(_signature() == expected_continuation, "current-schema next-turn continuation is exact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _city_of(owner: int) -> City:
	for city in game.cities:
		if city.faction_id == owner:
			return city
	return null


func _sum_generated() -> int:
	var total := 0
	for amount in game.network_sol_generated.values():
		total += int(amount)
	return total


func _signature() -> String:
	var owners := []
	for city in game.cities:
		owners.append([city.cell.x, city.cell.y, city.faction_id, city.occupation_until_turn])
	owners.sort()
	return JSON.stringify([game.turn, game.resources, game.ai.serialize_tech(), owners,
		game._serialize_relations(false), game.war_exhaustion, game.network_sol_generated,
		str(game._rng.state)])


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: " + message)
	else:
		failures += 1
		print("  FAIL: " + message)
