extends Node
## (translated)
## (translated)

signal resources_changed
signal turn_changed(turn: int)
signal selection_changed(obj)
signal unit_moved(unit)
signal unit_orders_changed(unit)
signal city_changed(city)
signal city_build_completed(city, building_id: String)
signal log_message(text: String)
signal game_over(winner_name: String, reason: String)
signal match_ready

const TILE_SIZE := 16
const CITY_MIN_DISTANCE := 5
const CITY_FOCUSES := ["balanced", "biomass", "scrap", "energy", "sol"]

var grid: GridManager
var resources: Dictionary = Data.START_RESOURCES.duplicate()
var turn: int = 1
var faction_id: int = 0

## Party factions: [0] = player, [1..] = AI.
var factions: Array = []  # Array[Faction]
var tech: TechManager
var ai: AiPlayer = null

var units: Array = []   # Array[Unit]
var cities: Array = []  # Array[City]

var selected_unit: Unit = null
var selected_city: City = null

## Fog of War for the player: permanent map memory and current sight.
var explored: Dictionary = {}  # Vector2i -> true (explored this match)
var visible: Dictionary = {}   # Vector2i -> true (visible now)
var explored_terrain: Dictionary = {}  # Vector2i -> terrain id last seen
var satellite_intel: Dictionary = {}  # Vector2i -> true (last-known enemy validator)

var city_name_counter: int = 1

## Ancient Terminals (goody huts) and Master Server lairs (botnet camps)
var terminals: Array = []   # Array[Vector2i]
var lairs: Array = []       # Array[Vector2i]
const BARB_FACTION := 99

## Victory counters
var uplink_turns: int = 0      # turns with Orbital Mainframe running
var monopoly_turns: int = 0    # turns holding >80% of $SOL
var orbital_mainframe_turn: int = -1  # build turn
var global_server: bool = false      # Global Server built (diplomatic victory)
var protocol: String = "p2p"         # network protocol (form of government)
var wonders: Dictionary = {}         # built wonders: id -> true
var shield_turns: int = 0            # Genesis Block anti-hack counter
var sync_turns: int = 0              # Satellite Emitter victory timer

## Random events (Solana lore): outage/meme
var event_active: String = ""        # "" / "outage" / "meme"
var event_turns_left: int = 0
var meme_city_idx: int = -1
var next_event_turn: int = 8         # first possible event turn

## Relic artifacts: id -> true (dragon_suit, genesis_chapter)
var artifacts: Dictionary = {}

## Pairwise diplomacy: canonical "lower:higher" -> "peace" / "alliance" / "war".
var diplomacy: Dictionary = {}
var ping: Dictionary = {}          # canonical pair -> int relations (0..100)
var war_exhaustion: Dictionary = {} # canonical pair -> war turns / negative ceasefire turns
var monopoly_progress: Dictionary = {} # faction_idx -> qualifying turns
var network_sol_generated: Dictionary = {} # faction_idx -> cumulative minted SOL
var council_law: String = ""       # active Council law
var law_turns_left: int = 0
var locked_faction: int = -1       # Address Lock: protected faction
var trade_used: int = 0            # trades used this turn
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func start_game(
	map_size: int = Data.MapSize.MEDIUM,
	map_type: int = Data.MapType.CONTINENTS,
	seed_value: int = 0,
	player_faction_id: String = "rust_tech",
	faction_ids: Array = []
) -> void:
	var dims: Vector2i = Data.MAP_DIMENSIONS[map_size]
	_map_size = map_size
	if seed_value == 0:
		_rng.randomize()
		_game_seed = _rng.randi()
	else:
		_game_seed = seed_value
	_rng.seed = _game_seed
	_requested_map_type = map_type
	_map_type = map_type
	if _map_type == Data.MapType.RANDOM:
		var random_idx: int = _rng.randi_range(0, MapGenerator.PROCEDURAL_TYPES.size() - 1)
		_map_type = int(MapGenerator.PROCEDURAL_TYPES[random_idx])
	var generator := MapGenerator.create(_map_type)
	grid = GridManager.new(dims.x, dims.y, generator, _game_seed)
	selected_unit = null
	selected_city = null
	units.clear()
	cities.clear()
	resources = Data.START_RESOURCES.duplicate()
	turn = 1
	tech = TechManager.new()
	ai = AiPlayer.new()
	explored.clear()
	visible.clear()
	explored_terrain.clear()
	satellite_intel.clear()
	terminals.clear()
	lairs.clear()
	uplink_turns = 0
	monopoly_turns = 0
	global_server = false
	orbital_mainframe_turn = -1
	protocol = "p2p"
	wonders.clear()
	shield_turns = 0
	sync_turns = 0
	event_active = ""
	event_turns_left = 0
	meme_city_idx = -1
	next_event_turn = _rng.randi_range(8, 15)
	artifacts.clear()
	diplomacy.clear()
	ping.clear()
	war_exhaustion.clear()
	monopoly_progress.clear()
	network_sol_generated.clear()
	council_law = ""
	law_turns_left = 0
	locked_faction = -1
	trade_used = 0

	# Factions: exact saved roster, or player pick + 1 AI for a new game.
	factions.clear()
	if faction_ids.is_empty():
		factions.append(Faction.new(player_faction_id, true))
		var ai_id := "rust_tech"
		for f_id in Data.FACTIONS:
			if f_id != player_faction_id:
				ai_id = f_id
				break
		factions.append(Faction.new(ai_id, false))
		faction_id = 0
	else:
		var canonical_ids: Array = [player_faction_id]
		for faction_value in faction_ids:
			var roster_id: String = str(faction_value)
			if roster_id != player_faction_id:
				canonical_ids.append(roster_id)
		for i in canonical_ids.size():
			factions.append(Faction.new(str(canonical_ids[i]), i == 0))
		faction_id = 0
	diplomacy.clear()
	ping.clear()
	for first in factions.size():
		monopoly_progress[first] = 0
		network_sol_generated[first] = 0
		for second in range(first + 1, factions.size()):
			var pair := relation_key(first, second)
			diplomacy[pair] = "peace"
			ping[pair] = 50
			war_exhaustion[pair] = 0
	for ai_idx in range(1, factions.size()):
		ai.agenda_for(ai_idx, factions)
	council_law = ""
	law_turns_left = 0
	locked_faction = -1
	trade_used = 0

	# Start points per faction (different map regions)
	var spawns: Array = grid.find_spawn_points(factions.size())
	for f_idx in factions.size():
		var start_pos: Vector2i = spawns[f_idx] if f_idx < spawns.size() else Vector2i(dims.x / 2, dims.y / 2)
		if f_idx == faction_id:
			# Player: city on start tile, founder + guards around
			_found_city_at(start_pos, f_idx)
			_spawn_unit("founder", grid.find_free_tile_near(start_pos.x + 1, start_pos.y + 1, 3), f_idx)
			var offsets := [Vector2i(2, 2), Vector2i(-2, 2)]
			var idx := 0
			for u_id in Data.START_UNITS:
				var p := grid.find_free_tile_near(start_pos.x + offsets[idx % 2].x, start_pos.y + offsets[idx % 2].y, 4)
				_spawn_unit(u_id, p, f_idx)
				idx += 1
		else:
			# AI faction: city on start tile, units around
			_found_city_at(start_pos, f_idx)
			_spawn_unit("founder", grid.find_free_tile_near(start_pos.x + 1, start_pos.y + 1, 3), f_idx)
			for i in range(2):
				var p := grid.find_free_tile_near(start_pos.x + (i * 2) - 1, start_pos.y + 2, 4)
				_spawn_unit("rust_guard", p, f_idx)

	_spawn_terminals()
	_spawn_lairs()
	emit_signal("resources_changed")
	emit_signal("turn_changed", turn)
	emit_signal("selection_changed", null)
	update_visibility()
	game_log("The wasteland awaits. Map: %s (%dx%d). Goal: Consensus." % [
		Data.MAP_TYPE_NAMES[_map_type], dims.x, dims.y,
	])
	emit_signal("match_ready")


## ---------- Ancient Terminals (Goody Huts) ----------

func _spawn_terminals() -> void:
	var count := maxi(4, (grid.w * grid.h) / 600)
	for i in count:
		for attempt in range(50):
			var x: int = _rng.randi_range(0, grid.w - 1)
			var y: int = _rng.randi_range(0, grid.h - 1)
			if grid.is_land(x, y) and not _near_start(x, y, 6):
				terminals.append(Vector2i(x, y))
				break


func _spawn_lairs() -> void:
	var count := 2
	for i in count:
		for attempt in range(80):
			var x: int = _rng.randi_range(0, grid.w - 1)
			var y: int = _rng.randi_range(0, grid.h - 1)
			if grid.is_land(x, y) and not _near_start(x, y, 8):
				lairs.append(Vector2i(x, y))
				break


func _near_start(x: int, y: int, dist: int) -> bool:
	for c in cities:
		if absi(c.cell.x - x) <= dist and absi(c.cell.y - y) <= dist:
			return true
	return false


var _game_seed: int = 0
var _map_size: int = Data.MapSize.MEDIUM
var _map_type: int = Data.MapType.CONTINENTS
var _requested_map_type: int = Data.MapType.CONTINENTS


func gameplay_randf() -> float:
	return _rng.randf()


func gameplay_randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Read-only seed for deterministic cosmetic variation. Never advances gameplay RNG.
func visual_seed() -> int:
	return _game_seed


## Unit enters a terminal — random outcome.
func activate_terminal(u: Unit, pos: Vector2i) -> void:
	if not terminals.has(pos):
		return
	terminals.erase(pos)
	var roll: float = _rng.randf()
	if roll < 0.15:
		# Relic artifact (Solana lore)
		var art := _random_artifact()
		artifacts[art] = true
		var art_name := "Dragon Suit" if art == "dragon_suit" else "Genesis Chapter"
		game_log("Ancient Terminal: relic found — %s!" % art_name)
	elif roll < 0.40:
		# Network fork: 10-50 $SOL
		var amount: int = _rng.randi_range(10, 50)
		resources.sol += amount
		game_log("Ancient Terminal: network fork — +%d $SOL!" % amount)
	elif roll < 0.5:
		# Blueprint leak: random tech of current era
		var t := _random_current_era_tech(_rng)
		if t != "":
			var had_satellite_intel := has_passive("reveal_validators")
			tech.researched[t] = true
			if not had_satellite_intel and has_passive("reveal_validators"):
				_activate_satellite_intel()
			game_log("Ancient Terminal: blueprint leak — %s unlocked!" % Data.TECHS[t].name)
		else:
			resources.sol += 20
			game_log("Ancient Terminal: empty vault — +20 $SOL")
	elif roll < 0.75:
		# Ancient automaton joins your army
		var gift := "miner_quad" if _rng.randf() < 0.5 else "heavy_mech"
		_spawn_unit(gift, grid.find_free_tile_near(pos.x, pos.y, 2), u.faction_id)
		game_log("Ancient Terminal: dormant automaton reconnected — %s!" % Faction.unit_data(gift).name)
	else:
		# Power surge: trap — 2 botnets nearby
		_spawn_unit("virus_pickup", grid.find_free_tile_near(pos.x + 1, pos.y, 2), BARB_FACTION)
		_spawn_unit("auto_mech", grid.find_free_tile_near(pos.x - 1, pos.y, 2), BARB_FACTION)
		game_log("Ancient Terminal: power surge! Rogue botnets awakened!")
	emit_signal("resources_changed")
	UnitsView.sync()


func _random_current_era_tech(rng: RandomNumberGenerator) -> String:
	var era := tech.current_era()
	var candidates: Array = []
	for t in Data.TECHS:
		if not tech.researched.has(t) and int(Data.TECHS[t].era) == era:
			candidates.append(t)
	if candidates.is_empty():
		for t in Data.TECHS:
			if not tech.researched.has(t):
				candidates.append(t)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## ---------- Rogue Botnets (barbarians) ----------

## Spawn botnets every 10 turns in fog of war.
func spawn_barbarians() -> void:
	if turn % 10 != 0:
		return
	var spawned := 0
	for attempt in range(60):
		var x: int = _rng.randi_range(0, grid.w - 1)
		var y: int = _rng.randi_range(0, grid.h - 1)
		var pos := Vector2i(x, y)
		if not grid.is_passable(x, y) or visible.has(pos):
			continue
		# far from validators
		var near_validator := false
		for c in cities:
			if Vector2(c.cell - pos).length() < 10.0:
				near_validator = true
				break
		if near_validator:
			continue
		_spawn_unit("virus_pickup", pos, BARB_FACTION)
		spawned += 1
		if spawned >= 2:
			break


## Botnet turn: move to nearest enemy, attack, raze.
func barbarian_turn() -> void:
	var bots: Array = []
	for u in units:
		if u.faction_id == BARB_FACTION:
			bots.append(u)
	for u in bots:
		u.reset_moves()
		var target := _nearest_enemy(u)
		if target == Vector2i(-1, -1):
			continue
		if Vector2(target - u.cell).length() <= 1.5:
			_barbarian_attack(u, target)
		else:
			var steps: int = int(ceil(u.moves_left))
			for i in range(steps):
				var dx := signi(target.x - u.cell.x)
				var dy := signi(target.y - u.cell.y)
				var moved := false
				if dx != 0:
					var nx := Vector2i(u.cell.x + dx, u.cell.y)
					if u.can_move_to(nx):
						u.try_move(nx)
						moved = true
				if not moved and dy != 0:
					var ny := Vector2i(u.cell.x, u.cell.y + dy)
					if u.can_move_to(ny):
						u.try_move(ny)


func _nearest_enemy(u: Unit) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := INF
	for enemy in units:
		if enemy.faction_id == u.faction_id:
			continue
		var d := Vector2(enemy.cell - u.cell).length()
		if d < best_dist:
			best_dist = d
			best = enemy.cell
	for c in cities:
		if c.faction_id == u.faction_id:
			continue
		var d := Vector2(c.cell - u.cell).length()
		if d < best_dist:
			best_dist = d
			best = c.cell
	return best


func _barbarian_attack(u: Unit, target: Vector2i) -> void:
	var enemy_unit := unit_at(target)
	var enemy_city := city_at(target)
	if enemy_unit != null and enemy_unit.faction_id != BARB_FACTION:
		if u.fight_vs(enemy_unit, _rng.randf()):
			_remove_unit(enemy_unit)
			game_log("%s destroyed by rogue botnet!" % Faction.unit_data(enemy_unit.type_id).name)
		else:
			_remove_unit(u)
	elif enemy_city != null and enemy_city.faction_id != BARB_FACTION:
		# Virus Pickup razes power plants; Auto-Mech hits population
		if u.type_id == "virus_pickup":
			for b in ["nuclear_plant", "steam_turbine", "bio_server"]:
				if enemy_city.has_building(b):
					enemy_city.buildings.erase(enemy_city.faction.building_for(b))
					game_log("%s razed by rogue botnet!" % enemy_city.name)
					break
		else:
			var previous_population := enemy_city.population
			enemy_city.population = maxi(enemy_city.population - 1, 1)
			if enemy_city.population != previous_population:
				recompute_city_worked_tiles()
			game_log("%s struck by rogue automaton!" % enemy_city.name)
		u.moves_left = 0


## ---------- Victories ----------

func record_network_sol(owner: int, amount: int) -> void:
	# Monopoly measures sustained validator/city output. Trades, gifts, terminal
	# windfalls, and combat loot only move or award spendable treasury SOL.
	if owner < 0 or owner >= factions.size() or amount <= 0:
		return
	network_sol_generated[owner] = int(network_sol_generated.get(owner, 0)) + amount

func update_victories() -> bool:
	# 1) Domination: one faction controls every original capital.
	var capitals := 0
	var capital_owner := -1
	var one_owner := true
	for c in cities:
		if not c.is_capital:
			continue
		capitals += 1
		if capital_owner < 0:
			capital_owner = c.faction_id
		elif capital_owner != c.faction_id:
			one_owner = false
	if capitals > 1 and one_owner and capital_owner >= 0 and capital_owner < factions.size():
		emit_signal("game_over", factions[capital_owner].name, "all Genesis Nodes captured (51% Attack)")
		return true

	# 2) Global Uplink: Orbital Mainframe running for 20 turns
	if orbital_mainframe_turn > 0 and turn - orbital_mainframe_turn >= 20:
		emit_signal("game_over", factions[faction_id].name, "Global Uplink sustained (space race)")
		return true

	# 3) Validator Monopoly: any faction minted >80% of network SOL for 10 turns.
	var all_pool := 0
	var sol_participants := 0
	for f in factions.size():
		var generated := int(network_sol_generated.get(f, 0))
		all_pool += generated
		if generated > 0:
			sol_participants += 1
	for owner in factions.size():
		var pool := int(network_sol_generated.get(owner, 0))
		var qualifying := all_pool >= Data.MONOPOLY_MIN_NETWORK_SOL \
			and sol_participants >= 2 and float(pool) / all_pool > 0.8
		monopoly_progress[owner] = int(monopoly_progress.get(owner, 0)) + 1 if qualifying else 0
		if int(monopoly_progress[owner]) >= 10:
			emit_signal("game_over", factions[owner].name, "Validator Monopoly (80%+ of network $SOL)")
			return true
	monopoly_turns = int(monopoly_progress.get(faction_id, 0))
	return false


## Master Server (lair) capture — reward.
func capture_lair(pos: Vector2i) -> bool:
	if not lairs.has(pos):
		return false
	lairs.erase(pos)
	resources.sol += 25
	resources.scrap += 30
	game_log("Master Server seized! +25 $SOL, +30 Scrap")
	emit_signal("resources_changed")
	return true


## ---------- Save / Load (JSON) ----------

const SAVE_VERSION := 9


func save_to_file(path: String) -> bool:
	var data := {
		"version": SAVE_VERSION,
		"seed": _game_seed,
		"rng_state": str(_rng.state),
		"map_size": _map_size,
		"map_type": _map_type,
		"resolved_map_type": _map_type,
		"requested_map_type": _requested_map_type,
		"turn": turn,
		"faction_id": faction_id,
		"factions": _faction_ids(),
		"resources": resources,
		"city_name_counter": city_name_counter,
		"tech": {
			"researched": tech.researched.keys(),
			"current": tech.current,
			"points": tech.points,
		},
		"units": _serialize_units(),
		"cities": _serialize_cities(),
		"terminals": _serialize_points(terminals),
		"lairs": _serialize_points(lairs),
		"explored": _serialize_points(explored.keys()),
		"explored_terrain": _serialize_explored_terrain(),
		"satellite_intel": _serialize_points(satellite_intel.keys()),
		"ai": _serialize_ai(),
		"ai_tech": ai.serialize_tech() if ai != null else {},
		"ai_agendas": ai.serialize_agendas() if ai != null else {},
		"uplink_turns": uplink_turns,
		"monopoly_turns": monopoly_turns,
		"monopoly_progress": monopoly_progress,
		"network_sol_generated": network_sol_generated,
		"global_server": global_server,
		"orbital_mainframe_turn": orbital_mainframe_turn,
		"protocol": protocol,
		"wonders": wonders.keys(),
		"shield_turns": shield_turns,
		"sync_turns": sync_turns,
		"event_active": event_active,
		"event_turns_left": event_turns_left,
		"meme_city_idx": meme_city_idx,
		"next_event_turn": next_event_turn,
		"artifacts": artifacts.keys(),
		"terrain": _serialize_grid_strings(grid.terrain),
		"infra": _serialize_grid_array(grid.infra),
		"improvements": _serialize_grid_strings(grid.improvements),
		"diplomacy": _serialize_relations(false),
		"ping": _serialize_relations(true),
		"war_exhaustion": war_exhaustion,
		"council_law": council_law,
		"law_turns_left": law_turns_left,
		"locked_faction": locked_faction,
		"trade_used": trade_used,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		return false
	var save_data: Dictionary = data
	if not _validate_save_data(save_data):
		return false
	var saved_faction_ids: Array = []
	for saved_faction_id in save_data.factions:
		saved_faction_ids.append(str(saved_faction_id))
	var saved_player_id: String = str(saved_faction_ids[0])
	start_game(
		int(save_data.map_size),
		int(save_data.get("resolved_map_type", save_data.map_type)),
		int(save_data.seed),
		saved_player_id,
		saved_faction_ids
	)
	_requested_map_type = int(save_data.get("requested_map_type", save_data.map_type))
	turn = int(save_data.turn)
	faction_id = 0
	resources = _normalized_resources(save_data.resources)
	city_name_counter = int(save_data.city_name_counter)
	tech.researched.clear()
	for t in save_data.tech.researched:
		tech.researched[t] = true
	tech.current = save_data.tech.current
	tech.points = int(save_data.tech.points)
	if save_data.has("terrain"):
		_deserialize_grid_strings(grid.terrain, save_data.terrain)
	grid.clear_occupants()
	# units
	units.clear()
	for ud in save_data.units:
		var u := Unit.new(ud.type, int(ud.faction), Vector2i(int(ud.x), int(ud.y)), grid)
		u.moves_left = float(ud.moves)
		u.veteran = bool(ud.veteran)
		u.fortified = bool(ud.fortified)
		u.has_moved_this_turn = bool(ud.get("moved", false))
		u.orders_skipped = bool(ud.get("orders_skipped", false))
		for cargo_data in ud.get("cargo", []):
			var passenger := Unit.new(cargo_data.type, int(cargo_data.faction), u.cell, grid)
			passenger.cell = u.cell
			passenger.moves_left = float(cargo_data.moves)
			passenger.veteran = bool(cargo_data.veteran)
			passenger.fortified = bool(cargo_data.fortified)
			passenger.has_moved_this_turn = bool(cargo_data.get("moved", false))
			u.cargo.append(passenger)
		units.append(u)
		grid.place_occupant(u.cell.x, u.cell.y, u)
	# cities
	cities.clear()
	for cd in save_data.cities:
		var fac: Faction = factions[int(cd.faction)]
		var c := City.new(cd.name, int(cd.faction), fac, Vector2i(int(cd.x), int(cd.y)), grid)
		c.population = int(cd.pop)
		c.food_stock = int(cd.food)
		c.scrap_stock = int(cd.scrap_stock)
		c.is_capital = bool(cd.capital)
		c.fatigue = int(cd.get("fatigue", 0))
		c.offline_turns = int(cd.get("offline", 0))
		c.dos_turns = int(cd.get("dos", 0))
		c.occupation_until_turn = int(cd.get("occupation_until", 0))
		c.focus = str(cd.get("focus", "balanced"))
		for b in cd.buildings:
			c.buildings[b] = true
		for bq in cd.queue:
			c.build_queue.append(bq)
		cities.append(c)
		grid.place_occupant(c.cell.x, c.cell.y, c)
	recompute_city_worked_tiles()
	# terminals / lairs / explored
	terminals = _deserialize_points(save_data.terminals)
	lairs = _deserialize_points(save_data.lairs)
	explored.clear()
	for p2 in _deserialize_points(save_data.explored):
		explored[p2] = true
	explored_terrain.clear()
	if int(save_data.get("version", 1)) >= 7:
		for memory_entry in save_data.explored_terrain:
			var memory_cell := Vector2i(int(memory_entry[0]), int(memory_entry[1]))
			explored_terrain[memory_cell] = str(memory_entry[2])
	else:
		# Legacy saves already recorded which cells the player knew. Snapshot only
		# those cells from their saved map; never infer any additional exploration.
		for memory_cell in explored:
			explored_terrain[memory_cell] = grid.terrain[memory_cell.x][memory_cell.y]
	# AI
	for f_key in save_data.ai:
		var fid := int(f_key)
		if ai != null:
			ai.ai_resources[fid] = _normalized_resources(save_data.ai[f_key])
	if ai != null:
		ai.restore_tech(save_data.get("ai_tech", {}))
		ai.restore_agendas(save_data.get("ai_agendas", {}), factions)
	uplink_turns = int(save_data.uplink_turns)
	monopoly_turns = int(save_data.monopoly_turns)
	monopoly_progress.clear()
	if save_data.has("monopoly_progress"):
		for progress_key in save_data.monopoly_progress:
			monopoly_progress[int(progress_key)] = int(save_data.monopoly_progress[progress_key])
	else:
		for owner in factions.size():
			monopoly_progress[owner] = monopoly_turns if owner == faction_id else 0
	network_sol_generated.clear()
	if int(save_data.get("version", 1)) >= 6:
		for owner_key in save_data.network_sol_generated:
			network_sol_generated[int(owner_key)] = int(save_data.network_sol_generated[owner_key])
	else:
		# Legacy saves cannot distinguish minted SOL from transfers or treasury.
		# A fresh certification history avoids awarding a false Monopoly.
		monopoly_progress.clear()
		monopoly_turns = 0
	for owner in factions.size():
		if not network_sol_generated.has(owner):
			network_sol_generated[owner] = 0
		if not monopoly_progress.has(owner):
			monopoly_progress[owner] = 0
	global_server = bool(save_data.global_server)
	orbital_mainframe_turn = int(save_data.orbital_mainframe_turn)
	protocol = save_data.get("protocol", "p2p")
	wonders.clear()
	for w in save_data.get("wonders", []):
		wonders[w] = true
	shield_turns = int(save_data.get("shield_turns", 0))
	sync_turns = int(save_data.get("sync_turns", 0))
	if save_data.has("infra"):
		_deserialize_grid_array(grid.infra, save_data.infra)
		_deserialize_grid_strings(grid.improvements, save_data.improvements)
	if save_data.has("diplomacy"):
		diplomacy.clear()
		ping.clear()
		if int(save_data.get("version", 1)) >= 5:
			for diplomacy_key in save_data.diplomacy:
				diplomacy[str(diplomacy_key)] = save_data.diplomacy[diplomacy_key]
			for ping_key in save_data.ping:
				ping[str(ping_key)] = int(save_data.ping[ping_key])
		else:
			for diplomacy_key in save_data.diplomacy:
				var rival_idx: int = int(diplomacy_key)
				diplomacy[relation_key(faction_id, rival_idx)] = save_data.diplomacy[diplomacy_key]
			for ping_key in save_data.ping:
				var rival_idx: int = int(ping_key)
				ping[relation_key(faction_id, rival_idx)] = int(save_data.ping[ping_key])
		for first in factions.size():
			for second in range(first + 1, factions.size()):
				var pair := relation_key(first, second)
				if not diplomacy.has(pair): diplomacy[pair] = "peace"
				if not ping.has(pair): ping[pair] = 50
	war_exhaustion.clear()
	if int(save_data.get("version", 1)) >= 6:
		for pair_key in save_data.war_exhaustion:
			war_exhaustion[str(pair_key)] = int(save_data.war_exhaustion[pair_key])
	for first in factions.size():
		for second in range(first + 1, factions.size()):
			var pair := relation_key(first, second)
			if not war_exhaustion.has(pair):
				war_exhaustion[pair] = 0
	council_law = save_data.council_law
	law_turns_left = int(save_data.law_turns_left)
	locked_faction = int(save_data.locked_faction)
	trade_used = int(save_data.get("trade_used", 0))
	event_active = save_data.get("event_active", "")
	event_turns_left = int(save_data.get("event_turns_left", 0))
	meme_city_idx = int(save_data.get("meme_city_idx", -1))
	next_event_turn = int(save_data.get("next_event_turn", 8))
	artifacts.clear()
	for a in save_data.get("artifacts", []):
		artifacts[a] = true
	if save_data.has("rng_state"):
		_rng.state = int(str(save_data.rng_state))
	update_visibility()
	# Loading restores last-known intel exactly. Legacy saves had no such memory,
	# so they intentionally migrate to an empty snapshot.
	satellite_intel.clear()
	if int(save_data.get("version", 1)) >= 7:
		for intel_cell in _deserialize_points(save_data.satellite_intel):
			satellite_intel[intel_cell] = true
	emit_signal("resources_changed")
	emit_signal("turn_changed", turn)
	UnitsView.sync()
	emit_signal("match_ready")
	return true


func _validate_save_data(data: Dictionary) -> bool:
	var required_keys: Array = [
		"seed", "map_size", "map_type", "turn", "faction_id", "factions",
		"resources", "city_name_counter", "tech", "units", "cities", "terminals",
		"lairs", "explored", "ai", "uplink_turns", "monopoly_turns", "global_server",
		"orbital_mainframe_turn",
	]
	for key in required_keys:
		if not data.has(key):
			return false
	for key in [
		"seed", "map_size", "map_type", "turn", "faction_id", "city_name_counter",
		"uplink_turns", "monopoly_turns", "orbital_mainframe_turn",
	]:
		if not _is_int_like(data[key]):
			return false
	if not (data.global_server is bool):
		return false
	if data.has("version") and not _is_int_like(data.version):
		return false
	var save_version: int = int(data.get("version", 1))
	if save_version < 1 or save_version > SAVE_VERSION:
		return false
	if data.has("rng_state") and (not (data.rng_state is String) or not data.rng_state.is_valid_int()):
		return false
	if data.has("trade_used") and not _is_int_like(data.trade_used):
		return false
	if data.has("resolved_map_type") and not _is_int_like(data.resolved_map_type):
		return false
	if data.has("requested_map_type") and not _is_int_like(data.requested_map_type):
		return false
	if save_version >= 2:
		for key in ["rng_state", "resolved_map_type", "requested_map_type", "terrain", "trade_used"]:
			if not data.has(key):
				return false
		if not _is_int_like(data.resolved_map_type) or not _is_int_like(data.requested_map_type) \
				or not _is_int_like(data.trade_used):
			return false
	if save_version >= 4 and (not data.has("ai_tech") or not (data.ai_tech is Dictionary)):
		return false
	if save_version >= 5 and (not data.has("ai_agendas") or not (data.ai_agendas is Dictionary) \
			or not data.has("monopoly_progress") or not (data.monopoly_progress is Dictionary)):
		return false
	if save_version >= 6 and (not data.has("network_sol_generated") \
			or not (data.network_sol_generated is Dictionary) or not data.has("war_exhaustion") \
			or not (data.war_exhaustion is Dictionary)):
		return false
	var map_size: int = int(data.map_size)
	if not Data.MAP_DIMENSIONS.has(map_size):
		return false
	var resolved_type: int = int(data.get("resolved_map_type", data.map_type))
	if not Data.MAP_TYPE_NAMES.has(resolved_type):
		return false
	if save_version >= 2 and resolved_type == Data.MapType.RANDOM:
		return false
	var requested_type: int = int(data.get("requested_map_type", data.map_type))
	if not Data.MAP_TYPE_NAMES.has(requested_type):
		return false
	if not (data.factions is Array) or data.factions.size() < 2:
		return false
	if int(data.faction_id) != 0:
		return false
	var seen_factions: Dictionary = {}
	for faction_value in data.factions:
		if not (faction_value is String):
			return false
		var faction_name: String = faction_value
		if not Data.FACTIONS.has(faction_name) or seen_factions.has(faction_name):
			return false
		seen_factions[faction_name] = true
	if not (data.resources is Dictionary) or not (data.tech is Dictionary):
		return false
	if not _validate_numeric_fields(data.resources, Data.START_RESOURCES.keys()):
		return false
	if not data.tech.has("researched") or not (data.tech.researched is Array) \
			or not data.tech.has("current") or not data.tech.has("points"):
		return false
	if not (data.tech.current is String) or (data.tech.current != "" and not Data.TECHS.has(data.tech.current)) \
			or not _is_number(data.tech.points):
		return false
	for tech_id in data.tech.researched:
		if not (tech_id is String) or not Data.TECHS.has(tech_id):
			return false
	if not (data.units is Array) or not (data.cities is Array) or not (data.ai is Dictionary):
		return false
	var dims: Vector2i = Data.MAP_DIMENSIONS[map_size]
	for unit_data in data.units:
		if not (unit_data is Dictionary) or (save_version >= 3 and not unit_data.has("cargo")) \
				or (save_version >= 8 and not unit_data.has("orders_skipped")) \
				or not _validate_entity_data(unit_data, dims, data.factions.size(), false):
			return false
	for city_data in data.cities:
		if not (city_data is Dictionary) or (save_version >= 6 and not city_data.has("occupation_until")) \
				or (save_version >= 9 and not city_data.has("focus")) \
				or not _validate_entity_data(city_data, dims, data.factions.size(), true):
			return false
	if not _validate_points(data.terminals, dims) or not _validate_points(data.lairs, dims) \
			or not _validate_points(data.explored, dims):
		return false
	if save_version >= 7 and (not data.has("explored_terrain") \
			or not _validate_explored_terrain(data.explored_terrain, data.explored, dims) \
			or not data.has("satellite_intel") \
			or not _validate_unique_points(data.satellite_intel, dims)):
		return false
	var expected_cells: int = dims.x * dims.y
	if data.has("terrain"):
		if not (data.terrain is Array) or data.terrain.size() != expected_cells:
			return false
		for terrain_id in data.terrain:
			if not (terrain_id is String) or not Data.TERRAIN.has(terrain_id):
				return false
	if save_version >= 3 and not _validate_v3_occupancy(data, dims):
		return false
	if data.has("infra") or data.has("improvements"):
		if not data.has("infra") or not data.has("improvements") \
				or not (data.infra is Array) or not (data.improvements is Array) \
				or data.infra.size() != expected_cells or data.improvements.size() != expected_cells:
			return false
		for infra_value in data.infra:
			if not _is_int_like(infra_value) or int(infra_value) < 0 or int(infra_value) > 2:
				return false
		for improvement_id in data.improvements:
			if not (improvement_id is String) or improvement_id not in ["", "mine", "dome", "tower"]:
				return false
	if data.has("diplomacy") or data.has("ping") or data.has("council_law") \
			or data.has("law_turns_left") or data.has("locked_faction"):
		if not data.has("diplomacy") or not (data.diplomacy is Dictionary) \
				or not data.has("ping") or not (data.ping is Dictionary) \
				or not data.has("council_law") or not data.has("law_turns_left") or not data.has("locked_faction"):
			return false
		for diplomacy_key in data.diplomacy:
			if not _is_int_key(diplomacy_key) or not (data.diplomacy[diplomacy_key] is String):
				if save_version < 5 or not _valid_relation_key(str(diplomacy_key), data.factions.size()): return false
			elif save_version >= 5: return false
			var diplomacy_idx: int = _int_key(diplomacy_key)
			if save_version < 5 and (diplomacy_idx <= 0 or diplomacy_idx >= data.factions.size()) \
					or data.diplomacy[diplomacy_key] not in ["peace", "alliance", "war"]:
				return false
		for ping_key in data.ping:
			if (save_version < 5 and not _is_int_key(ping_key)) \
					or (save_version >= 5 and not _valid_relation_key(str(ping_key), data.factions.size())) \
					or not _is_number(data.ping[ping_key]):
				return false
			var ping_idx: int = _int_key(ping_key) if _is_int_key(ping_key) else 1
			if save_version < 5 and (ping_idx <= 0 or ping_idx >= data.factions.size()):
				return false
		if save_version >= 5:
			var expected_pairs: int = data.factions.size() * (data.factions.size() - 1) / 2
			if data.diplomacy.size() != expected_pairs or data.ping.size() != expected_pairs:
				return false
			for first in data.factions.size():
				for second in range(first + 1, data.factions.size()):
					var required_pair := relation_key(first, second)
					if not data.diplomacy.has(required_pair) or not data.ping.has(required_pair):
						return false
		if not (data.council_law is String) \
				or (data.council_law != "" and not Data.COUNCIL_LAWS.has(data.council_law)) \
				or not _is_int_like(data.law_turns_left) or not _is_int_like(data.locked_faction):
			return false
	for ai_key in data.ai:
		if not _is_int_key(ai_key) or not (data.ai[ai_key] is Dictionary):
			return false
		var ai_idx: int = _int_key(ai_key)
		if ai_idx <= 0 or ai_idx >= data.factions.size() \
				or not _validate_numeric_fields(data.ai[ai_key], Data.START_RESOURCES.keys()):
			return false
	if data.has("ai_tech"):
		for ai_key in data.ai_tech:
			if not _is_int_key(ai_key) or not (data.ai_tech[ai_key] is Dictionary):
				return false
			var ai_idx: int = _int_key(ai_key)
			var saved_tech: Dictionary = data.ai_tech[ai_key]
			if ai_idx <= 0 or ai_idx >= data.factions.size() \
					or not saved_tech.has("researched") or not (saved_tech.researched is Array) \
					or not saved_tech.has("current") or not (saved_tech.current is String) \
					or not saved_tech.has("points") or not _is_number(saved_tech.points):
				return false
			if saved_tech.current != "" and not Data.TECHS.has(saved_tech.current):
				return false
			for tech_id in saved_tech.researched:
				if not (tech_id is String) or not Data.TECHS.has(tech_id):
					return false
	if data.has("ai_agendas"):
		for agenda_key in data.ai_agendas:
			if not _is_int_key(agenda_key) or _int_key(agenda_key) <= 0 \
					or _int_key(agenda_key) >= data.factions.size() \
					or str(data.ai_agendas[agenda_key]) not in AiPlayer.AGENDAS:
				return false
		if save_version >= 5:
			for faction_idx in range(1, data.factions.size()):
				if not data.ai_agendas.has(str(faction_idx)):
					return false
	if data.has("monopoly_progress"):
		for progress_key in data.monopoly_progress:
			if not _is_int_key(progress_key) or _int_key(progress_key) < 0 \
					or _int_key(progress_key) >= data.factions.size() \
					or not _is_int_like(data.monopoly_progress[progress_key]):
				return false
		if save_version >= 5:
			for faction_idx in data.factions.size():
				if not data.monopoly_progress.has(str(faction_idx)):
					return false
	if save_version >= 6:
		for faction_idx in data.factions.size():
			var faction_key := str(faction_idx)
			if not data.network_sol_generated.has(faction_key) \
					or not _is_int_like(data.network_sol_generated[faction_key]) \
					or int(data.network_sol_generated[faction_key]) < 0:
				return false
		var expected_exhaustion_pairs: int = data.factions.size() * (data.factions.size() - 1) / 2
		if data.war_exhaustion.size() != expected_exhaustion_pairs:
			return false
		for first in data.factions.size():
			for second in range(first + 1, data.factions.size()):
				var pair := relation_key(first, second)
				if not data.war_exhaustion.has(pair) \
						or not _is_int_like(data.war_exhaustion[pair]):
					return false
	if not _validate_optional_save_fields(data):
		return false
	return true


func _validate_v3_occupancy(data: Dictionary, dims: Vector2i) -> bool:
	var occupied_cells: Dictionary = {}
	for unit_data in data.units:
		var unit_cell := Vector2i(int(unit_data.x), int(unit_data.y))
		var cell_key := "%d,%d" % [unit_cell.x, unit_cell.y]
		if occupied_cells.has(cell_key):
			return false
		occupied_cells[cell_key] = true
		var terrain_id: String = data.terrain[unit_cell.x * dims.y + unit_cell.y]
		var terrain_data: Dictionary = Data.TERRAIN[terrain_id]
		var naval: bool = bool(Faction.unit_data(unit_data.type).get("naval", false))
		if naval != bool(terrain_data.get("water", false)):
			return false
		if not naval and bool(terrain_data.get("impassable", false)):
			return false
	for city_data in data.cities:
		var city_key := "%d,%d" % [int(city_data.x), int(city_data.y)]
		if occupied_cells.has(city_key):
			return false
		occupied_cells[city_key] = true
	return true


func _validate_entity_data(data: Dictionary, dims: Vector2i, faction_count: int, city: bool) -> bool:
	var keys: Array = ["faction", "x", "y"]
	if city:
		keys.append_array(["name", "pop", "food", "scrap_stock", "capital", "buildings", "queue"])
	else:
		keys.append_array(["type", "moves", "veteran", "fortified"])
	for key in keys:
		if not data.has(key):
			return false
	if not _is_int_like(data.faction) or not _is_int_like(data.x) or not _is_int_like(data.y):
		return false
	if city:
		if not (data.name is String) or not _is_number(data.pop) or not _is_number(data.food) \
				or not _is_number(data.scrap_stock) or not (data.capital is bool) \
				or not (data.buildings is Array) or not (data.queue is Array):
			return false
		for building_id in data.buildings:
			if not _is_known_building_id(building_id):
				return false
		for queued_id in data.queue:
			if not _is_known_building_id(queued_id):
				return false
		for optional_key in ["fatigue", "offline", "dos", "occupation_until"]:
			if data.has(optional_key) and not _is_int_like(data[optional_key]):
				return false
		if data.has("occupation_until") and int(data.occupation_until) < 0:
			return false
		if data.has("focus") and (not (data.focus is String) or data.focus not in CITY_FOCUSES):
			return false
	else:
		if not _is_known_unit_id(data.type) or not _is_number(data.moves) \
				or not (data.veteran is bool) or not (data.fortified is bool):
			return false
		if data.has("moved") and not (data.moved is bool):
			return false
		if data.has("orders_skipped") and not (data.orders_skipped is bool):
			return false
		if data.has("cargo"):
			if not (data.cargo is Array):
				return false
			var carrier_data: Dictionary = Faction.unit_data(data.type)
			if data.cargo.size() > int(carrier_data.get("transport_capacity", 0)):
				return false
			for cargo_data in data.cargo:
				if not _validate_cargo_data(cargo_data, int(data.faction)):
					return false
	var entity_faction: int = int(data.faction)
	var x: int = int(data.x)
	var y: int = int(data.y)
	var valid_faction: bool = entity_faction >= 0 and entity_faction < faction_count
	if not city and entity_faction == BARB_FACTION:
		valid_faction = true
	return valid_faction \
		and x >= 0 and x < dims.x and y >= 0 and y < dims.y


func _validate_cargo_data(data: Variant, carrier_faction: int) -> bool:
	if not (data is Dictionary):
		return false
	for key in ["type", "faction", "moves", "veteran", "fortified"]:
		if not data.has(key):
			return false
	if data.has("cargo") or not _is_known_unit_id(data.type) \
			or bool(Faction.unit_data(data.type).get("naval", false)):
		return false
	if data.has("moved") and not (data.moved is bool):
		return false
	return _is_int_like(data.faction) and int(data.faction) == carrier_faction \
		and _is_number(data.moves) and data.veteran is bool and data.fortified is bool


func _validate_points(points: Variant, dims: Vector2i) -> bool:
	if not (points is Array):
		return false
	for pair in points:
		if not (pair is Array) or pair.size() != 2:
			return false
		if not _is_int_like(pair[0]) or not _is_int_like(pair[1]):
			return false
		var x: int = int(pair[0])
		var y: int = int(pair[1])
		if x < 0 or x >= dims.x or y < 0 or y >= dims.y:
			return false
	return true


func _validate_unique_points(points: Variant, dims: Vector2i) -> bool:
	if not _validate_points(points, dims):
		return false
	var seen: Dictionary = {}
	for pair in points:
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		if seen.has(cell):
			return false
		seen[cell] = true
	return true


func _validate_explored_terrain(memory: Variant, explored_points: Variant,
		dims: Vector2i) -> bool:
	if not (memory is Array) or not (explored_points is Array) \
			or memory.size() != explored_points.size():
		return false
	var explored_cells: Dictionary = {}
	for pair in explored_points:
		explored_cells[Vector2i(int(pair[0]), int(pair[1]))] = true
	var seen: Dictionary = {}
	for entry in memory:
		if not (entry is Array) or entry.size() != 3 \
				or not _is_int_like(entry[0]) or not _is_int_like(entry[1]) \
				or not (entry[2] is String):
			return false
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if cell.x < 0 or cell.x >= dims.x or cell.y < 0 or cell.y >= dims.y \
				or not explored_cells.has(cell) \
				or seen.has(cell) or not Data.TERRAIN.has(str(entry[2])):
			return false
		seen[cell] = true
	return true


func _validate_optional_save_fields(data: Dictionary) -> bool:
	for key in ["shield_turns", "sync_turns", "event_turns_left", "meme_city_idx", "next_event_turn"]:
		if data.has(key) and not _is_int_like(data[key]):
			return false
	if data.has("protocol") and (not (data.protocol is String) or data.protocol not in Data.PROTOCOL_NAMES):
		return false
	if data.has("event_active") and (not (data.event_active is String) \
			or data.event_active not in ["", "outage", "meme"]):
		return false
	if data.has("wonders"):
		if not (data.wonders is Array):
			return false
		for wonder_id in data.wonders:
			if not (wonder_id is String) or not Data.WONDERS.has(wonder_id):
				return false
	if data.has("artifacts"):
		if not (data.artifacts is Array):
			return false
		for artifact_id in data.artifacts:
			if not (artifact_id is String) or artifact_id not in ["dragon_suit", "genesis_chapter"]:
				return false
	return true


func _validate_numeric_fields(data: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not data.has(key) or not _is_number(data[key]):
			return false
	return true


func _is_known_unit_id(value: Variant) -> bool:
	if not (value is String):
		return false
	if Data.UNITS.has(value):
		return true
	for faction_name in Faction.UNIQUE_UNITS:
		if Faction.UNIQUE_UNITS[faction_name].has(value):
			return true
	return false


func _is_known_building_id(value: Variant) -> bool:
	if not (value is String):
		return false
	if Data.BUILDINGS.has(value):
		return true
	for faction_name in Faction.UNIQUE_BUILDINGS:
		if Faction.UNIQUE_BUILDINGS[faction_name].has(value):
			return true
	return false


func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floor(value)


func _is_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))


func _is_int_key(value: Variant) -> bool:
	return _is_int_like(value) or (value is String and value.is_valid_int())


func _int_key(value: Variant) -> int:
	return int(value)


func _valid_relation_key(value: String, faction_count: int) -> bool:
	var parts := value.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	var first := int(parts[0])
	var second := int(parts[1])
	return first >= 0 and first < second and second < faction_count


func _faction_ids() -> Array:
	var out: Array = []
	for f in factions:
		out.append(f.id)
	return out


func _serialize_units() -> Array:
	var out: Array = []
	for u in units:
		out.append({
			"type": u.type_id, "faction": u.faction_id,
			"x": u.cell.x, "y": u.cell.y,
			"moves": u.moves_left, "veteran": u.veteran, "fortified": u.fortified,
			"moved": u.has_moved_this_turn, "orders_skipped": u.orders_skipped,
			"cargo": _serialize_cargo(u.cargo),
		})
	return out


func _serialize_relations(ping_values: bool) -> Dictionary:
	var out := {}
	for first in factions.size():
		for second in range(first + 1, factions.size()):
			var pair := relation_key(first, second)
			out[pair] = relation_ping(first, second) if ping_values else relation_status(first, second)
	return out


func _serialize_cargo(cargo_units: Array) -> Array:
	var out: Array = []
	for passenger in cargo_units:
		out.append({
			"type": passenger.type_id, "faction": passenger.faction_id,
			"moves": passenger.moves_left, "veteran": passenger.veteran,
			"fortified": passenger.fortified, "moved": passenger.has_moved_this_turn,
		})
	return out


func _serialize_cities() -> Array:
	var out: Array = []
	for c in cities:
		out.append({
			"name": c.name, "faction": c.faction_id,
			"x": c.cell.x, "y": c.cell.y,
			"pop": c.population, "food": c.food_stock, "scrap_stock": c.scrap_stock,
			"capital": c.is_capital,
			"fatigue": c.fatigue, "offline": c.offline_turns, "dos": c.dos_turns,
			"occupation_until": c.occupation_until_turn,
			"focus": c.focus,
			"buildings": c.buildings.keys(), "queue": c.build_queue,
		})
	return out


func _serialize_points(points: Array) -> Array:
	var out: Array = []
	for p2 in points:
		out.append([p2.x, p2.y])
	return out


func _deserialize_points(data: Array) -> Array:
	var out: Array = []
	for pair in data:
		out.append(Vector2i(int(pair[0]), int(pair[1])))
	return out


func _serialize_grid_array(arr: Array) -> Array:
	var out: Array = []
	for col in arr:
		for v in col:
			out.append(v)
	return out


func _deserialize_grid_array(arr: Array, data: Array) -> void:
	var i := 0
	for x in arr.size():
		for y in arr[x].size():
			arr[x][y] = int(data[i])
			i += 1


func _serialize_grid_strings(arr: Array) -> Array:
	var out: Array = []
	for col in arr:
		for v in col:
			out.append(v)
	return out


func _deserialize_grid_strings(arr: Array, data: Array) -> void:
	var i := 0
	for x in arr.size():
		for y in arr[x].size():
			arr[x][y] = data[i]
			i += 1


func _serialize_ai() -> Dictionary:
	var out := {}
	if ai != null:
		for f_key in ai.ai_resources:
			out[str(f_key)] = ai.ai_resources[f_key]
	return out


func _serialize_explored_terrain() -> Array:
	var out: Array = []
	for cell in explored:
		out.append([cell.x, cell.y, str(explored_terrain.get(cell,
			grid.terrain[cell.x][cell.y]))])
	return out


func _normalized_resources(saved: Dictionary) -> Dictionary:
	var out := {}
	for key in Data.START_RESOURCES:
		out[key] = int(saved[key])
	return out


## ---------- Random events (Solana lore) ----------

func _tick_events() -> void:
	# end active event
	if event_active != "":
		event_turns_left -= 1
		if event_turns_left <= 0:
			if event_active == "meme":
				game_log("Meme Coin Surge subsided")
			elif event_active == "outage":
				game_log("Network sync restored")
			event_active = ""
			meme_city_idx = -1
	# new event (Era II+, not with Firedancer)
	if event_active == "" and turn >= next_event_turn and tech != null 			and tech.current_era() >= 2 and not has_passive("firedancer"):
		if _rng.randf() < 0.5:
			event_active = "outage"
			event_turns_left = 1
			game_log("NETWORK OUTAGE! Validators lost sync for 1 turn")
		else:
			var candidates: Array = []
			for i in cities.size():
				if cities[i].faction_id == faction_id:
					candidates.append(i)
			if not candidates.is_empty():
				meme_city_idx = candidates[_rng.randi_range(0, candidates.size() - 1)]
				event_active = "meme"
				event_turns_left = 3
				# Meme surge: network chaos -> fatigue to max
				for c2 in cities:
					if c2.faction_id == faction_id:
						c2.fatigue = 100
				game_log("MEME COIN SURGE! %s minting +300%% $SOL for 3 turns" % cities[meme_city_idx].name)
		next_event_turn = turn + _rng.randi_range(8, 15)


## Jito Priority Fee: instantly finish a building/unit for a $SOL fee.
func jito_rush(city: City, kind: String, id: String) -> bool:
	var cost := 0
	if kind == "building":
		var bd: Dictionary = Faction.building_data(id)
		cost = maxi(1, int(round(int(bd.scrap_cost) * 0.1)))
	elif kind == "unit":
		var actual_type: String = id
		if city.faction != null:
			actual_type = city.faction.unit_for(id)
		var ud: Dictionary = Faction.unit_data(actual_type)
		var required_tech: String = str(ud.get("requires_tech", ""))
		if required_tech != "" and not tech.is_researched(required_tech):
			game_log("%s requires %s" % [ud.name, Data.TECHS[required_tech].name])
			return false
		if bool(ud.get("naval", false)) and grid.find_free_ocean_neighbor(city.cell).x < 0:
			game_log("%s requires a coastal city with free adjacent ocean" % ud.name)
			return false
		cost = maxi(1, int(round(int(ud.scrap_cost) * 0.1)))
		if resources.scrap < int(ud.scrap_cost) \
				or resources.sol < int(ud.sol_cost) + cost:
			game_log("Jito rush needs the full unit cost plus its priority fee")
			return false
		if not train_unit(city, id):
			return false
		resources.sol -= cost
		emit_signal("resources_changed")
		return true
	if resources.sol < cost:
		game_log("Jito rush needs ◎%d" % cost)
		return false
	resources.sol -= cost
	if kind == "building":
		city.build_queue.append(id)
		# instant build
		var bd2: Dictionary = Faction.building_data(id)
		if resources.sol >= int(bd2.sol_cost):
			resources.sol -= int(bd2.sol_cost)
			city.buildings[id] = true
			city.build_queue.erase(id)
			game_log("Jito rush: %s built instantly!" % bd2.name)
	emit_signal("resources_changed")
	return true


## Artifact from terminal (15% chance instead of standard outcomes).
func _random_artifact() -> String:
	var roll: float = _rng.randf()
	if roll < 0.5:
		return "dragon_suit"
	return "genesis_chapter"


## ---------- Infrastructure / improvements / evolution ----------

## Cable on the unit's tile (1/3 MP movement).
func build_cable(u: Unit) -> bool:
	if grid.infra[u.cell.x][u.cell.y] >= 1:
		game_log("Cable already here")
		return false
	if grid.is_water(u.cell.x, u.cell.y):
		return false
	grid.infra[u.cell.x][u.cell.y] = 1
	u.moves_left = 0
	game_log("Cable laid (1/3 MP movement)")
	return true


## Monorail on the unit's tile (~0 MP, +1 $SOL per tile).
func build_monorail(u: Unit) -> bool:
	if grid.infra[u.cell.x][u.cell.y] >= 2:
		game_log("Monorail already here")
		return false
	if grid.is_water(u.cell.x, u.cell.y):
		return false
	grid.infra[u.cell.x][u.cell.y] = 2
	recompute_city_worked_tiles()
	u.moves_left = 0
	game_log("Monorail built (0 MP, +1 $SOL)")
	return true


## Tile improvement on the unit's tile (mine/dome/tower).
func build_improvement(u: Unit, imp: String) -> bool:
	if u.type_id != "founder":
		game_log("Only a Node Founder can build improvements")
		return false
	var city := _nearest_friendly_city(u.cell)
	if city == null:
		game_log("No friendly city nearby")
		return false
	if not city.can_build_improvement(u.cell.x, u.cell.y, imp):
		game_log("Cannot build %s here" % imp)
		return false
	city.build_improvement(u.cell.x, u.cell.y, imp)
	recompute_city_worked_tiles()
	u.moves_left = 0
	game_log("Improvement built: %s" % imp)
	return true


func _nearest_friendly_city(cell: Vector2i) -> City:
	var best: City = null
	var best_d := INF
	for c in cities:
		if c.faction_id != faction_id:
			continue
		var d := Vector2(c.cell - cell).length()
		if d < best_d:
			best_d = d
			best = c
	if best != null and best_d < 3.0:
		return best
	return null


## Unit upgrade (evolution for $SOL). Unit must be next to a city.
func upgrade_unit(u: Unit) -> bool:
	if not u.cargo.is_empty():
		game_log("Unload all cargo before upgrading this unit")
		return false
	var target: String = u.upgrade_target()
	if target == "":
		game_log("%s cannot upgrade" % Faction.unit_data(u.type_id).name)
		return false
	var cost: int = u.upgrade_cost()
	if resources.sol < cost:
		game_log("Upgrade needs ◎%d" % cost)
		return false
	if _nearest_friendly_city(u.cell) == null:
		game_log("Move next to a city to upgrade")
		return false
	resources.sol -= cost
	var pos := u.cell
	var faction := u.faction_id
	units.erase(u)
	grid.clear_occupant(pos.x, pos.y, u)
	var nu := _spawn_unit(target, pos, faction)
	nu.moves_left = nu.max_moves() * 0.5
	game_log("%s upgraded to %s" % [Faction.unit_data(target).name, nu.data().name])
	emit_signal("resources_changed")
	UnitsView.sync()
	return true


## Scrap a unit: refund half its cost.
func scrap_unit(u: Unit) -> bool:
	if not u.cargo.is_empty():
		game_log("Unload all cargo before scrapping this unit")
		return false
	var ud: Dictionary = Faction.unit_data(u.type_id)
	var refund := int(ud.scrap_cost) / 2
	_remove_unit(u)
	resources.scrap += refund
	game_log("%s scrapped for +%d Scrap" % [ud.name, refund])
	emit_signal("resources_changed")
	UnitsView.sync()
	return true


## Building upgrade in a city (turbine -> reactor -> fusion).
func upgrade_city_building(city: City) -> bool:
	var built: String = city.upgrade_building(resources, tech)
	if built == "":
		game_log("No upgrade available in %s" % city.name)
		return false
	game_log("%s upgraded to %s" % [city.name, Faction.building_data(built).name])
	emit_signal("resources_changed")
	emit_signal("city_changed", city)
	return true


## ---------- Diplomacy (treaties, trade, Council) ----------

const WAR_EXHAUSTION_LIMIT := 30
const CAPTURE_EXHAUSTION := 4
const CEASEFIRE_TURNS := 6
const OCCUPATION_TURNS := 7

func relation_key(first: int, second: int) -> String:
	return "%d:%d" % [mini(first, second), maxi(first, second)]


func relation_status(first: int, second: int) -> String:
	if first == second:
		return "alliance"
	var rival := second if first == faction_id else first if second == faction_id else -1
	if rival >= 0 and diplomacy.has(rival):
		return str(diplomacy[rival])
	var pair := relation_key(first, second)
	if diplomacy.has(pair):
		return str(diplomacy[pair])
	# Runtime compatibility for tests and migrated pre-v5 player-centric state.
	return str(diplomacy.get(rival, "peace"))


func relation_ping(first: int, second: int) -> int:
	var rival := second if first == faction_id else first if second == faction_id else -1
	if rival >= 0 and ping.has(rival):
		return int(ping[rival])
	var pair := relation_key(first, second)
	if ping.has(pair):
		return int(ping[pair])
	return int(ping.get(rival, 50))


func set_relation(first: int, second: int, status: String) -> void:
	if first == second or status not in ["peace", "alliance", "war"]:
		return
	var pair := relation_key(first, second)
	var previous := relation_status(first, second)
	diplomacy[relation_key(first, second)] = status
	if status == "war" and previous != "war":
		war_exhaustion[pair] = 0
	elif status == "peace" and previous == "war":
		war_exhaustion[pair] = -CEASEFIRE_TURNS
	elif status == "alliance":
		war_exhaustion[pair] = 0
	var rival := second if first == faction_id else first if second == faction_id else -1
	if rival >= 0 and diplomacy.has(rival):
		diplomacy[rival] = status


func set_relation_ping(first: int, second: int, value: int) -> void:
	if first == second:
		return
	ping[relation_key(first, second)] = clampi(value, 0, 100)
	var rival := second if first == faction_id else first if second == faction_id else -1
	if rival >= 0 and ping.has(rival):
		ping[rival] = clampi(value, 0, 100)


func diplomatic_status(f_idx: int) -> String:
	return relation_status(faction_id, f_idx)


func are_factions_at_war(first: int, second: int) -> bool:
	if first == second:
		return false
	return relation_status(first, second) == "war" \
			and not (locked_faction in [first, second] and law_turns_left > 0)


func can_start_war(first: int, second: int) -> bool:
	return first != second and int(war_exhaustion.get(relation_key(first, second), 0)) >= 0


func _advance_strategic_state() -> void:
	for first in factions.size():
		for second in range(first + 1, factions.size()):
			var pair := relation_key(first, second)
			var exhaustion := int(war_exhaustion.get(pair, 0))
			if relation_status(first, second) == "war":
				exhaustion += 1
				war_exhaustion[pair] = exhaustion
				if exhaustion >= WAR_EXHAUSTION_LIMIT:
					set_relation(first, second, "peace")
					set_relation_ping(first, second, maxi(58, relation_ping(first, second)))
			else:
				war_exhaustion[pair] = mini(0, exhaustion + 1) if exhaustion < 0 else 0


## Friendship Airdrop: gifting $SOL raises Ping.
func gift_sol(f_idx: int, amount: int) -> bool:
	if resources.sol < amount:
		return false
	resources.sol -= amount
	set_relation_ping(faction_id, f_idx, relation_ping(faction_id, f_idx) + amount / 2)
	game_log("Gifted %d $SOL to %s (ping +%d)" % [amount, factions[f_idx].name, amount / 2])
	emit_signal("resources_changed")
	return true


## Trade (Primitive Coding): 10 $SOL <-> 50 Scrap, 3 deals per turn.
func trade_resources(f_idx: int, buy_scrap: bool) -> bool:
	if trade_used >= 3:
		game_log("Trade limit reached for this turn")
		return false
	if buy_scrap:
		if resources.sol < 10:
			return false
		resources.sol -= 10
		resources.scrap += 50
		game_log("Bought 50 Scrap for 10 $SOL")
	else:
		if resources.scrap < 50:
			return false
		resources.scrap -= 50
		resources.sol += 10
		game_log("Sold 50 Scrap for 10 $SOL")
	trade_used += 1
	emit_signal("resources_changed")
	return true


## Staking Alliance: merged energy grids; war on one ally = war on the pool.
func propose_alliance(f_idx: int) -> bool:
	if relation_ping(faction_id, f_idx) < 60:
		game_log("%s declines the alliance (ping too low)" % factions[f_idx].name)
		return false
	set_relation(faction_id, f_idx, "alliance")
	game_log("Staking Alliance with %s! Energy networks merged" % factions[f_idx].name)
	return true


## Hardfork: declaration of war (full transaction lock).
func declare_war(f_idx: int) -> void:
	if not can_start_war(faction_id, f_idx):
		game_log("Ceasefire with %s is still secured" % factions[f_idx].name)
		return
	set_relation(faction_id, f_idx, "war")
	game_log("HARDFORK! War declared on %s — borders locked" % factions[f_idx].name)


func propose_peace(f_idx: int) -> bool:
	if relation_ping(faction_id, f_idx) < 30:
		game_log("%s rejects peace (ping too low)" % factions[f_idx].name)
		return false
	set_relation(faction_id, f_idx, "peace")
	game_log("Truce with %s" % factions[f_idx].name)
	return true


## Can this faction be attacked (alliance/peace blocked; address_lock blocked).
func can_attack_faction(f_idx: int) -> bool:
	if relation_status(faction_id, f_idx) != "war":
		return false
	if locked_faction == f_idx and law_turns_left > 0:
		return false
	return true


## Alliance energy transfer: automatic surplus supply.
func alliance_energy_transfer() -> void:
	if ai == null:
		return
	for f in range(1, factions.size()):
		if relation_status(faction_id, f) != "alliance":
			continue
		if ai.ai_resources.has(f) and int(ai.ai_resources[f].energy) < 0 and resources.energy > 0:
			var need := mini(resources.energy, -int(ai.ai_resources[f].energy))
			resources.energy -= need
			ai.ai_resources[f].energy += need
			game_log("Alliance: transferred %d Energy to %s" % [need, factions[f].name])


## Consensus Council: vote + random law application.
func consensus_council() -> void:
	if turn % 15 != 0:
		return
	var total_sol := 0.0
	var my_sol := 0.0
	for f in factions.size():
		var f_sol := 0.0
		if f == faction_id:
			f_sol = resources.sol
		elif ai != null and ai.ai_resources.has(f):
			f_sol = ai.ai_resources[f].sol
		total_sol += f_sol
		if f == faction_id:
			my_sol = f_sol
	if total_sol <= 0:
		return
	var share := my_sol / total_sol
	game_log("Consensus Council: your vote share is %.0f%% of the network" % (share * 100))
	if share >= 0.67 and global_server:
		emit_signal("game_over", factions[faction_id].name, "2/3 Consensus vote (Global Server)")
		return
	# Apply a law (random, not immediately repeated)
	var laws: Array = Data.COUNCIL_LAWS.keys()
	if council_law != "":
		laws.erase(council_law)
	if not laws.is_empty():
		council_law = laws[_rng.randi_range(0, laws.size() - 1)]
		law_turns_left = int(Data.COUNCIL_LAWS[council_law].duration)
		var ld: Dictionary = Data.COUNCIL_LAWS[council_law]
		game_log("Council law passed: %s — %s" % [ld.name, ld.desc])
		match ld.effect:
			"token_burn":
				resources.sol = int(round(resources.sol * 0.8))
				if ai != null:
					for f2 in range(1, factions.size()):
						if ai.ai_resources.has(f2):
							ai.ai_resources[f2].sol = int(round(ai.ai_resources[f2].sol * 0.8))
			"address_lock":
				locked_faction = faction_id if share < 0.5 else (1 if factions.size() > 1 else -1)
				game_log("Address Lock protects %s" % (factions[locked_faction].name if locked_faction >= 0 else "nobody"))


## Kill reward (Armored Courier loot: 50% enemy cost in $SOL).
func on_kill(attacker: Unit, killed: Unit) -> void:
	if Faction.unit_data(attacker.type_id).get("looter", false):
		var loot := int(Faction.unit_data(killed.type_id).scrap_cost) / 2
		resources.sol += loot
		game_log("Courier looted %d $SOL from %s" % [loot, Faction.unit_data(killed.type_id).name])
		emit_signal("resources_changed")


## EMP aura (Cyber Acolyte): adjacent enemy units lose 1 movement.
func emp_aura_penalty(u: Unit) -> int:
	for other in units:
		if other.faction_id == u.faction_id:
			continue
		var hostile: bool = other.faction_id == BARB_FACTION \
				or relation_status(u.faction_id, other.faction_id) == "war"
		if hostile and Faction.unit_data(other.type_id).get("emp_aura", false) \
				and Vector2(other.cell - u.cell).length() <= 1.5:
			return 1
	return 0


func reset_unit_moves_with_emp(u: Unit) -> void:
	u.reset_moves()
	u.moves_left = maxf(u.moves_left - emp_aura_penalty(u), 0.0)


## ---------- Fog of War ----------

## Recomputes player visibility (units/cities — vision radius).
const VISION_RADIUS := 3

func update_visibility() -> void:
	if grid == null:
		return
	visible.clear()
	var eyes: Array = []
	for u in units:
		if u.faction_id == faction_id:
			eyes.append(u.cell)
	for c in cities:
		if c.faction_id == faction_id:
			eyes.append(c.cell)
	for eye in eyes:
		for x in range(eye.x - VISION_RADIUS, eye.x + VISION_RADIUS + 1):
			for y in range(eye.y - VISION_RADIUS, eye.y + VISION_RADIUS + 1):
				var cell := Vector2i(x, y)
				if grid.in_bounds(x, y) \
						and absi(x - eye.x) + absi(y - eye.y) <= VISION_RADIUS:
					visible[cell] = true
					explored[cell] = true
					explored_terrain[cell] = grid.terrain[x][y]
	if selected_unit != null and selected_unit.faction_id != faction_id \
			and not visible.has(selected_unit.cell):
		select(null)
	elif selected_city != null and selected_city.faction_id != faction_id \
			and not visible.has(selected_city.cell):
		select(null)
	_refresh_satellite_intel()


func is_explored(cell: Vector2i) -> bool:
	return explored.has(cell)


func is_visible(cell: Vector2i) -> bool:
	return visible.has(cell)


func remembered_terrain(cell: Vector2i) -> String:
	return str(explored_terrain.get(cell, ""))


func _activate_satellite_intel() -> void:
	satellite_intel.clear()
	for city in cities:
		if _is_enemy_validator(city):
			satellite_intel[city.cell] = true


func _refresh_satellite_intel() -> void:
	if not has_passive("reveal_validators"):
		return
	# Current sight is authoritative. Hidden cells retain their last-known marker.
	for cell in visible:
		satellite_intel.erase(cell)
	for city in cities:
		if visible.has(city.cell) and _is_enemy_validator(city):
			satellite_intel[city.cell] = true


func _is_enemy_validator(city: City) -> bool:
	if city == null or city.faction_id == faction_id:
		return false
	for building_id in ["genesis_node", "relic_validator", "server_altar"]:
		if city.has_building(building_id):
			return true
	return false


func game_log(text: String) -> void:
	emit_signal("log_message", text)


## Visual era: name and accent color (change with tech).
const ERA_NAMES := ["", "Foundation", "Composition", "Scale", "Production"]
const ERA_ACCENTS := [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.55, 0.25),  # Diesel: copper
	Color(0.7, 0.78, 0.9),   # Silicon: steel blue
	Color(0.2, 0.9, 0.9),    # Cybernetics: cyan
	Color(0.65, 0.45, 1.0),  # Orbit: violet
]


func era_index() -> int:
	if tech == null:
		return 1
	return clampi(tech.current_era(), 1, 4)


func era_name() -> String:
	return ERA_NAMES[era_index()]


func era_accent() -> Color:
	return ERA_ACCENTS[era_index()]


## SFX hook: Audio autoload is declared after Game in project.godot,
## so we reach it via node path (available at runtime).
func _sfx(name: String) -> void:
	var a := get_node_or_null("/root/Audio")
	if a != null:
		a.play(name)


## Any enemies near player cities (for fatigue).
func _faction_at_war() -> bool:
	return _faction_under_threat(faction_id)


func _faction_under_threat(target_faction: int) -> bool:
	for c in cities:
		if c.faction_id != target_faction:
			continue
		for u in units:
			var hostile: bool = u.faction_id == BARB_FACTION or (u.faction_id != target_faction \
					and relation_status(target_faction, u.faction_id) == "war")
			if hostile and Vector2(u.cell - c.cell).length() < 6.0:
				return true
	return false


## Switch network protocol.
func switch_protocol(protocol_id: String) -> void:
	if Data.PROTOCOLS.has(protocol_id):
		protocol = protocol_id
		game_log("Protocol switched to %s" % Data.PROTOCOLS[protocol_id].name)


## Build a wonder (global, once per game).
func build_wonder(w_id: String) -> bool:
	if wonders.has(w_id):
		return false
	var wd: Dictionary = Data.WONDERS[w_id]
	if not tech.is_researched(wd.tech):
		game_log("Requires %s" % Data.TECHS[wd.tech].name)
		return false
	if resources.sol < int(wd.sol_cost):
		game_log("Not enough $SOL for %s" % wd.name)
		return false
	resources.sol -= int(wd.sol_cost)
	wonders[w_id] = true
	match wd.effect:
		"genesis_shield":
			shield_turns = 50
		"uplink":
			orbital_mainframe_turn = turn
		"sync":
			sync_turns = 0
	game_log("Wonder built: %s" % wd.name)
	emit_signal("resources_changed")
	return true


func can_build_wonder(w_id: String) -> bool:
	var wd: Dictionary = Data.WONDERS[w_id]
	return not wonders.has(w_id) and tech.is_researched(wd.tech) and resources.sol >= int(wd.sol_cost)


## True if the player has researched a tech with this passive effect.
func has_passive(passive_id: String) -> bool:
	if tech == null:
		return false
	for t_id in tech.researched:
		var td: Dictionary = Data.TECHS[t_id]
		if td.get("passive", "") == passive_id:
			return true
	return false


## Infantry move bonus (Cyber Implants): +1 move for infantry units.
func infantry_move_bonus() -> int:
	return 1 if has_passive("infantry_plus1move") else 0


## Attack bonus: Steel Protocol (+25%) + Dragon Suit morale (+10%).
func faction_attack_bonus() -> float:
	var mult := faction_attack_bonus_for(faction_id)
	if artifacts.has("dragon_suit"):
		mult += 0.1
	return mult


func faction_attack_bonus_for(target_faction: int) -> float:
	var fb3: Dictionary = factions[target_faction].bonuses()
	var mult := float(fb3.get("attack_bonus", 1.0))
	return mult


## ---------- Units ----------

func _spawn_unit(type_id: String, pos: Vector2i, faction: int = 0) -> Unit:
	var u := Unit.new(type_id, faction, pos, grid)
	units.append(u)
	grid.place_occupant(pos.x, pos.y, u)
	return u


func spawn_unit(type_id: String, pos: Vector2i, faction: int = 0) -> Unit:
	return _spawn_unit(type_id, pos, faction)


func capture_city(city: City, new_faction: int) -> bool:
	if not cities.has(city) or new_faction < 0 or new_faction >= factions.size():
		return false
	if city.faction_id == new_faction or occupation_remaining(city) > 0:
		return false
	var old_faction := city.faction_id
	city.faction_id = new_faction
	city.faction = factions[new_faction]
	city.occupation_until_turn = turn + OCCUPATION_TURNS
	city.buildings["genesis_node"] = true
	var pair := relation_key(old_faction, new_faction)
	war_exhaustion[pair] = int(war_exhaustion.get(pair, 0)) + CAPTURE_EXHAUSTION
	recompute_city_worked_tiles()
	_refresh_satellite_intel()
	emit_signal("city_changed", city)
	return true


func occupation_remaining(city: City) -> int:
	return maxi(0, city.occupation_until_turn - turn) if city != null else 0


func unit_at(cell: Vector2i) -> Unit:
	for u in units:
		if u.cell == cell:
			return u
	return null


func units_of_faction(f: int) -> Array:
	var result: Array = []
	for u in units:
		if u.faction_id == f:
			result.append(u)
	return result


func city_at(cell: Vector2i) -> City:
	for c in cities:
		if c.cell == cell:
			return c
	return null


## ---------- Turn ----------

## Derived every turn from saved infrastructure; no component state is serialized.
func _player_energy_grid_state() -> Dictionary:
	return _faction_energy_grid_state(faction_id)


func _faction_energy_grid_state(target_faction: int) -> Dictionary:
	var player_cities: Array = []
	var city_cells: Array = []
	var blocked_foreign_cells: Array = []
	for c in cities:
		if c.faction_id == target_faction:
			player_cities.append(c)
			city_cells.append(c.cell)
		else:
			blocked_foreign_cells.append(c.cell)
	var gathered: Dictionary = {}
	var powered: Dictionary = {}
	var fatigue_surplus: Dictionary = {}
	var component_by_city: Dictionary = {}
	var component_surpluses: Array = []
	var groups: Array = grid.connected_city_groups(city_cells, blocked_foreign_cells)
	for component_idx in groups.size():
		var component_surplus := 0
		for city_idx in groups[component_idx]:
			var city: City = player_cities[int(city_idx)]
			var city_gather: Dictionary = city.gather_total()
			gathered[city] = city_gather
			component_by_city[city] = component_idx
			if city.is_offline() or city.is_dos():
				continue
			component_surplus += int(city_gather.energy) + city.energy_production()
			component_surplus -= _city_building_energy_upkeep(city)
		component_surpluses.append(component_surplus)

	# Unit upkeep is assigned once to the capital component before power is resolved.
	var unit_upkeep: int = _faction_unit_energy_upkeep(target_faction)
	var anchor: City = _energy_upkeep_anchor(player_cities)
	if anchor != null:
		var anchor_component: int = int(component_by_city[anchor])
		component_surpluses[anchor_component] = int(component_surpluses[anchor_component]) - unit_upkeep
	var total_positive_surplus := 0
	for component_idx in groups.size():
		var adjusted_surplus: int = int(component_surpluses[component_idx])
		total_positive_surplus += maxi(adjusted_surplus, 0)
		for city_idx in groups[component_idx]:
			var city: City = player_cities[int(city_idx)]
			powered[city] = adjusted_surplus > 0
			fatigue_surplus[city] = adjusted_surplus
	return {
		"cities": player_cities,
		"gathered": gathered,
		"powered": powered,
		"fatigue_surplus": fatigue_surplus,
		"component_surpluses": component_surpluses,
		"unit_upkeep": unit_upkeep,
		"available_energy": total_positive_surplus,
	}


## Every city works its center plus one surrounding cell per population.
## Stable coordinate priority resolves malformed legacy overlaps independently
## of the serialized city array order.
func recompute_city_worked_tiles() -> void:
	if grid == null:
		return
	var ordered: Array = cities.duplicate()
	ordered.sort_custom(func(a: City, b: City): return _city_claim_before(a, b))
	var claimed: Dictionary = {}
	for city: City in ordered:
		city.worked_cells.clear()
		if grid.in_bounds(city.cell.x, city.cell.y) and not claimed.has(city.cell):
			city.worked_cells.append(city.cell)
			claimed[city.cell] = city
	for city: City in ordered:
		var candidates := _city_work_candidates(city, city.focus, claimed)
		for candidate in candidates:
			if city.worked_cells.size() >= mini(city.population, 8) + 1:
				break
			if claimed.has(candidate):
				continue
			city.worked_cells.append(candidate)
			claimed[candidate] = city


func _city_work_candidates(city: City, focus_id: String, claimed: Dictionary = {}) -> Array:
	var candidates: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var candidate := city.cell + Vector2i(dx, dy)
			if candidate == city.cell or not grid.in_bounds(candidate.x, candidate.y) \
					or claimed.has(candidate):
				continue
			candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i):
		var a_score := _city_tile_score(city, a, focus_id)
		var b_score := _city_tile_score(city, b, focus_id)
		return a_score > b_score or (a_score == b_score and _cell_before(a, b)))
	return candidates


func _city_tile_score(city: City, target: Vector2i, focus_id: String) -> int:
	var tile: Dictionary = city.gather_tile(target.x, target.y)
	var total := int(tile.food) + int(tile.scrap) + int(tile.energy) + int(tile.sol)
	var primary := 0
	match focus_id:
		"biomass": primary = int(tile.food)
		"scrap": primary = int(tile.scrap)
		"energy": primary = int(tile.energy)
		"sol": primary = int(tile.sol)
	return primary * 100 + total


func _city_claim_before(a: City, b: City) -> bool:
	if a.cell != b.cell:
		return _cell_before(a.cell, b.cell)
	if a.faction_id != b.faction_id:
		return a.faction_id < b.faction_id
	return a.name < b.name


func set_city_focus(city: City, focus_id: String) -> bool:
	if city == null or not cities.has(city) or city.faction_id != faction_id \
			or focus_id not in CITY_FOCUSES or city.focus == focus_id:
		return false
	var before := city.gather_total()
	var previous := city.focus
	city.focus = focus_id
	recompute_city_worked_tiles()
	if city.gather_total() == before:
		city.focus = previous
		recompute_city_worked_tiles()
		return false
	emit_signal("city_changed", city)
	return true


func next_effective_city_focus(city: City) -> Dictionary:
	if city == null:
		return {}
	recompute_city_worked_tiles()
	var before: Dictionary = city.gather_total()
	var original := city.focus
	var start := CITY_FOCUSES.find(original)
	for step in range(1, CITY_FOCUSES.size() + 1):
		var candidate: String = CITY_FOCUSES[(start + step) % CITY_FOCUSES.size()]
		city.focus = candidate
		recompute_city_worked_tiles()
		var after: Dictionary = city.gather_total()
		if after != before:
			city.focus = original
			recompute_city_worked_tiles()
			return {"focus": candidate, "before": before, "after": after}
	city.focus = original
	recompute_city_worked_tiles()
	return {}


func network_status_snapshot() -> Dictionary:
	var state: Dictionary = _player_energy_grid_state()
	var validators: Array = []
	var powered_validators := 0
	var base_validator_output := 0
	for city in state.cities:
		for building_id in city.buildings:
			if building_id not in ["genesis_node", "relic_validator", "server_altar"]:
				continue
			var component_powered: bool = bool(state.powered.get(city, false))
			var reason := "Operational"
			if event_active == "outage":
				reason = "Fictional network outage event"
			elif city.is_offline():
				reason = "City fatigue offline"
			elif city.is_dos():
				reason = "Fictional DoS status"
			elif not component_powered:
				reason = "Energy component has no positive surplus"
			var operational: bool = reason == "Operational"
			var output: int = int(city.building_data(building_id).sol_gen) if operational else 0
			if operational:
				powered_validators += 1
				base_validator_output += output
			validators.append({
				"city": city.name,
				"building": building_id,
				"powered": operational,
				"component_powered": component_powered,
				"base_output": output,
				"reason": reason,
			})
	return {
		"simplified_analogy": true,
		"powered_validators": powered_validators,
		"total_validators": validators.size(),
		"component_count": state.component_surpluses.size(),
		"component_surpluses": state.component_surpluses.duplicate(),
		"available_energy": int(state.available_energy),
		"unit_upkeep": int(state.unit_upkeep),
		"base_validator_output": base_validator_output,
		"validators": validators,
	}


func _city_building_energy_upkeep(city: City) -> int:
	var upkeep: int = city.energy_upkeep_total()
	if wonders.has("quantum_cooler"):
		for building_id in city.buildings:
			if building_id in ["genesis_node", "relic_validator", "server_altar"]:
				upkeep -= int(Faction.building_data(building_id).energy_upkeep)
	if council_law == "energy_tax" and city.has_building("genesis_node"):
		upkeep += 2
	return maxi(upkeep, 0)


func _player_unit_energy_upkeep() -> int:
	return _faction_unit_energy_upkeep(faction_id)


func _faction_unit_energy_upkeep(target_faction: int) -> int:
	var upkeep := 0
	var faction_bonuses: Dictionary = factions[target_faction].bonuses()
	var faction_protocol := protocol if target_faction == faction_id else "p2p"
	var active_protocol: Dictionary = Data.PROTOCOLS[faction_protocol]
	for u in units:
		if u.faction_id != target_faction:
			continue
		upkeep += _unit_energy_upkeep(u, faction_bonuses, active_protocol)
		for passenger in u.cargo:
			upkeep += _unit_energy_upkeep(passenger, faction_bonuses, active_protocol)
	return upkeep


func _unit_energy_upkeep(unit: Unit, faction_bonuses: Dictionary, active_protocol: Dictionary) -> int:
	if faction_bonuses.has("broker_free") and unit.type_id == "net_broker":
		return 0
	if active_protocol.get("upkeep_free", false):
		return 0
	var upkeep: int = unit.energy_upkeep()
	if active_protocol.has("army_energy_mult"):
		upkeep = int(round(upkeep * float(active_protocol.army_energy_mult)))
	return upkeep


func _energy_upkeep_anchor(player_cities: Array) -> City:
	var anchor: City = null
	for city in player_cities:
		if city.is_capital and (anchor == null or _cell_before(city.cell, anchor.cell)):
			anchor = city
	if anchor != null:
		return anchor
	for city in player_cities:
		if anchor == null or _cell_before(city.cell, anchor.cell):
			anchor = city
	return anchor


func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


func end_turn() -> void:
	_advance_strategic_state()
	# 1) Resolve faction-local energy components before city operation.
	var total_sol := 0
	var total_scrap := 0
	var total_food := 0
	var energy_state: Dictionary = _player_energy_grid_state()
	var total_energy: int = int(energy_state.available_energy)
	var powered: Dictionary = energy_state.powered
	var gathered: Dictionary = energy_state.gathered
	var population_changed := false
	for c in energy_state.cities:
		if c.is_offline() or c.is_dos():
			continue
		if not bool(powered.get(c, false)):
			continue
		var g: Dictionary = gathered[c]
		var usable_food: int = c.usable_food(int(g.food), has_passive("swamp_immune"))
		total_scrap += g.scrap
		total_food += usable_food
		var built: String = c.process_build(resources)
		if built != "":
			_sfx("build")
			game_log("Built: %s in %s" % [Faction.building_data(built).name, c.name])
			emit_signal("city_build_completed", c, built)
			if built == "global_server":
				global_server = true
				game_log("Global Server online — diplomatic victory unlocked!")
			emit_signal("city_changed", c)
		if c.process_growth(usable_food):
			population_changed = true
			game_log("Population of %s grew to %d" % [c.name, c.population])
			emit_signal("city_changed", c)
	if population_changed:
		recompute_city_worked_tiles()

	# 2) Energy accounting is component-local; unit upkeep belongs to the anchor component.
	# Building upkeep was charged inside each component. Unit upkeep was charged once.

	# 3) $SOL: validators + exchanges — ONLY with surplus Energy (uptime)
	for c in energy_state.cities:
		if c.is_offline() or c.is_dos() or not bool(powered.get(c, false)):
			continue
		var c_sol: int = int(gathered[c].sol) + c.sol_production() + c.sol_from_population()
		# Meme Coin Surge: city +300% $SOL generation
		if event_active == "meme" and cities.find(c) == meme_city_idx:
			c_sol *= 4
		total_sol += c_sol
	# Network Outage: all validators lose sync for 1 turn
	if event_active == "outage":
		total_sol = 0

	# 3b) Offline cities: validators silent, no production
	var prot: Dictionary = Data.PROTOCOLS[protocol]
	var at_war := _faction_at_war()
	var offline_cities: Array = []
	for c in cities:
		if c.faction_id != faction_id:
			continue
		c.tick_offline()
		var city_surplus: int = int(energy_state.fatigue_surplus.get(c, 0))
		if c.process_fatigue(city_surplus, at_war, bool(prot.get("ignore_fatigue", false))):
			offline_cities.append(c)
	for c in offline_cities:
		game_log("%s went offline — rogue automaton spawned!" % c.name)
		var bp := grid.find_free_tile_near(c.cell.x, c.cell.y, 3)
		if bp.x >= 0:
			_spawn_unit("auto_mech", bp, BARB_FACTION)

	# 3c) Protocol effects on income
	if prot.has("sol_mult"):
		total_sol = int(round(total_sol * float(prot.sol_mult)))
	if prot.has("scrap_mult"):
		total_scrap = int(round(total_scrap * float(prot.scrap_mult)))

	# 4) Faction bonuses (new BONUSES keys)
	var fb: Dictionary = factions[faction_id].bonuses()
	if fb.has("validator_boost") and powered.values().has(true):
		total_sol = int(round(total_sol * float(fb.validator_boost)))

	# 4a) Tech passive: Terraforming -> Wasteland +1 food
	if has_passive("terraform"):
		for c in energy_state.cities:
			if bool(powered.get(c, false)) and not c.is_offline() and not c.is_dos():
				total_food += c.count_terrain_near("wasteland")

	# 4b) Tech passives: Steam Synthesis -> +1 Scrap on Ruins
	if has_passive("ruins_scrap_plus1"):
		for c in energy_state.cities:
			if bool(powered.get(c, false)) and not c.is_offline() and not c.is_dos():
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var gx: int = c.cell.x + dx
						var gy: int = c.cell.y + dy
						if grid.in_bounds(gx, gy) and grid.terrain_at(gx, gy) == "ruins":
							total_scrap += 1

	# 4c) Tech passive: Atomic Reactor -> +10 Energy/turn
	if has_passive("energy_plus10"):
		total_energy += 10
	# Firedancer: independent client -> +50% Energy
	if has_passive("firedancer"):
		total_energy = int(round(total_energy * 1.5))

	# 4d) Tech passive: Smart Contracts -> 10 surplus Energy = 1 $SOL
	if has_passive("energy_to_sol") and total_energy > 0:
		var converted := total_energy / 10
		if converted > 0:
			total_sol += converted
			total_energy -= converted * 10

	# 4e) Tech passive: Global Consensus -> $SOL output up
	if has_passive("sol_output_boost"):
		total_sol = int(round(total_sol * 1.5))
	# Artifacts: Dragon Suit (+20% build speed -> +20% scrap), Genesis Chapter (+10% $SOL)
	if artifacts.has("dragon_suit"):
		total_scrap = int(round(total_scrap * 1.2))
	if artifacts.has("genesis_chapter"):
		total_sol = int(round(total_sol * 1.1))

	resources.scrap += total_scrap
	resources.biomass += total_food
	resources.energy += total_energy
	resources.sol += total_sol
	record_network_sol(faction_id, total_sol)
	if total_sol > 0:
		_sfx("sol")

	# 5) Player research (protocol modifiers)
	if tech.current != "":
		var had_satellite_intel := has_passive("reveal_validators")
		var tech_points := 0
		for c in cities:
			if c.faction_id == faction_id:
				tech_points += tech.city_tech_points(c)
		var prot3: Dictionary = Data.PROTOCOLS[protocol]
		if prot3.get("free_research", false):
			tech_points *= 2
		if prot3.has("research_mult"):
			tech_points = int(round(tech_points * float(prot3.research_mult)))
		var done: Dictionary = tech.add_points(tech_points)
		if not done.is_empty():
			game_log("Research complete: %s" % done.tech)
			if not had_satellite_intel and has_passive("reveal_validators"):
				_activate_satellite_intel()

	# 6) Reset player unit moves (+Cyber Implants bonus, -EMP aura); fortify
	var move_bonus := infantry_move_bonus()
	for u in units:
		if u.faction_id == faction_id:
			u.update_fortify()
			reset_unit_moves_with_emp(u)
			if move_bonus > 0 and u.data().get("infantry", false):
				u.moves_left += move_bonus

	turn += 1
	emit_signal("resources_changed")
	emit_signal("turn_changed", turn)
	game_log("Turn %d: +%d Scrap, +%d Biomass, +%d Energy, +%d $SOL" % [
		turn, total_scrap, total_food, total_energy, total_sol,
	])

	# 7) AI factions take their turn
	for f_idx in range(1, factions.size()):
		if ai != null:
			ai.take_turn(f_idx, self)
			# A prior rival may have captured the player's last eye. Refresh before
			# the next rival can emit production/combat feedback from that stale area.
			update_visibility()

	# 7b) Barbarians spawn and act every 10 turns
	if turn % 10 == 0:
		spawn_barbarians()
	barbarian_turn()
	# AI movement and captures can remove or add player sight after turn_changed.
	# Recompute before any final map refresh so stale ownership never leaks vision.
	update_visibility()
	UnitsView.sync()

	# 7c) Consensus Council every 15 turns
	consensus_council()
	alliance_energy_transfer()

	# 7d) Wonders: Genesis Block shield tickdown, Satellite Emitter sync timer
	if shield_turns > 0:
		shield_turns -= 1
	if wonders.has("satellite_emitter"):
		sync_turns += 1
		if sync_turns >= 20:
			emit_signal("game_over", factions[faction_id].name, "Global Sync — planet unified")
			return

	# 7e) Random events (Solana lore) — tick + trigger
	_tick_events()
	trade_used = 0
	if law_turns_left > 0:
		law_turns_left -= 1
		if law_turns_left <= 0:
			council_law = ""
			locked_faction = -1

	# 8) Victory check
	if not check_victory():
		update_victories()


## Victory: last faction with cities (Consensus = validator control).
func check_victory() -> bool:
	if factions.is_empty():
		return false
	var alive: Dictionary = {}
	for c in cities:
		alive[c.faction_id] = true
	if alive.size() <= 1:
		var winner_idx: int = alive.keys()[0] if not alive.is_empty() else -1
		var winner_name: String = factions[winner_idx].name if winner_idx >= 0 else "Nobody"
		var reason := "all validators controlled"
		if winner_idx != faction_id:
			reason = "your nodes were lost"
		emit_signal("game_over", winner_name, reason)
		return true
	return false


## ---------- Actions ----------

## One ordered answer for the turn UI. Entries only exist when the player can
## resolve them now, so the guide never opens a dead end.
func next_required_action() -> Dictionary:
	for unit in units:
		if unit_requires_orders(unit):
			return {"kind": "unit", "target": unit}
	if tech != null and tech.current == "":
		for tech_id in tech.researchable():
			if tech.can_research(tech_id, resources):
				return {"kind": "research"}
	for city in cities:
		if city.faction_id == faction_id and city.build_queue.is_empty() \
				and city_has_legal_production(city):
			return {"kind": "production", "target": city}
	return {"kind": "end_turn"}


func unit_requires_orders(unit: Unit) -> bool:
	return unit != null and units.has(unit) and unit.faction_id == faction_id \
		and unit.moves_left > 0.001 and not unit.fortified and not unit.orders_skipped


func complete_unit_orders(unit: Unit) -> bool:
	if not unit_requires_orders(unit):
		return false
	unit.orders_skipped = true
	unit.moves_left = 0.0
	# Attack-capable land units use the existing stationary fortification rule;
	# founders, brokers, and transports simply wait for the turn.
	if unit.attack() > 0 and not unit.is_naval() and not unit.has_moved_this_turn:
		unit.update_fortify()
	emit_signal("unit_orders_changed", unit)
	emit_signal("selection_changed", unit)
	return true


func unit_order_label(unit: Unit) -> String:
	return "FORTIFY" if unit != null and unit.attack() > 0 and not unit.is_naval() \
		and not unit.has_moved_this_turn else "WAIT"


func city_has_legal_production(city: City) -> bool:
	for building_id in Data.BUILDINGS:
		if building_id not in ["nuclear_plant", "fusion_plant"] \
				and city.can_queue_build(str(building_id), tech):
			return true
	if can_upgrade_city_building(city):
		return true
	for unit_id in Data.UNITS:
		if unit_id not in ["virus_pickup", "auto_mech"] and can_train_unit(city, str(unit_id)):
			return true
	var unique_units: Dictionary = Faction.UNIQUE_UNITS.get(factions[faction_id].id, {})
	for unit_id in unique_units:
		if can_train_unit(city, str(unit_id)):
			return true
	return false


func can_upgrade_city_building(city: City) -> bool:
	if city == null or city.faction_id != faction_id:
		return false
	for building_id in City.BUILDING_UPGRADES:
		if city.has_building(str(building_id)):
			var upgrade: Dictionary = City.BUILDING_UPGRADES[building_id]
			if tech.is_researched(str(upgrade.tech)) \
					and int(resources.sol) >= int(upgrade.sol_cost):
				return true
	return false


func can_train_unit(city: City, type_id: String) -> bool:
	if city == null or city.faction_id != faction_id:
		return false
	var actual_type: String = city.faction.unit_for(type_id) if city.faction != null else type_id
	var unit_data: Dictionary = Faction.unit_data(actual_type)
	var required_tech := str(unit_data.get("requires_tech", ""))
	if required_tech != "" and not tech.is_researched(required_tech):
		return false
	if resources.scrap < int(unit_data.scrap_cost) or resources.sol < int(unit_data.sol_cost):
		return false
	if bool(unit_data.get("naval", false)):
		return grid.find_free_ocean_neighbor(city.cell).x >= 0
	return grid.find_free_tile_near(city.cell.x, city.cell.y, 3).x >= 0

## Founder builds a city on its tile (if empty, not a city).
func can_found_city(unit: Unit) -> bool:
	return unit != null and units.has(unit) and unit.faction_id == faction_id \
		and unit.type_id == "founder" and grid != null \
		and can_found_site(unit.cell, unit.faction_id, unit) \
		and resources.scrap >= Data.SCRAP_PER_CITY


func can_found_site(pos: Vector2i, founding_faction: int, founder: Unit = null) -> bool:
	if founding_faction < 0 or founding_faction >= factions.size() or grid == null \
			or not grid.in_bounds(pos.x, pos.y) or grid.is_water(pos.x, pos.y) \
			or bool(grid.terrain_data(pos.x, pos.y).get("impassable", false)) \
			or city_at(pos) != null:
		return false
	var occupant: Variant = grid.occupant_at(pos.x, pos.y)
	if occupant != null and occupant != founder:
		return false
	for city in cities:
		if absi(city.cell.x - pos.x) + absi(city.cell.y - pos.y) < CITY_MIN_DISTANCE:
			return false
	return true


func founding_site_preview(pos: Vector2i, founding_faction: int, founder: Unit = null) -> Dictionary:
	var legal := can_found_site(pos, founding_faction, founder)
	if not legal:
		return {"legal": false, "reason": founding_site_reason(pos, founding_faction, founder)}
	var previous_worked: Dictionary = {}
	for existing_city in cities:
		previous_worked[existing_city] = existing_city.worked_cells.duplicate()
	var preview_city := City.new("Preview", founding_faction, factions[founding_faction], pos, grid)
	cities.append(preview_city)
	recompute_city_worked_tiles()
	var yields := preview_city.gather_total()
	var worked := preview_city.worked_cells.duplicate()
	cities.erase(preview_city)
	for existing_city in cities:
		existing_city.worked_cells.assign(previous_worked[existing_city])
	return {"legal": true, "yields": yields, "worked": worked,
		"score": int(yields.food) * 3 + int(yields.scrap) * 2 \
			+ int(yields.energy) + int(yields.sol) * 2}


func founding_site_reason(pos: Vector2i, founding_faction: int, founder: Unit = null) -> String:
	if grid == null or not grid.in_bounds(pos.x, pos.y) or grid.is_water(pos.x, pos.y) \
			or bool(grid.terrain_data(pos.x, pos.y).get("impassable", false)):
		return "INVALID TERRAIN"
	var occupant: Variant = grid.occupant_at(pos.x, pos.y)
	if city_at(pos) != null or (occupant != null and occupant != founder):
		return "SITE OCCUPIED"
	for city in cities:
		if absi(city.cell.x - pos.x) + absi(city.cell.y - pos.y) < CITY_MIN_DISTANCE:
			return "CITY TOO CLOSE"
	return "UNAVAILABLE"


func found_city(unit: Unit) -> bool:
	if unit == null or unit.type_id != "founder" or unit.faction_id != faction_id:
		return false
	if not can_found_site(unit.cell, unit.faction_id, unit):
		game_log("City needs open land at least %d tiles from another city" % CITY_MIN_DISTANCE)
		return false
	# Founding costs Scrap
	if resources.scrap < Data.SCRAP_PER_CITY:
		game_log("Not enough Scrap for a city (%d)" % Data.SCRAP_PER_CITY)
		return false
	resources.scrap -= Data.SCRAP_PER_CITY
	var c := _found_city_at(unit.cell)
	if c == null:
		return false
	# Founder is consumed (like Civ settlers)
	_remove_unit(unit)
	emit_signal("resources_changed")
	game_log("City %s founded" % c.name)
	return true


func _found_city_at(pos: Vector2i, faction: int = 0) -> City:
	if not grid.in_bounds(pos.x, pos.y):
		return null
	var c := City.new("Bunker-%d" % city_name_counter, faction, factions[faction], pos, grid)
	city_name_counter += 1
	cities.append(c)
	var first := true
	for cc in cities:
		if cc.faction_id == faction and cc.is_capital:
			first = false
			break
	c.is_capital = first
	# City occupies its tile (blocks movement)
	grid.place_occupant(pos.x, pos.y, c)
	c.buildings["genesis_node"] = true
	recompute_city_worked_tiles()
	_refresh_satellite_intel()
	return c


func _remove_unit(unit: Unit) -> void:
	grid.clear_occupant(unit.cell.x, unit.cell.y, unit)
	units.erase(unit)
	unit.cargo.clear()
	if selected_unit == unit:
		selected_unit = null
		emit_signal("selection_changed", null)


## Train a unit in a city (instant, from resources). Supports
## faction unique units and discounts.
func train_unit(city: City, type_id: String) -> bool:
	# UU replacement: faction builds its unique unit instead of the standard one
	var actual_type: String = type_id
	if city.faction != null:
		actual_type = city.faction.unit_for(type_id)
	var ud: Dictionary = Faction.unit_data(actual_type)
	var required_tech: String = str(ud.get("requires_tech", ""))
	if required_tech != "" and not tech.is_researched(required_tech):
		game_log("%s requires %s" % [ud.name, Data.TECHS[required_tech].name])
		return false
	var pos: Vector2i
	if bool(ud.get("naval", false)):
		pos = grid.find_free_ocean_neighbor(city.cell)
		if pos.x < 0:
			game_log("%s requires a coastal city with free adjacent ocean" % ud.name)
			return false
	else:
		pos = grid.find_free_tile_near(city.cell.x, city.cell.y, 3)
		if pos.x < 0:
			game_log("No space around %s" % city.name)
			return false
	if resources.scrap < int(ud.scrap_cost) or resources.sol < int(ud.sol_cost):
		game_log("Not enough resources for %s" % ud.name)
		return false
	resources.scrap -= int(ud.scrap_cost)
	resources.sol -= int(ud.sol_cost)
	var u := _spawn_unit(actual_type, pos, city.faction_id)
	if city.has_building("assembly_forge"):
		u.veteran = true
	emit_signal("resources_changed")
	game_log("Trained: %s" % ud.name)
	return true


func load_unit(passenger: Unit, carrier: Unit) -> bool:
	if not units.has(passenger) or not units.has(carrier) or passenger == carrier:
		return false
	if passenger.faction_id != faction_id or carrier.faction_id != faction_id \
			or passenger.faction_id != carrier.faction_id \
			or passenger.is_naval() or not passenger.cargo.is_empty():
		return false
	if not carrier.is_naval() or carrier.transport_capacity() <= carrier.cargo.size():
		return false
	if _orthogonal_distance(passenger.cell, carrier.cell) != 1:
		return false
	grid.clear_occupant(passenger.cell.x, passenger.cell.y, passenger)
	units.erase(passenger)
	passenger.cell = carrier.cell
	carrier.cargo.append(passenger)
	select(carrier)
	game_log("Loaded %s onto %s (%d/%d)" % [
		passenger.data().name, carrier.data().name, carrier.cargo.size(), carrier.transport_capacity(),
	])
	return true


func unload_unit(carrier: Unit, target: Vector2i) -> bool:
	if not units.has(carrier) or carrier.faction_id != faction_id \
			or not carrier.is_naval() or carrier.cargo.is_empty():
		return false
	if _orthogonal_distance(carrier.cell, target) != 1 or not grid.is_passable(target.x, target.y):
		return false
	var passenger: Unit = carrier.cargo.pop_front()
	passenger.cell = target
	passenger.moves_left = 0
	units.append(passenger)
	grid.place_occupant(target.x, target.y, passenger)
	select(carrier)
	game_log("Unloaded %s from %s (%d/%d)" % [
		passenger.data().name, carrier.data().name, carrier.cargo.size(), carrier.transport_capacity(),
	])
	return true


func _orthogonal_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Unit data: standard or faction-unique.
func _unit_data(type_id: String) -> Dictionary:
	return Faction.unit_data(type_id)


## ---------- Selection ----------

func select(obj) -> void:
	selected_unit = obj if obj is Unit else null
	selected_city = obj if obj is City else null
	emit_signal("selection_changed", obj)


func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2.0, cell.y * TILE_SIZE + TILE_SIZE / 2.0)


func pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))
