extends MapGenerator
## EarthGenerator — classic "Earth" map (like Civ 1 Earth).
## Continents defined as ellipses in map fractions; scale to any size.

var rng := RandomNumberGenerator.new()

## Continents: [cx, cy, rx, ry] in fractions (0..1) — rough Earth geography.
const CONTINENTS := [
	# Eurasia
	[0.68, 0.22, 0.26, 0.12],
	# Europe (western part)
	[0.48, 0.22, 0.07, 0.08],
	# Scandinavia
	[0.52, 0.10, 0.05, 0.06],
	# Africa
	[0.52, 0.56, 0.09, 0.13],
	# North America
	[0.17, 0.22, 0.11, 0.16],
	# South America
	[0.22, 0.70, 0.08, 0.14],
	# Australia
	[0.86, 0.78, 0.06, 0.07],
	# Antarctica
	[0.50, 0.97, 0.38, 0.03],
	# Greenland
	[0.32, 0.05, 0.05, 0.04],
	# Britain
	[0.40, 0.17, 0.02, 0.04],
	# Japan
	[0.90, 0.30, 0.015, 0.05],
	# Madagascar
	[0.64, 0.66, 0.02, 0.035],
	# Indonesia / islands
	[0.80, 0.48, 0.05, 0.03],
	[0.86, 0.44, 0.025, 0.03],
	# Caribbean
	[0.28, 0.46, 0.04, 0.02],
]


func generate(grid: GridManager, seed_value: int) -> void:
	rng.seed = seed_value

	# Default to water
	for x in grid.w:
		for y in grid.h:
			grid.terrain[x][y] = "ocean"

	# Land per continent
	for c in CONTINENTS:
		_continent(grid, c[0] * grid.w, c[1] * grid.h, c[2] * grid.w, c[3] * grid.h)

	# Coastal roughness
	for x in grid.w:
		for y in grid.h:
			if grid.terrain[x][y] == "ocean" and rng.randf() < 0.02:
				grid.terrain[x][y] = "wasteland"

	# Resources: metropolis ruins, mountains (Himalayas/Andes), node zones
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.05
	var node_noise := FastNoiseLite.new()
	node_noise.seed = seed_value + 5
	node_noise.frequency = 0.02
	for x in grid.w:
		for y in grid.h:
			if grid.terrain[x][y] != "wasteland":
				continue
			var v := noise.get_noise_2d(x, y)
			var nv := node_noise.get_noise_2d(x, y)
			if v > 0.72:
				grid.terrain[x][y] = "mountains"
			elif v > 0.42:
				grid.terrain[x][y] = "ruins"
			elif nv > 0.72:
				grid.terrain[x][y] = "node_zone"
				if rng.randf() < 0.08:
					grid.terrain[x][y] = "crater"
			if v > 0.55 and v <= 0.7 and rng.randf() < 0.04:
				grid.terrain[x][y] = "dump"
			if v < -0.35 and grid.terrain[x][y] == "swamp" and rng.randf() < 0.04:
				grid.terrain[x][y] = "rift"


func _continent(grid: GridManager, cx: float, cy: float, rx: float, ry: float) -> void:
	for x in grid.w:
		for y in grid.h:
			var dx := (x - cx) / maxf(rx, 1.0)
			var dy := (y - cy) / maxf(ry, 1.0)
			if dx * dx + dy * dy < 1.0:
				grid.terrain[x][y] = "wasteland"
