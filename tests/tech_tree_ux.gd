extends SceneTree
## Mobile-first research selection and educational disclosure acceptance.

const EXPECTED_GRAPH := {
	"steam_synthesis": [],
	"primitive_coding": [],
	"hydroponics": [],
	"atomic_reactor": ["steam_synthesis"],
	"block_encryption": ["primitive_coding"],
	"radiation_engineering": ["hydroponics"],
	"quantum_computing": ["atomic_reactor"],
	"smart_contracts": ["block_encryption"],
	"cyber_implants": ["radiation_engineering"],
	"satellite_uplink": ["quantum_computing"],
	"global_consensus": ["smart_contracts"],
	"firedancer": ["global_consensus"],
	"terraforming": ["cyber_implants"],
}

var failures := 0
var game: Node
var opened_urls: Array[String] = []


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	_test_data_contract()
	_test_radiation_mechanic()
	_test_runtime_food_parity()
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _test_size(size)
	print("TECH_TREE_UX_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_data_contract() -> void:
	check(Data.TECHS.size() == 13 and EducationData.TECHS.size() == 13,
		"the stable 13-technology curriculum is unchanged")
	for tech_id in EXPECTED_GRAPH:
		check(Data.TECHS.has(tech_id) and Data.TECHS[tech_id].requires == EXPECTED_GRAPH[tech_id],
			"%s keeps its exact prerequisite edge" % tech_id)
		var education: Dictionary = EducationData.TECHS.get(tech_id, {})
		check(not str(education.get("card_effect", "")).is_empty()
			and "\n" not in str(education.get("card_effect", "")),
			"%s has one concise strategic card effect" % tech_id)
		check(str(education.get("real_solana", "")).split(" ").size() >= 40,
			"%s retains substantive real-Solana learning behind info" % tech_id)
		for source_url in education.get("source_urls", []):
			check(str(source_url).begins_with("https://solana.com/")
				or str(source_url).begins_with("https://docs.anza.xyz/")
				or str(source_url).begins_with("https://developers.metaplex.com/")
				or str(source_url).begins_with("https://github.com/firedancer-io/")
				or str(source_url).begins_with("https://docs.jito.wtf/"),
				"%s source stays on an official primary domain" % tech_id)


func _test_radiation_mechanic() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88079,
		"rust_tech", ["rust_tech", "global_net"])
	var city: City
	for candidate in game.cities:
		if candidate.faction_id == 0:
			city = candidate
			break
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var target := city.cell + Vector2i(dx, dy)
			if game.grid.in_bounds(target.x, target.y):
				game.grid.terrain[target.x][target.y] = "swamp"
	var swamp_count := city.count_terrain_near("swamp")
	check(city.usable_food(20, false) == 20 - swamp_count,
		"nearby swamps subtract Biomass exactly once")
	check(city.usable_food(20, true) == 20,
		"CPI & SPL Tokens removes the complete swamp penalty")
	city.buildings["biomass_purifier"] = true
	check(city.usable_food(20, false) == 20,
		"Biomass Purifier uses the same complete immunity path")
	city.buildings.erase("biomass_purifier")
	city.faction = Faction.new("bio", false)
	check(city.usable_food(20, false) == 20,
		"Bio-Coder identity uses the same complete immunity path")


func _test_runtime_food_parity() -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88078,
		"rust_tech", ["rust_tech", "global_net"])
	game.next_event_turn = 999
	var player_city := _city_of(0)
	var ai_city := _city_of(1)
	_set_swamp_ring(player_city)
	_set_swamp_ring(ai_city)
	var player_state: Dictionary = game._player_energy_grid_state()
	var player_raw: int = int(player_state.gathered[player_city].food)
	var player_expected := player_city.usable_food(player_raw, false)
	game.resources.biomass = 0
	game.end_turn()
	check(int(game.resources.biomass) == player_expected,
		"player economy applies the shared swamp penalty once")

	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88078,
		"rust_tech", ["rust_tech", "global_net"])
	game.next_event_turn = 999
	player_city = _city_of(0)
	_set_swamp_ring(player_city)
	game.tech.researched["radiation_engineering"] = true
	player_state = game._player_energy_grid_state()
	player_raw = int(player_state.gathered[player_city].food)
	game.resources.biomass = 0
	game.end_turn()
	check(int(game.resources.biomass) == player_raw,
		"player economy consumes CPI & SPL Tokens immunity")

	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88077,
		"rust_tech", ["rust_tech", "global_net"])
	game.next_event_turn = 999
	ai_city = _city_of(1)
	_set_swamp_ring(ai_city)
	var ai_state: Dictionary = game._faction_energy_grid_state(1)
	var ai_raw: int = int(ai_state.gathered[ai_city].food)
	var ai_expected := ai_city.usable_food(ai_raw, false)
	var ai_resources: Dictionary = game.ai._resources(1)
	ai_resources.biomass = 0
	game.ai._run_economy(1, [ai_city], ai_resources, game)
	check(int(ai_resources.biomass) == ai_expected,
		"AI economy applies the same shared swamp penalty once")

	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88077,
		"rust_tech", ["rust_tech", "global_net"])
	game.next_event_turn = 999
	ai_city = _city_of(1)
	_set_swamp_ring(ai_city)
	ai_state = game._faction_energy_grid_state(1)
	ai_raw = int(ai_state.gathered[ai_city].food)
	ai_resources = game.ai._resources(1)
	ai_resources.biomass = 0
	game.ai._tech(1).researched["radiation_engineering"] = true
	game.ai._run_economy(1, [ai_city], ai_resources, game)
	check(int(ai_resources.biomass) == ai_raw,
		"AI economy consumes the same CPI & SPL Tokens immunity")


func _set_swamp_ring(city: City) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var target := city.cell + Vector2i(dx, dy)
			if game.grid.in_bounds(target.x, target.y):
				game.grid.terrain[target.x][target.y] = "swamp"


func _city_of(faction_id: int) -> City:
	for city in game.cities:
		if city.faction_id == faction_id:
			return city
	return null


func _test_size(size: Vector2i) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 88080 + size.x,
		"rust_tech", ["rust_tech", "global_net"])
	game.resources.sol = 1000
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var ui = load("res://scripts/ui/GameUI.gd").new()
	viewport.add_child(ui)
	await process_frame
	ui._external_url_opener = func(url: String): opened_urls.append(url)
	ui._toggle_tech_panel()
	await process_frame
	await process_frame
	var panel: Control = ui.get_node("TechPanel/Content")
	var scroll: ScrollContainer = panel.find_child("TechScroll", true, false)
	var tree = panel.find_child("DependencyTree", true, false)
	check(tree != null and tree._cards.size() == 13,
		"%dpx renders every technology once in the dependency tree" % size.x)
	check(scroll != null and scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		and tree.custom_minimum_size.x > scroll.size.x,
		"%dpx exposes later eras through one horizontal tree gesture" % size.x)
	check(tree._era_header(4) == "ERA IV · CONTINUED"
		and tree._cards.firedancer.position.x > tree._cards.satellite_uplink.position.x
		and int(Data.TECHS.firedancer.era) == 4,
		"%dpx labels the extra Client Diversity column as Era IV continued" % size.x)
	var all_touch_safe := true
	for tech_id in tree._cards:
		var card: PanelContainer = tree._cards[tech_id]
		var info: Button = card.find_child("Info", true, false)
		var research: Button = tree._research_buttons[tech_id]
		all_touch_safe = all_touch_safe and info.custom_minimum_size.x >= 48.0 \
			and info.custom_minimum_size.y >= 48.0 and research.custom_minimum_size.y >= 48.0
	check(all_touch_safe, "%dpx keeps research and every info target at least 48px" % size.x)
	check(not _tree_contains_prose(tree),
		"%dpx keeps real-Solana prose out of the strategic tree" % size.x)

	var sol_before: int = int(game.resources.sol)
	var foundation_research: Button = tree._research_buttons["steam_synthesis"]
	foundation_research.emit_signal("pressed")
	await process_frame
	check(game.tech.current == "steam_synthesis" and int(game.resources.sol) == sol_before - 10,
		"%dpx starts legal research directly without a detail modal" % size.x)
	check(ui.get_node_or_null("TechDetailPanel") == null,
		"%dpx research action does not add another modal" % size.x)

	ui._toggle_tech_panel()
	await process_frame
	tree = ui.get_node("TechPanel/Content").find_child("DependencyTree", true, false)
	var info_before: int = int(game.resources.sol)
	var info_button: Button = tree._cards["primitive_coding"].find_child("Info", true, false)
	info_button.emit_signal("pressed")
	await process_frame
	var detail: Control = ui.get_node_or_null("TechDetailPanel")
	check(detail != null and int(game.resources.sol) == info_before,
		"%dpx info opens education without changing simulation state" % size.x)
	if detail != null:
		var labels := detail.find_children("*", "Label", true, false)
		var combined := ""
		for label in labels:
			combined += str((label as Label).text) + "\n"
		check("IN GAME" in combined and "REAL SOLANA" in combined
			and "FICTION BOUNDARY" in combined,
			"%dpx info separates mechanic, fact, and fiction" % size.x)
		var hidden_disclosures := 0
		for label in labels:
			if not (label as Label).visible:
				hidden_disclosures += 1
		check(hidden_disclosures >= 1,
			"%dpx terms begin progressively disclosed" % size.x)
		var official_links: VBoxContainer = detail.find_child("OfficialLinks", true, false)
		check(official_links != null and not official_links.visible
			and official_links.get_child_count() == EducationData.TECHS.primitive_coding.source_urls.size(),
			"%dpx official links are touch controls hidden until requested" % size.x)
		var valid_url: String = EducationData.TECHS.primitive_coding.source_urls[0]
		var opened_before := opened_urls.size()
		check(not ui._open_official_url("http://example.com/")
			and opened_urls.size() == opened_before,
			"%dpx rejects URLs outside the exact educational allowlist" % size.x)
		var links_toggle: Button
		for button in detail.find_children("*", "Button", true, false):
			if str((button as Button).text).begins_with("OFFICIAL LINKS"):
				links_toggle = button
				break
		links_toggle.emit_signal("pressed")
		var link: LinkButton = official_links.get_child(0)
		link.emit_signal("pressed")
		check(official_links.visible and opened_urls.size() == opened_before + 1
			and opened_urls.back() == valid_url,
			"%dpx opens an exact official URL only after explicit link activation" % size.x)
	ui._handle_ui_cancel()
	await process_frame
	check(ui.get_node_or_null("TechDetailPanel") == null
		and ui.get_node_or_null("TechPanel") != null,
		"%dpx Back closes info before the tree" % size.x)
	viewport.queue_free()
	await process_frame


func _tree_contains_prose(tree: Node) -> bool:
	for label in tree.find_children("*", "Label", true, false):
		var text := str((label as Label).text)
		for tech_id in EducationData.TECHS:
			if text.contains(str(EducationData.TECHS[tech_id].real_solana)):
				return true
	return false


func check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: " + message)
	else:
		failures += 1
		print("  FAIL: " + message)
