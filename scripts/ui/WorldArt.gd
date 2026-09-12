class_name WorldArt
extends RefCounted
## Shared, deterministic asset contract for the first world-art vertical slice.

const TILE_SIZE := 16
const TERRAIN_VARIANTS := 4
const LANDMARK_VARIANTS := 3
const TERRAIN_KINDS := [
	&"ocean", &"wasteland", &"ruins", &"swamp", &"node_zone",
	&"mountains", &"crater", &"dump", &"rift",
]
const LANDMARK_KINDS := [&"mountains", &"crater", &"rift"]
const EDGE_DIRECTIONS := [&"n", &"e", &"s", &"w"]
const NATIVE_UNIT_IDS := [
	&"founder", &"rust_guard", &"miner_quad", &"raider_walker", &"heavy_mech",
	&"net_broker", &"steam_cruiser", &"virus_pickup", &"auto_mech",
]

const ENTITY_CONTRACTS := {
	"city_era_1": {
		"path": "res://assets/world/entities/city/era_1_validator.png",
		"source_size": Vector2i(128, 128),
		"anchor": Vector2(64, 112),
		"display_size": Vector2(24, 24),
	},
	"founder": {
		"path": "res://assets/world/entities/units/founder.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 84),
		"display_size": Vector2(20, 20),
	},
	"rust_guard": {
		"path": "res://assets/world/entities/units/rust_guard.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 84),
		"display_size": Vector2(20, 20),
	},
	"miner_quad": {
		"path": "res://assets/world/entities/units/miner_quad.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 90),
		"display_size": Vector2(21, 21),
	},
	"raider_walker": {
		"path": "res://assets/world/entities/units/raider_walker.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 90),
		"display_size": Vector2(22, 22),
	},
	"heavy_mech": {
		"path": "res://assets/world/entities/units/heavy_mech.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 91),
		"display_size": Vector2(24, 24),
	},
	"net_broker": {
		"path": "res://assets/world/entities/units/net_broker.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 90),
		"display_size": Vector2(21, 21),
	},
	"steam_cruiser": {
		"path": "res://assets/world/entities/units/steam_cruiser.png",
		"source_size": Vector2i(128, 96),
		"anchor": Vector2(64, 76),
		"display_size": Vector2(24, 18),
	},
	"virus_pickup": {
		"path": "res://assets/world/entities/units/virus_pickup.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 88),
		"display_size": Vector2(22, 22),
	},
	"auto_mech": {
		"path": "res://assets/world/entities/units/auto_mech.png",
		"source_size": Vector2i(96, 96),
		"anchor": Vector2(48, 91),
		"display_size": Vector2(23, 23),
	},
	"terminal": {
		"path": "res://assets/world/entities/terminal.png",
		"source_size": Vector2i(64, 64),
		"anchor": Vector2(32, 52),
		"display_size": Vector2(16, 16),
	},
	"master_server_lair": {
		"path": "res://assets/world/entities/rogue/master_server_lair.png",
		"source_size": Vector2i(128, 128),
		"anchor": Vector2(64, 116),
		"display_size": Vector2(28, 28),
	},
}

const CITY_OVERLAY_PATHS := {
	"construction": "res://assets/world/entities/city/construction.png",
	"capital": "res://assets/world/entities/city/capital.png",
	"powered": "res://assets/world/entities/city/powered.png",
	"offline_dos": "res://assets/world/entities/city/offline_dos.png",
}

const RESOURCE_ICON_PATHS := {
	"scrap": "res://assets/icons/resources/scrap.svg",
	"biomass": "res://assets/icons/resources/biomass.svg",
	"energy": "res://assets/icons/resources/energy.svg",
	"sol": "res://assets/icons/resources/sol.svg",
}

const ACTION_ICON_PATHS := {
	"move": "res://assets/icons/actions/move.svg",
	"attack": "res://assets/icons/actions/attack.svg",
	"select": "res://assets/icons/actions/select.svg",
	"reachable": "res://assets/icons/actions/reachable.svg",
	"blocked": "res://assets/icons/actions/blocked.svg",
}

const CABLE_PATH := "res://assets/world/infrastructure/cable.svg"

static var _texture_cache: Dictionary = {}
static var _faction_marker_cache: Dictionary = {}
static var _secured_city_cache: Texture2D


static func terrain_path(kind: String, variant: int) -> String:
	return "res://assets/world/terrain/%s/base_%02d.png" % [kind, variant]


static func transition_path(kind: String, direction: String) -> String:
	return "res://assets/world/terrain/%s/edge_%s.png" % [kind, direction]


static func landmark_path(kind: String, variant: int) -> String:
	return "res://assets/world/terrain/%s/landmark_%02d.png" % [kind, variant]


static func terrain_texture(kind: String, cell: Vector2i, seed: int) -> Texture2D:
	if TERRAIN_KINDS.has(StringName(kind)):
		var path := terrain_path(kind, variant_index(kind, cell, seed))
		var texture := _load_texture(path)
		if texture != null:
			return texture
	for legacy_path in [
		"res://assets/terrain/%s.png" % kind,
		"res://assets/terrain/tile_%s.png" % kind,
		"res://assets/terrain/%s.svg" % kind,
	]:
		var legacy := _load_texture(legacy_path)
		if legacy != null:
			return legacy
	return null


static func has_native_terrain(kind: String, cell: Vector2i, seed: int) -> bool:
	return ResourceLoader.exists(terrain_path(kind, variant_index(kind, cell, seed)))


static func transition_texture(kind: String, direction: String) -> Texture2D:
	if not EDGE_DIRECTIONS.has(StringName(direction)):
		return null
	return _load_texture(transition_path(kind, direction))


static func terrain_landmark_texture(kind: String, cell: Vector2i, seed: int) -> Texture2D:
	if not LANDMARK_KINDS.has(StringName(kind)):
		return null
	return _load_texture(landmark_path(kind, landmark_variant_index(kind, cell, seed)))


static func landmark_variant_index(kind: String, cell: Vector2i, seed: int) -> int:
	var value := seed ^ (cell.x * 73856093) ^ (cell.y * 19349663)
	value ^= _stable_string_hash(kind) * 83492791
	return posmod(value, LANDMARK_VARIANTS)


static func entity_contract(entity_id: String) -> Dictionary:
	return ENTITY_CONTRACTS.get(entity_id, {})


static func entity_texture(entity_id: String) -> Texture2D:
	var contract := entity_contract(entity_id)
	if contract.is_empty():
		return null
	return _load_texture(contract.path)


static func requires_native_unit(entity_id: String) -> bool:
	return NATIVE_UNIT_IDS.has(StringName(entity_id))


static func city_overlay_texture(state_id: String) -> Texture2D:
	return _load_texture(CITY_OVERLAY_PATHS.get(state_id, ""))


static func secured_city_texture() -> Texture2D:
	if _secured_city_cache != null:
		return _secured_city_cache
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var ink := Color("171b20")
	var quantum := Color("9b7ce8")
	var brass := Color("e6bd70")
	# Angular shield silhouette; the inset lock remains legible without color.
	for point in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
			Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
			Vector2i(1, 2), Vector2i(10, 2), Vector2i(1, 3), Vector2i(10, 3),
			Vector2i(1, 4), Vector2i(10, 4), Vector2i(2, 5), Vector2i(9, 5),
			Vector2i(2, 6), Vector2i(9, 6), Vector2i(3, 7), Vector2i(8, 7),
			Vector2i(4, 8), Vector2i(7, 8), Vector2i(5, 9), Vector2i(6, 9)]:
		image.set_pixelv(point, ink)
	image.fill_rect(Rect2i(3, 2, 6, 5), quantum)
	image.fill_rect(Rect2i(4, 3, 4, 2), ink)
	image.fill_rect(Rect2i(5, 2, 2, 2), brass)
	image.fill_rect(Rect2i(4, 5, 4, 3), brass)
	image.set_pixel(5, 6, ink)
	image.set_pixel(6, 6, ink)
	_secured_city_cache = ImageTexture.create_from_image(image)
	return _secured_city_cache


static func faction_marker_texture(faction_id: int, player_faction: int, barbarian_faction: int) -> Texture2D:
	var role := "player" if faction_id == player_faction else "barbarian" if faction_id == barbarian_faction else "rival_%d" % posmod(faction_id, 3)
	if _faction_marker_cache.has(role):
		return _faction_marker_cache[role]
	var image := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var ink := Color("171b20")
	var marker_color := Color("e6bd70")
	if role == "barbarian":
		marker_color = Color("d45b4f")
		for point in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5)]:
			image.set_pixelv(point, ink if point.y in [0, 5] or point.x in [0, 6] else marker_color)
	elif role == "player":
		for point in [Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(3, 6)]:
			image.set_pixelv(point, ink if point.x in [0, 6] or point.y in [0, 6] else marker_color)
	else:
		marker_color = [Color("70a8bf"), Color("aa78bd"), Color("8eb06d")][posmod(faction_id, 3)]
		image.fill_rect(Rect2i(0, 0, 7, 7), ink)
		image.fill_rect(Rect2i(1, 1, 5, 5), marker_color)
		for i in range(1, 6):
			image.set_pixel(i, i, ink)
	var texture := ImageTexture.create_from_image(image)
	_faction_marker_cache[role] = texture
	return texture


static func cable_texture() -> Texture2D:
	return _load_texture(CABLE_PATH)


static func resource_icon(resource_id: String) -> Texture2D:
	return _load_texture(RESOURCE_ICON_PATHS.get(resource_id, ""))


static func action_icon(action_id: String) -> Texture2D:
	return _load_texture(ACTION_ICON_PATHS.get(action_id, ""))


static func variant_index(kind: String, cell: Vector2i, seed: int) -> int:
	return posmod(cosmetic_hash(kind, cell, seed), TERRAIN_VARIANTS)


static func cosmetic_hash(kind: String, cell: Vector2i, seed: int) -> int:
	# Avalanche before any caller applies a small modulo. This keeps cosmetic
	# placement deterministic without exposing coordinate low-bit lattices.
	var value := seed + cell.x * 73856093 + cell.y * 19349663
	value += _stable_string_hash(kind) * 83492791
	value = (value ^ (value >> 15)) * 2246822519
	value ^= value >> 13
	return value


static func configure_anchored_sprite(sprite: Sprite2D, entity_id: String) -> bool:
	var contract := entity_contract(entity_id)
	var texture := entity_texture(entity_id)
	if contract.is_empty() or texture == null:
		return false
	var source_size: Vector2 = Vector2(contract.source_size)
	var display_size: Vector2 = contract.display_size
	var scale_factor := minf(display_size.x / source_size.x, display_size.y / source_size.y)
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * scale_factor
	# The node remains at the cell center for existing movement tweens. The
	# source anchor lands at the bottom-center of the logical tile.
	sprite.offset = -contract.anchor + Vector2(0, TILE_SIZE * 0.5 / scale_factor)
	return true


static func anchored_rect(entity_id: String, cell: Vector2i) -> Rect2:
	var contract := entity_contract(entity_id)
	if contract.is_empty():
		return Rect2()
	var source_size: Vector2 = Vector2(contract.source_size)
	var display_size: Vector2 = contract.display_size
	var scale_factor := minf(display_size.x / source_size.x, display_size.y / source_size.y)
	var ground := Vector2(
		cell.x * TILE_SIZE + TILE_SIZE * 0.5,
		cell.y * TILE_SIZE + TILE_SIZE)
	return Rect2(ground - contract.anchor * scale_factor, source_size * scale_factor)


static func _stable_string_hash(value: String) -> int:
	var result := 2166136261
	for byte in value.to_utf8_buffer():
		result = (result ^ byte) * 16777619
	return result


static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path)
	_texture_cache[path] = texture
	return texture
