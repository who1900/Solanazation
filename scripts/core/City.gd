extends RefCounted
class_name City
## City — bunker town. Population (biomass), production (scrap), buildings, $SOL.
## Accounts for faction unique buildings (UB replacements).

const WORKED_SECTOR_MULT := 2

var name: String
var faction_id: int
var faction: Faction
var cell: Vector2i
var is_capital: bool = false
var fatigue: int = 0        # High Latency / Network Fatigue (0..100)
var offline_turns: int = 0  # turns offline (after riot)
var dos_turns: int = 0      # DoS attack: production halted
var occupation_until_turn: int = 0 # absolute turn when post-capture stabilization expires
var population: int = 1
var focus: String = "balanced"
var worked_cells: Array[Vector2i] = []
var food_stock: int = 0
var scrap_stock: int = 0   # accumulated scrap (build queue)
var build_queue: Array = []  # building ids in queue
var buildings: Dictionary = {}  # id -> true (built)
var node: Node

var _grid: GridManager


func _init(city_name: String, faction_idx: int, faction: Faction, pos: Vector2i, grid: GridManager) -> void:
	name = city_name
	faction_id = faction_idx
	self.faction = faction
	cell = pos
	_grid = grid


func _faction() -> Faction:
	return faction


## Building check with UB replacement: has_building("assembly_forge") is true
## if "scrap_dock" (its replacement) is built.
func has_building(b_id: String) -> bool:
	if buildings.has(b_id):
		return true
	var f := _faction()
	if f != null:
		var ub_id: String = f.building_for(b_id)
		if ub_id != b_id and buildings.has(ub_id):
			return true
	return false


func building_data(b_id: String) -> Dictionary:
	return Faction.building_data(b_id)


## Gather resources from a tile, accounting for improvements, infrastructure,
## relic sites and faction bonuses.
func gather_tile(x: int, y: int) -> Dictionary:
	var td := _grid.terrain_data(x, y)
	var food: int = td.food
	var scrap: int = td.scrap
	var energy: int = td.energy
	var sol: int = td.sol
	# Tile improvements
	match _grid.improvements[x][y]:
		"mine":
			if _grid.terrain_at(x, y) == "ruins":
				scrap += 2
		"dome":
			if _grid.terrain_at(x, y) == "swamp":
				food += 2
		"tower":
			food += 1
			energy += 1
	# Monorail: +1 $SOL per tile
	if _grid.infra[x][y] == 2:
		sol += 1
	# Faction: Bio-Coders ignore swamp penalties (food not penalized anyway here)
	return { "food": food, "scrap": scrap, "energy": energy, "sol": sol }


func gather_total() -> Dictionary:
	var totals := { "food": 0, "scrap": 0, "energy": 0, "sol": 0 }
	var cells: Array[Vector2i] = worked_cells
	if cells.is_empty() and _grid.in_bounds(cell.x, cell.y):
		cells = [cell]
	for worked_cell in cells:
		var t := gather_tile(worked_cell.x, worked_cell.y)
		totals.food += int(t.food) * WORKED_SECTOR_MULT
		totals.scrap += int(t.scrap) * WORKED_SECTOR_MULT
		totals.energy += int(t.energy) * WORKED_SECTOR_MULT
		totals.sol += int(t.sol) * WORKED_SECTOR_MULT
	# UB: Scrap Dock — +2 Scrap from nearby Ruins
	if has_building("assembly_forge"):
		for worked_cell in cells:
			if _grid.terrain_at(worked_cell.x, worked_cell.y) == "ruins":
				totals.scrap += 2
	return totals


## Swamp radiation reduces usable Biomass for growth and the faction stockpile.
## The same deterministic path is shared by player and AI economies.
func usable_food(gathered_food: int, technology_immune: bool = false) -> int:
	if technology_immune or has_building("biomass_purifier"):
		return gathered_food
	if faction != null and bool(faction.bonuses().get("radiation_immune", false)):
		return gathered_food
	return maxi(gathered_food - count_terrain_near("swamp"), 0)


func energy_production() -> int:
	var total := 0
	for b in buildings:
		total += int(building_data(b).energy_gen)
	return total


func sol_production() -> int:
	var total := 0
	for b in buildings:
		total += int(building_data(b).sol_gen)
	return total


func sol_from_population() -> int:
	if has_building("sol_exchange"):
		return population * 2
	return 0


func energy_upkeep_total() -> int:
	var total := 0
	for b in buildings:
		total += int(building_data(b).energy_upkeep)
	return total


func can_build(b_id: String, resources: Dictionary) -> bool:
	var bd: Dictionary = building_data(b_id)
	if bd.unique and has_building(b_id):
		return false
	if b_id == "relic_validator":
		var t0 := _grid.terrain_at(cell.x, cell.y)
		if t0 != "ruins" and t0 not in ["node_zone", "crater"]:
			return false
	# Node Zone / Server Crater: turbines and validators only
	var t := _grid.terrain_at(cell.x, cell.y)
	if t in ["node_zone", "crater"] and b_id not in ["steam_turbine", "relic_validator", "bio_server"]:
		return false
	if has_building(b_id):
		return false
	return resources.scrap >= int(bd.scrap_cost) and resources.sol >= int(bd.sol_cost)


## Queue eligibility is structural; Scrap accumulates while the queue advances.
func can_queue_build(b_id: String, tech: TechManager) -> bool:
	if has_building(b_id) or build_queue.has(b_id) \
			or b_id in ["nuclear_plant", "fusion_plant"]:
		return false
	var bd: Dictionary = building_data(b_id)
	if bd.unique and has_building(b_id):
		return false
	var terrain_id := _grid.terrain_at(cell.x, cell.y)
	if b_id == "relic_validator" \
			and terrain_id not in ["ruins", "node_zone", "crater"]:
		return false
	if terrain_id in ["node_zone", "crater"] \
			and b_id not in ["steam_turbine", "relic_validator", "bio_server"]:
		return false
	for tech_id in Data.TECHS:
		if b_id in Data.TECHS[tech_id].buildings:
			return tech != null and tech.is_researched(tech_id)
	return true


func add_to_queue(b_id: String) -> void:
	if not build_queue.has(b_id):
		build_queue.append(b_id)


## Build progress (scrap into current queue item).
## Returns built building id or "".
func process_build(resources: Dictionary) -> String:
	if build_queue.is_empty():
		return ""
	var b_id: String = build_queue[0]
	# UB replacement: build faction building instead of base
	var f := _faction()
	if f != null:
		b_id = f.building_for(b_id)
		build_queue[0] = b_id
	var bd: Dictionary = building_data(b_id)
	var cost: int = int(bd.scrap_cost)
	if f != null:
		cost = f.building_cost(cost)
	var spend: int = mini(resources.scrap, cost - scrap_stock)
	scrap_stock += spend
	resources.scrap -= spend
	if scrap_stock >= cost:
		if resources.sol < int(bd.sol_cost):
			return ""
		resources.sol -= int(bd.sol_cost)
		buildings[b_id] = true
		scrap_stock = 0
		build_queue.pop_front()
		return b_id
	return ""


## Count tiles of a kind around the city (radius-1 cross).
func count_terrain_near(kind: String) -> int:
	var n := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var gx := cell.x + dx
			var gy := cell.y + dy
			if _grid.in_bounds(gx, gy) and _grid.terrain_at(gx, gy) == kind:
				n += 1
	return n


## Can an improvement be built on this tile.
func can_build_improvement(x: int, y: int, imp: String) -> bool:
	if not _grid.in_bounds(x, y):
		return false
	if _grid.improvements[x][y] != "":
		return false
	match imp:
		"mine":
			return _grid.terrain_at(x, y) == "ruins"
		"dome":
			return _grid.terrain_at(x, y) == "swamp"
		"tower":
			return _grid.terrain_at(x, y) == "wasteland"
	return false


## Build a tile improvement.
func build_improvement(x: int, y: int, imp: String) -> bool:
	if not can_build_improvement(x, y, imp):
		return false
	_grid.improvements[x][y] = imp
	return true


## Build infrastructure on a tile (cable/monorail).
func build_infra(x: int, y: int, kind: int) -> bool:
	if not _grid.in_bounds(x, y):
		return false
	if _grid.is_water(x, y):
		return false
	if _grid.infra[x][y] >= kind:
		return false
	_grid.infra[x][y] = kind
	return true


## Building evolution: turbine -> reactor -> fusion.
## {from: {to, sol_cost, tech}}
const BUILDING_UPGRADES := {
	"steam_turbine": { "to": "nuclear_plant", "sol_cost": 20, "tech": "atomic_reactor" },
	"nuclear_plant": { "to": "fusion_plant",  "sol_cost": 50, "tech": "quantum_computing" },
}


func can_upgrade_building(tech: TechManager) -> bool:
	for b in BUILDING_UPGRADES:
		if has_building(b):
			var up: Dictionary = BUILDING_UPGRADES[b]
			if tech.is_researched(up.tech):
				return true
	return false


func upgrade_building(resources: Dictionary, tech: TechManager) -> String:
	for b in BUILDING_UPGRADES:
		if has_building(b):
			var up: Dictionary = BUILDING_UPGRADES[b]
			if not tech.is_researched(up.tech):
				continue
			if resources.sol < int(up.sol_cost):
				return ""
			resources.sol -= int(up.sol_cost)
			buildings.erase(b)
			buildings[up.to] = true
			return up.to
	return ""


## Population growth: biomass accumulates, threshold scales with population.
func process_growth(food_income: int) -> bool:
	food_stock += food_income
	var need: int = Data.FOOD_PER_POP * population
	if food_stock >= need:
		food_stock -= need
		population += 1
		return true
	return false


## Network Fatigue per turn. Returns true if the city "rioted"
## (offline + chance to spawn rogue automatons).
func process_fatigue(energy_surplus: int, at_war: bool, ignore: bool) -> bool:
	if ignore:
		fatigue = 0
		return false
	if energy_surplus < 0:
		fatigue += 10
	else:
		fatigue -= 2
	if at_war:
		fatigue += 5
	if has_building("net_shrine"):
		fatigue -= 5
	fatigue = clampi(fatigue, 0, 120)
	if fatigue >= 100:
		fatigue = 40
		offline_turns = 3
		return true
	return false


## City is offline (validators silent, production halted).
func is_offline() -> bool:
	return offline_turns > 0


func is_dos() -> bool:
	return dos_turns > 0


func tick_offline() -> void:
	if offline_turns > 0:
		offline_turns -= 1
	if dos_turns > 0:
		dos_turns -= 1
