extends SceneTree
## Viewport-dispatched acceptance for the touch-first core loop.

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _run_size(size)
	print("=== CORE LOOP INPUT %s (failures: %d) ===" % [
		"PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _run_size(size: Vector2i) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88000 + size.x, "rust_tech")
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var map = load("res://scripts/ui/MapView.gd").new()
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
	ui._close_overlay("MenuPanel")
	await process_frame

	var unit: Variant = _arena_unit("rust_guard", Vector2i(20, 20))
	camera.zoom = Vector2(2.0, 2.0)
	camera.position = game.cell_to_pixel(unit.cell)
	await process_frame
	var unit_screen := _cell_screen(map, unit.cell)
	_push_touch(viewport, 0, unit_screen, true)
	_push_drag(viewport, 0, unit_screen + Vector2(8, 5), Vector2(8, 5))
	_push_touch(viewport, 0, unit_screen + Vector2(8, 5), false)
	await process_frame
	_check(game.selected_unit == unit, "%s jitter tap selects exactly once" % size.x)

	var target: Vector2i = unit.cell + Vector2i(1, 1)
	var moves_before: float = unit.moves_left
	_check(map._movement_plan(unit).reachable.has(target),
		"%s highlighted reachable target comes from execution plan" % size.x)
	_push_tap(viewport, _cell_screen(map, target))
	await process_frame
	_check(unit.cell == target and is_equal_approx(unit.moves_left, moves_before - 1.0),
		"%s reachable tap reaches exact target once" % size.x)

	var invalid: Vector2i = target + Vector2i(4, 0)
	var invalid_state := [unit.cell, unit.moves_left, game.units.size(), game.selected_unit]
	var fx_before: int = map._fx.size()
	_push_tap(viewport, _cell_screen(map, invalid))
	await process_frame
	_check([unit.cell, unit.moves_left, game.units.size(), game.selected_unit] == invalid_state
		and map._fx.size() > fx_before and map._fx.back().pos == Vector2(invalid),
		"%s invalid target is mutation-free and preserves selection" % size.x)

	_push_touch(viewport, 1, Vector2(size) * 0.5, true)
	_push_drag(viewport, 1, Vector2(size) * 0.5 + Vector2(44, 0), Vector2(44, 0))
	_push_touch(viewport, 1, Vector2(size) * 0.5 + Vector2(44, 0), false)
	await process_frame
	_check(unit.cell == target and game.selected_unit == unit,
		"%s drag dispatches no gameplay action" % size.x)

	camera.position = game.cell_to_pixel(unit.cell)
	await process_frame
	_push_touch(viewport, 2, _cell_screen(map, unit.cell), true)
	_push_touch(viewport, 2, Vector2(size.x * 0.5, size.y - 44), false)
	await process_frame
	_check(map._touches.is_empty(), "%s map press/UI release clears gesture state" % size.x)
	_push_tap(viewport, _cell_screen(map, unit.cell))
	await process_frame
	_check(game.selected_unit == null, "%s next tap works after cross-surface release" % size.x)

	var enemy: Variant = _add_unit("rust_guard", 1, unit.cell + Vector2i(2, 0))
	game.select(unit)
	var enemy_cell: Vector2i = enemy.cell
	_push_tap(viewport, _cell_screen(map, enemy.cell))
	await process_frame
	_check(enemy.cell == enemy_cell and game.selected_unit == unit,
		"%s blocked enemy tap never moves enemy or loses own selection" % size.x)
	game.diplomacy[1] = "war"
	game.grid.clear_occupant(enemy.cell.x, enemy.cell.y, enemy)
	enemy.cell = unit.cell + Vector2i(1, 0)
	game.grid.place_occupant(enemy.cell.x, enemy.cell.y, enemy)
	unit.moves_left = 1.0
	game.select(unit)
	_push_tap(viewport, _cell_screen(map, enemy.cell))
	_check(unit.moves_left <= 0.001,
		"%s adjacent hostile target consumes movement before combat resolves" % size.x)
	await create_timer(0.45).timeout
	enemy_cell = enemy.cell
	game.select(null)
	_push_tap(viewport, _cell_screen(map, enemy.cell))
	await process_frame
	_push_tap(viewport, _cell_screen(map, enemy.cell + Vector2i(0, 1)))
	await process_frame
	_check(enemy.cell == enemy_cell, "%s inspected enemy is never actionable" % size.x)

	var founder: Variant = _arena_unit("founder", Vector2i(20, 20))
	game.resources.scrap = 100
	game.emit_signal("resources_changed")
	camera.position = game.cell_to_pixel(founder.cell)
	game.select(founder)
	await process_frame
	var selection_action := ui.get_node("SelectionPanel").find_child(
		"FounderAction", true, false) as Button
	_check(selection_action != null and selection_action.visible,
		"%s founder exposes one contextual action" % size.x)
	_push_button(viewport, selection_action)
	await process_frame
	var founded_city = game.city_at(Vector2i(20, 20))
	_check(founded_city != null and game.selected_city == founded_city and not game.units.has(founder),
		"%s found-city action consumes founder and selects city" % size.x)
	selection_action = ui.get_node("SelectionPanel").find_child(
		"CityAction", true, false) as Button
	_check(selection_action.is_visible_in_tree() and selection_action.text == "PRODUCTION"
		and selection_action.size.y >= 48.0
		and ui.get_node("SelectionPanel").get_global_rect().encloses(
			selection_action.get_global_rect())
		and selection_action.get_global_rect().end.y <= \
			ui.get_node("BottomNav").get_global_rect().position.y,
		"%s founded city exposes one labeled production action" % size.x)
	game.resources.scrap = 100
	game.emit_signal("resources_changed")

	selection_action = ui.get_node("SelectionPanel").find_child(
		"CityAction", true, false) as Button
	_push_button(viewport, selection_action)
	await process_frame
	var city_actions: Node = ui.get_node_or_null("CityActions")
	var build_button: Button = null
	if city_actions != null:
		for node in city_actions.find_children("*", "Button", true, false):
			var button := node as Button
			if not button.disabled and button.text.contains("Scrap") and not button.text.begins_with("TRAIN"):
				build_button = button
				break
	_check(build_button != null, "%s production opens a build choice" % size.x)
	if build_button != null:
		_push_button(viewport, build_button)
		await process_frame
	_check(founded_city != null and not founded_city.build_queue.is_empty(),
		"%s production tap queues build" % size.x)
	ui._close_overlay("CityActions")
	await process_frame

	var end_turn := ui.get_node("BottomNav").find_child("EndTurnButton", true, false) as Button
	var turn_before: int = game.turn
	_push_mouse(viewport, end_turn.get_global_rect().get_center(), true)
	await create_timer(0.9).timeout
	_push_mouse(viewport, end_turn.get_global_rect().get_center(), false)
	await process_frame
	_check(game.turn == turn_before + 1, "%s hold end turn advances exactly once" % size.x)
	if size.x == 720:
		game.start_game(Data.MapSize.LARGE, Data.MapType.PANGAEA, 99117, "rust_tech")
		var perf_unit: Variant = _arena_unit("miner_quad", Vector2i(60, 35))
		for x in game.grid.w:
			for y in game.grid.h:
				game.grid.terrain[x][y] = "wasteland"
				game.grid.infra[x][y] = 2
		var started_usec := Time.get_ticks_usec()
		var perf_plan: Dictionary = map._movement_plan(perf_unit)
		var elapsed_msec := float(Time.get_ticks_usec() - started_usec) / 1000.0
		_check(perf_plan.reachable.size() == game.grid.w * game.grid.h - 1
			and elapsed_msec < 200.0,
			"large all-monorail planner remains bounded (%d cells, %.1f ms)" % [
				perf_plan.reachable.size(), elapsed_msec])

	viewport.queue_free()
	await process_frame


func _arena_unit(type_id: String, cell: Vector2i) -> Variant:
	game.grid.clear_occupants()
	game.units.clear()
	game.cities.clear()
	for x in range(cell.x - 6, cell.x + 7):
		for y in range(cell.y - 6, cell.y + 7):
			game.grid.terrain[x][y] = "wasteland"
	var unit: Variant = _add_unit(type_id, game.faction_id, cell)
	game.select(null)
	game.update_visibility()
	return unit


func _add_unit(type_id: String, faction: int, cell: Vector2i) -> Variant:
	var unit: Variant = Unit.new(type_id, faction, cell, game.grid)
	game.units.append(unit)
	game.grid.place_occupant(cell.x, cell.y, unit)
	return unit


func _cell_screen(map: Node2D, cell: Vector2i) -> Vector2:
	return map.cell_to_screen(cell) + Vector2.ONE * 8.0


func _push_tap(viewport: Viewport, position: Vector2) -> void:
	_push_touch(viewport, 0, position, true)
	_push_touch(viewport, 0, position, false)


func _push_touch(viewport: Viewport, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	viewport.push_input(event, true)


func _push_drag(viewport: Viewport, index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	viewport.push_input(event, true)


func _push_mouse(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	viewport.push_input(event, true)


func _push_button(viewport: Viewport, button: Button) -> void:
	button.grab_focus()
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = pressed
		viewport.push_input(event, true)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)
