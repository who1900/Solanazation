extends Node2D
class_name WaterSurfaceView
## Sparse world-space water motion. Kept separate so the static terrain map is
## not rebuilt for every animation tick.

const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")
const WorldArt = preload("res://scripts/ui/WorldArt.gd")

const TILE_SIZE := 16
const UPDATE_INTERVAL := 0.25
const ANIMATED_MIN_ZOOM := 1.0
const COAST_INK := Color("18252d")
const COAST_LIGHT := Color("8c927f")
const RIPPLE_LIGHT := Color("8299a0")
const RIPPLE_DARK := Color("172832")
const EDGE_OFFSETS := {
	"n": Vector2i(0, -1),
	"e": Vector2i(1, 0),
	"s": Vector2i(0, 1),
	"w": Vector2i(-1, 0),
}

var camera: Camera2D
var game: Node
var phase_step := 0
var last_drawn_water_cells := 0
var last_draw_usec := 0
var _elapsed := 0.0
var _was_animated := false
var _last_camera_position := Vector2(INF, INF)
var _last_camera_zoom := Vector2(INF, INF)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if game == null:
		return
	game.turn_changed.connect(func(_turn): _refresh())
	game.unit_moved.connect(func(_unit): _refresh())
	game.city_changed.connect(func(_city): _refresh())
	game.match_ready.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	# Static/reduced-motion water still depends on which world cells the camera
	# exposes. Pan and zoom therefore invalidate commands independently of motion.
	if camera != null and (not camera.position.is_equal_approx(_last_camera_position)
			or not camera.zoom.is_equal_approx(_last_camera_zoom)):
		_last_camera_position = camera.position
		_last_camera_zoom = camera.zoom
		queue_redraw()
	# At overview zoom a sub-tile ripple is imperceptible; keeping that view
	# static avoids rebuilding a full-map overlay on mobile.
	var animated := MotionFeedback.scale() > 0.0 and camera != null \
		and camera.zoom.x >= ANIMATED_MIN_ZOOM
	if not animated:
		if _was_animated or phase_step != 0:
			phase_step = 0
			queue_redraw()
		_was_animated = false
		return
	_was_animated = true
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL:
		return
	_elapsed = fmod(_elapsed, UPDATE_INTERVAL)
	phase_step = posmod(phase_step + 1, 120)
	queue_redraw()


func _refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var started := Time.get_ticks_usec()
	last_drawn_water_cells = 0
	if game == null or game.grid == null or camera == null:
		last_draw_usec = Time.get_ticks_usec() - started
		return
	var grid: GridManager = game.grid
	var bounds := visible_cell_bounds(camera, get_viewport_rect().size, Vector2i(grid.w, grid.h))
	var visual_seed: int = game.visual_seed()
	var draw_phase := 0 if MotionFeedback.scale() <= 0.0 else phase_step
	for x in range(bounds.position.x, bounds.end.x):
		for y in range(bounds.position.y, bounds.end.y):
			var cell := Vector2i(x, y)
			if not game.is_visible(cell) or grid.terrain[x][y] != "ocean":
				continue
			last_drawn_water_cells += 1
			_draw_ripple(cell, visual_seed, draw_phase)
			_draw_coast(cell, grid)
	last_draw_usec = Time.get_ticks_usec() - started


func _draw_ripple(cell: Vector2i, visual_seed: int, draw_phase: int) -> void:
	# Flecks are sparse and offset by a world hash, so a large ocean reads as one
	# moving surface rather than a grid of animated tiles.
	var ripple_hash := WorldArt.cosmetic_hash("ocean_ripple", cell, visual_seed)
	if posmod(ripple_hash, 13) != 0:
		return
	var shape := posmod(ripple_hash >> 8, 3)
	var drift := posmod(draw_phase + posmod(ripple_hash >> 12, 12), 12)
	# Keep the full fleck inside its visible ocean cell; a drifting endpoint must
	# never paint across a coast or into shroud.
	var local_x := float(posmod((ripple_hash >> 16) + drift, 9)) + 1.5
	var local_y := float(posmod(ripple_hash >> 24, 10)) + 3.0
	var origin := Vector2(cell * TILE_SIZE) + Vector2(local_x, local_y)
	var length := 2.75 + float(shape) * 1.15
	var alpha := 0.08 + float(posmod(draw_phase + shape, 5)) * 0.008
	var light := RIPPLE_LIGHT
	light.a = alpha
	var dark := RIPPLE_DARK
	dark.a = 0.11
	draw_line(origin, origin + Vector2(length, -0.35), light, 0.65, true)
	draw_line(origin + Vector2(1.0, 1.35), origin + Vector2(length - 0.5, 1.0),
		dark, 0.55, true)


func _draw_coast(cell: Vector2i, grid: GridManager) -> void:
	var rect := Rect2(Vector2(cell * TILE_SIZE), Vector2.ONE * TILE_SIZE)
	for direction in EDGE_OFFSETS:
		var neighbor: Vector2i = cell + EDGE_OFFSETS[direction]
		# Never sample a hidden neighbor: even a coastline silhouette can reveal
		# land through the shroud.
		if not grid.in_bounds(neighbor.x, neighbor.y) or not game.is_visible(neighbor):
			continue
		if grid.terrain[neighbor.x][neighbor.y] == "ocean":
			continue
		var a := Vector2.ZERO
		var b := Vector2.ZERO
		match direction:
			"n":
				a = rect.position + Vector2(0, 0.8)
				b = rect.position + Vector2(TILE_SIZE, 0.8)
			"e":
				a = rect.end - Vector2(0.8, TILE_SIZE)
				b = rect.end - Vector2(0.8, 0)
			"s":
				a = rect.end - Vector2(TILE_SIZE, 0.8)
				b = rect.end - Vector2(0, 0.8)
			"w":
				a = rect.position + Vector2(0.8, 0)
				b = rect.position + Vector2(0.8, TILE_SIZE)
		var coast_ink := COAST_INK
		coast_ink.a = 0.72
		var coast_light := COAST_LIGHT
		coast_light.a = 0.22
		draw_line(a, b, coast_ink, 1.25, true)
		draw_line(a, b, coast_light, 0.45, true)


static func visible_cell_bounds(active_camera: Camera2D, viewport_size: Vector2,
		grid_size: Vector2i) -> Rect2i:
	var zoom := maxf(active_camera.zoom.x, 0.001)
	var half_world := viewport_size * 0.5 / zoom + Vector2.ONE * TILE_SIZE
	var minimum := Vector2i(floor((active_camera.position.x - half_world.x) / TILE_SIZE),
		floor((active_camera.position.y - half_world.y) / TILE_SIZE)).max(Vector2i.ZERO)
	var maximum := Vector2i(ceil((active_camera.position.x + half_world.x) / TILE_SIZE),
		ceil((active_camera.position.y + half_world.y) / TILE_SIZE)).min(grid_size)
	return Rect2i(minimum, (maximum - minimum).max(Vector2i.ZERO))
