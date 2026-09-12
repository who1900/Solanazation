extends SceneTree
## SECURED state must stay compact and legible at both target portrait widths.

var failures := 0
var game: Node


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _run_size(size)
	print("STRATEGIC_ARC_VISUAL_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _run_size(size: Vector2i) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 99200 + size.x,
		"rust_tech", ["rust_tech", "global_net", "steel"])
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var units_view = load("res://scripts/ui/UnitsView.gd").new()
	units_view.name = "UnitsView"
	scene.add_child(units_view)
	var ui = load("res://scripts/ui/GameUI.gd").new()
	ui.name = "UI"
	scene.add_child(ui)
	await process_frame
	var own: City = _city_of(0)
	var rival: City = _city_of(1)
	own.occupation_until_turn = game.turn + 2
	own.build_queue = ["assembly_forge"]
	rival.occupation_until_turn = game.turn + 2
	rival.dos_turns = 2
	game.explored[rival.cell] = true
	game.explored_terrain[rival.cell] = game.grid.terrain[rival.cell.x][rival.cell.y]
	game.visible[rival.cell] = true
	await units_view._sync()
	game.select(own)
	await process_frame
	var secured: Array[Node] = []
	for child in units_view.find_children("*", "Sprite2D", true, false):
		if child.has_meta("secured_city"):
			secured.append(child)
	var construction: Array[Node] = units_view.find_children("CityOverlay_construction", "Sprite2D", true, false)
	var offline: Array[Node] = units_view.find_children("CityOverlay_offline_dos", "Sprite2D", true, false)
	check(secured.size() == 2, "%dpx shows SECURED for both owners (found %d)" % [size.x, secured.size()])
	check(construction.size() == 1 and offline.size() == 1,
		"%dpx preserves construction and offline markers" % size.x)
	if secured.size() == 2 and not construction.is_empty() and not offline.is_empty():
		check(secured[0].position != construction[0].position \
				and secured[1].position != offline[0].position,
			"%dpx shape marker does not occupy existing state anchors" % size.x)
	check("SECURED 2T" in ui._selection_summary_text,
		"%dpx selected-city summary exposes compact duration" % size.x)
	viewport.queue_free()
	await process_frame


func _city_of(owner: int) -> City:
	for city in game.cities:
		if city.faction_id == owner:
			return city
	return null


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: " + message)
	else:
		failures += 1
		print("  FAIL: " + message)
