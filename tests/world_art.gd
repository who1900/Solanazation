extends SceneTree

const WorldArt = preload("res://scripts/ui/WorldArt.gd")

var _failures := 0


func _initialize() -> void:
	_check(WorldArt.TILE_SIZE == 16, "logical tile size remains 16")
	_check(WorldArt.TERRAIN_KINDS.size() == Data.TERRAIN.size(),
		"native terrain contract covers every Data terrain ID")
	for data_kind in Data.TERRAIN:
		_check(WorldArt.TERRAIN_KINDS.has(StringName(data_kind)),
			"%s has a native terrain contract" % data_kind)
	for kind in WorldArt.TERRAIN_KINDS:
		for variant in WorldArt.TERRAIN_VARIANTS:
			var path := WorldArt.terrain_path(String(kind), variant)
			_check(ResourceLoader.exists(path), "%s variant %d exists" % [kind, variant])
			var texture := load(path) as Texture2D
			_check(texture != null and texture.get_size() == Vector2(64, 64),
				"%s variant %d is native 64 px" % [kind, variant])
			if texture != null:
				_check(_edge_delta(texture.get_image()) == Vector2i.ZERO,
					"%s variant %d has repeat-safe opposite edges" % [kind, variant])
		for direction in WorldArt.EDGE_DIRECTIONS:
			var edge_path := WorldArt.transition_path(String(kind), String(direction))
			_check(ResourceLoader.exists(edge_path), "%s edge %s exists" % [kind, direction])
			var edge := load(edge_path) as Texture2D
			_check(edge != null and edge.get_size() == Vector2(64, 64),
				"%s edge %s is native 64 px" % [kind, direction])
		_check(WorldArt.terrain_texture(String(kind), Vector2i(2, 3), 424242) != null,
			"%s resolves through the native deterministic loader" % kind)
		_check(WorldArt.has_native_terrain(String(kind), Vector2i(2, 3), 424242),
			"%s ordinary map cells never use a legacy/procedural fallback" % kind)

	for kind in WorldArt.LANDMARK_KINDS:
		for variant in WorldArt.LANDMARK_VARIANTS:
			var landmark_path := WorldArt.landmark_path(String(kind), variant)
			_check(ResourceLoader.exists(landmark_path),
				"%s landmark variant %d exists" % [kind, variant])
			var landmark := load(landmark_path) as Texture2D
			_check(landmark != null and landmark.get_size() == Vector2(64, 64),
				"%s landmark variant %d is native 64 px" % [kind, variant])
			if landmark != null:
				var image := landmark.get_image()
				_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(63, 63).a == 0.0,
					"%s landmark variant %d keeps transparent corners" % [kind, variant])
				var coverage := _alpha_coverage(image)
				_check(coverage >= 0.07 and coverage <= 0.68,
					"%s landmark variant %d has restrained coverage" % [kind, variant])
		var cluster := {}
		for cell in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)]:
			cluster[WorldArt.landmark_variant_index(String(kind), cell, 424242)] = true
		_check(cluster.size() > 1,
			"%s adjacent 2x2 cluster is not a repeated landmark wallpaper" % kind)
		_check(WorldArt.terrain_landmark_texture(String(kind), Vector2i(4, 4), 424242) != null,
			"%s deterministic landmark loader resolves" % kind)

	var cells := [Vector2i(3, 7), Vector2i(4, 7), Vector2i(3, 8), Vector2i(9, 2)]
	var variants: Array = []
	for cell in cells:
		var first := WorldArt.variant_index("wasteland", cell, 424242)
		var second := WorldArt.variant_index("wasteland", cell, 424242)
		_check(first == second and first >= 0 and first < WorldArt.TERRAIN_VARIANTS,
			"terrain variant selection is deterministic and bounded")
		variants.append(first)
	var unique_variants := {}
	for variant in variants:
		unique_variants[variant] = true
	_check(unique_variants.size() > 1, "nearby cells use more than one variant")
	var first_row: Array[int] = []
	var second_row: Array[int] = []
	for x in 12:
		first_row.append(WorldArt.variant_index("wasteland", Vector2i(x, 0), 424242))
		second_row.append(WorldArt.variant_index("wasteland", Vector2i(x, 4), 424242))
	_check(first_row != second_row,
		"terrain mixing avoids the old four-row lattice repetition")
	_check(WorldArt.variant_index("ocean", Vector2i(3, 7), 424242)
		!= WorldArt.variant_index("ocean", Vector2i(3, 7), 424243),
		"visual seed participates in variant selection")

	for entity_id in WorldArt.ENTITY_CONTRACTS:
		var contract: Dictionary = WorldArt.entity_contract(entity_id)
		var texture := WorldArt.entity_texture(entity_id)
		_check(texture != null, "%s runtime texture loads" % entity_id)
		_check(texture != null and Vector2i(texture.get_size()) == contract.source_size,
			"%s matches native source-size contract" % entity_id)
		if texture != null:
			var image := texture.get_image()
			_check(image.get_pixel(0, 0).a == 0.0, "%s has a transparent corner" % entity_id)

	_check(WorldArt.cable_texture() != null, "cable texture loads")
	_check(WorldArt.entity_texture("outside_slice") == null,
		"unknown entities preserve the procedural fallback")
	_check(WorldArt.terrain_texture("outside_contract", Vector2i.ZERO, 1) == null,
		"unknown terrain does not masquerade as a native material")
	for resource_id in WorldArt.RESOURCE_ICON_PATHS:
		_check(WorldArt.resource_icon(resource_id) != null, "%s resource icon loads" % resource_id)
	for action_id in WorldArt.ACTION_ICON_PATHS:
		_check(WorldArt.action_icon(action_id) != null, "%s action icon loads" % action_id)

	var map_source := FileAccess.get_file_as_string("res://scripts/ui/MapView.gd")
	var units_source := FileAccess.get_file_as_string("res://scripts/ui/UnitsView.gd")
	_check(map_source.contains("TEXTURE_FILTER_LINEAR"), "map uses explicit linear filtering")
	_check(units_source.contains("TEXTURE_FILTER_LINEAR"), "entities use explicit linear filtering")
	_check(FileAccess.file_exists("res://docs/.gdignore"), "source provenance is excluded from runtime import")
	var import_source := FileAccess.get_file_as_string(
		"res://assets/world/entities/units/founder.png.import")
	_check(import_source.contains("compress/mode=0")
		and import_source.contains("mipmaps/generate=false")
		and import_source.contains("process/fix_alpha_border=true")
		and import_source.contains("process/premult_alpha=false"),
		"runtime PNG import matches the documented lossless alpha contract")

	if _failures == 0:
		print("WORLD_ART_PASS")
		quit(0)
	else:
		push_error("WORLD_ART_FAIL failures=%d" % _failures)
		quit(1)


func _edge_delta(image: Image) -> Vector2i:
	var horizontal := 0
	var vertical := 0
	for y in image.get_height():
		for channel in 3:
			horizontal = maxi(horizontal, absi(
				_round_channel(image.get_pixel(0, y), channel)
				- _round_channel(image.get_pixel(image.get_width() - 1, y), channel)))
	for x in image.get_width():
		for channel in 3:
			vertical = maxi(vertical, absi(
				_round_channel(image.get_pixel(x, 0), channel)
				- _round_channel(image.get_pixel(x, image.get_height() - 1), channel)))
	return Vector2i(horizontal, vertical)


func _round_channel(color: Color, channel: int) -> int:
	return roundi([color.r, color.g, color.b][channel] * 255.0)


func _alpha_coverage(image: Image) -> float:
	var visible := 0
	for x in image.get_width():
		for y in image.get_height():
			if image.get_pixel(x, y).a >= 0.0625:
				visible += 1
	return float(visible) / float(image.get_width() * image.get_height())


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("World art: %s" % description)
