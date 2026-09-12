extends SceneTree

const WorldArt = preload("res://scripts/ui/WorldArt.gd")

var failures := 0


func _initialize() -> void:
	var expected := {
		"miner_quad": Vector2i(96, 96),
		"raider_walker": Vector2i(96, 96),
		"heavy_mech": Vector2i(96, 96),
		"net_broker": Vector2i(96, 96),
		"virus_pickup": Vector2i(96, 96),
		"auto_mech": Vector2i(96, 96),
		"master_server_lair": Vector2i(128, 128),
	}
	for entity_id in expected:
		var contract := WorldArt.entity_contract(entity_id)
		var texture := WorldArt.entity_texture(entity_id)
		_check(not contract.is_empty(), "%s has a central contract" % entity_id)
		_check(texture != null and Vector2i(texture.get_size()) == expected[entity_id],
			"%s has its native source size" % entity_id)
		if texture != null:
			var image := texture.get_image()
			_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(image.get_width() - 1, 0).a == 0.0,
				"%s keeps transparent corners" % entity_id)
			_check(_alpha_coverage(image) >= 0.16 and _alpha_coverage(image) <= 0.48,
				"%s has readable restrained coverage" % entity_id)
	for unit_id in WorldArt.NATIVE_UNIT_IDS:
		_check(WorldArt.requires_native_unit(String(unit_id)), "%s is native-required" % unit_id)
		_check(WorldArt.entity_texture(String(unit_id)) != null, "%s cannot need fallback" % unit_id)

	for state_id in ["construction", "capital", "powered", "offline_dos"]:
		var overlay := WorldArt.city_overlay_texture(state_id)
		_check(overlay != null and Vector2i(overlay.get_size()) == Vector2i(64, 64),
			"%s city overlay is native 64 px" % state_id)
	_check(WorldArt.city_overlay_texture("ordinary") == null,
		"ordinary city state stays visually quiet")

	var player := WorldArt.faction_marker_texture(0, 0, 99).get_image()
	var rival := WorldArt.faction_marker_texture(1, 0, 99).get_image()
	var rogue := WorldArt.faction_marker_texture(99, 0, 99).get_image()
	for marker in [player, rival, rogue]:
		var bounds := _alpha_bounds(marker)
		_check(bounds.size.x >= 5 and bounds.size.y >= 5,
			"faction marker renders at least two pixels at default zoom")
	_check(_alpha_signature(player) != _alpha_signature(rival)
		and _alpha_signature(rival) != _alpha_signature(rogue),
		"ownership survives grayscale/CVD through different marker shapes")
	_check(_alpha_signature(WorldArt.faction_marker_texture(1, 0, 99).get_image())
		== _alpha_signature(rival), "faction marker is deterministic")

	var units_source := FileAccess.get_file_as_string("res://scripts/ui/UnitsView.gd")
	var map_source := FileAccess.get_file_as_string("res://scripts/ui/MapView.gd")
	_check(units_source.contains("WorldArt.requires_native_unit(u.type_id)")
		and units_source.contains("Missing required native unit art"),
		"native-required IDs stop instead of entering procedural fallback")
	_check(units_source.contains("_add_faction_marker(pos, u.faction_id")
		and units_source.contains("_add_faction_marker(sprite.position, c.faction_id"),
		"one ownership overlay covers both native units and cities")
	_check(units_source.contains("Vector2(-5.5, 5.5)")
		and units_source.contains("Vector2(-5, -7), 9"),
		"ownership and construction anchors do not overlap")
	_check(units_source.contains("city.is_offline() or city.is_dos()")
		and units_source.contains("not c.build_queue.is_empty()"),
		"city state and construction overlays use existing model state")
	_check(map_source.contains("entity_texture(\"master_server_lair\")")
		and not map_source.contains("Master Server lair marker (red core)\n\t\t\tif Game.lairs.has(cell):\n\t\t\t\tdraw_rect"),
		"Master Server lair no longer uses its red-square fallback")

	if failures == 0:
		print("EARLY_CONFLICT_ART_PASS")
		quit(0)
	else:
		push_error("EARLY_CONFLICT_ART_FAIL failures=%d" % failures)
		quit(1)


func _alpha_coverage(image: Image) -> float:
	var visible := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.0625:
				visible += 1
	return float(visible) / float(image.get_width() * image.get_height())


func _alpha_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i.ZERO
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.5:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x + 1, y + 1))
	return Rect2i(minimum, maximum - minimum)


func _alpha_signature(image: Image) -> String:
	var signature := ""
	for y in image.get_height():
		for x in image.get_width():
			signature += "1" if image.get_pixel(x, y).a >= 0.5 else "0"
	return signature


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	failures += 1
	push_error("Early conflict art: %s" % description)
