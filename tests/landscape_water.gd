extends SceneTree
## Water motion remains quiet, bounded to the camera, deterministic when motion
## is reduced, and incapable of revealing hidden coastlines.

const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")
const WaterSurface = preload("res://scripts/ui/WaterSurfaceView.gd")

var failures := 0


func _init() -> void:
	await process_frame
	var game := root.get_node("Game")
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 882501, "rust_tech")
	for x in game.grid.w:
		for y in game.grid.h:
			game.grid.terrain[x][y] = "ocean"
	game.explored.clear()
	game.visible.clear()
	for x in range(4, 15):
		for y in range(5, 16):
			game.explored[Vector2i(x, y)] = true
			game.visible[Vector2i(x, y)] = true
	# Hidden land directly beside visible water must not be sampled by either
	# native transitions or the water coastline pass.
	game.grid.terrain[15][10] = "wasteland"

	var viewport := SubViewport.new()
	viewport.size = Vector2i(575, 1280)
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var camera := Camera2D.new()
	camera.position = Vector2(9.5, 10.5) * 16.0
	camera.zoom = Vector2.ONE * 3.0
	camera.enabled = true
	scene.add_child(camera)
	var water := WaterSurface.new()
	water.camera = camera
	water.game = game
	scene.add_child(water)
	MotionFeedback.test_reduced_motion = true
	water.phase_step = 17
	water._process(1.0)
	water.queue_redraw()
	await process_frame
	await process_frame
	check(water.phase_step == 0, "reduced motion locks water to its static phase")
	MotionFeedback.test_reduced_motion = false
	camera.zoom = Vector2.ONE * 0.6
	water.phase_step = 9
	water._process(1.0)
	check(water.phase_step == 0, "overview zoom avoids recurring full-map water redraws")
	camera.zoom = Vector2.ONE * 3.0
	MotionFeedback.test_reduced_motion = true
	var focus_position := camera.position
	camera.position = Vector2(30.0, 10.5) * 16.0
	water._process(0.0)
	await process_frame
	check(water.last_drawn_water_cells == 0,
		"reduced-motion pan invalidates water commands for the new camera bounds")
	camera.position = focus_position
	water._process(0.0)
	await process_frame
	check(water.last_drawn_water_cells == 121,
		"water overlay draws visible water only and ignores hidden land")
	var bounds := WaterSurface.visible_cell_bounds(camera, viewport.size,
		Vector2i(game.grid.w, game.grid.h))
	check(bounds.position.x >= 0 and bounds.position.y >= 0
		and bounds.end.x <= game.grid.w and bounds.end.y <= game.grid.h,
		"water command generation is clamped to the camera and map")
	check(water.last_draw_usec < 12000,
		"575px reduced-motion water pass stays below a 12 ms CPU command budget")

	var map_source := FileAccess.get_file_as_string("res://scripts/ui/MapView.gd")
	var transition_block := map_source.get_slice("if native_terrain:", 1) \
		.get_slice("var terrain_landmark", 0)
	check(transition_block.contains("if not Game.is_visible(neighbor):"),
		"terrain transitions cannot reveal a hidden neighboring material")
	for kind in ["wasteland", "ruins", "swamp", "node_zone"]:
		check(map_source.contains("\"%s\":" % kind),
			"%s receives sparse native material detail" % kind)
	var water_source := FileAccess.get_file_as_string("res://scripts/ui/WaterSurfaceView.gd")
	check(water_source.contains("not game.is_visible(neighbor)")
		and water_source.contains("not game.is_visible(cell)"),
		"coasts and ripples are both visibility-gated")
	check(water_source.contains("WorldArt.cosmetic_hash(\"ocean_ripple\"")
		and not water_source.contains("cell.x * 31 + cell.y * 47"),
		"ocean ripple placement uses an avalanched cosmetic hash")
	check(water_source.contains("posmod((ripple_hash >> 16) + drift, 9)"),
		"animated flecks remain inside their visible ocean cell")

	MotionFeedback.test_reduced_motion = false
	viewport.queue_free()
	print("LANDSCAPE_WATER_%s failures=%d draw_usec=%d" % [
		"PASS" if failures == 0 else "FAIL", failures, water.last_draw_usec])
	quit(0 if failures == 0 else 1)


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: " + message)
		return
	failures += 1
	print("  FAIL: " + message)
