extends SceneTree
## Deterministic contracts for non-blocking motion feedback.

const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	MotionFeedback.test_reduced_motion = true
	_check(MotionFeedback.scale() == 0.0 and MotionFeedback.duration(0.3) == 0.0,
		"reduced motion has an instant fallback")
	await _run_feedback_contracts()
	MotionFeedback.test_reduced_motion = false
	print("MOTION_FEEDBACK_%s failures=%d" % [
		"PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _run_feedback_contracts() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94017, "rust_tech")
	var scene := Node2D.new()
	root.add_child(scene)
	var map = load("res://scripts/ui/MapView.gd").new()
	map.name = "MapView"
	scene.add_child(map)
	var units_view = load("res://scripts/ui/UnitsView.gd").new()
	units_view.name = "UnitsView"
	scene.add_child(units_view)
	var camera := Camera2D.new()
	camera.name = "Camera"
	scene.add_child(camera)
	await process_frame
	await process_frame

	var unit: Unit = _first_player_unit()
	game.select(unit)
	var plan: Dictionary = map._movement_plan(unit)
	var targets: Array = plan.reachable.keys()
	_check(not targets.is_empty(), "movement arena has a reachable cell")
	if not targets.is_empty():
		var move_count := [0]
		var moved_unit := [null]
		var on_move := func(value):
			move_count[0] += 1
			moved_unit[0] = value
		game.unit_moved.connect(on_move)
		var start := unit.cell
		var target: Vector2i = _closest_target(unit.cell, targets)
		var expected_path: Array = map._path_from_plan(plan, start, target)
		var moved: bool = map._move_unit(unit, target)
		await process_frame
		_check(moved and unit.cell == target and move_count[0] == 1
			and moved_unit[0] == unit, "executed path emits unit_moved exactly once")
		_check(expected_path.back() == target and units_view._active_units.is_empty(),
			"instant feedback lands on the actually executed path")
		var second_plan: Dictionary = map._movement_plan(unit)
		var second_targets: Array = second_plan.reachable.keys()
		if not second_targets.is_empty():
			var second_target: Vector2i = _closest_target(unit.cell, second_targets)
			var moves_before_second := unit.moves_left
			var second_moved: bool = map._move_unit(unit, second_target)
			await process_frame
			_check(second_moved and unit.cell == second_target and move_count[0] == 2
				and unit.moves_left < moves_before_second,
				"rapid consecutive input executes each move exactly once")
		game.unit_moved.disconnect(on_move)

	# Feedback consumes snapshots only: it must not advance RNG or mutate either unit.
	game.grid.clear_occupants()
	game.units.clear()
	var attacker: Unit = game.spawn_unit("rust_guard", Vector2i(20, 20), game.faction_id)
	var defender: Unit = game.spawn_unit("rust_guard", Vector2i(21, 20), 1)
	units_view.sync()
	await process_frame
	await process_frame
	var before := _unit_state(attacker, defender)
	var rng_before: int = game._rng.state
	units_view.play_combat(attacker, defender, true)
	await process_frame
	_check(_unit_state(attacker, defender) == before and game._rng.state == rng_before,
		"combat feedback is RNG- and gameplay-mutation-free")
	_check(units_view._feedback_nodes.is_empty() and units_view._active_units.is_empty(),
		"reduced-motion combat leaves no transition state")
	var city_for_hit: City = game.cities[0] if not game.cities.is_empty() else null
	if city_for_hit != null:
		var city_faction_before: int = city_for_hit.faction_id
		var city_buildings_before: Dictionary = city_for_hit.buildings.duplicate(true)
		units_view.play_city_combat(attacker, city_for_hit, false)
		await process_frame
		_check(city_for_hit.faction_id == city_faction_before
			and city_for_hit.buildings.hash() == city_buildings_before.hash()
			and units_view._active_cities.is_empty(),
			"failed-city hit feedback preserves the surviving city")
	var fx_before_attack: int = map._fx.size()
	var units_before_attack: int = game.units.size()
	map._attack(attacker, defender)
	await process_frame
	_check(map._fx.size() == fx_before_attack and game.units.size() == units_before_attack - 1,
		"reduced-motion routed combat resolves immediately without timed map FX")

	# Preserve the established city-combat rule: a failed roll spends the action,
	# but does not silently delete the attacker.
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94019, "rust_tech")
	await process_frame
	var enemy_city: City = null
	for candidate in game.cities:
		if candidate.faction_id != game.faction_id:
			enemy_city = candidate
			break
	var attack_cell := _free_attack_cell(enemy_city.cell)
	var city_attacker: Unit = game.spawn_unit("rust_guard", attack_cell, game.faction_id)
	units_view.sync()
	await process_frame
	await process_frame
	var losing_seed := _seed_with_roll_above(0.99)
	game._rng.seed = losing_seed
	var enemy_faction_before: int = enemy_city.faction_id
	map._attack_city(city_attacker, enemy_city)
	await process_frame
	_check(game.units.has(city_attacker) and enemy_city.faction_id == enemy_faction_before,
		"failed city attack preserves the pre-motion gameplay semantic")

	# The production domain emits one semantic completion event; visuals do not echo it.
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94018, "rust_tech")
	await process_frame
	var city: City = game.cities[0]
	var building_id := "archio_archive"
	var building: Dictionary = Faction.building_data(building_id)
	var adjusted_cost := int(building.scrap_cost)
	if city.faction != null:
		adjusted_cost = city.faction.building_cost(adjusted_cost)
	city.build_queue = [building_id]
	city.scrap_stock = maxi(adjusted_cost - 1, 0)
	city.buildings["steam_turbine"] = true
	game.resources.scrap = 100
	game.resources.sol = 100
	var completions: Array = []
	var on_complete := func(completed_city, completed_id):
		completions.append([completed_city, completed_id])
	game.city_build_completed.connect(on_complete)
	game.end_turn()
	await process_frame
	_check(completions.size() == 1 and completions[0][0] == city
		and completions[0][1] == building_id,
		"city completion feedback signal fires exactly once")
	game.city_build_completed.disconnect(on_complete)

	# Pause/reset cleanup is idempotent and never changes domain state.
	var state_before_cancel := [game.turn, game.resources.duplicate(true), game.units.size()]
	var orphan := Node2D.new()
	units_view._register_feedback(orphan)
	units_view._active_units[12345] = true
	var live_tween: Tween = units_view.create_tween()
	live_tween.tween_interval(30.0)
	units_view._feedback_tweens.append(live_tween)
	units_view._unit_transitions[12345] = {
		"tween": live_tween, "nodes": [orphan]}
	units_view.cancel_motion_feedback()
	units_view.cancel_motion_feedback()
	await process_frame
	_check(units_view._feedback_nodes.is_empty() and units_view._active_units.is_empty()
		and units_view._unit_transitions.is_empty() and not live_tween.is_valid()
		and [game.turn, game.resources, game.units.size()] == state_before_cancel,
		"pause/reset cancels a live transition and is domain-mutation-free")

	scene.queue_free()
	await process_frame


func _first_player_unit() -> Unit:
	var best: Unit = null
	for unit in game.units:
		if unit.faction_id == game.faction_id \
				and (best == null or unit.max_moves() > best.max_moves()):
			best = unit
	return best


func _unit_state(attacker: Unit, defender: Unit) -> Array:
	return [attacker.cell, attacker.moves_left, attacker.veteran, attacker.fortified,
		defender.cell, defender.moves_left, defender.veteran, defender.fortified,
		game.units.size()]


func _closest_target(origin: Vector2i, targets: Array) -> Vector2i:
	var closest: Vector2i = targets[0]
	var closest_distance := 99999
	for candidate: Vector2i in targets:
		var distance := maxi(absi(candidate.x - origin.x), absi(candidate.y - origin.y))
		if distance < closest_distance:
			closest = candidate
			closest_distance = distance
	return closest


func _free_attack_cell(city_cell: Vector2i) -> Vector2i:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var cell := city_cell + Vector2i(dx, dy)
			if game.grid.in_bounds(cell.x, cell.y) and game.grid.is_passable(cell.x, cell.y):
				var occupant = game.grid.occupant_at(cell.x, cell.y)
				if occupant != null:
					game._remove_unit(occupant)
				return cell
	return city_cell + Vector2i(1, 0)


func _seed_with_roll_above(threshold: float) -> int:
	var probe := RandomNumberGenerator.new()
	for seed_value in range(1, 10000):
		probe.seed = seed_value
		if probe.randf() > threshold:
			return seed_value
	return 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS: %s" % label)
	else:
		failures += 1
		push_error("  FAIL: %s" % label)
