extends RefCounted
class_name Data
## Data.gd — Solanazation game data (data-driven).

const MAP_W := 80
const MAP_H := 50

## Map sizes
enum MapSize { SMALL, MEDIUM, LARGE }
const MAP_DIMENSIONS := {
	MapSize.SMALL:  Vector2i(60, 40),
	MapSize.MEDIUM: Vector2i(80, 50),
	MapSize.LARGE:  Vector2i(120, 70),
}

## Map types (generators). RANDOM = random pick at start.
enum MapType { RANDOM, CONTINENTS, PANGAEA, ARCHIPELAGO, INLAND_SEA, ISLANDS, EARTH }
const MAP_TYPE_NAMES := {
	MapType.RANDOM: "Random",
	MapType.CONTINENTS: "Continents",
	MapType.PANGAEA: "Pangaea",
	MapType.ARCHIPELAGO: "Archipelago",
	MapType.INLAND_SEA: "Inland Sea",
	MapType.ISLANDS: "Islands",
	MapType.EARTH: "Earth",
}

## Terrain: {id: {name, food, scrap, energy, sol, color, desc, penalty, water}}
const TERRAIN := {
	"ocean":     { "name": "Ocean",          "food": 0, "scrap": 0, "energy": 0, "sol": 0, "color": Color("1a3a5a"), "desc": "Open water", "water": true },
	"wasteland": { "name": "Wasteland",       "food": 1, "scrap": 1, "energy": 0, "sol": 0, "color": Color("8a7f52"), "desc": "Radioactive wasteland", "def_mod": 1.0 },
	"ruins":     { "name": "Server Ruins",    "food": 0, "scrap": 3, "energy": 0, "sol": 1, "color": Color("6b4a3a"), "desc": "Rusty racks in sand", "def_mod": 1.5 },
	"swamp":     { "name": "Toxic Swamp",     "food": 2, "scrap": 0, "energy": 0, "sol": 0, "color": Color("4a6b3a"), "desc": "+1 radiation (growth penalty)", "penalty": 1, "def_mod": 0.75 },
	"node_zone": { "name": "Node Zone",       "food": 0, "scrap": 0, "energy": 20, "sol": 5, "color": Color("2a3a5a"), "desc": "Turbine / Validator only" },
	"mountains": { "name": "Mountains",       "food": 0, "scrap": 1, "energy": 0, "sol": 0, "color": Color("5a5a6a"), "desc": "Impassable. +100% defense", "def_mod": 2.0, "impassable": true },
	"crater":     { "name": "Server Crater",   "food": 0, "scrap": 0, "energy": 0, "sol": 15, "color": Color("4a2a6a"), "desc": "Relic site. +15 $SOL. Validator only" },
	"dump":       { "name": "Living Dump",     "food": 0, "scrap": 10, "energy": 0, "sol": 0, "color": Color("6a6a2a"), "desc": "Relic site. +10 Scrap" },
	"rift":       { "name": "Geothermal Rift", "food": 0, "scrap": 0, "energy": 50, "sol": 0, "color": Color("8a3a2a"), "desc": "Relic site. +50 Energy" },
}

## Units: {id: {name, moves, atk, def, scrap_cost, sol_cost, energy_upkeep, color, desc, infantry}}
const UNITS := {
	"founder":     { "name": "Node Founder",    "moves": 1, "atk": 0, "def": 1, "scrap_cost": 20, "sol_cost": 0,  "energy_upkeep": 1, "color": Color("e2c98f"), "desc": "Founds a bunker-validator city", "infantry": true },
	"rust_guard":  { "name": "Rust Guard",      "moves": 2, "atk": 1, "def": 1, "scrap_cost": 10, "sol_cost": 0,  "energy_upkeep": 0, "color": Color("a86b4a"), "desc": "Militia with pipe guns", "infantry": true },
	"miner_quad":  { "name": "Miner Quad",      "moves": 4, "atk": 2, "def": 1, "scrap_cost": 15, "sol_cost": 5,  "energy_upkeep": 1, "color": Color("8fbf5a"), "desc": "Fast scout, light flamethrower", "infantry": false },
	"raider_walker": { "name": "Raider Walker", "moves": 3, "atk": 3, "def": 2, "scrap_cost": 25, "sol_cost": 10, "energy_upkeep": 2, "color": Color("b0703a"), "desc": "Main assault walker", "infantry": false },
	"heavy_mech":  { "name": "Heavy Mech",      "moves": 3, "atk": 5, "def": 4, "scrap_cost": 40, "sol_cost": 30, "energy_upkeep": 5, "color": Color("5a8fbf"), "desc": "Cybernetic giant, plasma cannon", "infantry": false },
	"net_broker":  { "name": "Net Broker",      "moves": 2, "atk": 0, "def": 1, "scrap_cost": 0,  "sol_cost": 25, "energy_upkeep": 1, "color": Color("bf5abf"), "desc": "Hack, bribe, sabotage", "infantry": false },
	"steam_cruiser": { "name": "Steam Cruiser", "moves": 4, "atk": 2, "def": 3, "scrap_cost": 35, "sol_cost": 10, "energy_upkeep": 2, "color": Color("4f7f91"), "desc": "Coastal transport for two land units", "infantry": false, "naval": true, "transport_capacity": 2, "requires_tech": "steam_synthesis" },
	# Rogue Botnets (barbarians)
	"virus_pickup":{ "name": "Virus Pickup",    "moves": 3, "atk": 1, "def": 1, "scrap_cost": 0,  "sol_cost": 0,  "energy_upkeep": 0, "color": Color("8a2a2a"), "desc": "Rogue raider. Hunts founders", "infantry": false },
	"auto_mech":   { "name": "Auto-Mech",       "moves": 2, "atk": 3, "def": 2, "scrap_cost": 0,  "sol_cost": 0,  "energy_upkeep": 0, "color": Color("6a1a1a"), "desc": "Rogue heavy. Attacks cities", "infantry": false },
}

## Buildings: {id: {name, scrap_cost, sol_cost, energy_upkeep, sol_gen, energy_gen, food_gen, scrap_gen, unique, desc}}
const BUILDINGS := {
	"genesis_node":    { "name": "Genesis Node",     "scrap_cost": 0,  "sol_cost": 0,  "energy_upkeep": 0, "sol_gen": 5,  "energy_gen": 3, "food_gen": 0, "scrap_gen": 0, "unique": true,  "desc": "Bootstrap microgrid. +3 Energy, +5 $SOL/turn" },
	"steam_turbine":   { "name": "Steam Turbine",    "scrap_cost": 30, "sol_cost": 0,  "energy_upkeep": 0, "sol_gen": 0,  "energy_gen": 20, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "Biomass → +20 Energy" },
	"relic_validator": { "name": "Relic Validator",  "scrap_cost": 60, "sol_cost": 10, "energy_upkeep": 5, "sol_gen": 10, "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "Ruins only. +10 $SOL/turn" },
	"assembly_forge":  { "name": "Assembly Forge",   "scrap_cost": 25, "sol_cost": 0,  "energy_upkeep": 1, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "New units are veterans" },
	"net_shrine":      { "name": "Net Shrine",       "scrap_cost": 20, "sol_cost": 0,  "energy_upkeep": 1, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "Reduces Network Fatigue" },
	"sol_exchange":    { "name": "SOL Exchange",     "scrap_cost": 40, "sol_cost": 15, "energy_upkeep": 2, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "+$SOL from population" },
	"archio_archive":  { "name": "Archio-Archive",   "scrap_cost": 35, "sol_cost": 5,  "energy_upkeep": 1, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "+50% tech points" },
	"biomass_purifier":{ "name": "Biomass Purifier", "scrap_cost": 30, "sol_cost": 0,  "energy_upkeep": 1, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "Removes radiation penalties" },
	"nuclear_plant":   { "name": "Nuclear Plant",    "scrap_cost": 80, "sol_cost": 20, "energy_upkeep": 0, "sol_gen": 0,  "energy_gen": 100, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "+100 Energy" },
	"auto_factory":    { "name": "Auto-Factory",     "scrap_cost": 90, "sol_cost": 40, "energy_upkeep": 5, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 5, "unique": false, "desc": "+5 Scrap/turn. Smart Contracts era" },
	"cyber_forge":     { "name": "Cyber Forge",      "scrap_cost": 70, "sol_cost": 30, "energy_upkeep": 3, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "Builds cyborg units cheaper" },
	"fusion_plant":    { "name": "Fusion Plant",     "scrap_cost": 0,  "sol_cost": 0,  "energy_upkeep": 0, "sol_gen": 0,  "energy_gen": 200, "food_gen": 0, "scrap_gen": 0, "unique": false, "desc": "+200 Energy. Era III upgrade" },
	"global_server":   { "name": "Global Server",    "scrap_cost": 200, "sol_cost": 100, "energy_upkeep": 10, "sol_gen": 0,  "energy_gen": 0, "food_gen": 0, "scrap_gen": 0, "unique": true,  "desc": "Unlocks diplomatic victory (2/3 Council vote)" },
}

## Techs: four pedagogical eras across validator, program, and transaction branches.
## {id: {era, branch, requires, name, sol_cost, units, buildings, passive, desc}}
## Passives: ruins_scrap_plus1, trade_unlocked, hack_defense, energy_plus10, firedancer,
##            swamp_immune, energy_to_sol, infantry_plus1move, reveal_validators,
##            sol_output_boost, terraform
const TECHS := {
	# --- Era I: Foundation ---
	"steam_synthesis":   { "era": 1, "branch": "validator", "requires": [], "name": "Proof of History & Slots", "sol_cost": 10, "units": ["steam_cruiser"], "buildings": ["steam_turbine"], "passive": "ruins_scrap_plus1", "desc": "Verifiable ordering; slot leaders may produce blocks" },
	"primitive_coding":  { "era": 1, "branch": "program", "requires": [], "name": "Accounts & Ownership", "sol_cost": 10, "units": ["net_broker"], "buildings": [], "passive": "trade_unlocked", "desc": "State lives in addressed, program-owned accounts" },
	"hydroponics":       { "era": 1, "branch": "transaction", "requires": [], "name": "Transactions & Fees", "sol_cost": 10, "units": [], "buildings": ["biomass_purifier"], "passive": "", "desc": "Atomic instructions with signatures, blockhashes, and fees" },
	# --- Era II: Composition ---
	"atomic_reactor":    { "era": 2, "branch": "validator", "requires": ["steam_synthesis"], "name": "Validators & Tower BFT", "sol_cost": 40, "units": [], "buildings": ["nuclear_plant"], "passive": "energy_plus10", "desc": "Stake-weighted votes and increasing fork lockouts" },
	"block_encryption":  { "era": 2, "branch": "program", "requires": ["primitive_coding"], "name": "Programs & PDAs", "sol_cost": 40, "units": [], "buildings": ["relic_validator", "sol_exchange"], "passive": "hack_defense", "desc": "Stateless sBPF programs and deterministic authorities" },
	"radiation_engineering": { "era": 2, "branch": "transaction", "requires": ["hydroponics"], "name": "CPI & SPL Tokens", "sol_cost": 40, "units": [], "buildings": [], "passive": "swamp_immune", "desc": "Program composition and authority-checked token operations" },
	# --- Era III: Scale ---
	"quantum_computing": { "era": 3, "branch": "validator", "requires": ["atomic_reactor"], "name": "Turbine & Stake-weighted QoS", "sol_cost": 120, "units": [], "buildings": [], "passive": "", "desc": "Block propagation and Sybil-resistant ingress allocation" },
	"smart_contracts":   { "era": 3, "branch": "program", "requires": ["block_encryption"], "name": "Parallel Runtime & Compute", "sol_cost": 120, "units": [], "buildings": ["auto_factory"], "passive": "energy_to_sol", "desc": "Independent account access runs in parallel; compute is metered" },
	"cyber_implants":    { "era": 3, "branch": "transaction", "requires": ["radiation_engineering"], "name": "V0 Transactions & ALTs", "sol_cost": 120, "units": ["heavy_mech"], "buildings": ["cyber_forge"], "passive": "infantry_plus1move", "desc": "Compact address references fit more accounts in a message" },
	# --- Era IV: Production ---
	"satellite_uplink":  { "era": 4, "branch": "validator", "requires": ["quantum_computing"], "name": "RPC & Commitment", "sol_cost": 400, "units": [], "buildings": [], "passive": "reveal_validators", "desc": "Read network state with explicit confidence levels" },
	"global_consensus":  { "era": 4, "branch": "program", "requires": ["smart_contracts"], "name": "State Compression", "sol_cost": 400, "units": [], "buildings": ["global_server"], "passive": "sol_output_boost", "desc": "Compact commitments trade storage cost for proof infrastructure" },
	"firedancer":        { "era": 4, "branch": "validator", "requires": ["global_consensus"], "name": "Client Diversity", "sol_cost": 600, "units": [], "buildings": [], "passive": "firedancer", "desc": "Independent implementations reduce correlated software risk" },
	"terraforming":      { "era": 4, "branch": "transaction", "requires": ["cyber_implants"], "name": "Token Extensions & Jito Bundles", "sol_cost": 400, "units": [], "buildings": [], "passive": "terraform", "desc": "Explicit asset policies and tipped atomic transaction groups" },
}

## Factions: {id: {name, archetype, passive, desc}}
## Passives: building_discount (-20% Scrap buildings), validator_boost (+25% SOL validators),
##            broker_free (Net Broker no upkeep), radiation_immune, attack_bonus (+25% outside territory)
const FACTIONS := {
	"rust_tech": { "name": "Rust-Tech Clan", "archetype": "Industrialists", "passive": "building_discount", "desc": "-20% Scrap cost for buildings" },
	"global_net": { "name": "Global-Net Cult", "archetype": "Network zealots", "passive": "validator_boost", "desc": "Validators +25% $SOL with surplus Energy" },
	"dao": { "name": "DAO Syndicate", "archetype": "Capitalists", "passive": "broker_free", "desc": "Net Brokers free; trade +50% $SOL" },
	"bio": { "name": "Bio-Coders", "archetype": "Wasteland adapters", "passive": "radiation_immune", "desc": "Immune to radiation/swamp penalties" },
	"steel": { "name": "Steel Protocol", "archetype": "Militarists", "passive": "attack_bonus", "desc": "+25% attack outside own territory" },
}

## Start config (founder is spawned separately)
const START_RESOURCES := { "scrap": 40, "biomass": 30, "energy": 10, "sol": 0 }
const START_UNITS := ["rust_guard", "rust_guard"]

## Growth / costs
const FOOD_PER_POP := 20
const SCRAP_PER_CITY := 25

## $SOL generation: validators require Energy (uptime)
const ENERGY_PER_SOL := 5

## Monopoly only represents a functioning contested network, not one bootstrap validator.
const MONOPOLY_MIN_NETWORK_SOL := 100

## Network protocols (forms of government): {id: {name, desc, effects}}
## effects: sol_mult, scrap_mult, upkeep_free, army_energy_mult, free_research,
##          ignore_fatigue, research_mult
const PROTOCOLS := {
	"p2p": { "name": "Peer-to-Peer", "desc": "No unit upkeep. $SOL output -50%", "sol_mult": 0.5, "upkeep_free": true },
	"pow": { "name": "Proof-of-Work", "desc": "+50% Scrap. Army costs more Energy", "scrap_mult": 1.5, "army_energy_mult": 2.0 },
	"pos": { "name": "Proof-of-Stake", "desc": "+50% $SOL, free research. Units cost $SOL", "sol_mult": 1.5, "free_research": true },
	"central": { "name": "Central Server", "desc": "Cities ignore Fatigue. Research -30%", "ignore_fatigue": true, "research_mult": 0.7 },
}
const PROTOCOL_NAMES := ["p2p", "pow", "pos", "central"]

## Consensus Council laws: {id: {name, desc, effect, duration}}
## effect: token_burn (all treasuries -20%, research -50%), energy_tax (validators +2 Energy upkeep),
##         address_lock (attacks on one faction banned)
const COUNCIL_LAWS := {
	"token_burn": { "name": "Token Burn", "desc": "All treasuries -20%, research cost -50%", "effect": "token_burn", "duration": 10 },
	"energy_tax": { "name": "Energy Tax", "desc": "Validators cost +2 Energy upkeep", "effect": "energy_tax", "duration": 10 },
	"address_lock": { "name": "Address Lock", "desc": "Attacks on one faction banned for 10 turns", "effect": "address_lock", "duration": 10 },
}

## Great Artifacts (wonders): {id: {name, tech, sol_cost, desc, effect}}
## effect: genesis_shield (50-turn anti-DoS), uplink (20-turn victory timer),
##         quantum_cool (validator upkeep = 0), sync (20-turn victory)
const WONDERS := {
	"genesis_block": { "name": "Genesis Block", "tech": "block_encryption", "sol_cost": 60, "desc": "Cities immune to hacks for 50 turns", "effect": "genesis_shield" },
	"orbital_mainframe": { "name": "Orbital Mainframe", "tech": "satellite_uplink", "sol_cost": 250, "desc": "Space race victory timer (20 turns)", "effect": "uplink" },
	"quantum_cooler": { "name": "Quantum Cooler", "tech": "quantum_computing", "sol_cost": 150, "desc": "Validator Energy upkeep = 0", "effect": "quantum_cool" },
	"satellite_emitter": { "name": "Satellite Emitter", "tech": "satellite_uplink", "sol_cost": 300, "desc": "Global Sync timer (20 turns)", "effect": "sync" },
}
