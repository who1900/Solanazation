extends RefCounted
class_name MapGenerator
## MapGenerator — base class for map generators (scenario architecture).
##
## Each scenario/map type = class with generate(grid, seed).
## Registry lets you add new generators without touching game code:
## register(name) + create(type). Foundation for future scenarios
## (prebuilt maps, campaigns, missions).

const PROCEDURAL_TYPES: Array = [
	Data.MapType.CONTINENTS,
	Data.MapType.PANGAEA,
	Data.MapType.ARCHIPELAGO,
	Data.MapType.INLAND_SEA,
	Data.MapType.ISLANDS,
]

## Registry: MapType -> generator script (lazy load).
const _REGISTRY: Dictionary = {
	Data.MapType.CONTINENTS: "res://scripts/core/map/ProceduralGenerator.gd",
	Data.MapType.PANGAEA: "res://scripts/core/map/ProceduralGenerator.gd",
	Data.MapType.ARCHIPELAGO: "res://scripts/core/map/ProceduralGenerator.gd",
	Data.MapType.INLAND_SEA: "res://scripts/core/map/ProceduralGenerator.gd",
	Data.MapType.ISLANDS: "res://scripts/core/map/ProceduralGenerator.gd",
	Data.MapType.EARTH: "res://scripts/core/map/EarthGenerator.gd",
}


## Creates a generator for a resolved map type. GameRoot resolves RANDOM from the match seed.
static func create(map_type: int) -> MapGenerator:
	var t: int = map_type
	if t == Data.MapType.RANDOM:
		push_error("MapGenerator.create requires a resolved map type")
		t = Data.MapType.CONTINENTS
	var script_path: String = _REGISTRY[t]
	var gen: MapGenerator = (load(script_path) as GDScript).new()
	gen.map_type = t
	return gen


## Map type this generator builds.
var map_type: int = Data.MapType.RANDOM


## Fills the grid with terrain (land + resources + water).
func generate(grid: GridManager, seed_value: int) -> void:
	push_error("MapGenerator.generate() must be overridden")
