extends Node2D
class_name MapView
const WorldArt = preload("res://scripts/ui/WorldArt.gd")
const WaterSurfaceView = preload("res://scripts/ui/WaterSurfaceView.gd")
## MapView — map rendering via _draw.

const TILE_SIZE := 16
const EDGE_OFFSETS := {
	"n": Vector2i(0, -1),
	"e": Vector2i(1, 0),
	"s": Vector2i(0, 1),
	"w": Vector2i(-1, 0),
}

static var instance: Node2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	Game.resources_changed.connect(_redraw)
	Game.turn_changed.connect(func(_t): _redraw())
	Game.unit_moved.connect(func(_u): _redraw())
	Game.city_changed.connect(func(_c): _redraw())
	Game.selection_changed.connect(func(_o): _redraw())
	Game.log_message.connect(func(_t): _redraw())
	Game.match_ready.connect(func(): call_deferred("_focus_player_start"))
	Game.match_ready.connect(cancel_motion_feedback)
	_camera = get_node_or_null("../Camera")
	_water_surface = WaterSurfaceView.new()
	_water_surface.name = "WaterSurface"
	_water_surface.camera = _camera
	_water_surface.game = Game
	add_child(_water_surface)
	instance = self
	if Game.grid != null:
		call_deferred("_focus_player_start")


func _focus_player_start() -> void:
	if _camera == null or Game.grid == null:
		return
	var focus_cells: Array[Vector2i] = []
	for city in Game.cities:
		if city.faction_id == Game.faction_id and city.is_capital:
			focus_cells.append(city.cell)
			break
	for unit in Game.units:
		if unit.faction_id == Game.faction_id:
			focus_cells.append(unit.cell)
	if focus_cells.is_empty():
		focus_cells.append(Vector2i(Game.grid.w / 2, Game.grid.h / 2))
	var viewport_size := get_viewport_rect().size
	var playable_rect := _playable_viewport_rect()
	var world_bounds := _cell_bounds(focus_cells).grow(TILE_SIZE * 1.5)
	var frame := camera_frame(viewport_size, playable_rect, world_bounds)
	var initial_zoom: float = frame.zoom
	_camera.zoom = Vector2(initial_zoom, initial_zoom)
	_camera.position = frame.position
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = Game.grid.w * TILE_SIZE
	_camera.limit_bottom = Game.grid.h * TILE_SIZE


static func camera_frame(viewport_size: Vector2, playable_rect: Rect2,
		world_bounds: Rect2) -> Dictionary:
	var available := (playable_rect.size - Vector2(48, 48)).max(Vector2(96, 96))
	var zoom := clampf(minf(
		available.x / maxf(world_bounds.size.x, TILE_SIZE),
		available.y / maxf(world_bounds.size.y, TILE_SIZE)), 1.0, MAX_ZOOM)
	# The revealed start area is shallower than the portrait playfield. Keeping
	# its group in the upper 38% avoids a large dead shroud above the first move.
	var screen_anchor := Vector2(playable_rect.get_center().x,
		playable_rect.position.y + playable_rect.size.y * 0.38)
	var camera_position := world_bounds.get_center() \
		- (screen_anchor - viewport_size * 0.5) / zoom
	return { "zoom": zoom, "position": camera_position, "screen_anchor": screen_anchor }


func _cell_bounds(cells: Array[Vector2i]) -> Rect2:
	var minimum := Vector2(cells[0]) * TILE_SIZE
	var maximum := minimum + Vector2.ONE * TILE_SIZE
	for cell in cells:
		minimum = minimum.min(Vector2(cell) * TILE_SIZE)
		maximum = maximum.max((Vector2(cell) + Vector2.ONE) * TILE_SIZE)
	return Rect2(minimum, maximum - minimum)


func _playable_viewport_rect() -> Rect2:
	var ui := get_node_or_null("../UI")
	if ui != null and ui.has_method("playable_map_rect"):
		return ui.playable_map_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func keep_cell_in_playable_rect(cell: Vector2i) -> void:
	if _camera == null:
		return
	var playable := _playable_viewport_rect().grow(-24.0)
	var viewport_center := get_viewport_rect().size * 0.5
	var world_point := Vector2(cell) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
	var screen_point := (world_point - _camera.position) * _camera.zoom.x + viewport_center
	var clamped := Vector2(
		clampf(screen_point.x, playable.position.x, playable.end.x),
		clampf(screen_point.y, playable.position.y, playable.end.y))
	_camera.position -= (clamped - screen_point) / _camera.zoom.x


func _redraw() -> void:
	_movement_cache.clear()
	queue_redraw()
	if _water_surface != null:
		_water_surface.queue_redraw()


func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	var alive: Array = []
	for f in _fx:
		f.t += delta
		if f.t < f.life:
			alive.append(f)
	_fx = alive
	queue_redraw()


## Flash/effect on a tile.
func add_fx(pos: Vector2, color: Color, life: float = 0.35) -> void:
	_fx.append({ "kind": "flash", "pos": pos, "pos2": pos, "t": 0.0, "life": life, "color": color })


## Projectile from tile to tile.
func add_shot(from: Vector2, to: Vector2, color: Color, life: float = 0.22) -> void:
	_fx.append({ "kind": "shot", "pos": from, "pos2": to, "t": 0.0, "life": life, "color": color })


static func shroud_color(cell: Vector2i, visual_seed: int) -> Color:
	# Low-amplitude deterministic grain reads as one material, not a tile grid.
	var grain := posmod(cell.x * 37 + cell.y * 61 + visual_seed, 11)
	return Color("0b1118").lerp(Color("101821"), float(grain) / 42.0)


func _draw_reveal_boundary(cell: Vector2i, rect: Rect2, grid: GridManager,
		visual_seed: int) -> void:
	for direction in EDGE_OFFSETS:
		var neighbor: Vector2i = cell + EDGE_OFFSETS[direction]
		if not grid.in_bounds(neighbor.x, neighbor.y) or not Game.is_explored(neighbor):
			continue
		var edge := Rect2()
		match direction:
			"n": edge = Rect2(rect.position, Vector2(TILE_SIZE, 2))
			"e": edge = Rect2(rect.end - Vector2(2, TILE_SIZE), Vector2(2, TILE_SIZE))
			"s": edge = Rect2(rect.end - Vector2(TILE_SIZE, 2), Vector2(TILE_SIZE, 2))
			"w": edge = Rect2(rect.position, Vector2(2, TILE_SIZE))
		draw_rect(edge, Color("202b35"))
		# A sparse second line softens the reveal without sampling hidden terrain.
		if posmod(cell.x * 13 + cell.y * 29 + visual_seed, 3) == 0:
			draw_rect(edge.grow(-0.75), Color("2b3741"), false, 0.75)


func _draw() -> void:
	if Game.grid == null:
		return
	var g: GridManager = Game.grid
	var visual_seed: int = Game.visual_seed()
	var accent := Game.era_accent()
	var reachable: Dictionary = {}
	var attackable: Dictionary = {}
	var selected_owned := Game.selected_unit != null \
		and Game.selected_unit.faction_id == Game.faction_id
	if selected_owned and Game.selected_unit.moves_left > 0.001:
		reachable = _cached_movement_plan(Game.selected_unit).reachable.duplicate()
		attackable = _attackable_cells(Game.selected_unit)
		for action_cell in _transport_action_cells(Game.selected_unit):
			reachable[action_cell] = []
	for x in g.w:
		for y in g.h:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			if not Game.is_explored(cell):
				# Information-neutral shroud: no terrain lookup or checkerboard leakage.
				draw_rect(rect, shroud_color(cell, visual_seed))
				_draw_reveal_boundary(cell, rect, g, visual_seed)
				continue
			if not Game.is_visible(cell):
				# Draw the last terrain the player actually saw. Never sample the live
				# grid here: purification and other changes behind fog stay hidden.
				var remembered_kind := Game.remembered_terrain(cell)
				var remembered_color: Color = Data.TERRAIN.get(remembered_kind,
					Data.TERRAIN.wasteland).color.darkened(0.72)
				draw_rect(rect, remembered_color)
				continue
			var td: Dictionary = g.terrain_data(x, y)
			var color: Color = td.color
			var terrain_kind: String = g.terrain[x][y]
			var tex: Texture2D = WorldArt.terrain_texture(terrain_kind, cell, visual_seed)
			var native_terrain := WorldArt.has_native_terrain(terrain_kind, cell, visual_seed)
			if tex != null:
				draw_texture_rect(tex, rect, false)
			else:
				draw_rect(rect, color)
				# thin border for readability
				draw_rect(rect, Color(0, 0, 0, 0.15), false, 1.0)
			if native_terrain:
				for direction in WorldArt.EDGE_DIRECTIONS:
					var neighbor: Vector2i = cell + EDGE_OFFSETS[String(direction)]
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= g.w or neighbor.y >= g.h:
						continue
					# A transition silhouette is still terrain information. Never sample
					# it through the shroud or the explored-but-not-visible fog.
					if not Game.is_visible(neighbor):
						continue
					if g.terrain[neighbor.x][neighbor.y] == terrain_kind:
						continue
					# Feather the neighboring material into this tile's boundary.
					var neighbor_kind: String = g.terrain[neighbor.x][neighbor.y]
					var edge := WorldArt.transition_texture(neighbor_kind, String(direction))
					if edge != null:
						draw_texture_rect(edge, rect, false)
			var terrain_landmark := WorldArt.terrain_landmark_texture(
				terrain_kind, cell, visual_seed)
			if terrain_landmark != null:
				draw_texture_rect(terrain_landmark, rect, false)
			_draw_material_detail(terrain_kind, cell, rect, visual_seed)
			# node zones — highlight
			if terrain_kind == "node_zone" and not native_terrain:
				draw_rect(rect, Color(0.13, 0.83, 0.93, 0.35), false, 1.0)
			# Ancient Terminal marker (blinking green screen)
			if Game.terminals.has(cell):
				var terminal := WorldArt.entity_texture("terminal")
				if terminal != null:
					draw_texture_rect(terminal, WorldArt.anchored_rect("terminal", cell), false)
				else:
					var blink := 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.004))
					draw_rect(Rect2(x * TILE_SIZE + 3, y * TILE_SIZE + 3, 10, 10), Color(0.2, 0.9, 0.4, blink))
			# Master Server lair marker (red core)
			if Game.lairs.has(cell):
				var lair := WorldArt.entity_texture("master_server_lair")
				if lair != null:
					draw_texture_rect(lair, WorldArt.anchored_rect("master_server_lair", cell), false)
			# Infrastructure: cable (yellow dots), monorail (cyan line)
			var infra_kind: int = g.infra[x][y]
			if infra_kind == 1:
				var cable := WorldArt.cable_texture()
				if cable != null:
					for offset in EDGE_OFFSETS.values():
						var linked: Vector2i = cell + offset
						if linked.x < 0 or linked.y < 0 or linked.x >= g.w or linked.y >= g.h:
							continue
						if g.infra[linked.x][linked.y] != 1:
							continue
						var end := rect.get_center() + Vector2(offset) * TILE_SIZE * 0.5
						draw_line(rect.get_center(), end, Color("191f25"), 3.0, true)
						draw_line(rect.get_center(), end, Color("b98755"), 1.4, true)
					draw_texture_rect(cable, rect, false)
				else:
					draw_rect(Rect2(x * TILE_SIZE + 6, y * TILE_SIZE + 6, 4, 4), Color(1.0, 0.85, 0.2, 0.9))
			elif infra_kind == 2:
				draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE + 7, TILE_SIZE, 2), Color(0.2, 0.9, 0.9, 0.8))
			# Selected unit highlight (era accent)
			if Game.selected_unit != null and Game.selected_unit.cell == cell:
				var select_icon := WorldArt.action_icon("select")
				if select_icon != null:
					draw_texture_rect(select_icon, rect.grow(1.0), false)
				else:
					draw_rect(rect.grow(1.5), accent, false, 2.0)
			elif Game.selected_city != null and Game.selected_city.cell == cell:
				var city_select_icon := WorldArt.action_icon("select")
				if city_select_icon != null:
					draw_texture_rect(city_select_icon, rect.grow(1.0), false)
				else:
					draw_rect(rect.grow(1.5), accent, false, 2.0)
			# Tile detail: ocean waves, mountain peak, node pulse
			if terrain_kind == "ocean" and not native_terrain:
				draw_line(rect.position + Vector2(2, 8), rect.position + Vector2(6, 8), Color(1, 1, 1, 0.08))
				draw_line(rect.position + Vector2(9, 12), rect.position + Vector2(13, 12), Color(1, 1, 1, 0.06))
			elif terrain_kind == "mountains" and terrain_landmark == null:
				var m := rect.position
				draw_colored_polygon(PackedVector2Array([m + Vector2(8, 3), m + Vector2(13, 13), m + Vector2(3, 13)]), Color(0.75, 0.75, 0.85, 0.35))
			elif terrain_kind == "node_zone" and not native_terrain:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005 + x * 0.7)
				draw_circle(rect.get_center(), 3.0 + pulse * 2.0, Color(0.2, 0.85, 0.95, 0.18 + pulse * 0.15))
			if reachable.has(cell):
				var reachable_icon := WorldArt.action_icon("reachable")
				if reachable_icon != null:
					draw_texture_rect(reachable_icon, rect, false)
				else:
					draw_rect(rect.grow(-1.0), Color(0.13, 0.83, 0.93, 0.22))
					draw_rect(rect.grow(-1.0), Color("35d2dd"), false, 1.0)
			if attackable.has(cell):
				var attack_icon := WorldArt.action_icon("attack")
				if attack_icon != null:
					draw_texture_rect(attack_icon, rect, false)
				else:
					draw_rect(rect.grow(-1.0), Color(0.83, 0.22, 0.22, 0.30))
					draw_rect(rect.grow(-1.0), Color("d45b5b"), false, 1.5)
			# Tile improvements: small white triangle
			var imp: String = g.improvements[x][y]
			if imp == "mine":
				draw_rect(Rect2(x * TILE_SIZE + 5, y * TILE_SIZE + 11, 6, 4), Color(1.0, 1.0, 1.0, 0.8))
			elif imp == "dome":
				draw_rect(Rect2(x * TILE_SIZE + 5, y * TILE_SIZE + 11, 6, 4), Color(0.7, 1.0, 0.7, 0.8))
			elif imp == "tower":
				draw_rect(Rect2(x * TILE_SIZE + 6, y * TILE_SIZE + 10, 4, 6), Color(0.9, 0.9, 1.0, 0.8))
	# --- Visual effects (flashes, shots) ---
	for f in _fx:
		var a: float = 1.0 - f.t / f.life
		if f.kind == "flash":
			var center: Vector2 = f.pos * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
			var radius := 9.0 + 4.0 * a
			var flash_color := Color(1.0, 0.72, 0.08, a)
			draw_circle(center, radius, flash_color, false, 3.0, true)
			draw_line(center - Vector2.ONE * 5.0, center + Vector2.ONE * 5.0,
				flash_color, 3.0, true)
			draw_line(center + Vector2(-5.0, 5.0), center + Vector2(5.0, -5.0),
				flash_color, 3.0, true)
		elif f.kind == "shot":
			var prog: float = f.t / f.life
			var p1: Vector2 = f.pos * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
			var p2: Vector2 = f.pos2 * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
			var cur: Vector2 = p1.lerp(p2, prog)
			draw_circle(cur, 3.0, Color(f.color.r, f.color.g, f.color.b, 0.9))
			draw_line(p1, cur, Color(f.color.r, f.color.g, f.color.b, 0.4), 1.5)
		elif f.kind == "blocked":
			var blocked := WorldArt.action_icon("blocked")
			var blocked_rect := Rect2(f.pos * TILE_SIZE, Vector2.ONE * TILE_SIZE)
			if blocked != null:
				draw_texture_rect(blocked, blocked_rect, false, Color(1, 1, 1, a))
			else:
				draw_rect(blocked_rect.grow(-2.0), Color(0.83, 0.22, 0.22, a), false, 2.0)


func _draw_material_detail(kind: String, cell: Vector2i, rect: Rect2,
		visual_seed: int) -> void:
	# Large value groups stay in the authored base. These sparse marks communicate
	# material/function at phone scale without turning every tile into an icon.
	var cluster_cell := Vector2i(floori(float(cell.x) / 3.0), floori(float(cell.y) / 3.0))
	var cluster_hash := WorldArt.cosmetic_hash(kind + "_detail_cluster", cluster_cell, visual_seed)
	if posmod(cluster_hash, 5) != 0:
		return
	var detail_hash := WorldArt.cosmetic_hash(kind + "_detail", cell, visual_seed)
	if posmod(detail_hash, 3) != 0:
		return
	var signature := posmod(detail_hash >> 8, 11)
	var offset := Vector2(float(posmod(detail_hash >> 12, 3)),
		float(posmod(detail_hash >> 16, 3)))
	var p := rect.position + offset
	match kind:
		"wasteland":
			draw_line(p + Vector2(5, 6), p + Vector2(8, 8), Color("665f55"), 0.55, true)
			draw_line(p + Vector2(8, 8), p + Vector2(7, 11), Color("665f55"), 0.55, true)
		"ruins":
			draw_line(p + Vector2(3, 5), p + Vector2(10, 5), Color("8e8b82"), 0.75, true)
			draw_line(p + Vector2(10, 5), p + Vector2(10, 9), Color("575b5d"), 0.75, true)
			if signature <= 2:
				draw_line(p + Vector2(5, 10), p + Vector2(8, 10), Color("9a6748"), 0.65, true)
		"swamp":
			draw_line(p + Vector2(3, 10), p + Vector2(10, 9), Color("7d8264"), 0.65, true)
			draw_line(p + Vector2(8, 9), p + Vector2(8, 5), Color("77755b"), 0.65, true)
			draw_line(p + Vector2(10, 9), p + Vector2(11, 6), Color("77755b"), 0.65, true)
		"node_zone":
			var signal_color := Color("8f82c9")
			signal_color.a = 0.48
			draw_line(p + Vector2(3, 9), p + Vector2(7, 9), Color("555b67"), 0.7, true)
			draw_line(p + Vector2(7, 9), p + Vector2(7, 5), Color("555b67"), 0.7, true)
			draw_circle(p + Vector2(7, 5), 0.85, signal_color)


var _drag_start: Vector2 = Vector2.ZERO
var _dragging := false
var _camera: Camera2D
var _water_surface: WaterSurfaceView
var _fx: Array = []  # {kind, pos, pos2, t, life, color}
var _movement_cache: Dictionary = {}
var _touches: Dictionary = {}  # touch index -> screen position
var _touch_start := Vector2.ZERO
var _touch_index := -1
var _touch_panning := false
var _touch_was_multitouch := false
var _last_mouse_position := Vector2(-10000.0, -10000.0)
var _last_mouse_msec := -1000
var _last_touch_position := Vector2(-10000.0, -10000.0)
var _last_touch_msec := -1000

const MIN_ZOOM := 0.6
const MAX_ZOOM := 3.5
const TOUCH_PAN_THRESHOLD := 20.0


func _unhandled_input(event: InputEvent) -> void:
	if _handle_map_input(event):
		get_viewport().set_input_as_handled()


func _handle_map_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.position.distance_to(_last_touch_position) < 1.0 \
				and Time.get_ticks_msec() - _last_touch_msec < 80:
			return true
		_last_mouse_position = event.position
		_last_mouse_msec = Time.get_ticks_msec()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.1)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 0.9)
			return true
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_start = event.position
				_dragging = true
			else:
				var drag_dist: float = (event.position - _drag_start).length()
				if drag_dist < 15.0 and _dragging:
					# tap -> action
					var local: Vector2 = _screen_to_local(event.position)
					_handle_click(_cell_at(local))
				_dragging = false
			return true
	elif event is InputEventMouseMotion and _dragging:
		if _camera != null:
			_camera.position -= event.relative / _camera.zoom.x
		return true
	elif event is InputEventScreenTouch:
		if event.position.distance_to(_last_mouse_position) < 1.0 \
				and Time.get_ticks_msec() - _last_mouse_msec < 80:
			return true
		_last_touch_position = event.position
		_last_touch_msec = Time.get_ticks_msec()
		_handle_screen_touch(event)
		return true
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
		return true
	return false


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_touch_index = event.index
			_touch_start = event.position
			_touch_panning = false
			_touch_was_multitouch = false
		else:
			_touch_was_multitouch = true
			_touch_panning = false
		return
	var may_tap := event.index == _touch_index and _touches.size() == 1 \
		and not _touch_panning and not _touch_was_multitouch \
		and event.position.distance_to(_touch_start) < TOUCH_PAN_THRESHOLD
	_touches.erase(event.index)
	if may_tap:
		_handle_click(_cell_at(_screen_to_local(event.position)))
	if _touches.is_empty():
		cancel_touch_gestures()
	else:
		# A finger left after a pinch must never become a tap from stale state.
		_touch_index = int(_touches.keys()[0])
		_touch_start = _touches[_touch_index]
		_touch_panning = false
		_touch_was_multitouch = true


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var old_position: Vector2 = _touches[event.index]
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_touch_was_multitouch = true
		var indices: Array = _touches.keys()
		var first_index: int = int(indices[0])
		var second_index: int = int(indices[1])
		var first_new: Vector2 = _touches[first_index]
		var second_new: Vector2 = _touches[second_index]
		var first_old := old_position if first_index == event.index else first_new
		var second_old := old_position if second_index == event.index else second_new
		var old_distance: float = first_old.distance_to(second_old)
		var new_distance: float = first_new.distance_to(second_new)
		_apply_pinch(first_old, second_old, first_new, second_new,
			old_distance, new_distance)
		return
	if event.index != _touch_index:
		return
	if not _touch_panning and event.position.distance_to(_touch_start) >= TOUCH_PAN_THRESHOLD:
		_touch_panning = true
	if _touch_panning and _camera != null:
		_camera.position -= event.relative / _camera.zoom.x


func cancel_touch_gestures() -> void:
	_touches.clear()
	_touch_index = -1
	_touch_panning = false
	_touch_was_multitouch = false
	_dragging = false


func cancel_motion_feedback() -> void:
	_fx.clear()
	queue_redraw()


func _apply_pinch(first_old: Vector2, second_old: Vector2,
		first_new: Vector2, second_new: Vector2,
		old_distance: float, new_distance: float) -> void:
	if _camera == null or old_distance <= 0.001:
		return
	var viewport_center := get_viewport_rect().size * 0.5
	var old_midpoint := (first_old + second_old) * 0.5
	var new_midpoint := (first_new + second_new) * 0.5
	var old_zoom: float = _camera.zoom.x
	var world_anchor := _camera.position + (old_midpoint - viewport_center) / old_zoom
	var new_zoom := clampf(old_zoom * new_distance / old_distance, MIN_ZOOM, MAX_ZOOM)
	_camera.position = world_anchor - (new_midpoint - viewport_center) / new_zoom
	_camera.zoom = Vector2(new_zoom, new_zoom)


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x) / TILE_SIZE, int(pos.y) / TILE_SIZE)


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	if _camera == null:
		return
	var viewport_center := get_viewport_rect().size * 0.5
	var world_at_point := _camera.position + (screen_pos - viewport_center) / _camera.zoom.x
	var new_zoom := clampf(_camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	_camera.position = world_at_point - (screen_pos - viewport_center) / new_zoom
	_camera.zoom = Vector2(new_zoom, new_zoom)


## Screen position of a tile (camera-aware) — for radial menus.
func cell_to_screen(cell: Vector2i) -> Vector2:
	var world := Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
	return get_global_transform_with_canvas() * world


func _handle_click(cell: Vector2i) -> void:
	if Game.grid == null or not Game.grid.in_bounds(cell.x, cell.y):
		return
	var city := Game.city_at(cell)
	var unit := Game.unit_at(cell)
	# Blind taps must not turn hidden occupants into an information channel.
	if not Game.is_visible(cell):
		if city != null and city.faction_id != Game.faction_id:
			city = null
		if unit != null and unit.faction_id != Game.faction_id:
			unit = null
	var sel: Unit = Game.selected_unit

	if sel != null and sel.faction_id == Game.faction_id:
		if unit == sel:
			Game.select(null)
			return
		if unit != null and unit.faction_id == Game.faction_id:
			var loaded := Game.load_unit(unit, sel) if sel.is_naval() \
				else Game.load_unit(sel, unit)
			if loaded:
				UnitsView.sync()
				return
			Game.select(unit)
			return
		if city != null and city.faction_id == Game.faction_id:
			Game.select(city)
			return
		if sel.moves_left <= 0.001:
			_invalid_target(cell)
			return
		if sel.type_id == "net_broker":
			_net_broker_action(sel, cell)
			return
		if unit == null and city == null and sel.is_naval() and not sel.cargo.is_empty() \
				and Game.unload_unit(sel, cell):
			UnitsView.sync()
			return
		if unit != null and unit.faction_id != Game.faction_id:
			if _can_attack_cell(sel, cell) and Game.can_attack_faction(unit.faction_id):
				_attack(sel, unit)
			else:
				_invalid_target(cell)
			return
		if city != null and city.faction_id != Game.faction_id:
			if _can_attack_cell(sel, cell) and Game.can_attack_faction(city.faction_id):
				_attack_city(sel, city)
			else:
				_invalid_target(cell)
			return
		if unit == null and city == null:
			if _move_unit(sel, cell):
				return
			_invalid_target(cell)
			return

	if unit != null:
		Game.select(null if Game.selected_unit == unit else unit)
	elif city != null:
		Game.select(null if Game.selected_city == city else city)
	else:
		Game.select(null)


func _invalid_target(cell: Vector2i) -> void:
	_fx.append({
		"kind": "blocked",
		"pos": Vector2(cell.x, cell.y),
		"pos2": Vector2(cell.x, cell.y),
		"t": 0.0,
		"life": 0.55,
		"color": Color("d45b5b"),
	})


func _move_unit(u: Unit, target: Vector2i) -> bool:
	var plan := _cached_movement_plan(u)
	var reachable: Dictionary = plan.reachable
	if not reachable.has(target):
		return false
	var path := _path_from_plan(plan, u.cell, target)
	var executed: Array = []
	var start_cell := u.cell
	var start_moves := u.moves_left
	var start_moved := u.has_moved_this_turn
	var start_fortified := u.fortified
	for step in path:
		if not u.try_move(step):
			Game.grid.clear_occupant(u.cell.x, u.cell.y, u)
			u.cell = start_cell
			for passenger in u.cargo:
				passenger.cell = start_cell
			Game.grid.place_occupant(start_cell.x, start_cell.y, u)
			u.moves_left = start_moves
			u.has_moved_this_turn = start_moved
			u.fortified = start_fortified
			return false
		executed.append(step)
	if UnitsView.instance != null:
		UnitsView.instance.play_unit_move(u, start_cell, executed)
	Game._sfx("move")
	Game.update_visibility()
	UnitsView.sync()
	Game.emit_signal("unit_moved", u)
	# Ancient Terminals (goody huts) and Master Server lairs
	if Game.terminals.has(u.cell):
		Game.activate_terminal(u, u.cell)
	if Game.lairs.has(u.cell):
		Game.capture_lair(u.cell)
	return true


func _movement_plan(u: Unit) -> Dictionary:
	# Movement costs have two decimal precision (1.00 / 0.34 / 0.01), so a
	# bounded integer bucket queue is both exact and linear in reachable tiles.
	var budget := maxi(roundi(u.moves_left * 100.0), 0)
	var width: int = Game.grid.w
	var cell_count: int = width * Game.grid.h
	var passable := PackedByteArray()
	passable.resize(cell_count)
	var naval := u.is_naval()
	for x in Game.grid.w:
		for y in Game.grid.h:
			if Game.grid.occupant[x][y] != null:
				continue
			var terrain_data: Dictionary = Data.TERRAIN[Game.grid.terrain[x][y]]
			var water: bool = terrain_data.get("water", false)
			if (naval and water) or (not naval and not water \
					and not terrain_data.get("impassable", false)):
				passable[y * width + x] = 1
	var costs := PackedInt32Array()
	var previous := PackedInt32Array()
	costs.resize(cell_count)
	previous.resize(cell_count)
	costs.fill(-1)
	previous.fill(-1)
	var start_index := u.cell.y * width + u.cell.x
	costs[start_index] = 0
	var buckets: Array = []
	buckets.resize(budget + 1)
	for index in buckets.size():
		buckets[index] = []
	buckets[0].append(start_index)
	for distance in range(budget + 1):
		var bucket: Array = buckets[distance]
		var read_index := 0
		while read_index < bucket.size():
			var current_index: int = bucket[read_index]
			read_index += 1
			if costs[current_index] != distance:
				continue
			var current_x := current_index % width
			var current_y := current_index / width
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var next_x := current_x + dx
					var next_y := current_y + dy
					if next_x < 0 or next_x >= width or next_y < 0 or next_y >= Game.grid.h:
						continue
					var next_index := next_y * width + next_x
					if passable[next_index] == 0:
						continue
					var step_cost := 100
					if Game.grid.infra[next_x][next_y] == 1:
						step_cost = 34
					elif Game.grid.infra[next_x][next_y] == 2:
						step_cost = 1
					var next_cost := distance + step_cost
					if next_cost > budget or (costs[next_index] >= 0 \
							and costs[next_index] <= next_cost):
						continue
					costs[next_index] = next_cost
					previous[next_index] = current_index
					buckets[next_cost].append(next_index)
	var reachable: Dictionary = {}
	for index in cell_count:
		if index != start_index and costs[index] >= 0:
			reachable[Vector2i(index % width, index / width)] = true
	return {"previous": previous, "reachable": reachable, "width": width}


func _cached_movement_plan(u: Unit) -> Dictionary:
	var key := "%d:%d:%d:%.3f" % [u.get_instance_id(), u.cell.x, u.cell.y, u.moves_left]
	if _movement_cache.get("key", "") != key:
		_movement_cache = {"key": key, "plan": _movement_plan(u)}
	return _movement_cache.plan


func _path_from_plan(plan: Dictionary, start: Vector2i, target: Vector2i) -> Array:
	var path: Array = []
	var width: int = plan.width
	var previous: PackedInt32Array = plan.previous
	var start_index := start.y * width + start.x
	var cursor_index := target.y * width + target.x
	while cursor_index != start_index:
		if cursor_index < 0 or cursor_index >= previous.size() \
				or previous[cursor_index] < 0:
			return []
		path.push_front(Vector2i(cursor_index % width, cursor_index / width))
		cursor_index = previous[cursor_index]
	return path


func _movement_neighbors(cell: Vector2i) -> Array:
	var result: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx != 0 or dy != 0:
				result.append(cell + Vector2i(dx, dy))
	return result


func _attackable_cells(u: Unit) -> Dictionary:
	var result: Dictionary = {}
	if u.attack() <= 0 or u.moves_left <= 0.001:
		return result
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var cell := u.cell + Vector2i(dx, dy)
			if _can_attack_cell(u, cell):
				result[cell] = true
	return result


func _transport_action_cells(u: Unit) -> Array:
	var result: Array = []
	for cell in _movement_neighbors(u.cell):
		if absi(cell.x - u.cell.x) + absi(cell.y - u.cell.y) != 1:
			continue
		var other := Game.unit_at(cell)
		if other != null and other.faction_id == Game.faction_id:
			if (u.is_naval() and not other.is_naval() and u.cargo.size() < u.transport_capacity()) \
					or (not u.is_naval() and other.is_naval() \
					and other.cargo.size() < other.transport_capacity()):
				result.append(cell)
		elif u.is_naval() and not u.cargo.is_empty() \
				and Game.grid.is_passable(cell.x, cell.y):
			result.append(cell)
	return result


func _can_attack_cell(u: Unit, cell: Vector2i) -> bool:
	if u.attack() <= 0 or u.moves_left <= 0.001 \
			or maxi(absi(cell.x - u.cell.x), absi(cell.y - u.cell.y)) != 1:
		return false
	var unit := Game.unit_at(cell)
	var city := Game.city_at(cell)
	var faction := unit.faction_id if unit != null else city.faction_id if city != null else -1
	return faction >= 0 and faction != Game.faction_id and Game.can_attack_faction(faction)


func _attack(attacker: Unit, defender: Unit) -> void:
	attacker.moves_left = 0
	Game._sfx("combat")
	# Steel Protocol: +25% attack (faction passive)
	var atk_mult := 1.0
	if attacker.faction_id == Game.faction_id:
		atk_mult = Game.faction_attack_bonus()
	var attacker_won := attacker.fight_vs(defender, Game.gameplay_randf(), atk_mult)
	if UnitsView.instance != null:
		UnitsView.instance.play_combat(attacker, defender, attacker_won)
	if attacker_won:
		Game.game_log("%s destroyed %s" % [attacker.data().name, defender.data().name])
		Game.on_kill(attacker, defender)
		Game._remove_unit(defender)
	else:
		Game.game_log("%s died fighting %s" % [attacker.data().name, defender.data().name])
		Game._remove_unit(attacker)
	Game.emit_signal("unit_moved", attacker)
	UnitsView.sync()


func _attack_city(attacker: Unit, city: City) -> void:
	if Game.occupation_remaining(city) > 0:
		Game.game_log("%s is secured for %d more turns" % [city.name, Game.occupation_remaining(city)])
		return
	attacker.moves_left = 0
	# City capture: simple attack; city flips on win
	var garrison := Unit.new("rust_guard", city.faction_id, city.cell, Game.grid)
	var def_mult := 1.0
	if city.has_building("assembly_forge") and city.faction != null \
			and city.faction.id == "steel":
		# Fortress Server: +100% city defense
		def_mult = 2.0
	var attacker_won := attacker.fight_vs(garrison, Game.gameplay_randf(), 1.0, def_mult)
	if UnitsView.instance != null:
		UnitsView.instance.play_city_combat(attacker, city, attacker_won)
	if attacker_won:
		Game.capture_city(city, Game.faction_id)
		Game.game_log("City %s captured! Consensus expands." % city.name)
	Game.emit_signal("unit_moved", attacker)
	UnitsView.sync()

## ---------- Net Broker: bribe / sabotage / theft ----------

func _net_broker_action(broker: Unit, target: Vector2i) -> void:
	# Network Outage: active abilities unavailable
	if Game.event_active == "outage":
		Game.game_log("Network outage — broker abilities offline")
		return
	var enemy_unit := Game.unit_at(target)
	var enemy_city := Game.city_at(target)
	if enemy_unit != null and enemy_unit.faction_id != Game.faction_id:
		_bribe(broker, enemy_unit)
	elif enemy_city != null and enemy_city.faction_id != Game.faction_id:
		_show_broker_menu(broker, enemy_city)
	else:
		# otherwise — normal movement
		if _move_unit(broker, target):
			pass


## Net Broker city operation menu (mobile: large buttons).
func _show_broker_menu(broker: Unit, city: City) -> void:
	_close_broker_menu()
	var menu := Control.new()
	menu.name = "BrokerMenu"
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ui := get_node_or_null("../UI")
	if ui != null and ui.has_method("control_theme"):
		menu.theme = ui.control_theme()
	add_child(menu)
	var center: Vector2 = cell_to_screen(city.cell)
	var items := [
		["DOS / 3 TURNS", func(): _hack(broker, city, "dos")],
		["SYBIL / 30%", func(): _hack(broker, city, "sybil")],
		["HARDFORK", func(): _hack(broker, city, "revolt")],
	]
	for i in items.size():
		var angle := -PI / 2.0 + (TAU * i / items.size())
		var b := Button.new()
		b.text = items[i][0]
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(150, 48)
		b.position = _clamp_menu_position(
			center + Vector2(cos(angle), sin(angle)) * 130 - Vector2(75, 24),
			Vector2(150, 48), get_viewport_rect().size, _broker_safe_rect())
		b.pressed.connect(items[i][1])
		menu.add_child(b)
	# cancel button
	var cancel := Button.new()
	cancel.text = "CLOSE"
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.custom_minimum_size = Vector2(48, 48)
	cancel.position = _clamp_menu_position(
		center + Vector2(0, -60) - Vector2(24, 24),
		Vector2(48, 48), get_viewport_rect().size, _broker_safe_rect())
	cancel.pressed.connect(_close_broker_menu)
	menu.add_child(cancel)


func _close_broker_menu() -> void:
	var old := get_node_or_null("BrokerMenu")
	if old != null:
		old.queue_free()


func _clamp_menu_position(desired: Vector2, control_size: Vector2,
		viewport_size: Vector2, safe_rect: Rect2 = Rect2()) -> Vector2:
	var bounds := safe_rect if safe_rect.size.x > 0.0 and safe_rect.size.y > 0.0 \
		else Rect2(Vector2.ZERO, viewport_size)
	return Vector2(
		clampf(desired.x, bounds.position.x,
			maxf(bounds.end.x - control_size.x, bounds.position.x)),
		clampf(desired.y, bounds.position.y,
			maxf(bounds.end.y - control_size.y, bounds.position.y)))


func _broker_safe_rect() -> Rect2:
	var ui := get_node_or_null("../UI")
	if ui != null and ui.has_method("current_safe_rect"):
		return ui.current_safe_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


## Hack defense: Genesis Block (50 turns), Genesis Chapter (50%), Block Encryption (-25%).
func _hack_blocked() -> bool:
	if Game.shield_turns > 0:
		Game.game_log("Genesis Block repels the hack (%d turns left)" % Game.shield_turns)
		return true
	if Game.artifacts.has("genesis_chapter") and Game.gameplay_randf() < 0.5:
		Game.game_log("Genesis Chapter deflected the Sybil attack!")
		return true
	if Game.has_passive("hack_defense") and Game.gameplay_randf() < 0.25:
		Game.game_log("Block Encryption fended off the hack!")
		return true
	return false


## Execute broker operation (DoS / Sybil / Hardfork).
func _hack(broker: Unit, city: City, op: String) -> void:
	_close_broker_menu()
	if _hack_blocked():
		broker.moves_left = 0
		Game.emit_signal("unit_orders_changed", broker)
		return
	match op:
		"dos":
			city.dos_turns = 3
			Game.game_log("DoS: %s offline for 3 turns!" % city.name)
		"sybil":
			var stolen := 0
			if Game.ai != null and Game.ai.ai_resources.has(city.faction_id):
				stolen = int(Game.ai.ai_resources[city.faction_id].sol * 0.3)
				Game.ai.ai_resources[city.faction_id].sol -= stolen
				Game.resources.sol += stolen
				Game.game_log("Sybil: stole %d $SOL from %s" % [stolen, city.name])
				Game.emit_signal("resources_changed")
			else:
				Game.game_log("Sybil: no treasury to drain")
		"revolt":
			var previous_population := city.population
			city.population = maxi(city.population - 1, 1)
			if city.population != previous_population:
				Game.recompute_city_worked_tiles()
			var bp := Game.grid.find_free_tile_near(city.cell.x, city.cell.y, 3)
			if bp.x >= 0:
				Game._spawn_unit("auto_mech", bp, Game.BARB_FACTION)
			Game.game_log("Hardfork: riot in %s! Population -1" % city.name)
	broker.moves_left = 0
	Game.emit_signal("unit_orders_changed", broker)
	UnitsView.sync()


func _bribe(broker: Unit, enemy: Unit) -> void:
	if not enemy.cargo.is_empty():
		Game.game_log("A loaded transport cannot be bribed")
		return
	var price := 10
	if Game.resources.sol < price:
		Game.game_log("Not enough $SOL to bribe (%d)" % price)
		return
	if Game.gameplay_randf() < 0.6:
		Game.resources.sol -= price
		enemy.faction_id = Game.faction_id
		enemy.moves_left = 0
		broker.moves_left = 0
		Game.game_log("%s bribed into the Consensus!" % enemy.data().name)
		Game.emit_signal("resources_changed")
	else:
		Game.resources.sol -= price
		broker.moves_left = 0
		Game.game_log("Bribe failed — %s stayed loyal" % enemy.data().name)
	Game.emit_signal("unit_orders_changed", broker)
	UnitsView.sync()


func _sabotage(broker: Unit, city: City) -> void:
	# Genesis Block: immune to hacks for 50 turns
	if Game.shield_turns > 0:
		Game.game_log("Genesis Block repels the hack (%d turns left)" % Game.shield_turns)
		broker.moves_left = 0
		Game.emit_signal("unit_orders_changed", broker)
		return
	# Genesis Chapter artifact: 50% Sybil protection
	if Game.artifacts.has("genesis_chapter") and Game.gameplay_randf() < 0.5:
		Game.game_log("Genesis Chapter deflected the Sybil attack!")
		broker.moves_left = 0
		Game.emit_signal("unit_orders_changed", broker)
		return
	# Sabotage: destroy an energy building; else skim $SOL
	var energy_buildings := ["nuclear_plant", "steam_turbine"]
	var removed := ""
	for b in energy_buildings:
		if city.has_building(b):
			city.buildings.erase(b)
			removed = Data.BUILDINGS[b].name
			break
	if removed != "":
		Game.game_log("%s sabotaged! %s destroyed." % [city.name, removed])
	else:
		var stolen := mini(Game.resources.sol, 10)
		Game.resources.sol -= stolen
		Game.game_log("No reactor found — %d $SOL skimmed from %s" % [stolen, city.name])
		Game.emit_signal("resources_changed")
	broker.moves_left = 0
	Game.emit_signal("unit_orders_changed", broker)
	Game.emit_signal("city_changed", city)
	UnitsView.sync()
