extends RefCounted
class_name GridManager
## GridManager — the map (dimensions set externally). Storage + helpers.
## Terrain generation via MapGenerator (random types / scenarios).

var w: int = Data.MAP_W
var h: int = Data.MAP_H

## terrain[x][y] -> terrain id ("ocean", "wasteland", ...)
var terrain: Array = []
## (translated)
var node_owner: Array = []
## tile occupancy: [x][y] -> Unit/City or null
var occupant: Array = []

## Infrastructure: [x][y] -> 0 none / 1 cable (1/3 MP) / 2 monorail (0 MP, +1 $SOL)
var infra: Array = []
## Tile improvements: [x][y] -> "" / "mine" / "dome" / "tower"
var improvements: Array = []
var _seed: int = 0


func _init(map_w: int = Data.MAP_W, map_h: int = Data.MAP_H, generator: MapGenerator = null, seed_value: int = 0) -> void:
	w = map_w
	h = map_h
	_seed = seed_value
	_build_arrays()
	var gen: MapGenerator = generator
	if gen == null:
		gen = MapGenerator.create(Data.MapType.CONTINENTS)
	gen.generate(self, seed_value)


func _build_arrays() -> void:
	terrain.clear()
	node_owner.clear()
	occupant.clear()
	infra.clear()
	improvements.clear()
	for x in w:
		var col_t: Array = []
		var col_n: Array = []
		var col_o: Array = []
		var col_i: Array = []
		var col_m: Array = []
		for y in h:
			col_t.append("wasteland")
			col_n.append(-1)
			col_o.append(null)
			col_i.append(0)
			col_m.append("")
		terrain.append(col_t)
		node_owner.append(col_n)
		occupant.append(col_o)
		infra.append(col_i)
		improvements.append(col_m)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < w and y >= 0 and y < h


func terrain_at(x: int, y: int) -> String:
	if not in_bounds(x, y):
		return "ocean"
	return terrain[x][y]


func terrain_data(x: int, y: int) -> Dictionary:
	return Data.TERRAIN[terrain_at(x, y)]


func is_water(x: int, y: int) -> bool:
	return Data.TERRAIN[terrain_at(x, y)].get("water", false)


func is_land(x: int, y: int) -> bool:
	return not is_water(x, y)


## Movement cost of a tile in MP (1 / 1/3 / ~0).
func move_cost(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 1.0
	match infra[x][y]:
		1:
			return 0.34  # cable: 1/3 MP
		2:
			return 0.01  # monorail: ~0 MP
	return 1.0


func is_passable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	if is_water(x, y):
		return false
	if Data.TERRAIN[terrain_at(x, y)].get("impassable", false):
		return false
	return occupant[x][y] == null


func place_occupant(x: int, y: int, obj: Variant) -> void:
	if in_bounds(x, y):
		occupant[x][y] = obj


func clear_occupant(x: int, y: int, obj: Variant) -> void:
	if in_bounds(x, y) and occupant[x][y] == obj:
		occupant[x][y] = null


func occupant_at(x: int, y: int) -> Variant:
	if not in_bounds(x, y):
		return null
	return occupant[x][y]


func find_free_tile_near(cx: int, cy: int, radius: int = 3) -> Vector2i:
	for r in range(1, radius + 1):
		for x in range(cx - r, cx + r + 1):
			for y in range(cy - r, cy + r + 1):
				if in_bounds(x, y) and is_passable(x, y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func find_free_ocean_neighbor(cell: Vector2i) -> Vector2i:
	for neighbor in _orthogonal_neighbors(cell):
		if in_bounds(neighbor.x, neighbor.y) and is_water(neighbor.x, neighbor.y) \
				and occupant_at(neighbor.x, neighbor.y) == null:
			return neighbor
	return Vector2i(-1, -1)


func count_terrain(kind: String) -> int:
	var n := 0
	for x in w:
		for y in h:
			if terrain[x][y] == kind:
				n += 1
	return n


## Start points for N factions: one traversable landmass, spread as far apart as possible.
## Until naval AI exists, this prevents a rival from spawning in an unwinnable pocket.
func find_spawn_points(n: int) -> Array:
	var components: Array = []
	var visited: Dictionary = {}
	for x in w:
		for y in h:
			var start := Vector2i(x, y)
			if visited.has(start) or not is_passable(x, y):
				continue
			var component: Array = [start]
			visited[start] = true
			var cursor := 0
			while cursor < component.size():
				var cell: Vector2i = component[cursor]
				cursor += 1
				for neighbor in _orthogonal_neighbors(cell):
					if in_bounds(neighbor.x, neighbor.y) and not visited.has(neighbor) \
							and is_passable(neighbor.x, neighbor.y):
						visited[neighbor] = true
						component.append(neighbor)
			components.append(component)
	var land: Array = []
	for component in components:
		if component.size() > land.size():
			land = component
	if land.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 19
	var points: Array = []
	points.append(land[rng.randi_range(0, land.size() - 1)])
	while points.size() < n:
		var best: Vector2i = land[0]
		var best_min_dist := -1.0
		for p in land:
			var min_dist := INF
			for q in points:
				var d := Vector2(p - q).length()
				min_dist = minf(min_dist, d)
			if min_dist > best_min_dist:
				best_min_dist = min_dist
				best = p
		points.append(best)
	return points


func clear_occupants() -> void:
	for x in w:
		for y in h:
			occupant[x][y] = null


## Groups same-faction city cells connected by neutral cable/monorail geometry.
## Foreign city cells block infrastructure traversal and cannot bridge groups.
func connected_city_groups(city_cells: Array, blocked_cells: Array = []) -> Array:
	var parents: Array = []
	for i in city_cells.size():
		parents.append(i)
	var infra_components: Dictionary = _infra_component_map(blocked_cells)
	var first_city_by_component: Dictionary = {}
	var city_by_cell: Dictionary = {}
	for i in city_cells.size():
		var city_cell: Vector2i = city_cells[i]
		city_by_cell[city_cell] = i
		for tile in _cell_and_neighbors(city_cell):
			if infra_components.has(tile):
				var component_id: int = infra_components[tile]
				if first_city_by_component.has(component_id):
					_union_city_groups(parents, i, int(first_city_by_component[component_id]))
				else:
					first_city_by_component[component_id] = i
	for i in city_cells.size():
		var city_cell: Vector2i = city_cells[i]
		for neighbor in _orthogonal_neighbors(city_cell):
			if city_by_cell.has(neighbor):
				_union_city_groups(parents, i, int(city_by_cell[neighbor]))
	var groups_by_root: Dictionary = {}
	for i in city_cells.size():
		var root: int = _city_group_root(parents, i)
		if not groups_by_root.has(root):
			groups_by_root[root] = []
		groups_by_root[root].append(i)
	return groups_by_root.values()


func _infra_component_map(blocked_cells: Array) -> Dictionary:
	var components: Dictionary = {}
	var blocked: Dictionary = {}
	for cell in blocked_cells:
		blocked[cell] = true
	var component_id := 0
	for x in w:
		for y in h:
			var start := Vector2i(x, y)
			if infra[x][y] <= 0 or blocked.has(start) or components.has(start):
				continue
			var queue: Array = [start]
			var queue_index := 0
			components[start] = component_id
			while queue_index < queue.size():
				var cell: Vector2i = queue[queue_index]
				queue_index += 1
				for neighbor in _orthogonal_neighbors(cell):
					if in_bounds(neighbor.x, neighbor.y) and infra[neighbor.x][neighbor.y] > 0 \
							and not blocked.has(neighbor) and not components.has(neighbor):
						components[neighbor] = component_id
						queue.append(neighbor)
			component_id += 1
	return components


func _cell_and_neighbors(cell: Vector2i) -> Array:
	var cells: Array = [cell]
	cells.append_array(_orthogonal_neighbors(cell))
	return cells


func _orthogonal_neighbors(cell: Vector2i) -> Array:
	return [
		cell + Vector2i.LEFT, cell + Vector2i.RIGHT,
		cell + Vector2i.UP, cell + Vector2i.DOWN,
	]


func _city_group_root(parents: Array, index: int) -> int:
	var root := index
	while int(parents[root]) != root:
		root = int(parents[root])
	while int(parents[index]) != index:
		var next: int = int(parents[index])
		parents[index] = root
		index = next
	return root


func _union_city_groups(parents: Array, a: int, b: int) -> void:
	var root_a: int = _city_group_root(parents, a)
	var root_b: int = _city_group_root(parents, b)
	if root_a != root_b:
		parents[root_b] = root_a
