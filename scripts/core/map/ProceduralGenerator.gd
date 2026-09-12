extends MapGenerator
## ProceduralGenerator — random generation by type (Continents, Pangaea,
## Archipelago, Inland Sea, Islands). Water + land + resources.

var rng := RandomNumberGenerator.new()


func generate(grid: GridManager, seed_value: int) -> void:
	rng.seed = seed_value
	_water_fill(grid)
	match map_type:
		Data.MapType.CONTINENTS:
			_continents(grid)
		Data.MapType.PANGAEA:
			_pangaea(grid)
		Data.MapType.ARCHIPELAGO:
			_archipelago(grid)
		Data.MapType.INLAND_SEA:
			_inland_sea(grid)
		Data.MapType.ISLANDS:
			_islands(grid)
	_resources(grid)


## Everything starts as water.
func _water_fill(grid: GridManager) -> void:
	for x in grid.w:
		for y in grid.h:
			grid.terrain[x][y] = "ocean"


## Elliptical land blob.
func _blob(grid: GridManager, cx: float, cy: float, rx: float, ry: float, hard_edge: float = 0.62) -> void:
	for x in grid.w:
		for y in grid.h:
			var dx := (x - cx) / rx
			var dy := (y - cy) / ry
			var d := dx * dx + dy * dy
			if d < hard_edge:
				grid.terrain[x][y] = "wasteland"
			elif d < 1.0 and rng.randf() < 0.35:
				grid.terrain[x][y] = "wasteland"  # rough coastline


## Continents: 2-4 large landmasses.
func _continents(grid: GridManager) -> void:
	var n := rng.randi_range(2, 4)
	for i in n:
		_blob(grid,
			rng.randf_range(grid.w * 0.15, grid.w * 0.85),
			rng.randf_range(grid.h * 0.2, grid.h * 0.8),
			rng.randf_range(grid.w * 0.12, grid.w * 0.22),
			rng.randf_range(grid.h * 0.12, grid.h * 0.2))


## Pangaea: one giant landmass + 1-2 islands.
func _pangaea(grid: GridManager) -> void:
	_blob(grid, grid.w * 0.5, grid.h * 0.5, grid.w * 0.42, grid.h * 0.38)
	if rng.randf() < 0.8:
		_blob(grid, rng.randf_range(grid.w * 0.05, grid.w * 0.3), rng.randf_range(grid.h * 0.05, grid.h * 0.3), grid.w * 0.06, grid.h * 0.05)
	if rng.randf() < 0.6:
		_blob(grid, rng.randf_range(grid.w * 0.7, grid.w * 0.95), rng.randf_range(grid.h * 0.6, grid.h * 0.95), grid.w * 0.05, grid.h * 0.05)


## Archipelago: many small islands.
func _archipelago(grid: GridManager) -> void:
	var n := maxi(18, int(grid.w * 0.4))
	for i in n:
		_blob(grid,
			rng.randf_range(0, grid.w),
			rng.randf_range(0, grid.h),
			rng.randf_range(2.5, 7.0),
			rng.randf_range(2.5, 7.0))


## Inland Sea: land ring, sea in the center.
func _inland_sea(grid: GridManager) -> void:
	# land ring
	_blob(grid, grid.w * 0.5, grid.h * 0.5, grid.w * 0.5, grid.h * 0.5)
	# sea in the center
	var sea_rx := grid.w * 0.16
	var sea_ry := grid.h * 0.16
	for x in grid.w:
		for y in grid.h:
			var dx := (x - grid.w * 0.5) / sea_rx
			var dy := (y - grid.h * 0.5) / sea_ry
			if dx * dx + dy * dy < 0.9:
				grid.terrain[x][y] = "ocean"


## Islands: 5-7 medium islands.
func _islands(grid: GridManager) -> void:
	var n := rng.randi_range(5, 7)
	for i in n:
		_blob(grid,
			rng.randf_range(grid.w * 0.1, grid.w * 0.9),
			rng.randf_range(grid.h * 0.1, grid.h * 0.9),
			rng.randf_range(grid.w * 0.07, grid.w * 0.13),
			rng.randf_range(grid.h * 0.06, grid.h * 0.12))


## Resources/biomes on land via FastNoiseLite (per spec):
##   < -0.3 -> water/swamp, -0.3..0.4 -> wasteland,
##   0.4..0.7 -> ruins, > 0.7 -> mountains.
func _resources(grid: GridManager) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.045
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var node_noise := FastNoiseLite.new()
	node_noise.seed = rng.seed + 5
	node_noise.frequency = 0.02
	for x in grid.w:
		for y in grid.h:
			if grid.terrain[x][y] != "wasteland":
				continue
			var v := noise.get_noise_2d(x, y)
			var nv := node_noise.get_noise_2d(x, y)
			if v > 0.7:
				grid.terrain[x][y] = "mountains"
			elif v > 0.4:
				grid.terrain[x][y] = "ruins"
			elif v < -0.3:
				grid.terrain[x][y] = "swamp"
			elif nv > 0.72:
				grid.terrain[x][y] = "node_zone"
				if rng.randf() < 0.08:
					grid.terrain[x][y] = "crater"
			if v > 0.55 and v <= 0.7 and rng.randf() < 0.04:
				grid.terrain[x][y] = "dump"
			if v < -0.35 and grid.terrain[x][y] == "swamp" and rng.randf() < 0.04:
				grid.terrain[x][y] = "rift"
