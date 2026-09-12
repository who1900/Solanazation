extends Node2D
class_name UnitsView
const WorldArt = preload("res://scripts/ui/WorldArt.gd")
const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")
## UnitsView — unit and city sprites. Synced from Game.

static var instance: Node2D

const TILE_SIZE := 16

static var _unit_tex_cache: Dictionary = {}  # type_id -> Texture2D or null
var _active_units: Dictionary = {}
var _active_cities: Dictionary = {}
var _unit_transitions: Dictionary = {}
var _feedback_nodes: Array[Node] = []
var _feedback_tweens: Array[Tween] = []


## Unit icon (PNG from assets/icons/units/) or null (procedural).
static func unit_texture(type_id: String) -> Texture2D:
	if _unit_tex_cache.has(type_id):
		return _unit_tex_cache[type_id]
	var tex: Texture2D = null
	for path in [
		"res://assets/icons/units/%s.png" % type_id,
		"res://assets/icons/units/unit_%s.png" % type_id,
		"res://assets/icons/units/%s.svg" % type_id,
	]:
		if ResourceLoader.exists(path):
			tex = load(path)
			break
	_unit_tex_cache[type_id] = tex
	return tex

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	instance = self
	if not Game.resources_changed.is_connected(sync):
		Game.resources_changed.connect(sync)
	Game.turn_changed.connect(func(_t): sync())
	Game.unit_moved.connect(func(_u): sync())
	Game.city_changed.connect(func(_c): sync())
	Game.city_build_completed.connect(_play_city_completion)
	Game.match_ready.connect(cancel_motion_feedback)
	sync()


## Rebuilds all sprites (simple and reliable for MVP).
static func sync() -> void:
	if instance == null:
		return
	instance._sync()


func _sync() -> void:
	for child in get_children():
		if child.has_meta("motion_feedback"):
			continue
		child.queue_free()
	# wait a frame so freed nodes don't interfere
	await get_tree().process_frame
	if Game.grid == null:
		return
	for u in Game.units:
		# Enemies visible only in vision range; own units always
		if u.faction_id != Game.faction_id and not Game.is_visible(u.cell):
			continue
		_add_unit_sprite(u)
	for c in Game.cities:
		if c.faction_id != Game.faction_id and not Game.is_visible(c.cell):
			continue
		_add_city_sprite(c)
	for cell in Game.satellite_intel:
		if not Game.is_visible(cell):
			_add_validator_signal(cell)


func _add_validator_signal(cell: Vector2i) -> void:
	var marker := Sprite2D.new()
	marker.name = "ValidatorSignal"
	marker.set_meta("validator_signal", true)
	marker.texture = WorldArt.action_icon("select")
	if marker.texture == null:
		marker.texture = _make_frame_texture()
	marker.position = Game.cell_to_pixel(cell)
	marker.modulate = Color("9274ba")
	marker.z_index = 4
	add_child(marker)


func _add_unit_sprite(u: Unit) -> void:
	var pos := Game.cell_to_pixel(u.cell)
	var sprite := Sprite2D.new()
	var native_art := WorldArt.configure_anchored_sprite(sprite, u.type_id)
	var bg: Sprite2D = null
	if not native_art:
		if WorldArt.requires_native_unit(u.type_id):
			push_error("Missing required native unit art: %s" % u.type_id)
			return
		# Faction square remains the fallback contract for units outside this slice.
		bg = Sprite2D.new()
		bg.texture = _make_faction_bg(u)
		bg.position = pos
		bg.z_index = 9
		add_child(bg)
		var png: Texture2D = UnitsView.unit_texture(u.type_id)
		sprite.texture = png if png != null else _make_unit_texture(u)
		if png != null and png.get_width() > 0 and png.get_height() > 0:
			var icon_size := TILE_SIZE * 1.125
			sprite.scale = Vector2(icon_size / float(png.get_width()), icon_size / float(png.get_height()))
	sprite.position = pos
	var motion_active := _active_units.has(u.get_instance_id())
	if u.faction_id == Game.faction_id and u.moves_left <= 0.001:
		sprite.modulate = Color(0.52, 0.57, 0.60, 0.78)
		if bg != null:
			bg.modulate = Color(0.52, 0.57, 0.60, 0.78)
	sprite.z_index = 10
	add_child(sprite)
	sprite.visible = not motion_active
	var faction_marker := _add_faction_marker(pos, u.faction_id, 12)
	faction_marker.visible = not motion_active
	u.node = sprite
	# selection frame (separate node — not the sprite, so animations move the unit)
	if Game.selected_unit == u and not motion_active:
		var frame := Sprite2D.new()
		frame.texture = _make_frame_texture()
		frame.position = pos
		frame.z_index = 11
		add_child(frame)


func _add_city_sprite(c: City) -> void:
	var sprite := Sprite2D.new()
	if not WorldArt.configure_anchored_sprite(sprite, "city_era_1"):
		sprite.texture = _make_city_texture(c)
	sprite.position = Game.cell_to_pixel(c.cell)
	sprite.z_index = 5
	add_child(sprite)
	var motion_active := _active_cities.has(c.get_instance_id())
	sprite.visible = not motion_active
	var faction_marker := _add_faction_marker(sprite.position, c.faction_id, 8)
	faction_marker.visible = not motion_active
	if not c.build_queue.is_empty():
		_add_city_overlay(sprite.position, "construction", Vector2(-5, -7), 9)
	var state := _city_state(c)
	if state != "ordinary":
		_add_city_overlay(sprite.position, state, Vector2(5, -8), 7)
	if Game.occupation_remaining(c) > 0:
		_add_secured_overlay(sprite.position)
	c.node = sprite


func _city_state(city: City) -> String:
	if city.is_offline() or city.is_dos():
		return "offline_dos"
	if city.is_capital:
		return "capital"
	if city.faction_id == Game.faction_id:
		var energy_state: Dictionary = Game._player_energy_grid_state()
		if bool(energy_state.powered.get(city, false)):
			return "powered"
	return "ordinary"


func _add_city_overlay(pos: Vector2, state_id: String, offset: Vector2, z: int) -> void:
	var texture := WorldArt.city_overlay_texture(state_id)
	if texture == null:
		push_error("Missing required city overlay art: %s" % state_id)
		return
	var sprite := Sprite2D.new()
	sprite.name = "CityOverlay_%s" % state_id
	sprite.texture = texture
	sprite.position = pos + offset
	sprite.scale = Vector2.ONE * (9.0 / 64.0)
	sprite.z_index = z
	add_child(sprite)


func _add_secured_overlay(pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "SecuredCityOverlay"
	sprite.set_meta("secured_city", true)
	sprite.texture = WorldArt.secured_city_texture()
	sprite.position = pos + Vector2(5, 5)
	sprite.scale = Vector2.ONE * 0.72
	sprite.z_index = 9
	add_child(sprite)


func _add_faction_marker(pos: Vector2, marker_faction: int, z: int) -> Sprite2D:
	var marker := Sprite2D.new()
	marker.texture = WorldArt.faction_marker_texture(marker_faction, Game.faction_id, Game.BARB_FACTION)
	marker.position = pos + Vector2(-5.5, 5.5)
	marker.scale = Vector2.ONE * 0.55
	marker.z_index = z
	add_child(marker)
	return marker


func play_unit_move(u: Unit, start_cell: Vector2i, path: Array) -> void:
	if u == null or u.node == null or path.is_empty():
		return
	_finish_existing_transition(u.get_instance_id())
	var ghost := _unit_snapshot(u.node as Sprite2D, Game.cell_to_pixel(start_cell), 20,
		u.faction_id)
	_active_units[u.get_instance_id()] = true
	if MotionFeedback.scale() <= 0.0:
		_finish_unit_feedback(u.get_instance_id(), ghost)
		return
	var tween := create_tween()
	_feedback_tweens.append(tween)
	_unit_transitions[u.get_instance_id()] = {"tween": tween, "nodes": [ghost]}
	var step_duration := minf(0.09, 0.36 / float(path.size()))
	for step in path:
		tween.tween_property(ghost, "position", Game.cell_to_pixel(step), step_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_unit_feedback.bind(u.get_instance_id(), ghost, tween))


func play_combat(attacker: Unit, defender: Unit, attacker_won: bool) -> void:
	if attacker == null or defender == null:
		return
	_finish_existing_transition(attacker.get_instance_id())
	_finish_existing_transition(defender.get_instance_id())
	var attacker_pos := Game.cell_to_pixel(attacker.cell)
	var defender_pos := Game.cell_to_pixel(defender.cell)
	var attacker_ghost := _unit_snapshot(attacker.node as Sprite2D, attacker_pos, 23,
		attacker.faction_id)
	var defender_ghost := _unit_snapshot(defender.node as Sprite2D, defender_pos, 22,
		defender.faction_id)
	var survivor: Unit = attacker if attacker_won else defender
	_active_units[survivor.get_instance_id()] = true
	if MotionFeedback.scale() <= 0.0:
		_finish_combat_feedback(survivor.get_instance_id(), attacker_ghost, defender_ghost)
		return
	var lunge_target := attacker_pos.lerp(defender_pos, 0.38)
	var tween := create_tween()
	_feedback_tweens.append(tween)
	_unit_transitions[survivor.get_instance_id()] = {
		"tween": tween, "nodes": [attacker_ghost, defender_ghost]}
	tween.set_parallel(true)
	tween.tween_property(attacker_ghost, "position", lunge_target,
		MotionFeedback.duration(0.09)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(defender_ghost, "modulate", Color("fff0c2"),
		MotionFeedback.duration(0.09))
	tween.chain().set_parallel(true)
	tween.tween_property(attacker_ghost, "position", attacker_pos,
		MotionFeedback.duration(0.12)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(defender_ghost, "position", defender_pos + Vector2(1.6, 0),
		MotionFeedback.duration(0.055)).set_trans(Tween.TRANS_SINE)
	var loser_ghost := defender_ghost if attacker_won else attacker_ghost
	tween.chain().tween_property(loser_ghost, "modulate:a", 0.0,
		MotionFeedback.duration(0.18)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(loser_ghost, "scale", loser_ghost.scale * 0.72,
		MotionFeedback.duration(0.18))
	tween.tween_callback(_finish_combat_feedback.bind(
		survivor.get_instance_id(), attacker_ghost, defender_ghost, tween))


func play_city_combat(attacker: Unit, city: City, attacker_won: bool) -> void:
	if attacker == null or city == null or attacker.node == null or city.node == null:
		return
	_finish_existing_transition(attacker.get_instance_id())
	var attacker_pos := Game.cell_to_pixel(attacker.cell)
	var city_pos := Game.cell_to_pixel(city.cell)
	var attacker_ghost := _unit_snapshot(attacker.node as Sprite2D, attacker_pos, 23,
		attacker.faction_id)
	var city_ghost := _unit_snapshot(city.node as Sprite2D, city_pos, 22, city.faction_id)
	_active_units[attacker.get_instance_id()] = true
	_active_cities[city.get_instance_id()] = true
	if MotionFeedback.scale() <= 0.0:
		_finish_combat_feedback(attacker.get_instance_id(), attacker_ghost, city_ghost,
			null, city.get_instance_id())
		return
	var tween := create_tween()
	_feedback_tweens.append(tween)
	_unit_transitions[attacker.get_instance_id()] = {
		"tween": tween, "nodes": [attacker_ghost, city_ghost],
		"city_id": city.get_instance_id()}
	tween.set_parallel(true)
	tween.tween_property(attacker_ghost, "position", attacker_pos.lerp(city_pos, 0.38),
		MotionFeedback.duration(0.09)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(city_ghost, "modulate", Color("fff0c2"),
		MotionFeedback.duration(0.09))
	tween.chain().set_parallel(true)
	tween.tween_property(attacker_ghost, "position", attacker_pos,
		MotionFeedback.duration(0.12)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(city_ghost, "modulate",
		Color("bda8ff") if attacker_won else Color.WHITE, MotionFeedback.duration(0.12))
	if attacker_won:
		tween.chain().tween_property(city_ghost, "modulate:a", 0.0,
			MotionFeedback.duration(0.14))
	else:
		tween.chain().tween_interval(MotionFeedback.duration(0.08))
	tween.tween_callback(_finish_combat_feedback.bind(
		attacker.get_instance_id(), attacker_ghost, city_ghost, tween,
		city.get_instance_id()))


func _play_city_completion(city: City, _building_id: String) -> void:
	if city == null or (city.faction_id != Game.faction_id and not Game.is_visible(city.cell)):
		return
	var position := Game.cell_to_pixel(city.cell)
	var scaffold := Sprite2D.new()
	scaffold.texture = WorldArt.city_overlay_texture("construction")
	scaffold.position = position + Vector2(-5, -7)
	scaffold.scale = Vector2.ONE * (9.0 / 64.0)
	scaffold.z_index = 24
	_register_feedback(scaffold)
	var pulse := Sprite2D.new()
	if city.node is Sprite2D:
		var city_sprite := city.node as Sprite2D
		pulse.texture = city_sprite.texture
		pulse.offset = city_sprite.offset
		pulse.scale = city_sprite.scale
	pulse.position = position
	pulse.modulate = Color("bda8ff")
	pulse.z_index = 23
	_register_feedback(pulse)
	if MotionFeedback.scale() <= 0.0:
		_remove_feedback(scaffold)
		_remove_feedback(pulse)
		return
	var tween := create_tween()
	_feedback_tweens.append(tween)
	tween.set_parallel(true)
	tween.tween_property(scaffold, "modulate:a", 0.0, MotionFeedback.duration(0.22))
	tween.tween_property(scaffold, "position:y", scaffold.position.y - 2.0,
		MotionFeedback.duration(0.22)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "scale", pulse.scale * 1.10,
		MotionFeedback.duration(0.16)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(pulse, "modulate:a", 0.0,
		MotionFeedback.duration(0.16))
	tween.tween_callback(func():
		_feedback_tweens.erase(tween)
		_remove_feedback(scaffold)
		_remove_feedback(pulse))


func cancel_motion_feedback() -> void:
	for tween in _feedback_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_feedback_tweens.clear()
	for node in _feedback_nodes.duplicate():
		_remove_feedback(node)
	_active_units.clear()
	_active_cities.clear()
	_unit_transitions.clear()
	sync()


func _finish_existing_transition(unit_id: int) -> void:
	if not _unit_transitions.has(unit_id):
		return
	var transition: Dictionary = _unit_transitions[unit_id]
	var tween: Tween = transition.get("tween")
	if tween != null and tween.is_valid():
		tween.kill()
	_feedback_tweens.erase(tween)
	for node in transition.get("nodes", []):
		_remove_feedback(node)
	var city_id: int = int(transition.get("city_id", 0))
	if city_id != 0:
		_active_cities.erase(city_id)
	_unit_transitions.erase(unit_id)
	_active_units.erase(unit_id)


func _unit_snapshot(source: Sprite2D, position: Vector2, z: int,
		faction_id: int) -> Node2D:
	var ghost := Node2D.new()
	var body := Sprite2D.new()
	if source != null:
		body.texture = source.texture
		body.offset = source.offset
		body.scale = source.scale
		body.modulate = source.modulate
		source.visible = false
	ghost.position = position
	ghost.z_index = z
	ghost.add_child(body)
	var marker := Sprite2D.new()
	marker.texture = WorldArt.faction_marker_texture(
		faction_id, Game.faction_id, Game.BARB_FACTION)
	marker.position = Vector2(-5.5, 5.5)
	marker.scale = Vector2.ONE * 0.55
	marker.z_index = 1
	ghost.add_child(marker)
	for sibling in get_children():
		if sibling is Sprite2D and sibling != source \
				and sibling.position.distance_to(position + Vector2(-5.5, 5.5)) < 0.1:
			sibling.visible = false
	_register_feedback(ghost)
	return ghost


func _register_feedback(node: Node) -> void:
	node.set_meta("motion_feedback", true)
	add_child(node)
	_feedback_nodes.append(node)


func _remove_feedback(node: Node) -> void:
	_feedback_nodes.erase(node)
	if is_instance_valid(node):
		if node is CanvasItem:
			node.visible = false
		node.queue_free()


func _finish_unit_feedback(unit_id: int, ghost: Node, tween: Tween = null) -> void:
	_feedback_tweens.erase(tween)
	if _unit_transitions.get(unit_id, {}).get("tween") == tween:
		_unit_transitions.erase(unit_id)
	_active_units.erase(unit_id)
	_remove_feedback(ghost)
	sync()


func _finish_combat_feedback(unit_id: int, attacker_ghost: Node,
		defender_ghost: Node, tween: Tween = null, city_id: int = 0) -> void:
	_feedback_tweens.erase(tween)
	if _unit_transitions.get(unit_id, {}).get("tween") == tween:
		_unit_transitions.erase(unit_id)
	_active_units.erase(unit_id)
	if city_id != 0:
		_active_cities.erase(city_id)
	_remove_feedback(attacker_ghost)
	_remove_feedback(defender_ghost)
	sync()


## Faction-colored backdrop square.
func _make_faction_bg(u: Unit) -> ImageTexture:
	var border := Color(0.9, 0.8, 0.3)
	if u.faction_id == Game.BARB_FACTION:
		border = Color(0.7, 0.15, 0.15)
	elif u.faction_id != Game.faction_id:
		border = Color(0.85, 0.3, 0.3)
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(border)
	return ImageTexture.create_from_image(img)


## Procedural unit texture: colored square with dark border.
func _make_unit_texture(u: Unit) -> ImageTexture:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color: Color = u.data().color
	# faction border: player = gold, AI = red, barbarians = dark red
	var border := Color(0.9, 0.8, 0.3)
	if u.faction_id == Game.BARB_FACTION:
		border = Color(0.7, 0.15, 0.15)
	elif u.faction_id != Game.faction_id:
		border = Color(0.85, 0.3, 0.3)
	img.fill_rect(Rect2i(0, 0, TILE_SIZE, TILE_SIZE), border)
	img.fill_rect(Rect2i(1, 1, TILE_SIZE - 2, TILE_SIZE - 2), color)
	img.fill_rect(Rect2i(3, 3, TILE_SIZE - 6, TILE_SIZE - 6), Color(color.lightened(0.25), 0.9))
	# veteran: gold dot in corner
	if u.veteran:
		img.fill_rect(Rect2i(10, 1, 4, 4), Color(1.0, 0.9, 0.4))
	# fortified: shield dot
	if u.fortified:
		img.fill_rect(Rect2i(1, 10, 4, 4), Color(0.6, 0.9, 1.0))
	return ImageTexture.create_from_image(img)


func _make_frame_texture() -> ImageTexture:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in TILE_SIZE:
		img.set_pixel(x, 0, Color(1, 1, 1, 0.9))
		img.set_pixel(x, TILE_SIZE - 1, Color(1, 1, 1, 0.9))
		img.set_pixel(0, x, Color(1, 1, 1, 0.9))
		img.set_pixel(TILE_SIZE - 1, x, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)


func _make_city_texture(c: City) -> ImageTexture:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color := Color(0.9, 0.85, 0.5) if c.faction_id == Game.faction_id else Color(0.9, 0.4, 0.3)
	img.fill_rect(Rect2i(2, 2, TILE_SIZE - 4, TILE_SIZE - 4), color)
	img.fill_rect(Rect2i(3, 3, TILE_SIZE - 6, TILE_SIZE - 6), Color(color, 0.6))
	return ImageTexture.create_from_image(img)
