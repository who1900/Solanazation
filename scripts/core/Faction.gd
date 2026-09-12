extends RefCounted
class_name Faction
## Faction — clan. Passives, unique units (UU) and buildings (UB).

var id: String
var name: String
var archetype: String
var passive: String
var desc: String
var is_player: bool = false

## Unique units: id -> {replaces, data...}
const UNIQUE_UNITS := {
	"rust_tech": {
		"steam_shredder": { "replaces": "heavy_mech", "name": "Steam Shredder", "moves": 3, "atk": 6, "def": 4, "scrap_cost": 40, "sol_cost": 15, "energy_upkeep": 5, "color": Color("b0703a"), "desc": "-50% $SOL cost, +50% vs infantry", "infantry": false },
	},
	"global_net": {
		"cyber_acolyte": { "replaces": "miner_quad", "name": "Cyber Acolyte", "moves": 4, "atk": 3, "def": 2, "scrap_cost": 15, "sol_cost": 5, "energy_upkeep": 1, "color": Color("5abfbf"), "desc": "EMP aura: adjacent enemies -1 move", "infantry": false, "emp_aura": true },
	},
	"dao": {
		"armored_courier": { "replaces": "raider_walker", "name": "Armored Courier", "moves": 3, "atk": 3, "def": 3, "scrap_cost": 25, "sol_cost": 10, "energy_upkeep": 2, "color": Color("e2c98f"), "desc": "Loot: 50% enemy cost in $SOL on kill", "infantry": false, "looter": true },
	},
	"bio": {
		"genetic_walker": { "replaces": "heavy_mech", "name": "Genetic Walker", "moves": 3, "atk": 5, "def": 4, "scrap_cost": 0, "sol_cost": 0, "energy_upkeep": 0, "color": Color("4a8a4a"), "desc": "Feeds on Biomass, no upkeep", "infantry": false, "biomass_fed": true },
	},
	"steel": {
		"centurion": { "replaces": "raider_walker", "name": "Centurion Tank", "moves": 3, "atk": 3, "def": 4, "scrap_cost": 25, "sol_cost": 10, "energy_upkeep": 2, "color": Color("8a5a8a"), "desc": "Double armor vs ranged", "infantry": false, "heavy_armor": true },
	},
}

## Unique buildings: id -> {replaces, data...}
const UNIQUE_BUILDINGS := {
	"rust_tech": {
		"scrap_dock": { "replaces": "assembly_forge", "name": "Scrap Dock", "scrap_cost": 25, "sol_cost": 0, "energy_upkeep": 1, "sol_gen": 0, "energy_gen": 0, "food_gen": 0, "scrap_gen": 2, "unique": false, "desc": "Veterans; +2 Scrap from nearby Ruins" },
	},
	"global_net": {
		"server_altar": { "replaces": "net_shrine", "name": "Server Altar", "scrap_cost": 20, "sol_cost": 0, "energy_upkeep": 1, "sol_gen": 2, "energy_gen": 2, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "+2 $SOL, +2 Energy, -3 Fatigue" },
	},
	"dao": {
		"liquidity_pool": { "replaces": "sol_exchange", "name": "Liquidity Pool", "scrap_cost": 40, "sol_cost": 15, "energy_upkeep": 2, "sol_gen": 0, "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "1 Pop = 1 $SOL" },
	},
	"bio": {
		"bio_server": { "replaces": "steam_turbine", "name": "Bio-Server", "scrap_cost": 30, "sol_cost": 0, "energy_upkeep": 0, "sol_gen": 0, "energy_gen": 20, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "Energy from Biomass instead of Scrap" },
	},
	"steel": {
		"fortress_server": { "replaces": "assembly_forge", "name": "Fortress Server", "scrap_cost": 25, "sol_cost": 0, "energy_upkeep": 1, "sol_gen": 0, "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "+100% city defense, shocks attackers" },
	},
}

## Passive faction bonuses (applied in GameRoot)
const BONUSES := {
	"rust_tech": { "building_discount": 0.8 },
	"global_net": { "validator_boost": 1.25 },
	"dao": { "broker_free": true, "trade_boost": 1.5 },
	"bio": { "radiation_immune": true },
	"steel": { "attack_bonus": 1.25 },
}


func _init(faction_id: String, player: bool = false) -> void:
	id = faction_id
	is_player = player
	var fd: Dictionary = Data.FACTIONS[faction_id]
	name = fd.name
	archetype = fd.archetype
	passive = fd.passive
	desc = fd.desc


func bonuses() -> Dictionary:
	return BONUSES[id]


## Faction UU (first unique unit) or "".
func unique_unit_id() -> String:
	var uu: Dictionary = UNIQUE_UNITS.get(id, {})
	return uu.keys()[0] if not uu.is_empty() else ""


## Faction UB (first unique building) or "".
func unique_building_id() -> String:
	var ub: Dictionary = UNIQUE_BUILDINGS.get(id, {})
	return ub.keys()[0] if not ub.is_empty() else ""


## Actual unit for type_id, accounting for faction replacement.
func unit_for(type_id: String) -> String:
	var uu: Dictionary = UNIQUE_UNITS.get(id, {})
	for u_id in uu:
		if uu[u_id].replaces == type_id:
			return u_id
	return type_id


## Actual building for base_id, accounting for replacement.
func building_for(base_id: String) -> String:
	var ub: Dictionary = UNIQUE_BUILDINGS.get(id, {})
	for b_id in ub:
		if ub[b_id].replaces == base_id:
			return b_id
	return base_id


## Unit data (standard or UU replacement).
static func unit_data(type_id: String) -> Dictionary:
	if Data.UNITS.has(type_id):
		return Data.UNITS[type_id]
	for f in Data.FACTIONS:
		var uu: Dictionary = UNIQUE_UNITS.get(f, {})
		if uu.has(type_id):
			return uu[type_id]
	return Data.UNITS["rust_guard"]


## Building data (standard or UB replacement).
static func building_data(b_id: String) -> Dictionary:
	if Data.BUILDINGS.has(b_id):
		return Data.BUILDINGS[b_id]
	for f in Data.FACTIONS:
		var ub: Dictionary = UNIQUE_BUILDINGS.get(f, {})
		if ub.has(b_id):
			return ub[b_id]
	return Data.BUILDINGS["genesis_node"]


## Building cost discount (building_discount passive).
func building_cost(base_scrap: int) -> int:
	var b := bonuses()
	if b.has("building_discount"):
		return int(round(base_scrap * b.building_discount))
	return base_scrap
