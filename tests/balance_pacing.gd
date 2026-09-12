extends SceneTree
## Bootstrap, Monopoly legitimacy, and bounded deterministic pacing contracts.

const FOUR_FACTIONS := ["rust_tech", "global_net", "bio", "steel"]
const MATRIX_MATCHES := 10
const MATRIX_TURNS := 200

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_bootstrap_power()
	_test_monopoly_participation_gate()
	_test_pacing_matrix()
	_test_deterministic_replay()
	print("BALANCE_PACING_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_bootstrap_power() -> void:
	check(int(Data.BUILDINGS.genesis_node.energy_gen) == 3,
		"Genesis Node has the minimal three-Energy early civic bootstrap")
	for seed in range(9600, 9608):
		var player_id: String = FOUR_FACTIONS[seed % FOUR_FACTIONS.size()]
		var roster: Array = [player_id]
		for faction_id in FOUR_FACTIONS:
			if faction_id != player_id:
				roster.append(faction_id)
		game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, player_id, roster)
		for faction_idx in range(game.factions.size()):
			var state: Dictionary = game._faction_energy_grid_state(faction_idx)
			check(not state.cities.is_empty() and int(state.available_energy) > 0,
				"seed %d faction %d starts with an operational energy component" % [seed, faction_idx])
			for city in state.cities:
				check(bool(state.powered.get(city, false)),
					"seed %d faction %d capital is powered" % [seed, faction_idx])


func _test_monopoly_participation_gate() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 9700,
		FOUR_FACTIONS[0], FOUR_FACTIONS)
	game.resources.sol = Data.MONOPOLY_MIN_NETWORK_SOL * 2
	game.network_sol_generated = {0: Data.MONOPOLY_MIN_NETWORK_SOL * 2, 1: 0, 2: 0, 3: 0}
	for faction_idx in range(1, game.factions.size()):
		game.ai.ai_resources[faction_idx] = {"scrap": 0, "biomass": 0, "energy": 0, "sol": 0}
	for step in range(12):
		check(not game.update_victories(), "one treasury cannot certify a network Monopoly")
	check(int(game.monopoly_progress[0]) == 0, "single-participant Monopoly makes no progress")
	game.resources.sol = 81
	game.ai.ai_resources[1].sol = 18
	game.network_sol_generated = {0: 81, 1: 18, 2: 0, 3: 0}
	for step in range(12):
		check(not game.update_victories(), "subscale network cannot certify Monopoly")
	check(int(game.monopoly_progress[0]) == 0, "subscale Monopoly makes no progress")
	game.ai.ai_resources[1].sol = 19
	game.network_sol_generated[1] = 19
	for step in range(9):
		check(not game.update_victories(), "legitimate Monopoly still requires ten turns")
	check(game.update_victories(), "81 of 100 contested SOL certifies on turn ten")


func _test_pacing_matrix() -> void:
	var started := Time.get_ticks_msec()
	var resolved := 0
	var premature_victories := 0
	var stalled_survivors := 0
	for offset in range(MATRIX_MATCHES):
		var roster: Array = FOUR_FACTIONS.slice(0, 3 if offset % 2 == 0 else 4)
		var outcome := _play_match(9800 + offset, roster, MATRIX_TURNS)
		if outcome.victory != "":
			resolved += 1
		if outcome.victory != "" and int(outcome.turn) < 30:
			premature_victories += 1
		stalled_survivors += int(outcome.stalled_survivors)
		# Each faction starts with one city and one founder; capture may concentrate
		# that fixed map total under a decisive winner without creating new sprawl.
		check(int(outcome.max_cities) <= roster.size() * 2,
			"matrix seed %d bounds cities by the fixed founder pool" % (9800 + offset))
		check(int(outcome.max_units) <= 20, "matrix seed %d bounds units per faction" % (9800 + offset))
	check(premature_victories == 0, "matrix has no victory before turn 30")
	check(stalled_survivors == 0, "every surviving AI reaches real economy and Era I")
	check(resolved >= 6 and resolved <= 10,
		"60-100%% of the bounded matrix resolves by turn %d (actual %d/%d)" \
		% [MATRIX_TURNS, resolved, MATRIX_MATCHES])
	var elapsed := Time.get_ticks_msec() - started
	check(elapsed < 60000, "10-match x 200-turn matrix stays below 60s (%dms)" % elapsed)
	print("BALANCE_PACING_MATRIX resolved=%d/%d runtime_ms=%d" % [resolved, MATRIX_MATCHES, elapsed])


func _test_deterministic_replay() -> void:
	var roster: Array = FOUR_FACTIONS.slice(0, 3)
	var first := _play_match(9900, roster, 100)
	var second := _play_match(9900, roster, 100)
	if first != second:
		for key in first:
			if first[key] != second[key]:
				print("BALANCE_DETERMINISM_DIFF %s first=%s second=%s" % [key, JSON.stringify(first[key]), JSON.stringify(second[key])])
	check(first == second, "same seed reproduces the complete 100-turn pacing snapshot")


func _play_match(seed: int, roster: Array, turn_limit: int) -> Dictionary:
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, roster[0], roster)
	var victory := {"name": "", "reason": ""}
	var handler := func(name: String, reason: String):
		victory.name = name
		victory.reason = reason
	game.game_over.connect(handler)
	while int(game.turn) <= turn_limit and victory.reason == "":
		game.end_turn()
	if game.game_over.is_connected(handler):
		game.game_over.disconnect(handler)
	var stalled_survivors := 0
	var max_cities := 0
	var max_units := 0
	for faction_idx in range(game.factions.size()):
		var cities := 0
		for city in game.cities:
			if city.faction_id == faction_idx: cities += 1
		var units: int = game.units_of_faction(faction_idx).size()
		max_cities = maxi(max_cities, cities)
		max_units = maxi(max_units, units)
		if faction_idx > 0 and cities > 0:
			var res: Dictionary = game.ai.ai_resources.get(faction_idx, {})
			var reached_era_one := false
			for tech_id in game.ai._tech(faction_idx).researched:
				if int(Data.TECHS[tech_id].era) >= 1: reached_era_one = true
			if int(res.get("biomass", 0)) <= int(Data.START_RESOURCES.biomass) or not reached_era_one:
				stalled_survivors += 1
	return {
		"turn": int(game.turn) - 1,
		"victory": _victory_type(str(victory.reason)),
		"winner": str(victory.name),
		"stalled_survivors": stalled_survivors,
		"max_cities": max_cities,
		"max_units": max_units,
		"units": game._serialize_units(),
		"cities": _gameplay_cities(),
		"ai": game._serialize_ai(),
		"tech": game.ai.serialize_tech(),
		"relations": game._serialize_relations(false),
		"rng": str(game._rng.state),
	}


func _gameplay_cities() -> Array:
	var out: Array = game._serialize_cities()
	for city in out:
		city.erase("name")
	return out


func _victory_type(reason: String) -> String:
	if "Monopoly" in reason: return "monopoly"
	if reason == "": return ""
	return "domination" if "validators controlled" in reason or "nodes were lost" in reason \
		or "captured" in reason else "other"


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("BALANCE_PACING_FAIL: " + message)
