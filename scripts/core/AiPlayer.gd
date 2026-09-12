extends RefCounted
class_name AiPlayer
## Multi-Rival v1: deterministic land opponents using the same core economy.

var ai_resources: Dictionary = {}
var ai_tech: Dictionary = {}
var ai_agendas: Dictionary = {}

const AGENDAS := ["Builder", "Conqueror", "Validator"]

const PATH_DIRECTIONS := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]
const PATH_SEARCH_LIMIT := 256
const RESEARCH_ORDER := [
	"primitive_coding", "steam_synthesis", "hydroponics",
	"block_encryption", "atomic_reactor", "radiation_engineering",
	"quantum_computing", "smart_contracts", "cyber_implants",
	"satellite_uplink", "global_consensus", "terraforming", "firedancer",
]


func take_turn(faction_idx: int, game: Node) -> void:
	var res: Dictionary = _resources(faction_idx)
	var faction_tech: TechManager = _tech(faction_idx)
	var agenda := agenda_for(faction_idx, game.factions)
	var cities_of_faction: Array = []
	for city in game.cities:
		if city.faction_id == faction_idx:
			cities_of_faction.append(city)

	_update_relations(faction_idx, agenda, game)
	_run_economy(faction_idx, cities_of_faction, res, game)
	_choose_research(faction_tech, res, agenda)
	_advance_research(cities_of_faction, faction_tech)
	_queue_legal_production(cities_of_faction, faction_tech, agenda)
	_train_units(faction_idx, cities_of_faction, res, faction_tech, game, agenda)

	var faction_units: Array = []
	for unit in game.units:
		if unit.faction_id == faction_idx:
			unit.update_fortify()
			game.reset_unit_moves_with_emp(unit)
			faction_units.append(unit)
	var explored_this_turn := false
	for unit in faction_units:
		if not game.units.has(unit):
			continue
		if unit.type_id == "founder":
			_founder_action(game, unit, faction_idx)
		else:
			var enemy := _nearest_war_enemy(game, unit.cell, faction_idx)
			if enemy >= 0:
				_combat_move(game, unit, faction_idx, enemy)
			elif not explored_this_turn:
				explored_this_turn = _explore_move(game, unit)


func _resources(faction_idx: int) -> Dictionary:
	if not ai_resources.has(faction_idx):
		ai_resources[faction_idx] = Data.START_RESOURCES.duplicate()
	return ai_resources[faction_idx]


func _tech(faction_idx: int) -> TechManager:
	if not ai_tech.has(faction_idx):
		ai_tech[faction_idx] = TechManager.new()
	return ai_tech[faction_idx]


func _update_relations(faction_idx: int, agenda: String, game: Node) -> void:
	if not _faction_has_city(faction_idx, game):
		return
	var threshold := 46 if agenda == "Conqueror" else 34 if agenda == "Validator" else 28
	for other in game.factions.size():
		if other == faction_idx or (other > 0 and other < faction_idx):
			continue
		if not _faction_has_city(other, game):
			continue
		if game.relation_status(faction_idx, other) != "peace":
			continue
		if not game.can_start_war(faction_idx, other):
			continue
		var value := maxi(0, game.relation_ping(faction_idx, other) - 1)
		game.set_relation_ping(faction_idx, other, value)
		if value < threshold and game.gameplay_randf() < 0.3:
			game.set_relation(faction_idx, other, "war")


func _faction_has_city(faction_idx: int, game: Node) -> bool:
	for city in game.cities:
		if city.faction_id == faction_idx:
			return true
	return false


func _run_economy(faction_idx: int, faction_cities: Array, res: Dictionary,
		game: Node) -> void:
	var agenda := agenda_for(faction_idx, game.factions)
	var city_focus := "scrap" if agenda == "Conqueror" else \
		"sol" if agenda == "Validator" else "biomass"
	var focus_changed := false
	for city in faction_cities:
		if city.focus != city_focus:
			city.focus = city_focus
			focus_changed = true
	if focus_changed:
		game.recompute_city_worked_tiles()
	var state: Dictionary = game._faction_energy_grid_state(faction_idx)
	var total_scrap := 0
	var total_food := 0
	var total_sol := 0
	var total_energy: int = int(state.available_energy)
	var population_changed := false
	for city in faction_cities:
		if city.is_offline() or city.is_dos() or not bool(state.powered.get(city, false)):
			continue
		var gathered: Dictionary = state.gathered[city]
		var usable_food: int = city.usable_food(int(gathered.food),
			_has_passive(_tech(faction_idx), "swamp_immune"))
		total_scrap += int(gathered.scrap)
		total_food += usable_food
		var built: String = city.process_build(res)
		if built != "":
			game.emit_signal("city_build_completed", city, built)
			game.emit_signal("city_changed", city)
		if city.process_growth(usable_food):
			population_changed = true
			game.emit_signal("city_changed", city)
		total_sol += int(gathered.sol) + city.sol_production() + city.sol_from_population()
	if game.event_active == "outage":
		total_sol = 0
	var protocol_data: Dictionary = Data.PROTOCOLS["p2p"]
	total_sol = int(round(total_sol * float(protocol_data.get("sol_mult", 1.0))))
	var bonuses: Dictionary = game.factions[faction_idx].bonuses()
	if bonuses.has("validator_boost") and state.powered.values().has(true):
		total_sol = int(round(total_sol * float(bonuses.validator_boost)))
	if _has_passive(_tech(faction_idx), "ruins_scrap_plus1"):
		for city in faction_cities:
			if bool(state.powered.get(city, false)) and not city.is_offline() and not city.is_dos():
				total_scrap += city.count_terrain_near("ruins")
	res.scrap += total_scrap
	res.biomass += total_food
	res.energy += total_energy
	res.sol += total_sol
	if population_changed:
		game.recompute_city_worked_tiles()
	game.record_network_sol(faction_idx, total_sol)
	var at_war: bool = game._faction_under_threat(faction_idx)
	for city in faction_cities:
		city.tick_offline()
		var surplus: int = int(state.fatigue_surplus.get(city, 0))
		if city.process_fatigue(surplus, at_war, false):
			var spawn: Vector2i = game.grid.find_free_tile_near(city.cell.x, city.cell.y, 3)
			if spawn.x >= 0:
				game.spawn_unit("auto_mech", spawn, game.BARB_FACTION)


func _choose_research(faction_tech: TechManager, res: Dictionary, agenda: String = "Builder") -> void:
	if faction_tech.current != "":
		return
	var order: Array = RESEARCH_ORDER
	if agenda == "Conqueror":
		order = ["primitive_coding", "block_encryption", "smart_contracts", "global_consensus",
			"steam_synthesis", "atomic_reactor", "quantum_computing", "satellite_uplink",
			"hydroponics", "radiation_engineering", "cyber_implants", "terraforming", "firedancer"]
	elif agenda == "Validator":
		order = ["steam_synthesis", "atomic_reactor", "quantum_computing", "satellite_uplink",
			"primitive_coding", "block_encryption", "smart_contracts", "global_consensus",
			"firedancer", "hydroponics", "radiation_engineering", "cyber_implants", "terraforming"]
	for tech_id in order:
		if tech_id in faction_tech.researchable() and faction_tech.start_research(tech_id, res):
			return


func _advance_research(faction_cities: Array, faction_tech: TechManager) -> void:
	if faction_tech.current == "":
		return
	var points := 0
	for city in faction_cities:
		if not city.is_offline() and not city.is_dos():
			points += faction_tech.city_tech_points(city)
	faction_tech.add_points(points)


func _queue_legal_production(faction_cities: Array, faction_tech: TechManager,
		agenda: String = "Builder") -> void:
	var priorities := ["assembly_forge", "steam_turbine", "sol_exchange"]
	if agenda == "Validator":
		priorities = ["sol_exchange", "steam_turbine", "assembly_forge"]
	elif agenda == "Conqueror":
		priorities = ["assembly_forge", "steam_turbine", "sol_exchange"]
	for city in faction_cities:
		if not city.build_queue.is_empty():
			continue
		for building_id in priorities:
			if city.can_queue_build(building_id, faction_tech):
				city.add_to_queue(building_id)
				break


func _train_units(faction_idx: int, faction_cities: Array, res: Dictionary,
		faction_tech: TechManager, game: Node, agenda: String = "Builder") -> void:
	var unit_count: int = game.units_of_faction(faction_idx).size()
	var unit_cap: int = (8 if agenda == "Conqueror" else 5) + faction_cities.size() * 2
	if unit_count >= unit_cap:
		return
	for city in faction_cities:
		if unit_count >= unit_cap:
			break
		var unit_type := "rust_guard"
		if faction_tech.is_researched("primitive_coding") and agenda != "Conqueror":
			unit_type = "miner_quad"
		var actual_type: String = game.factions[faction_idx].unit_for(unit_type)
		var data: Dictionary = Faction.unit_data(actual_type)
		if res.scrap < int(data.scrap_cost) or res.sol < int(data.sol_cost):
			continue
		var pos: Vector2i = game.grid.find_free_tile_near(city.cell.x, city.cell.y, 3)
		if pos.x < 0:
			continue
		var trained: Unit = game.spawn_unit(actual_type, pos, faction_idx)
		if city.has_building("assembly_forge"):
			trained.veteran = true
		res.scrap -= int(data.scrap_cost)
		res.sol -= int(data.sol_cost)
		unit_count += 1


func _founder_action(game: Node, unit: Unit, faction_idx: int) -> void:
	if game.can_found_site(unit.cell, faction_idx, unit):
		var res: Dictionary = _resources(faction_idx)
		if int(res.scrap) < Data.SCRAP_PER_CITY:
			return
		var city: City = game._found_city_at(unit.cell, faction_idx)
		if city != null:
			res.scrap -= Data.SCRAP_PER_CITY
			game.units.erase(unit)
			game.emit_signal("city_changed", city)
			return
	var target := _expansion_target(game, unit.cell)
	if target != Vector2i(-1, -1):
		_move_along_path(game, unit, target)


func _expansion_target(game: Node, origin: Vector2i) -> Vector2i:
	for radius in range(6, 13):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				var cell := Vector2i(x, y)
				if _distance(cell, origin) != radius or not game.grid.in_bounds(x, y):
					continue
				if game.grid.is_passable(x, y) and game.grid.occupant_at(x, y) == null:
					return cell
	return Vector2i(-1, -1)


func _explore_move(game: Node, unit: Unit) -> bool:
	var target := _expansion_target(game, unit.cell)
	if target != Vector2i(-1, -1):
		var origin := unit.cell
		_move_along_path(game, unit, target)
		return unit.cell != origin
	return false


func _combat_move(game: Node, unit: Unit, faction_idx: int, enemy_faction: int) -> void:
	var target := _nearest_enemy_cell(game, unit.cell, enemy_faction)
	if target == Vector2i(-1, -1):
		return
	if _is_adjacent(unit.cell, target):
		_attack_cell(game, unit, faction_idx, enemy_faction, target)
		return
	_move_along_path(game, unit, target)
	if game.units.has(unit) and unit.moves_left > 0 and _is_adjacent(unit.cell, target):
		_attack_cell(game, unit, faction_idx, enemy_faction, target)


func _nearest_enemy_cell(game: Node, origin: Vector2i, enemy_faction: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for enemy in game.units:
		if enemy.faction_id != enemy_faction:
			continue
		var distance := _distance(origin, enemy.cell)
		if distance < best_distance or (distance == best_distance and _cell_before(enemy.cell, best)):
			best_distance = distance
			best = enemy.cell
	for city in game.cities:
		if city.faction_id != enemy_faction or game.occupation_remaining(city) > 0:
			continue
		var distance := _distance(origin, city.cell)
		if distance < best_distance or (distance == best_distance and _cell_before(city.cell, best)):
			best_distance = distance
			best = city.cell
	return best


func _nearest_war_enemy(game: Node, origin: Vector2i, faction_idx: int) -> int:
	var best_faction := -1
	var best_distance := 1 << 30
	var best_cell := Vector2i(-1, -1)
	for enemy in game.units:
		var other: int = enemy.faction_id
		if other < 0 or other >= game.factions.size() or other == faction_idx \
				or not game.are_factions_at_war(faction_idx, other):
			continue
		var distance := _distance(origin, enemy.cell)
		if best_faction < 0 or distance < best_distance \
				or (distance == best_distance and (other < best_faction \
				or (other == best_faction and _cell_before(enemy.cell, best_cell)))):
			best_distance = distance
			best_faction = other
			best_cell = enemy.cell
	for city in game.cities:
		var other: int = city.faction_id
		if other == faction_idx or game.occupation_remaining(city) > 0 \
				or not game.are_factions_at_war(faction_idx, other):
			continue
		var distance := _distance(origin, city.cell)
		if best_faction < 0 or distance < best_distance \
				or (distance == best_distance and (other < best_faction \
				or (other == best_faction and _cell_before(city.cell, best_cell)))):
			best_distance = distance
			best_faction = other
			best_cell = city.cell
	return best_faction


func _move_along_path(game: Node, unit: Unit, target: Vector2i) -> void:
	while unit.moves_left > 0.001:
		var path := _path_steps(game, unit.cell, target)
		if path.is_empty():
			break
		var moved := false
		for next: Vector2i in path:
			if unit.moves_left <= 0.001 or not unit.try_move(next):
				break
			moved = true
			game.emit_signal("unit_moved", unit)
		if not moved:
			break


func _next_path_step(game: Node, start: Vector2i, target: Vector2i) -> Vector2i:
	var path := _path_steps(game, start, target)
	return path[0] if not path.is_empty() else Vector2i(-1, -1)


func _path_steps(game: Node, start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var frontier: Array = [start]
	var cursor := 0
	var came_from: Dictionary = {start: start}
	var reached := Vector2i(-1, -1)
	var closest := start
	var closest_distance := _distance(start, target)
	while cursor < frontier.size() and cursor < PATH_SEARCH_LIMIT:
		var current: Vector2i = frontier[cursor]
		cursor += 1
		var current_distance := _distance(current, target)
		if current_distance < closest_distance or (current_distance == closest_distance \
				and _cell_before(current, closest)):
			closest = current
			closest_distance = current_distance
		if _is_adjacent(current, target):
			reached = current
			break
		for direction in PATH_DIRECTIONS:
			var next: Vector2i = current + direction
			if came_from.has(next) or not game.grid.in_bounds(next.x, next.y):
				continue
			if not game.grid.is_passable(next.x, next.y):
				continue
			# Occupied intermediate cells are blockers, regardless of relation.
			# Combat is resolved only after reaching an adjacent free cell.
			if game.grid.occupant_at(next.x, next.y) != null:
				continue
			came_from[next] = current
			frontier.append(next)
	if reached == Vector2i(-1, -1):
		reached = closest
	if reached == start:
		return []
	var step: Vector2i = reached
	var path: Array[Vector2i] = []
	while step != start:
		path.push_front(step)
		step = came_from[step]
	return path


func _attack_cell(game: Node, attacker: Unit, faction_idx: int,
		enemy_faction: int, target: Vector2i) -> void:
	if not game.are_factions_at_war(faction_idx, enemy_faction) or attacker.moves_left <= 0:
		return
	var defender: Unit = game.unit_at(target)
	if defender != null and defender.faction_id == enemy_faction:
		attacker.moves_left = 0
		var won: bool = attacker.fight_vs(defender, game.gameplay_randf(),
			game.faction_attack_bonus_for(faction_idx))
		if won:
			game._remove_unit(defender)
		else:
			game._remove_unit(attacker)
		game.emit_signal("unit_moved", attacker)
		return
	var city: City = game.city_at(target)
	if city == null or city.faction_id != enemy_faction:
		return
	if game.occupation_remaining(city) > 0:
		return
	attacker.moves_left = 0
	var garrison := Unit.new("rust_guard", city.faction_id, city.cell, game.grid)
	var defense_multiplier := 2.0 if city.faction != null \
			and city.faction.id == "steel" and city.has_building("assembly_forge") else 1.0
	if attacker.fight_vs(garrison, game.gameplay_randf(),
			game.faction_attack_bonus_for(faction_idx), defense_multiplier):
		game.capture_city(city, faction_idx)
	game.emit_signal("unit_moved", attacker)


func serialize_tech() -> Dictionary:
	var out := {}
	for faction_idx in ai_tech:
		var manager: TechManager = ai_tech[faction_idx]
		out[str(faction_idx)] = {
			"researched": manager.researched.keys(),
			"current": manager.current,
			"points": manager.points,
		}
	return out


func restore_tech(data: Dictionary) -> void:
	ai_tech.clear()
	for faction_key in data:
		var manager := TechManager.new()
		var saved: Dictionary = data[faction_key]
		for tech_id in saved.get("researched", []):
			manager.researched[str(tech_id)] = true
		manager.current = str(saved.get("current", ""))
		manager.points = int(saved.get("points", 0))
		ai_tech[int(faction_key)] = manager


func agenda_for(faction_idx: int, factions: Array) -> String:
	if ai_agendas.has(faction_idx):
		return str(ai_agendas[faction_idx])
	var faction_identity := str(factions[faction_idx].id)
	var agenda := "Conqueror" if faction_identity == "steel" else \
			"Validator" if faction_identity in ["global_net", "dao"] else "Builder"
	ai_agendas[faction_idx] = agenda
	return agenda


func serialize_agendas() -> Dictionary:
	var out := {}
	for faction_idx in ai_agendas:
		out[str(faction_idx)] = ai_agendas[faction_idx]
	return out


func restore_agendas(data: Dictionary, factions: Array) -> void:
	ai_agendas.clear()
	for faction_key in data:
		ai_agendas[int(faction_key)] = str(data[faction_key])
	for faction_idx in range(1, factions.size()):
		agenda_for(faction_idx, factions)


func _has_passive(manager: TechManager, passive_id: String) -> bool:
	for tech_id in manager.researched:
		if Data.TECHS[tech_id].passive == passive_id:
			return true
	return false


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1


func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return b == Vector2i(-1, -1) or a.y < b.y or (a.y == b.y and a.x < b.x)
