extends SceneTree
## Multi-Rival v1 pairwise, agenda, migration, victory, and soak contracts.

var failures := 0
var game: Node
const ROSTER := ["rust_tech", "global_net", "bio", "steel"]


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_roster_and_relations()
	_test_pairwise_threat_isolation()
	_test_pairwise_emp_parity()
	_test_agendas_and_capture()
	_test_ai_monopoly()
	_test_v4_migration_and_v5_continuation()
	_test_four_faction_soak()
	print("MULTI_RIVAL_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_roster_and_relations() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 8101, ROSTER[0], ROSTER)
	check(game._faction_ids() == ROSTER and game.faction_id == 0,
		"four-faction roster is unique, deterministic, and player-first")
	check(game.cities.size() == 4, "every faction receives one starting city")
	var start_component := _reachable_cells(game.cities[0].cell)
	for city in game.cities:
		check(start_component.has(city.cell), "all Pangaea rivals start on one traversable landmass")
	game.set_relation(1, 2, "war")
	check(game.are_factions_at_war(1, 2), "AI-to-AI war is symmetric")
	check(not game.are_factions_at_war(0, 1) and not game.are_factions_at_war(0, 2)
		and not game.are_factions_at_war(1, 3), "one pair's war does not leak to other pairs")
	game.set_relation_ping(2, 3, 17)
	check(game.relation_ping(2, 3) == 17 and game.relation_ping(3, 2) == 17
		and game.relation_ping(0, 3) == 50, "pairwise Ping is symmetric and isolated")


func _test_agendas_and_capture() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 8102, ROSTER[0], ROSTER)
	check(game.ai.agenda_for(1, game.factions) == "Validator"
		and game.ai.agenda_for(2, game.factions) == "Builder"
		and game.ai.agenda_for(3, game.factions) == "Conqueror",
		"identity selects the three deterministic agendas")
	var builder := TechManager.new()
	var validator := TechManager.new()
	var res_a := {"scrap": 100, "biomass": 100, "energy": 100, "sol": 100}
	var res_b := res_a.duplicate()
	game.ai._choose_research(builder, res_a, "Builder")
	game.ai._choose_research(validator, res_b, "Validator")
	check(builder.current != validator.current,
		"same legal state diverges by agenda priority without resource multipliers")
	var city: City = null
	for candidate in game.cities:
		if candidate.faction_id == 2:
			city = candidate
			break
	check(city != null and game.capture_city(city, 3) and city.faction_id == 3
		and city.faction == game.factions[3], "AI-to-AI capture transfers ownership safely")
	check(_occupancy_error() == "", "four-faction capture preserves unique occupancy")


func _test_pairwise_threat_isolation() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 8110, ROSTER[0], ROSTER)
	game.units.clear()
	game.cities.clear()
	game.grid.clear_occupants()
	var city: City = game._found_city_at(Vector2i(10, 10), 0)
	var visitor := Unit.new("rust_guard", 1, Vector2i(12, 10), game.grid)
	game.units.append(visitor)
	game.grid.place_occupant(12, 10, visitor)
	game.set_relation(0, 1, "peace")
	game.set_relation(1, 2, "war")
	check(not game._faction_under_threat(0),
		"peaceful nearby AI and its unrelated war do not create player fatigue")
	game.set_relation(0, 1, "alliance")
	check(not game._faction_under_threat(0), "allied nearby AI does not create fatigue")
	game.set_relation(0, 1, "war")
	check(game._faction_under_threat(0), "only the exact hostile nearby pair creates fatigue")
	check(city != null, "pairwise threat fixture city exists")


func _test_pairwise_emp_parity() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 8111, ROSTER[0], ROSTER)
	game.units.clear()
	game.cities.clear()
	game.grid.clear_occupants()
	var target := Unit.new("rust_guard", 1, Vector2i(10, 10), game.grid)
	var acolyte := Unit.new("cyber_acolyte", 2, Vector2i(11, 10), game.grid)
	game.units.append_array([target, acolyte])
	game.grid.place_occupant(10, 10, target)
	game.grid.place_occupant(11, 10, acolyte)
	game.set_relation(1, 2, "peace")
	game.reset_unit_moves_with_emp(target)
	check(target.moves_left == target.max_moves(), "peaceful EMP neighbor does not penalize AI movement")
	game.set_relation(1, 2, "war")
	game.reset_unit_moves_with_emp(target)
	check(target.moves_left == target.max_moves() - 1,
		"hostile EMP applies the same reset penalty to an AI faction")


func _test_ai_monopoly() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 8103, ROSTER[0], ROSTER)
	game.resources.sol = 1
	game.ai.ai_resources[1] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 90}
	game.ai.ai_resources[2] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 5}
	game.ai.ai_resources[3] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 4}
	game.network_sol_generated = {0: 1, 1: 90, 2: 5, 3: 4}
	var winner := [""]
	game.game_over.connect(func(name: String, _reason: String): winner[0] = name, CONNECT_ONE_SHOT)
	for step in range(9):
		check(not game.update_victories(), "AI monopoly waits ten qualifying turns")
	check(game.update_victories() and winner[0] == game.factions[1].name,
		"AI can certify the existing nonmilitary Validator Monopoly route")


func _test_v4_migration_and_v5_continuation() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 8104, ROSTER[0], ROSTER)
	game.set_relation(0, 1, "war")
	game.set_relation(2, 3, "war")
	for step in range(3): game.end_turn()
	var v5_path := "user://multi_rival_v5.json"
	check(game.save_to_file(v5_path), "v5 save writes")
	var v5: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(v5_path))
	var v4 := v5.duplicate(true)
	v4.version = 4
	v4.erase("ai_agendas")
	v4.erase("monopoly_progress")
	v4.diplomacy = {"1": "war", "2": "peace", "3": "peace"}
	v4.ping = {"1": 31, "2": 52, "3": 73}
	var v4_path := "user://multi_rival_v4.json"
	var legacy := FileAccess.open(v4_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify(v4))
	legacy.close()
	check(game.load_from_file(v4_path), "v4 player-centric diplomacy migrates to v5 pair state")
	check(game.relation_status(0, 1) == "war" and game.relation_ping(0, 3) == 73
		and game.relation_status(2, 3) == "peace", "migration preserves player pairs and safely defaults AI pairs")
	check(game.ai.serialize_agendas().size() == 3, "migration deterministically restores all AI agendas")
	check(game.load_from_file(v5_path), "v5 baseline reloads")
	for step in range(6): game.end_turn()
	var expected := _snapshot()
	check(game.load_from_file(v5_path), "v5 continuation reloads")
	for step in range(6): game.end_turn()
	check(_snapshot() == expected, "v5 save/load continues the full multi-rival state exactly")


func _test_four_faction_soak() -> void:
	var started := Time.get_ticks_msec()
	for seed in range(8200, 8210):
		game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, ROSTER[0], ROSTER)
		var initial := _ai_activity()
		var previous_positions := _positions_by_faction()
		var moved_turns := {1: 0, 2: 0, 3: 0}
		var early_winner := false
		game.game_over.connect(func(_name: String, _reason: String):
			if game.turn < 20: early_winner = true)
		for step in range(100):
			game.end_turn()
			var positions := _positions_by_faction()
			for faction_idx in range(1, 4):
				if positions[faction_idx] != previous_positions[faction_idx]:
					moved_turns[faction_idx] += 1
			previous_positions = positions
			var error := _occupancy_error()
			if error != "":
				check(false, "soak seed %d turn %d: %s" % [seed, step + 1, error])
				break
		check(not early_winner, "soak seed %d has no premature victory" % seed)
		var final := _ai_activity()
		for faction_idx in range(1, 4):
			check(initial[faction_idx] != final[faction_idx],
				"soak seed %d faction %d does not stalemate" % [seed, faction_idx])
			if _city_count(faction_idx) > 0 and not game.units_of_faction(faction_idx).is_empty():
				check(int(moved_turns[faction_idx]) >= 2,
					"soak seed %d surviving faction %d has repeated map movement" % [seed, faction_idx])
	var elapsed := Time.get_ticks_msec() - started
	check(elapsed < 45000,
		"10-seed x 100-turn active four-faction soak stays below 45s (%dms)" % elapsed)
	print("MULTI_RIVAL_SOAK_MS=%d" % elapsed)


func _ai_activity() -> Dictionary:
	var out := {}
	for faction_idx in range(1, game.factions.size()):
		out[faction_idx] = "%s|%s|%d|%d" % [JSON.stringify(game.ai.ai_resources.get(faction_idx, {})),
			JSON.stringify(game.ai.serialize_tech().get(str(faction_idx), {})),
			game.units_of_faction(faction_idx).size(), _city_count(faction_idx)]
	return out


func _city_count(faction_idx: int) -> int:
	var count := 0
	for city in game.cities:
		if city.faction_id == faction_idx: count += 1
	return count


func _positions_by_faction() -> Dictionary:
	var out := {1: [], 2: [], 3: []}
	for unit in game.units:
		if out.has(unit.faction_id):
			out[unit.faction_id].append([unit.type_id, unit.cell.x, unit.cell.y])
	for faction_idx in out:
		out[faction_idx].sort()
	return out


func _reachable_cells(origin: Vector2i) -> Dictionary:
	var seen := {origin: true}
	var cells := [origin]
	var cursor := 0
	while cursor < cells.size():
		var cell: Vector2i = cells[cursor]
		cursor += 1
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if not seen.has(next) and game.grid.in_bounds(next.x, next.y) \
					and game.grid.is_land(next.x, next.y) \
					and not bool(game.grid.terrain_data(next.x, next.y).get("impassable", false)):
				seen[next] = true
				cells.append(next)
	return seen


func _occupancy_error() -> String:
	var occupied := {}
	for unit in game.units:
		if occupied.has(unit.cell): return "duplicate at %s" % unit.cell
		if game.grid.occupant_at(unit.cell.x, unit.cell.y) != unit:
			return "unit grid mismatch faction=%d type=%s cell=%s occupant=%s" % [unit.faction_id, unit.type_id, unit.cell, game.grid.occupant_at(unit.cell.x, unit.cell.y)]
		occupied[unit.cell] = true
	for city in game.cities:
		if occupied.has(city.cell): return "duplicate at %s" % city.cell
		if game.grid.occupant_at(city.cell.x, city.cell.y) != city: return "city grid mismatch"
		if city.faction_id < 0 or city.faction_id >= game.factions.size() \
				or city.faction != game.factions[city.faction_id]: return "invalid city owner"
		occupied[city.cell] = true
	return ""


func _snapshot() -> Dictionary:
	return {"turn": game.turn, "rng": str(game._rng.state), "units": game._serialize_units(),
		"cities": game._serialize_cities(), "ai": game._serialize_ai(),
		"tech": game.ai.serialize_tech(), "agendas": game.ai.serialize_agendas(),
		"diplomacy": game._serialize_relations(false), "ping": game._serialize_relations(true),
		"monopoly": game.monopoly_progress.duplicate(true)}


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("MULTI_RIVAL_FAIL: " + message)
