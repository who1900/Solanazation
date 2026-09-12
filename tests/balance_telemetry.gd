extends SceneTree
## Read-only deterministic balance telemetry for Small/Pangaea.

const ROSTERS := {
	3: ["rust_tech", "global_net", "steel"],
	4: ["rust_tech", "global_net", "bio", "steel"],
}
const MATCHES_PER_ROSTER := 12
const TURN_LIMIT := 300

var game: Node
var results: Array = []


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	for faction_count in [3, 4]:
		for offset in range(MATCHES_PER_ROSTER):
			results.append(_run_match(faction_count, 9100 + faction_count * 100 + offset))
	_print_report()
	quit(0)


func _run_match(faction_count: int, seed: int) -> Dictionary:
	var roster: Array = ROSTERS[faction_count]
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, seed, roster[0], roster)
	var victory := {"done": false, "winner": "", "reason": ""}
	var handler := func(winner: String, reason: String):
		victory.done = true
		victory.winner = winner
		victory.reason = reason
	game.game_over.connect(handler)
	var previous_relations := _relations()
	var previous_city_owners := _city_owners()
	var previous_signature := _strategic_signature()
	var wars := 0
	var captures := 0
	var longest_inactive := 0
	var inactive := 0
	var turn_runtime_us: Array[int] = []
	while game.turn <= TURN_LIMIT and not bool(victory.done):
		var started := Time.get_ticks_usec()
		game.end_turn()
		turn_runtime_us.append(Time.get_ticks_usec() - started)
		var relations := _relations()
		for key in relations:
			if relations[key] == "war" and previous_relations.get(key, "peace") != "war":
				wars += 1
		previous_relations = relations
		var city_owners := _city_owners()
		for key in city_owners:
			if previous_city_owners.has(key) and previous_city_owners[key] != city_owners[key]:
				captures += 1
		previous_city_owners = city_owners
		var signature := _strategic_signature()
		if signature == previous_signature:
			inactive += 1
			longest_inactive = maxi(longest_inactive, inactive)
		else:
			inactive = 0
		previous_signature = signature
	var turns_played: int = int(game.turn) - 1
	if game.game_over.is_connected(handler):
		game.game_over.disconnect(handler)
	var winner_idx := _faction_index(str(victory.winner))
	var sol_values := _resource_values("sol")
	var total_sol := 0
	for value in sol_values:
		total_sol += maxi(0, int(value))
	var max_sol := 0
	for value in sol_values:
		max_sol = maxi(max_sol, int(value))
	var unit_counts := _counts_by_faction(game.units)
	var city_counts := _counts_by_faction(game.cities)
	var total_units := _sum(unit_counts)
	var total_cities := _sum(city_counts)
	var max_units := _max_value(unit_counts)
	var max_cities := _max_value(city_counts)
	var final_relations := _relations()
	var final_wars := 0
	for status in final_relations.values():
		if status == "war": final_wars += 1
	var eras := _tech_eras()
	return {
		"seed": seed,
		"factions": faction_count,
		"turns": turns_played,
		"victory": _victory_type(str(victory.reason)) if victory.done else "none",
		"winner": winner_idx,
		"agenda": game.ai.agenda_for(winner_idx, game.factions) if winner_idx > 0 else ("Human" if winner_idx == 0 else ""),
		"cities": city_counts,
		"units": unit_counts,
		"eras": eras,
		"era4_factions": eras.count(4),
		"resources": _all_resources(),
		"sol_share": float(max_sol) / float(total_sol) if total_sol > 0 else 0.0,
		"city_concentration": float(max_cities) / float(total_cities) if total_cities > 0 else 0.0,
		"unit_concentration": float(max_units) / float(total_units) if total_units > 0 else 0.0,
		"wars": wars,
		"final_wars": final_wars,
		"all_pairs_war": final_wars == final_relations.size(),
		"captures": captures,
		"minted_sol": game.network_sol_generated.values(),
		"longest_inactive": longest_inactive,
		"runtime_ms": _sum(turn_runtime_us) / 1000.0,
		"max_turn_ms": _max_int(turn_runtime_us) / 1000.0,
	}


func _relations() -> Dictionary:
	var out := {}
	for first in range(game.factions.size()):
		for second in range(first + 1, game.factions.size()):
			out["%d:%d" % [first, second]] = game.relation_status(first, second)
	return out


func _city_owners() -> Dictionary:
	var out := {}
	for city in game.cities:
		out["%d,%d" % [city.cell.x, city.cell.y]] = city.faction_id
	return out


func _strategic_signature() -> String:
	var units: Array = []
	for unit in game.units:
		units.append([unit.faction_id, unit.type_id, unit.cell.x, unit.cell.y])
	units.sort()
	return JSON.stringify([units, _city_owners(), _relations(), _tech_eras()])


func _counts_by_faction(items: Array) -> Array[int]:
	var out: Array[int] = []
	out.resize(game.factions.size())
	for item in items:
		if item.faction_id >= 0 and item.faction_id < out.size():
			out[item.faction_id] += 1
	return out


func _tech_eras() -> Array[int]:
	var out: Array[int] = []
	out.resize(game.factions.size())
	for faction_idx in range(game.factions.size()):
		var manager: TechManager = game.tech if faction_idx == 0 else game.ai._tech(faction_idx)
		var highest := 0
		for tech_id in manager.researched:
			highest = maxi(highest, int(Data.TECHS[tech_id].era))
		out[faction_idx] = highest
	return out


func _all_resources() -> Array:
	var out := [game.resources.duplicate()]
	for faction_idx in range(1, game.factions.size()):
		out.append(game.ai.ai_resources.get(faction_idx, {}).duplicate())
	return out


func _resource_values(resource_id: String) -> Array[int]:
	var out: Array[int] = [int(game.resources.get(resource_id, 0))]
	for faction_idx in range(1, game.factions.size()):
		out.append(int(game.ai.ai_resources.get(faction_idx, {}).get(resource_id, 0)))
	return out


func _faction_index(faction_name: String) -> int:
	for faction_idx in range(game.factions.size()):
		if game.factions[faction_idx].name == faction_name:
			return faction_idx
	return -1


func _victory_type(reason: String) -> String:
	if "Monopoly" in reason: return "monopoly"
	if "captured" in reason or "validators controlled" in reason or "nodes were lost" in reason:
		return "domination"
	if "Uplink" in reason: return "uplink"
	if "Sync" in reason: return "sync"
	if "Consensus" in reason: return "council"
	return "other"


func _sum(values: Array) -> int:
	var total := 0
	for value in values: total += int(value)
	return total


func _max_value(values: Array) -> int:
	var maximum := 0
	for value in values: maximum = maxi(maximum, int(value))
	return maximum


func _max_int(values: Array[int]) -> int:
	var maximum := 0
	for value in values: maximum = maxi(maximum, value)
	return maximum


func _print_report() -> void:
	for result in results:
		print("BALANCE_MATCH " + JSON.stringify(result))
	var victories := {}
	var winners := {}
	var total_turns := 0
	var total_captures := 0
	var total_wars := 0
	var total_runtime := 0.0
	var maximum_inactive := 0
	var maximum_captures := 0
	var final_all_war := 0
	var era4_factions := 0
	var idle_human_wins := 0
	var unresolved_all_war := 0
	for result in results:
		victories[result.victory] = int(victories.get(result.victory, 0)) + 1
		var winner_key := "%s/%s" % [result.winner, result.agenda]
		winners[winner_key] = int(winners.get(winner_key, 0)) + 1
		total_turns += int(result.turns)
		total_captures += int(result.captures)
		maximum_captures = maxi(maximum_captures, int(result.captures))
		total_wars += int(result.wars)
		final_all_war += 1 if bool(result.all_pairs_war) else 0
		era4_factions += int(result.era4_factions)
		idle_human_wins += 1 if int(result.winner) == 0 else 0
		unresolved_all_war += 1 if result.victory == "none" and bool(result.all_pairs_war) else 0
		total_runtime += float(result.runtime_ms)
		maximum_inactive = maxi(maximum_inactive, int(result.longest_inactive))
	print("BALANCE_SUMMARY " + JSON.stringify({
		"matches": results.size(), "victories": victories, "winners": winners,
		"average_turns": float(total_turns) / results.size(),
		"average_captures": float(total_captures) / results.size(),
		"maximum_captures": maximum_captures,
		"average_wars": float(total_wars) / results.size(),
		"final_all_war": final_all_war, "era4_factions": era4_factions,
		"idle_human_wins": idle_human_wins,
		"unresolved_all_war": unresolved_all_war,
		"max_inactive": maximum_inactive, "runtime_ms": total_runtime,
	}))
