extends RefCounted
class_name Unit
## Unit on the map. Grid movement, combat, upkeep, fortify, veterancy.

var type_id: String
var faction_id: int
var cell: Vector2i
var moves_left: float
var has_moved_this_turn: bool = false
var veteran: bool = false
var fortified: bool = false
var orders_skipped: bool = false
var cargo: Array = []  # Nested land units carried by naval transports.
var node: Node  # visual node (Sprite2D), assigned by UnitsView

var _grid: GridManager


func _init(unit_type: String, faction: int, pos: Vector2i, grid: GridManager) -> void:
	type_id = unit_type
	faction_id = faction
	cell = pos
	_grid = grid
	moves_left = max_moves()


func data() -> Dictionary:
	return Faction.unit_data(type_id)


func max_moves() -> int:
	return int(data().moves)


func attack() -> int:
	return int(data().atk)


func defense() -> int:
	return int(data().def)


func energy_upkeep() -> int:
	return int(data().energy_upkeep)


func is_naval() -> bool:
	return bool(data().get("naval", false))


func transport_capacity() -> int:
	return int(data().get("transport_capacity", 0))


func reset_moves() -> void:
	moves_left = max_moves()
	has_moved_this_turn = false
	orders_skipped = false


## Fortify: unit that spent a full turn stationary gains +50% defense.
func update_fortify() -> void:
	if has_moved_this_turn:
		fortified = false
	elif not fortified:
		fortified = true


## Moves to a tile; cost depends on infrastructure (cable 1/3, monorail ~0).
func try_move(target: Vector2i) -> bool:
	if moves_left <= 0.001:
		return false
	if not can_move_to(target):
		return false
	_grid.clear_occupant(cell.x, cell.y, self)
	cell = target
	for passenger in cargo:
		passenger.cell = target
	_grid.place_occupant(target.x, target.y, self)
	moves_left -= _grid.move_cost(target.x, target.y)
	has_moved_this_turn = true
	fortified = false
	orders_skipped = false
	return true


func can_move_to(target: Vector2i) -> bool:
	if not _grid.in_bounds(target.x, target.y):
		return false
	if is_naval():
		return _grid.is_water(target.x, target.y) and _grid.occupant_at(target.x, target.y) == null
	if not _grid.is_passable(target.x, target.y):
		return false
	return true


## Unit evolution: upgrade table {from: {to, sol_cost}}.
const UPGRADES := {
	"rust_guard": { "to": "raider_walker", "sol_cost": 6 },
	"miner_quad": { "to": "raider_walker", "sol_cost": 5 },
	"raider_walker": { "to": "heavy_mech", "sol_cost": 15 },
	"founder": { "to": "miner_quad", "sol_cost": 8 },
}

func upgrade_target() -> String:
	var up: Dictionary = UPGRADES.get(type_id, {})
	return up.get("to", "")


func upgrade_cost() -> int:
	var up: Dictionary = UPGRADES.get(type_id, {})
	return int(up.get("sol_cost", 0))


## Terrains where a founder can build improvements.
const BUILDABLE_IMPROVEMENTS := ["mine", "dome", "tower"]


## Exact Civ-1 style combat: chance = Atk / (Atk + Def * land_mod * exp_mod).
## Attacker is always the aggressor; winner survives, loser is removed by caller.
func fight_vs(defender: Unit, roll: float, atk_mult: float = 1.0, def_mult: float = 1.0) -> bool:
	var atk := float(attack()) * atk_mult
	var def := float(defender.defense()) * def_mult

	# Terrain defense modifier (defender's tile)
	var td: Dictionary = Data.TERRAIN[_grid.terrain_at(defender.cell.x, defender.cell.y)]
	var land_mod := float(td.get("def_mod", 1.0))
	if defender.fortified:
		land_mod *= 1.5  # Fortify: +50%

	# Experience modifiers: +50% overall
	var exp_mod := 1.0
	if veteran:
		atk *= 1.5
	if defender.veteran:
		def *= 1.5

	var chance := atk / (atk + def * land_mod * exp_mod)
	chance = clampf(chance, 0.05, 0.95)
	var win := roll < chance

	# Survivor becomes veteran (first survival in combat)
	if win:
		veteran = true
	else:
		defender.veteran = true
	return win
