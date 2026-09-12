extends SceneTree
## Permanent player map memory must survive movement, turns, and save/load while
## all live foreign state remains gated by current visibility.

var failures := 0


class CaptureProbeAi extends AiPlayer:
	var target: City
	var probe: City
	var probe_was_visible := true

	func take_turn(f_idx: int, game: Node) -> void:
		if f_idx == 1:
			game.capture_city(target, f_idx)
		elif f_idx == 2:
			probe_was_visible = game.is_visible(probe.cell)
			game.emit_signal("city_build_completed", probe, "assembly_forge")


func _init() -> void:
	await process_frame
	var game := root.get_node("Game")
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 290825, "rust_tech")
	await process_frame

	# Isolate one player eye so the before/after sets are deterministic.
	var scout: Unit = game.units[0]
	game.units = [scout]
	game.cities.clear()
	game.grid.clear_occupants()
	var first_cell := _passable_cell(game, Vector2i.ZERO)
	var second_cell := _passable_cell(game, first_cell, 12)
	_relocate(game, scout, first_cell)
	game.explored.clear()
	game.visible.clear()
	game.update_visibility()
	var old_center := scout.cell
	var first_memory: Dictionary = game.explored.duplicate()
	check(game.is_visible(old_center) and game.is_explored(old_center),
		"current sight is recorded as permanent exploration")
	check(first_memory.size() == game.visible.size(),
		"newly explored cells are exactly cells the player has seen")
	var foreign_eye := Unit.new("rust_guard", 1, second_cell, game.grid)
	game.units.append(foreign_eye)
	game.update_visibility()
	check(_same_points(game.explored, first_memory),
		"AI units never contribute to player visibility or exploration")
	game.units.erase(foreign_eye)

	_relocate(game, scout, second_cell)
	game.update_visibility()
	check(game.is_explored(old_center) and not game.is_visible(old_center),
		"moving away retains old terrain without retaining live sight")
	var retained_after_move: int = game.explored.size()
	game.end_turn()
	await process_frame
	check(game.is_explored(old_center) and not game.is_visible(old_center),
		"ending the turn does not erase remembered terrain")
	check(game.explored.size() >= retained_after_move,
		"visibility recomputation only grows exploration memory")

	# Save/load restores the exact set; recomputing current sight only unions an
	# already-saved subset and cannot invent the rest of the map.
	var expected: Dictionary = game.explored.duplicate()
	var save_path := "user://persistent_exploration.json"
	check(game.save_to_file(save_path), "persistent exploration save writes")
	game.explored.clear()
	game.explored[Vector2i(0, 0)] = true
	check(game.load_from_file(save_path), "persistent exploration save loads")
	check(_same_points(game.explored, expected),
		"save/load restores the exact explored set")
	check(game.is_explored(old_center) and not game.is_visible(old_center),
		"load restores memory without restoring stale visibility")
	var remembered_kind: String = game.remembered_terrain(old_center)
	var changed_kind := "ocean" if remembered_kind != "ocean" else "wasteland"
	game.grid.terrain[old_center.x][old_center.y] = changed_kind
	check(game.remembered_terrain(old_center) == remembered_kind,
		"terrain changes behind fog do not alter remembered terrain")

	# v6 knew explored cells but had no terrain snapshot. Migration snapshots
	# only that saved known set and does not reveal any additional cell.
	var legacy_source := FileAccess.open(save_path, FileAccess.READ)
	var legacy: Dictionary = JSON.parse_string(legacy_source.get_as_text())
	legacy_source.close()
	legacy["version"] = 6
	legacy.erase("explored_terrain")
	var legacy_path := "user://persistent_exploration_v6.json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	check(game.load_from_file(legacy_path), "v6 exploration migrates safely")
	check(_same_points(game.explored, expected),
		"v6 migration preserves only its exact explored set")

	# Invalid exploration is rejected before start_game can mutate the match.
	var source := FileAccess.open(save_path, FileAccess.READ)
	var invalid: Dictionary = JSON.parse_string(source.get_as_text())
	source.close()
	invalid.explored.append([game.grid.w, game.grid.h])
	var corrupt_path := "user://persistent_exploration_corrupt.json"
	var corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_string(JSON.stringify(invalid))
	corrupt.close()
	var before_corrupt: Dictionary = game.explored.duplicate()
	var before_turn: int = game.turn
	check(not game.load_from_file(corrupt_path), "out-of-bounds exploration is rejected")
	check(game.turn == before_turn and _same_points(game.explored, before_corrupt),
		"corrupt exploration rejection does not mutate the running match")
	var malformed_source := FileAccess.open(save_path, FileAccess.READ)
	var malformed_base: Dictionary = JSON.parse_string(malformed_source.get_as_text())
	malformed_source.close()
	var missing_memory := malformed_base.duplicate(true)
	missing_memory.explored_terrain.pop_back()
	_reject_without_mutation(game, "user://persistent_memory_missing.json",
		missing_memory, "v7 missing terrain memory")
	var duplicate_memory := malformed_base.duplicate(true)
	duplicate_memory.explored.append(duplicate_memory.explored[0].duplicate())
	duplicate_memory.explored_terrain.append(
		duplicate_memory.explored_terrain[0].duplicate())
	_reject_without_mutation(game, "user://persistent_memory_duplicate.json",
		duplicate_memory, "v7 duplicate terrain memory")
	var unknown_memory := malformed_base.duplicate(true)
	unknown_memory.explored_terrain[0][2] = "secret_live_terrain"
	_reject_without_mutation(game, "user://persistent_memory_unknown.json",
		unknown_memory, "v7 unknown remembered terrain")

	# A foreign city in remembered fog must not expose its sprite or overlays.
	var rival_city := City.new("Remembered Validator", 1, game.factions[1], old_center, game.grid)
	rival_city.buildings["genesis_node"] = true
	game.cities.append(rival_city)
	game.grid.place_occupant(rival_city.cell.x, rival_city.cell.y, rival_city)
	check(rival_city != null, "foreign city fixture exists")
	if rival_city != null:
		game.explored[rival_city.cell] = true
		game.explored_terrain[rival_city.cell] = game.grid.terrain[rival_city.cell.x][rival_city.cell.y]
		game.visible.erase(rival_city.cell)
		game.tech.researched["satellite_uplink"] = true
		game._activate_satellite_intel()
		check(game.satellite_intel.has(rival_city.cell),
			"Satellite Uplink takes one global snapshot of existing enemy validators")
		var hidden_founding_cell := _empty_passable_cell(game, rival_city.cell)
		var hidden_founding := City.new("Hidden Founding", 1, game.factions[1],
			hidden_founding_cell, game.grid)
		hidden_founding.buildings["genesis_node"] = true
		game.cities.append(hidden_founding)
		game.grid.place_occupant(hidden_founding.cell.x, hidden_founding.cell.y, hidden_founding)
		game.visible.erase(hidden_founding.cell)
		game._refresh_satellite_intel()
		check(not game.satellite_intel.has(hidden_founding.cell),
			"hidden founding does not appear after the one-time satellite snapshot")
		rival_city.faction_id = game.faction_id
		rival_city.faction = game.factions[game.faction_id]
		game._refresh_satellite_intel()
		check(game.satellite_intel.has(rival_city.cell),
			"hidden ownership change retains the last-known neutral marker")
		game.cities.erase(rival_city)
		game.grid.clear_occupant(rival_city.cell.x, rival_city.cell.y, rival_city)
		game._refresh_satellite_intel()
		check(game.satellite_intel.has(rival_city.cell),
			"hidden raze retains the last-known neutral marker")
		game.visible[rival_city.cell] = true
		game._refresh_satellite_intel()
		check(not game.satellite_intel.has(rival_city.cell),
			"observing the razed validator removes its stale marker")
		game.visible.erase(rival_city.cell)
		rival_city.faction_id = 1
		rival_city.faction = game.factions[1]
		game.cities.append(rival_city)
		game.grid.place_occupant(rival_city.cell.x, rival_city.cell.y, rival_city)
		game.cities.erase(hidden_founding)
		game.grid.clear_occupant(hidden_founding.cell.x, hidden_founding.cell.y, hidden_founding)
		game._activate_satellite_intel()

		var intel_save := "user://persistent_satellite_v7.json"
		var expected_intel: Dictionary = game.satellite_intel.duplicate()
		check(game.save_to_file(intel_save), "v7 satellite intel save writes")
		game.satellite_intel.clear()
		check(game.load_from_file(intel_save), "v7 satellite intel save loads")
		check(_same_points(game.satellite_intel, expected_intel),
			"v7 restores the exact last-known satellite snapshot")
		var intel_source := FileAccess.open(intel_save, FileAccess.READ)
		var intel_v6: Dictionary = JSON.parse_string(intel_source.get_as_text())
		intel_source.close()
		intel_v6.version = 6
		var intel_v6_path := "user://persistent_satellite_v6.json"
		var intel_v6_file := FileAccess.open(intel_v6_path, FileAccess.WRITE)
		intel_v6_file.store_string(JSON.stringify(intel_v6))
		intel_v6_file.close()
		check(game.load_from_file(intel_v6_path), "v6 satellite migration loads")
		check(game.satellite_intel.is_empty(),
			"v6 migration starts with no invented satellite memory")
		check(game.load_from_file(intel_save), "v7 satellite fixture reloads for rendering")
		rival_city = game.city_at(old_center)
		var units_view = load("res://scripts/ui/UnitsView.gd").new()
		root.add_child(units_view)
		await process_frame
		await process_frame
		check(_city_sprite_count(units_view) == 0,
			"remembered foreign city does not render live city state")
		units_view._sync()
		await process_frame
		await process_frame
		check(_city_sprite_count(units_view) == 0,
			"Satellite Uplink still does not render a live hidden city")
		check(_validator_signal_count(units_view) == 1,
			"Satellite Uplink uses one neutral location signal behind fog")
		var feedback_before := _feedback_count(units_view)
		units_view._play_city_completion(rival_city, "assembly_forge")
		check(_feedback_count(units_view) == feedback_before,
			"hidden foreign production emits no completion feedback")
		var map_view = load("res://scripts/ui/MapView.gd").new()
		root.add_child(map_view)
		game.select(null)
		map_view._handle_click(rival_city.cell)
		check(game.selected_city == null and game.selected_unit == null,
			"blind tapping a hidden city cannot select or inspect it")
		var hidden_unit_cell := _empty_passable_cell(game, rival_city.cell)
		var hidden_unit := Unit.new("rust_guard", 1, hidden_unit_cell, game.grid)
		game.units.append(hidden_unit)
		game.grid.place_occupant(hidden_unit_cell.x, hidden_unit_cell.y, hidden_unit)
		game.explored[hidden_unit_cell] = true
		game.explored_terrain[hidden_unit_cell] = game.grid.terrain[hidden_unit_cell.x][hidden_unit_cell.y]
		game.visible.erase(hidden_unit_cell)
		map_view._handle_click(hidden_unit_cell)
		check(game.selected_city == null and game.selected_unit == null,
			"blind tapping a hidden unit cannot select or inspect it")
		game.select(hidden_unit)
		game.update_visibility()
		check(game.selected_unit == null,
			"a previously inspected enemy is dismissed when it moves behind fog")
		map_view.queue_free()
		units_view.queue_free()

	var map_source := FileAccess.get_file_as_string("res://scripts/ui/MapView.gd")
	var fog_block := map_source.get_slice("if not Game.is_visible(cell):", 1) \
		.get_slice("continue", 0)
	check(fog_block.contains("Game.remembered_terrain(cell)")
		and not fog_block.contains("WorldArt") and not fog_block.contains("terminals")
		and not fog_block.contains("terrain_data") and not fog_block.contains("infra")
		and not fog_block.contains("improvements"),
		"remembered fog draws subdued terrain only")
	var water_source := FileAccess.get_file_as_string("res://scripts/ui/WaterSurfaceView.gd")
	check(water_source.contains("if not game.is_visible(cell)"),
		"water animation remains current-visibility gated")
	# Permanent map memory must not exhaust the existing spawn-in-fog rule.
	game.units.clear()
	game.cities.clear()
	game.grid.clear_occupants()
	game.explored.clear()
	game.explored_terrain.clear()
	game.visible.clear()
	for x in game.grid.w:
		for y in game.grid.h:
			var known_cell := Vector2i(x, y)
			game.grid.terrain[x][y] = "wasteland"
			game.explored[known_cell] = true
			game.explored_terrain[known_cell] = "wasteland"
	game.turn = 10
	game._rng.seed = 290827
	game.spawn_barbarians()
	var fog_spawns := 0
	var all_spawns_hidden := true
	for unit in game.units:
		if unit.faction_id == game.BARB_FACTION:
			fog_spawns += 1
			all_spawns_hidden = all_spawns_hidden and not game.visible.has(unit.cell)
	check(fog_spawns == 2 and all_spawns_hidden,
		"explored-but-not-visible passable cells remain eligible for botnet waves")
	game.units.clear()
	game.grid.clear_occupants()
	game.visible = game.explored.duplicate()
	game._rng.seed = 290827
	game.spawn_barbarians()
	var visible_spawns := 0
	for unit in game.units:
		if unit.faction_id == game.BARB_FACTION:
			visible_spawns += 1
	check(visible_spawns == 0,
		"currently visible cells remain ineligible for botnet waves")
	game.explored_terrain[Vector2i(-1, -1)] = "rift"
	game.start_game(Data.MapSize.SMALL, Data.MapType.PANGAEA, 290826, "rust_tech",
		["rust_tech", "global_net", "steel"])
	check(not game.explored_terrain.has(Vector2i(-1, -1)),
		"starting a new match clears prior terrain memory")
	var lost_eye: City = null
	for city in game.cities:
		if city.faction_id == game.faction_id:
			lost_eye = city
			break
	game.units.clear()
	game.grid.clear_occupants()
	for city in game.cities:
		game.grid.place_occupant(city.cell.x, city.cell.y, city)
	game.update_visibility()
	check(lost_eye != null and game.is_visible(lost_eye.cell),
		"player city contributes current sight before an AI capture")
	var probe_ai := CaptureProbeAi.new()
	probe_ai.target = lost_eye
	for city in game.cities:
		if city.faction_id == 2:
			probe_ai.probe = city
			break
	game.ai = probe_ai
	game.end_turn()
	check(lost_eye.faction_id == 1, "first AI captures the player's last city eye")
	check(not probe_ai.probe_was_visible,
		"visibility refreshes before the next AI can emit hidden production feedback")
	check(game.visible.is_empty() and not game.is_visible(lost_eye.cell),
		"post-AI turn refresh removes vision immediately when no player eyes remain")

	print("PERSISTENT_EXPLORATION_%s failures=%d" % [
		"PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _relocate(game: Node, unit: Unit, cell: Vector2i) -> void:
	game.grid.clear_occupant(unit.cell.x, unit.cell.y, unit)
	unit.cell = cell
	game.grid.place_occupant(cell.x, cell.y, unit)


func _passable_cell(game: Node, away_from: Vector2i, minimum_distance: int = 0) -> Vector2i:
	for x in game.grid.w:
		for y in game.grid.h:
			var cell := Vector2i(x, y)
			if absi(cell.x - away_from.x) + absi(cell.y - away_from.y) >= minimum_distance \
					and game.grid.is_passable(x, y):
				return cell
	return Vector2i.ZERO


func _empty_passable_cell(game: Node, origin: Vector2i) -> Vector2i:
	for radius in range(1, 16):
		for x in range(origin.x - radius, origin.x + radius + 1):
			for y in range(origin.y - radius, origin.y + radius + 1):
				if game.grid.in_bounds(x, y) and game.grid.is_passable(x, y) \
						and game.grid.occupant[x][y] == null:
					return Vector2i(x, y)
	return Vector2i.ZERO


func _reject_without_mutation(game: Node, path: String, data: Dictionary,
		label: String) -> void:
	var before_points: Dictionary = game.explored.duplicate()
	var before_turn: int = game.turn
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(not game.load_from_file(path), "%s is rejected" % label)
	check(game.turn == before_turn and _same_points(game.explored, before_points),
		"%s rejection is atomic" % label)


func _same_points(first: Dictionary, second: Dictionary) -> bool:
	if first.size() != second.size():
		return false
	for point in first:
		if not second.has(point):
			return false
	return true


func _city_sprite_count(view: Node) -> int:
	var count := 0
	for child in view.get_children():
		if child is Sprite2D and child.z_index == 5:
			count += 1
	return count


func _validator_signal_count(view: Node) -> int:
	var count := 0
	for child in view.get_children():
		if child.has_meta("validator_signal"):
			count += 1
	return count


func _feedback_count(view: Node) -> int:
	var count := 0
	for child in view.get_children():
		if child.has_meta("motion_feedback"):
			count += 1
	return count


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: " + message)
		return
	failures += 1
	print("  FAIL: " + message)
