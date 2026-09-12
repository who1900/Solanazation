extends SceneTree
## Solanazation core smoke test: maps, turns, cities, units.
## Run: godot --headless --path . -s res://tests/smoke.gd

var failures: int = 0


func _init() -> void:
	print("=== SMOKE TEST START ===")
	await process_frame
	var g = root.get_node_or_null("Game")
	if g == null:
		g = load("res://scripts/GameRoot.gd").new()
		root.add_child(g)
	await process_frame
	var project_text: String = read_text("res://project.godot")
	var project_config := ConfigFile.new()
	check(project_text.count("[display]") == 1, "project has one authoritative display section")
	check(project_config.load("res://project.godot") == OK
		and int(project_config.get_value("display", "window/size/viewport_width", 0)) == 720
		and int(project_config.get_value("display", "window/size/viewport_height", 0)) == 1280
		and project_config.get_value("display", "window/stretch/mode", "") == "canvas_items"
		and project_config.get_value("display", "window/stretch/aspect", "") == "expand",
		"project keeps the 720x1280 portrait viewport and stretch settings")

	# --- 1. All map types x all sizes ---
	for size in [Data.MapSize.SMALL, Data.MapSize.MEDIUM, Data.MapSize.LARGE]:
		for mtype in [Data.MapType.CONTINENTS, Data.MapType.PANGAEA, Data.MapType.ARCHIPELAGO,
				Data.MapType.INLAND_SEA, Data.MapType.ISLANDS, Data.MapType.EARTH]:
			var dims: Vector2i = Data.MAP_DIMENSIONS[size]
			g.start_game(size, mtype, 777 + size * 100 + mtype)
			await process_frame
			check(g.grid.w == dims.x and g.grid.h == dims.y, "%s %dx%d dims" % [Data.MAP_TYPE_NAMES[mtype], dims.x, dims.y])
			var land: int = g.grid.count_terrain("wasteland") + g.grid.count_terrain("ruins") + g.grid.count_terrain("swamp") + g.grid.count_terrain("node_zone")
			var water: int = g.grid.count_terrain("ocean")
			check(land > 0, "%s has land (%d)" % [Data.MAP_TYPE_NAMES[mtype], land])
			check(water >= 0, "%s water ok" % Data.MAP_TYPE_NAMES[mtype])
			var spawns: Array = g.grid.find_spawn_points(2)
			check(spawns.size() == 2, "%s spawns x2" % Data.MAP_TYPE_NAMES[mtype])
			# 2 factions: player (3 units + 1 city) + AI (3 units + 1 city)
			check(g.units.size() == 6, "%s 6 units (2 factions), got %d" % [Data.MAP_TYPE_NAMES[mtype], g.units.size()])
			check(g.cities.size() == 2, "%s 2 cities, got %d" % [Data.MAP_TYPE_NAMES[mtype], g.cities.size()])

	# --- 2. RANDOM type ---
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.RANDOM, 999)
	await process_frame
	check(g.grid != null, "random map generated")

	# --- 3. Turns on large map ---
	g.start_game(Data.MapSize.LARGE, Data.MapType.PANGAEA, 123)
	await process_frame
	for i in range(3):
		g.end_turn()
	await process_frame
	check(g.turn == 4, "turn == 4 after 3 end_turn")
	check(g.resources.energy >= 0, "energy not negative")

	# --- 4. City and units ---
	var founder: Unit = null
	for u in g.units:
		if u.type_id == "founder":
			founder = u
			break
	check(founder != null, "founder exists")
	if founder != null:
		g.resources.scrap = 100
		for x in g.grid.w:
			for y in g.grid.h:
				var candidate := Vector2i(x, y)
				if g.can_found_site(candidate, founder.faction_id):
					g.grid.clear_occupant(founder.cell.x, founder.cell.y, founder)
					founder.cell = candidate
					g.grid.place_occupant(candidate.x, candidate.y, founder)
					break
			if g.can_found_site(founder.cell, founder.faction_id, founder):
				break
		var ok: bool = g.found_city(founder)
		check(ok, "founder founded city")
		check(g.cities.size() >= 2, ">=2 cities after founding, got %d" % g.cities.size())
	var city := g.cities[0] as City
	g.resources.scrap = 100
	g.resources.sol = 10
	var trained: bool = g.train_unit(city, "miner_quad")
	check(trained, "trained miner_quad")

	# --- 5. Tech ---
	g.resources.sol = 50
	var tech_ok: bool = g.tech.start_research("steam_synthesis", g.resources)
	check(tech_ok, "research started")
	g.tech.points = 100
	var done: Dictionary = g.tech.add_points(0)
	check(not done.is_empty(), "research completed: %s" % done.get("tech", "?"))
	check(g.tech.is_researched("steam_synthesis"), "diesel_restoration researched")

	# --- 5a. Standard educational layer ---
	check(Data.TECHS.size() == 13 and EducationData.TECHS.size() == Data.TECHS.size(),
		"education covers all 13 stable technology IDs")
	var education_complete := true
	var education_word_counts_valid := true
	var education_sources_valid := true
	var education_terms_valid := true
	for t_id in Data.TECHS:
		if not EducationData.TECHS.has(t_id):
			education_complete = false
			continue
		var education: Dictionary = EducationData.TECHS[t_id]
		for field in ["game_effect", "real_solana", "fiction", "terms", "source_urls"]:
			if not education.has(field):
				education_complete = false
		var words: int = String(education.get("real_solana", "")).split(" ", false).size()
		if words < 40 or words > 70:
			education_word_counts_valid = false
		for url in education.get("source_urls", []):
			var source_url := String(url)
			if not source_url.begins_with("https://") or not (
					source_url.contains("solana.com/")
					or source_url.contains("docs.anza.xyz/")
					or source_url.contains("docs.jito.wtf/")
					or source_url.contains("developers.metaplex.com/")
					or source_url.contains("github.com/firedancer-io/")):
				education_sources_valid = false
		for term in education.get("terms", []):
			var found_term := false
			for glossary_id in EducationData.GLOSSARY:
				if EducationData.GLOSSARY[glossary_id].name == term:
					found_term = true
					break
			if not found_term:
				education_terms_valid = false
	check(education_complete, "every education entry has the five required fields")
	check(education_word_counts_valid, "every Real Solana explanation is 40-70 words")
	check(education_sources_valid, "education uses formatted primary official source URLs")
	check(education_terms_valid, "every technology term resolves to the glossary")
	check(EducationData.GLOSSARY.size() >= 12 and EducationData.GLOSSARY.size() <= 18,
		"glossary contains 12-18 concise terms")
	var required_glossary_ids := [
		"account", "program", "transaction_fee", "poh_slot", "tower", "validator",
		"pda", "cpi", "spl", "parallel_compute", "v0_alt", "commitment", "turbine",
		"qos", "client_diversity", "compression", "token_extensions", "jito_bundle",
	]
	var required_glossary_complete := true
	for glossary_id in required_glossary_ids:
		if not EducationData.GLOSSARY.has(glossary_id):
			required_glossary_complete = false
	check(required_glossary_complete, "glossary covers the required current Solana concepts")
	var glossary_complete := true
	for glossary_id in EducationData.GLOSSARY:
		var glossary_entry: Dictionary = EducationData.GLOSSARY[glossary_id]
		if String(glossary_entry.get("name", "")) == "" \
				or String(glossary_entry.get("definition", "")) == "" \
				or not String(glossary_entry.get("source", "")).begins_with("https://"):
			glossary_complete = false
	check(glossary_complete, "glossary entries include definition and official source")
	var alt_copy: String = EducationData.TECHS.cyber_implants.real_solana
	check(alt_copy.contains("inline 32-byte account addresses")
		and alt_copy.contains("1-byte indexes into an onchain Address Lookup Table"),
		"ALT copy explains inline addresses and one-byte table indexes")
	var bundle_copy: String = EducationData.TECHS.terraforming.real_solana
	check(bundle_copy.contains("mints and token accounts")
		and bundle_copy.contains("handle them correctly or reject unsupported assets")
		and bundle_copy.contains("up to five signed transactions")
		and bundle_copy.contains("all-or-nothing if the bundle lands")
		and bundle_copy.contains("tip is separate from Solana's compute-unit priority fee")
		and bundle_copy.contains("does not guarantee landing"),
		"Token Extensions and Jito caveats remain explicit")
	check(EducationData.GLOSSARY.token_extensions.definition.contains(
		"mint and token-account behaviors")
		and EducationData.GLOSSARY.token_extensions.definition.contains(
			"handle or explicitly reject")
		and EducationData.GLOSSARY.jito_bundle.definition.contains(
			"all-or-nothing if landed")
		and EducationData.GLOSSARY.jito_bundle.definition.contains(
			"separate from the compute-unit priority fee")
		and EducationData.GLOSSARY.jito_bundle.definition.contains(
			"receipt or a higher tip does not guarantee landing"),
		"Token Extensions and Jito glossary entries preserve handling and landing caveats")
	var compression_copy: String = EducationData.TECHS.global_consensus.real_solana
	check(compression_copy.contains("Bubblegum V2 compressed NFTs")
		and compression_copy.contains("Merkle-tree")
		and compression_copy.contains("proofs and indexers")
		and compression_copy.contains("does not make ownership or metadata private")
		and EducationData.TECHS.global_consensus.source_urls.has(
			"https://developers.metaplex.com/smart-contracts/bubblegum-v2/sdk/javascript")
		and EducationData.GLOSSARY.compression.source ==
			"https://developers.metaplex.com/bubblegum-v2/concurrent-merkle-trees",
		"state compression copy is narrowly sourced to Bubblegum V2 cNFTs")
	check(read_text("res://docs/FULL-SPEC.md").contains("Jito Bundle Tip (game abstraction)")
		and read_text("res://docs/FULL-SPEC.md").contains(
			"separate from Solana's compute-unit priority fee"),
		"FULL-SPEC separates a bundle tip from a priority fee")

	var education_ui: CanvasLayer = load("res://scripts/ui/GameUI.gd").new()
	root.add_child(education_ui)
	await process_frame
	var saved_sol: int = int(g.resources.sol)
	g.tech.current = ""
	g.resources.sol = 0
	check(education_ui._research_disabled_reason("atomic_reactor") ==
		"Insufficient SOL: need ◎40, have ◎0.",
		"research status explains required and current SOL")
	check(education_ui._research_disabled_reason("firedancer") ==
		"Requires: State Compression.",
		"research status names unmet prerequisites")
	g.resources.sol = 100
	g.tech.current = "primitive_coding"
	check(education_ui._research_disabled_reason("atomic_reactor") ==
		"Unavailable: researching Accounts & Ownership.",
		"research status names the other active research")
	g.tech.current = ""
	g.resources.sol = saved_sol
	education_ui._toggle_tech_panel()
	await process_frame
	check(education_ui.get_node_or_null("TechPanel") != null, "technology panel opens headless")
	check(buttons_meet_accessibility(education_ui.get_node("TechPanel")),
		"technology, protocol, wonder, and header controls meet touch/font minimums")
	education_ui._show_tech_detail("steam_synthesis")
	await process_frame
	check(education_ui.get_node_or_null("TechDetailPanel") != null, "technology detail opens headless")
	check(buttons_meet_accessibility(education_ui.get_node("TechDetailPanel")),
		"technology detail controls meet touch/font minimums")
	education_ui._show_glossary()
	await process_frame
	check(education_ui.get_node_or_null("GlossaryPanel") != null, "glossary opens headless")
	check(buttons_meet_accessibility(education_ui.get_node("GlossaryPanel")),
		"glossary header control meets touch/font minimums")
	education_ui._show_network_status()
	await process_frame
	check(education_ui.get_node_or_null("NetworkStatusPanel") != null, "network status opens headless")
	check(buttons_meet_accessibility(education_ui.get_node("NetworkStatusPanel")),
		"network status header control meets touch/font minimums")
	education_ui._close_overlay("TechDetailPanel")
	education_ui._close_overlay("GlossaryPanel")
	education_ui._close_overlay("NetworkStatusPanel")
	education_ui._toggle_tech_panel()
	await process_frame
	check(education_ui.get_node_or_null("TechPanel") == null
		and education_ui.get_node_or_null("TechDetailPanel") == null
		and education_ui.get_node_or_null("GlossaryPanel") == null
		and education_ui.get_node_or_null("NetworkStatusPanel") == null,
		"educational panels close in one action")
	education_ui.queue_free()
	await process_frame

	# --- 5b. Phase 2A portrait geometry and Android Back stack ---
	var game_ui_script: Script = load("res://scripts/ui/GameUI.gd")
	for viewport_size in [Vector2i(720, 1280), Vector2i(1080, 2400)]:
		var phase_viewport := SubViewport.new()
		phase_viewport.size = viewport_size
		phase_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(phase_viewport)
		var underlay_presses: Array[int] = [0]
		var underlay := Button.new()
		underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		underlay.pressed.connect(func(): underlay_presses[0] += 1)
		phase_viewport.add_child(underlay)
		var phase_ui: CanvasLayer = game_ui_script.new()
		phase_viewport.add_child(phase_ui)
		await process_frame
		push_pointer_click(phase_viewport, Vector2(2, 2))
		await process_frame
		check(underlay_presses[0] == 1, "pointer baseline reaches exposed underlay margin")
		g.select(city)
		phase_ui.build_city_actions(city)
		phase_ui._toggle_diplomacy_panel()
		phase_ui._toggle_tech_panel()
		phase_ui._show_tech_detail("steam_synthesis")
		phase_ui._show_glossary()
		phase_ui._show_network_status()
		phase_ui.show_menu()
		phase_ui.show_game_over("Test Faction", "portrait geometry")
		await process_frame
		await process_frame
		var pointer_resources_before: Dictionary = g.resources.duplicate(true)
		push_pointer_click(phase_viewport, Vector2(2, 2))
		await process_frame
		check(underlay_presses[0] == 1 and g.resources == pointer_resources_before
			and g.selected_city == city,
			"hard-modal margin blocks pointer dispatch to HUD, map, and underlay")
		check(hard_modals_block_full_viewport(phase_ui, viewport_size),
			"menu, game-over, and education hard modals own full STOP blockers")
		check(primary_panels_inside_viewport(phase_ui, viewport_size),
			"primary panels fit %dx%d portrait viewport" % [viewport_size.x, viewport_size.y])
		check(interactive_controls_fit_width(phase_ui, viewport_size),
			"interactive controls avoid horizontal overflow at %dx%d" % [viewport_size.x, viewport_size.y])
		check(buttons_meet_accessibility(phase_ui) and text_meets_accessibility(phase_ui),
			"primary UI meets touch and text minimums at %dx%d" % [viewport_size.x, viewport_size.y])
		check(critical_panels_have_scroll(phase_ui),
			"long portrait content uses ScrollContainer at %dx%d" % [viewport_size.x, viewport_size.y])
		phase_ui.show_menu()
		phase_ui.show_game_over("Duplicate", "must be ignored")
		phase_ui._show_tech_detail("atomic_reactor")
		phase_ui._show_glossary()
		phase_ui._show_network_status()
		check(direct_named_child_count(phase_ui, "MenuPanel") == 1
			and direct_named_child_count(phase_ui, "GameOverPanel") == 1
			and direct_named_child_count(phase_ui, "TechDetailPanel") == 1
			and direct_named_child_count(phase_ui, "GlossaryPanel") == 1
			and direct_named_child_count(phase_ui, "NetworkStatusPanel") == 1,
			"repeated open calls do not duplicate primary panels")
		var turn_before_back: int = g.turn
		var resources_before_back: Dictionary = g.resources.duplicate(true)
		check(phase_ui.get_node_or_null("GameOverPanel") != null,
			"Back stack contains terminal GameOverPanel")
		phase_ui._handle_ui_cancel()
		await process_frame
		check(phase_ui.get_node_or_null("GameOverPanel") != null,
			"Back is consumed without dismissing terminal GameOverPanel")
		phase_ui._show_new_game_from_game_over()
		await process_frame
		check(phase_ui.get_node_or_null("GameOverPanel") == null
			and phase_ui.get_node_or_null("MenuPanel") != null,
			"New Game presents blocking setup menu before removing GameOver")
		for panel_name in [
			"GlossaryPanel", "NetworkStatusPanel", "TechDetailPanel",
			"DipPanel", "TechPanel", "CityActions",
		]:
			check(phase_ui.get_node_or_null(panel_name) != null,
				"Back stack contains %s" % panel_name)
			phase_ui._handle_ui_cancel()
			await process_frame
			check(phase_ui.get_node_or_null(panel_name) == null,
				"Back closes only top-priority %s" % panel_name)
		check(phase_ui.get_node_or_null("MenuPanel") != null, "main menu remains on first-screen Back")
		phase_ui._handle_ui_cancel()
		await process_frame
		check(phase_ui.get_node_or_null("MenuPanel") != null,
			"first-screen Back is consumed without quitting or hiding the menu")
		phase_ui._close_overlay("MenuPanel")
		await process_frame
		var map_stub := Node2D.new()
		map_stub.name = "MapView"
		phase_viewport.add_child(map_stub)
		var broker_stub := Control.new()
		broker_stub.name = "BrokerMenu"
		map_stub.add_child(broker_stub)
		phase_ui._handle_ui_cancel()
		await process_frame
		check(map_stub.get_node_or_null("BrokerMenu") == null and g.selected_city == city,
			"Back closes broker menu before clearing selection")
		phase_ui._handle_ui_cancel()
		await process_frame
		check(g.selected_city == null and g.selected_unit == null,
			"Back deselects city or unit after panels close")
		check(g.turn == turn_before_back and g.resources == resources_before_back,
			"Back stack does not mutate simulation state")
		phase_ui.queue_free()
		phase_viewport.queue_free()
		await process_frame
	# Restart reuses the exact requested map config, seed, player-first roster, and terrain.
	var restart_roster: Array = Data.FACTIONS.keys()
	g.start_game(Data.MapSize.SMALL, Data.MapType.RANDOM, 271828, "dao", restart_roster)
	var expected_restart_terrain: String = JSON.stringify(g.grid.terrain)
	var expected_restart_resolved_type: int = g._map_type
	var expected_restart_roster: Array = g._faction_ids()
	g.turn = 9
	g.resources.sol = 777
	var restart_viewport := SubViewport.new()
	restart_viewport.size = Vector2i(720, 1280)
	root.add_child(restart_viewport)
	var restart_ui: CanvasLayer = game_ui_script.new()
	restart_viewport.add_child(restart_ui)
	await process_frame
	restart_ui.show_game_over("Restart Test", "terminal recovery")
	await process_frame
	var restart_panel := restart_ui.get_node("GameOverPanel")
	check(restart_panel.find_child("RestartButton", true, false) != null
		and restart_panel.find_child("NewGameButton", true, false) != null,
		"GameOver exposes two explicit recovery actions")
	restart_ui._restart_current_match()
	await process_frame
	check(g.turn == 1 and g.resources == Data.START_RESOURCES
		and g._game_seed == 271828 and g._requested_map_type == Data.MapType.RANDOM
		and g._map_type == expected_restart_resolved_type
		and g._faction_ids() == expected_restart_roster
		and JSON.stringify(g.grid.terrain) == expected_restart_terrain,
		"Restart deterministically restores the same match configuration at turn one")
	check(restart_ui.get_node_or_null("GameOverPanel") == null,
		"successful Restart removes the terminal overlay")
	var recovery_underlay_presses: Array[int] = [0]
	var recovery_underlay := Button.new()
	recovery_underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recovery_underlay.pressed.connect(func(): recovery_underlay_presses[0] += 1)
	restart_viewport.add_child(recovery_underlay)
	restart_ui.show_game_over("New Game Test", "terminal recovery")
	restart_ui._show_new_game_from_game_over()
	await process_frame
	var start_button := restart_ui.get_node("MenuPanel").find_child(
		"StartButton", true, false) as Button
	check(start_button != null, "GameOver to New Game exposes the real Start action")
	push_pointer_click(restart_viewport, start_button.get_global_rect().get_center())
	await process_frame
	check(restart_ui.get_node_or_null("MenuPanel") == null
		and restart_ui.get_node_or_null("GameOverPanel") == null
		and g.turn == 1 and g.grid != null and g.factions.size() == 3,
		"actual Start dispatch removes the full menu blocker and starts a match")
	push_pointer_click(restart_viewport, Vector2(2, 2))
	await process_frame
	check(recovery_underlay_presses[0] == 1,
		"pointer reaches gameplay underlay after Start removes MenuPanel")
	g.end_turn()
	await process_frame
	check(g.turn == 2, "gameplay advances after Start removes the menu blocker")
	g.resources.sol = 321
	check(g.save_to_file("user://save.json"), "write menu Load dispatch fixture")
	g.resources.sol = 0
	restart_ui.show_menu()
	await process_frame
	var load_button := restart_ui.get_node("MenuPanel").find_child(
		"LoadButton", true, false) as Button
	check(load_button != null, "menu exposes the real Load action")
	push_pointer_click(restart_viewport, load_button.get_global_rect().get_center())
	await process_frame
	check(restart_ui.get_node_or_null("MenuPanel") == null
		and g.turn == 2 and int(g.resources.sol) == 321,
		"successful Load dispatch restores state and removes the full menu blocker")
	push_pointer_click(restart_viewport, Vector2(2, 2))
	await process_frame
	check(recovery_underlay_presses[0] == 2,
		"pointer reaches gameplay underlay after successful Load removes MenuPanel")
	restart_ui.queue_free()
	restart_viewport.queue_free()
	await process_frame

	# --- 5c. Phase 2B touch gestures, safe area, and mobile lifecycle ---
	g.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 24680, "rust_tech")
	var gesture_viewport := SubViewport.new()
	gesture_viewport.size = Vector2i(720, 1280)
	root.add_child(gesture_viewport)
	var gesture_root := Node2D.new()
	gesture_viewport.add_child(gesture_root)
	var gesture_camera := Camera2D.new()
	gesture_camera.name = "Camera"
	gesture_camera.zoom = Vector2.ONE
	gesture_root.add_child(gesture_camera)
	var gesture_map: Node2D = load("res://scripts/ui/MapView.gd").new()
	gesture_map.name = "MapView"
	gesture_root.add_child(gesture_map)
	var gesture_ui: CanvasLayer = game_ui_script.new()
	gesture_ui.name = "UI"
	gesture_root.add_child(gesture_ui)
	await process_frame
	var tap_city: City = g.cities[0]
	gesture_camera.zoom = Vector2.ONE
	gesture_camera.position = g.cell_to_pixel(tap_city.cell)
	await process_frame
	var screen_center: Vector2 = gesture_map.cell_to_screen(tap_city.cell) \
		+ Vector2.ONE * gesture_map.TILE_SIZE * gesture_camera.zoom.x * 0.5
	g.select(null)
	gesture_map._handle_map_input(make_touch(0, screen_center, true))
	check(gesture_map._touches.has(0), "touch press enters map gesture state")
	gesture_map._handle_map_input(make_touch(0, screen_center, false))
	check(g.selected_city == tap_city, "one-finger tap keeps map selection semantics")
	g.select(null)
	var pan_camera_start: Vector2 = gesture_camera.position
	gesture_map._handle_map_input(make_touch(0, screen_center, true))
	gesture_map._handle_map_input(make_drag(0, screen_center + Vector2(30, 0), Vector2(30, 0)))
	gesture_map._handle_map_input(make_touch(0, screen_center + Vector2(30, 0), false))
	check(gesture_camera.position.distance_to(pan_camera_start - Vector2(30, 0)) < 0.1
		and g.selected_city == null and g.selected_unit == null,
		"one-finger drag pans after threshold without releasing a tap")
	gesture_camera.position = g.cell_to_pixel(tap_city.cell)
	gesture_camera.zoom = Vector2.ONE
	var pinch_left := Vector2(300, 640)
	var pinch_right := Vector2(420, 640)
	var parallel_delta := Vector2(20, 12)
	var parallel_camera_start: Vector2 = gesture_camera.position
	gesture_map._handle_map_input(make_touch(0, pinch_left, true))
	gesture_map._handle_map_input(make_touch(1, pinch_right, true))
	gesture_map._handle_map_input(make_drag(
		0, pinch_left + parallel_delta, parallel_delta))
	gesture_map._handle_map_input(make_drag(
		1, pinch_right + parallel_delta, parallel_delta))
	check(absf(gesture_camera.zoom.x - 1.0) < 0.001
		and gesture_camera.position.distance_to(parallel_camera_start - parallel_delta) < 0.1
		and g.selected_city == null and g.selected_unit == null,
		"parallel two-finger translation pans without zoom or gameplay action")
	gesture_map.cancel_touch_gestures()
	gesture_camera.position = g.cell_to_pixel(tap_city.cell)
	gesture_camera.zoom = Vector2.ONE
	var symmetric_anchor_world: Vector2 = gesture_camera.position
	var moved_left := Vector2(280, 640)
	var moved_right := Vector2(440, 640)
	gesture_map._handle_map_input(make_touch(0, pinch_left, true))
	gesture_map._handle_map_input(make_touch(1, pinch_right, true))
	gesture_map._handle_map_input(make_drag(0, moved_left, moved_left - pinch_left))
	gesture_map._handle_map_input(make_drag(1, moved_right, moved_right - pinch_right))
	var projected_anchor: Vector2 = (symmetric_anchor_world - gesture_camera.position) \
		* gesture_camera.zoom.x + screen_center
	check(absf(gesture_camera.zoom.x - (160.0 / 120.0)) < 0.001
		and projected_anchor.distance_to(screen_center) < 1.0,
		"sequential symmetric pinch preserves its intended world anchor within one pixel")
	gesture_map._handle_map_input(make_touch(1, moved_right, false))
	gesture_map._handle_map_input(make_touch(0, moved_left, false))
	check(g.selected_city == null and g.selected_unit == null
		and gesture_map._touches.is_empty(),
		"pinch and two-to-one lift reset without a ghost tap")
	gesture_camera.zoom = Vector2(gesture_map.MAX_ZOOM, gesture_map.MAX_ZOOM)
	gesture_map._handle_map_input(make_touch(0, pinch_left, true))
	gesture_map._handle_map_input(make_touch(1, pinch_right, true))
	gesture_map._handle_map_input(make_drag(0, Vector2(200, 640), Vector2(-100, 0)))
	check(is_equal_approx(gesture_camera.zoom.x, gesture_map.MAX_ZOOM),
		"pinch zoom respects the existing maximum clamp")
	gesture_map.cancel_touch_gestures()
	gesture_map._last_touch_msec = -1000
	gesture_camera.position = g.cell_to_pixel(tap_city.cell)
	gesture_camera.zoom = Vector2.ONE
	g.select(null)
	gesture_map._handle_map_input(make_mouse_button(screen_center, MOUSE_BUTTON_LEFT, true))
	gesture_map._handle_map_input(make_mouse_button(screen_center, MOUSE_BUTTON_LEFT, false))
	check(g.selected_city == tap_city, "mouse click selection remains available")
	var mouse_zoom_before: float = gesture_camera.zoom.x
	gesture_map._handle_map_input(make_mouse_button(screen_center, MOUSE_BUTTON_WHEEL_UP, true))
	check(gesture_camera.zoom.x > mouse_zoom_before, "mouse wheel zoom remains available")
	g.select(null)
	var mouse_pan_start: Vector2 = gesture_camera.position
	var mouse_pan_delta := Vector2(24, 0)
	gesture_map._handle_map_input(make_mouse_button(screen_center, MOUSE_BUTTON_LEFT, true))
	gesture_map._handle_map_input(make_mouse_motion(
		screen_center + mouse_pan_delta, mouse_pan_delta))
	gesture_map._handle_map_input(make_mouse_button(
		screen_center + mouse_pan_delta, MOUSE_BUTTON_LEFT, false))
	check(gesture_camera.position.distance_to(
		mouse_pan_start - mouse_pan_delta / gesture_camera.zoom.x) < 0.1
		and g.selected_city == null and g.selected_unit == null,
		"mouse drag still pans without dispatching a click")
	gesture_camera.position = g.cell_to_pixel(tap_city.cell)
	gesture_camera.zoom = Vector2.ONE
	g.select(tap_city)
	var selected_after_mouse: City = g.selected_city
	var emulated_touch_position: Vector2 = screen_center + mouse_pan_delta
	gesture_map._handle_map_input(make_touch(0, emulated_touch_position, true))
	gesture_map._handle_map_input(make_touch(0, emulated_touch_position, false))
	check(g.selected_city == selected_after_mouse and gesture_map._touches.is_empty(),
		"mouse-emulated touch is deduplicated instead of firing a second action")

	gesture_ui.build_city_actions(tap_city)
	gesture_ui._toggle_tech_panel()
	gesture_ui._toggle_diplomacy_panel()
	gesture_ui.show_menu()
	gesture_ui._show_tech_detail("steam_synthesis")
	var safe_control_names := [
		"TopHUD", "SelectionPanel", "LogPanel", "BottomNav",
		"CityActions", "DipPanel",
	]
	var injected_safe := Rect2i(23, 47, 661, 1171)
	gesture_ui._set_safe_rect_for_test(injected_safe)
	await process_frame
	check(controls_inside_rect(gesture_ui, safe_control_names, Rect2(injected_safe))
		and hard_modal_contents_inside_rect(gesture_ui, Rect2(injected_safe)),
		"asymmetric 720x1280 safe rect contains persistent, soft, and hard content")
	check(visible_hard_modals_cover_viewport(gesture_ui, Vector2i(720, 1280)),
		"safe-area layout keeps full-screen modal blockers over the viewport")
	gesture_viewport.size = Vector2i(1080, 2400)
	var resized_safe := Rect2i(41, 83, 981, 2190)
	gesture_ui._set_safe_rect_for_test(resized_safe)
	await process_frame
	check(controls_inside_rect(gesture_ui, safe_control_names, Rect2(resized_safe))
		and hard_modal_contents_inside_rect(gesture_ui, Rect2(resized_safe)),
		"asymmetric 1080x2400 resize keeps every interactive panel in the safe rect")
	gesture_ui._clear_safe_rect_for_test()
	await process_frame
	check(absf((gesture_ui.get_node("TopHUD") as Control).offset_left - 8.0) < 0.1,
		"zero safe insets restore the original HUD layout")

	var pause_path := "user://pause_autosave.json"
	if FileAccess.file_exists(pause_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pause_path))
	var initialized_grid = g.grid
	var initialized_tech = g.tech
	var initialized_factions: Array = g.factions
	g.grid = null
	g.tech = null
	g.factions = []
	gesture_ui._handle_application_paused()
	check(not FileAccess.file_exists(pause_path),
		"pausing an uninitialized menu does not create an autosave")
	gesture_ui._handle_application_resumed()
	g.grid = initialized_grid
	g.tech = initialized_tech
	g.factions = initialized_factions
	g.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 24680, "rust_tech")
	gesture_ui._hold_start()
	gesture_map._handle_map_input(make_touch(3, Vector2(100, 100), true))
	var lifecycle_turn: int = g.turn
	var lifecycle_resources: Dictionary = g.resources.duplicate(true)
	var lifecycle_rng_state: int = g._rng.state
	var lifecycle_child_count: int = gesture_ui.get_child_count()
	gesture_ui._handle_application_paused()
	var pause_data: Variant = JSON.parse_string(read_text(pause_path))
	check(FileAccess.file_exists(pause_path) and pause_data is Dictionary
		and g._validate_save_data(pause_data),
		"active-match pause writes one valid dedicated autosave")
	check(not gesture_ui._holding_end and gesture_map._touches.is_empty()
		and g.turn == lifecycle_turn and g.resources == lifecycle_resources
		and g._rng.state == lifecycle_rng_state,
		"pause cancels hold and gestures without changing turn, RNG, or resources")
	gesture_ui._handle_application_paused()
	gesture_ui._handle_application_resumed()
	await process_frame
	check(not gesture_ui._holding_end and gesture_map._touches.is_empty()
		and gesture_ui.get_child_count() == lifecycle_child_count,
		"resume clears stale input and refreshes without duplicate UI nodes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pause_path))
	gesture_ui.show_game_over("Terminal", "no pause save")
	gesture_ui._handle_application_paused()
	check(not FileAccess.file_exists(pause_path),
		"terminal GameOver pause does not create an incomplete autosave")
	gesture_ui.queue_free()
	gesture_root.queue_free()
	gesture_viewport.queue_free()
	await process_frame

	g.start_game(Data.MapSize.MEDIUM, Data.MapType.CONTINENTS, 444, "rust_tech")
	var map_view_logic: Node2D = load("res://scripts/ui/MapView.gd").new()
	check(map_view_logic._clamp_menu_position(Vector2(-80, -30), Vector2(150, 48),
		Vector2(720, 1280)) == Vector2.ZERO
		and map_view_logic._clamp_menu_position(Vector2(710, 1270), Vector2(150, 48),
			Vector2(720, 1280)) == Vector2(570, 1232),
		"broker radial controls clamp to portrait viewport edges")
	map_view_logic.free()

	# --- 6. Factions and AI ---
	check(g.factions.size() == 2, "2 factions")
	check(g.factions[0].name == "Rust-Tech Clan", "player faction Rust-Tech")
	check(g.ai != null, "AI exists")
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.CONTINENTS, 555)
	await process_frame
	# AI turns (10 turns, must not crash)
	for i in range(10):
		g.end_turn()
		await process_frame
	check(g.turn == 11, "10 turns with AI, turn=%d" % g.turn)
	var ai_cities := 0
	for c in g.cities:
		if c.faction_id == 1:
			ai_cities += 1
	check(ai_cities >= 1, "AI has cities (%d)" % ai_cities)

	# --- 7. Faction unique unit ---
	var uu: Dictionary = Faction.UNIQUE_UNITS["rust_tech"]
	check(uu.has("steam_shredder"), "faction unique unit exists")
	var uu_data: Dictionary = g._unit_data("steam_shredder")
	check(uu_data.name == "Steam Shredder", "unique unit data resolves")

	# --- 8. Victory ---
	g.check_victory()
	check(g.cities.size() >= 2, "victory check safe (cities %d)" % g.cities.size())

	# --- 9. Combat formula (terrain modifiers) ---
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.PANGAEA, 1001)
	await process_frame
	var atk_unit := Unit.new("heavy_mech", 0, Vector2i(10, 10), g.grid)
	var def_unit := Unit.new("rust_guard", 1, Vector2i(11, 10), g.grid)
	g.grid.terrain[11][10] = "ruins"  # +50% defense
	var win_rate_ruins := 0
	for i in range(400):
		if atk_unit.fight_vs(def_unit, g.gameplay_randf()):
			win_rate_ruins += 1
		atk_unit.veteran = false
		def_unit.veteran = false
	check(win_rate_ruins < 400, "ruins defense reduces win rate (%d/400)" % win_rate_ruins)
	# mountains: +100% defense
	var def2 := Unit.new("rust_guard", 1, Vector2i(12, 10), g.grid)
	g.grid.terrain[12][10] = "mountains"
	var win_rate_mtn := 0
	for i in range(400):
		if atk_unit.fight_vs(def2, g.gameplay_randf()):
			win_rate_mtn += 1
		atk_unit.veteran = false
		def2.veteran = false
	check(win_rate_mtn < win_rate_ruins, "mountains defense > ruins (%d < %d)" % [win_rate_mtn, win_rate_ruins])
	check(not g.grid.is_passable(12, 10), "mountains impassable")

	# --- 10. Ancient Terminals + lairs ---
	check(g.terminals.size() > 0, "terminals spawned (%d)" % g.terminals.size())
	check(g.lairs.size() > 0, "lairs spawned (%d)" % g.lairs.size())
	if g.terminals.size() > 0:
		var tpos: Vector2i = g.terminals[0]
		check(g.terminals.has(tpos), "terminal exists")
		# unit enters
		g.resources.sol = 0
		var probe := Unit.new("rust_guard", 0, tpos, g.grid)
		g.activate_terminal(probe, tpos)
		check(not g.terminals.has(tpos), "terminal consumed")

	# --- 11. Barbarians (turn 10) ---
	g.start_game(Data.MapSize.LARGE, Data.MapType.CONTINENTS, 2002)
	await process_frame
	g.turn = 9
	g.end_turn()
	await process_frame
	var bots := 0
	for u in g.units:
		if u.faction_id == g.BARB_FACTION:
			bots += 1
	check(bots >= 2, "barbarians spawned at turn 10 (%d)" % bots)

	# --- 12. Save / Load roundtrip ---
	var save_path := "user://smoke_test_save.json"
	g.resources.sol = 77
	g.resources.scrap = 88
	var saved: bool = g.save_to_file(save_path)
	check(saved, "save_to_file")
	var loaded: bool = g.load_from_file(save_path)
	check(loaded, "load_from_file")
	check(g.resources.sol == 77, "SOL restored (%d)" % g.resources.sol)
	check(g.resources.scrap == 88, "Scrap restored (%d)" % g.resources.scrap)
	check(g.units.size() > 0, "units restored (%d)" % g.units.size())
	check(g.cities.size() > 0, "cities restored (%d)" % g.cities.size())
	check(occupancy_is_exact(g), "occupancy matches restored units and cities")

	# --- 13. Random events (Solana lore) — fresh game ---
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.PANGAEA, 3003)
	await process_frame
	# turbine so validators mint (energy 20 > upkeep)
	g.cities[0].buildings["steam_turbine"] = true

	# Outage: no $SOL for 1 turn
	g.event_active = "outage"
	g.event_turns_left = 1
	var sol_before: int = g.resources.sol
	g.end_turn()
	await process_frame
	check(g.resources.sol == sol_before, "outage blocks $SOL income")
	check(g.event_active == "", "outage expires after 1 turn")

	# Meme surge: +300% for the city
	g.event_active = "meme"
	g.event_turns_left = 2
	g.meme_city_idx = 0
	var sol_meme: int = g.resources.sol
	g.end_turn()
	await process_frame
	check(g.resources.sol > sol_meme, "meme surge boosts $SOL (was %d, now %d)" % [sol_meme, g.resources.sol])

	# --- 14. Jito rush + artifacts ---
	var j_city: City = g.cities[0]
	g.resources.sol = 500
	g.resources.scrap = 500
	var jito_ok: bool = g.jito_rush(j_city, "building", "steam_turbine")
	check(jito_ok, "jito rush builds instantly")
	check(j_city.has_building("steam_turbine"), "steam_turbine built by jito")
	g.artifacts["dragon_suit"] = true
	check(g.faction_attack_bonus() >= 1.1, "dragon suit morale bonus (%.2f)" % g.faction_attack_bonus())

	# --- 15. Firedancer: no outage ---
	g.resources.sol = 1000
	var fd_ok: bool = g.tech.start_research("firedancer", g.resources)
	check(fd_ok, "firedancer research started")
	g.tech.researched["firedancer"] = true
	check(g.has_passive("firedancer"), "firedancer passive active")

	# --- 16. Infrastructure (cable/monorail) ---
	var infra_u: Unit = g.units[0]
	var c_pos: Vector2i = infra_u.cell
	g.grid.infra[c_pos.x][c_pos.y] = 1
	check(absf(g.grid.move_cost(c_pos.x, c_pos.y) - 0.34) < 0.01, "cable cost 1/3 MP (%.2f)" % g.grid.move_cost(c_pos.x, c_pos.y))
	g.grid.infra[c_pos.x][c_pos.y] = 2
	check(g.grid.move_cost(c_pos.x, c_pos.y) < 0.05, "monorail cost ~0")
	# gather: monorail +1 SOL
	var mc: City = g.cities[0]
	mc.cell = Vector2i(c_pos.x, c_pos.y + 1)
	var gt: Dictionary = mc.gather_tile(c_pos.x, c_pos.y)
	check(int(gt.sol) >= 1, "monorail tile gives +1 $SOL")

	# --- 17. Tile improvements ---
	var imp_ok: bool = mc.build_improvement(c_pos.x, c_pos.y, "mine")
	check(not imp_ok, "mine on non-ruins rejected")
	if g.grid.terrain[c_pos.x][c_pos.y] == "wasteland":
		var tower_ok: bool = mc.build_improvement(c_pos.x, c_pos.y, "tower")
		check(tower_ok, "tower built on wasteland")
		check(g.grid.improvements[c_pos.x][c_pos.y] == "tower", "tower recorded")

	# --- 18. Unit evolution (upgrade) ---
	g.resources.sol = 200
	var guard: Unit = null
	for u in g.units:
		if u.type_id == "rust_guard":
			guard = u
			break
	if guard != null:
		guard.cell = g.cities[0].cell + Vector2i(1, 0)
		# find free passable tile next to city
		guard.cell = g.grid.find_free_tile_near(g.cities[0].cell.x, g.cities[0].cell.y, 2)
		var up_ok: bool = g.upgrade_unit(guard)
		check(up_ok, "rust_guard upgraded")
		var evolved := false
		for u2 in g.units:
			if u2.type_id == "raider_walker":
				evolved = true
		check(evolved, "raider_walker exists after upgrade")

	# --- 19. Building evolution (turbine -> reactor -> fusion) ---
	g.tech.researched["atomic_reactor"] = true
	g.resources.sol = 500
	var b_city: City = g.cities[0]
	b_city.buildings["steam_turbine"] = true
	var up_b: String = b_city.upgrade_building(g.resources, g.tech)
	check(up_b == "nuclear_plant", "turbine -> nuclear (%s)" % up_b)
	g.tech.researched["quantum_computing"] = true
	g.resources.sol = 500
	up_b = b_city.upgrade_building(g.resources, g.tech)
	check(up_b == "fusion_plant", "nuclear -> fusion (%s)" % up_b)

	# --- 20. Relic sites in generation ---
	var has_relic := false
	for x in g.grid.w:
		for y in g.grid.h:
			if g.grid.terrain[x][y] in ["crater", "dump", "rift"]:
				has_relic = true
				break
		if has_relic:
			break
	check(has_relic, "relic sites generated (crater/dump/rift)")

	# --- 21. Diplomacy (treaties, trade, war gates) ---
	g.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 4004)
	await process_frame
	check(g.diplomatic_status(1) == "peace", "start at peace")
	check(not g.can_attack_faction(1), "peace blocks attacks")
	g.declare_war(1)
	check(g.can_attack_faction(1), "war allows attacks")
	g.ping[1] = 90
	check(g.propose_alliance(1), "alliance at high ping")
	check(g.diplomatic_status(1) == "alliance", "alliance set")
	check(not g.can_attack_faction(1), "alliance blocks attacks")
	g.resources.sol = 50
	var trade_ok: bool = g.trade_resources(1, true)
	check(trade_ok, "trade buy scrap")
	check(g.resources.scrap >= 50, "scrap received (%d)" % g.resources.scrap)

	# --- 22. Council laws ---
	g.turn = 15
	var sol_before_law: int = g.resources.sol
	g.consensus_council()
	check(g.council_law != "", "council law passed (%s)" % g.council_law)
	check(g.law_turns_left > 0, "law duration set")
	if g.council_law == "token_burn":
		check(g.resources.sol < sol_before_law, "token burn cuts treasury")

	# --- 23. Wonders: Quantum Cooler + Global Server ---
	g.tech.researched["quantum_computing"] = true
	g.tech.researched["global_consensus"] = true
	g.resources.sol = 500
	g.resources.scrap = 300
	var w_ok: bool = g.build_wonder("quantum_cooler")
	check(w_ok, "quantum cooler built")
	check(g.wonders.has("quantum_cooler"), "wonder recorded")
	# Global Server via building
	var gs_city: City = g.cities[0]
	gs_city.buildings["global_server"] = true
	g.global_server = true
	check(g.global_server, "global server flag")

	# --- 24. Net Broker ops (DoS / Sybil / Hardfork) ---
	var ai_city: City = null
	for c in g.cities:
		if c.faction_id == 1:
			ai_city = c
			break
	if ai_city != null:
		ai_city.dos_turns = 3
		check(ai_city.is_dos(), "DoS status set")
		# Sybil steals 30% of AI treasury
		if g.ai != null:
			g.ai.ai_resources[1] = { "scrap": 0, "biomass": 0, "energy": 0, "sol": 100 }
			g.resources.sol = 10
			var stolen_before: int = g.resources.sol
			# direct _hack lives in MapView; emulate the 30% drain here
			g.ai.ai_resources[1].sol -= 30
			g.resources.sol += 30
			check(g.resources.sol == stolen_before + 30, "sybil steals 30")
		# Hardfork: population drop
		var pop_before: int = ai_city.population
		ai_city.population = maxi(ai_city.population - 1, 1)
		check(ai_city.population < pop_before or pop_before == 1, "hardfork cuts population")

	# --- 25. EMP aura + loot + crater gate ---
	var acolyte := Unit.new("cyber_acolyte", 1, Vector2i(5, 5), g.grid)
	g.units.append(acolyte)
	g.grid.place_occupant(5, 5, acolyte)
	var target_u := Unit.new("rust_guard", 0, Vector2i(5, 6), g.grid)
	g.units.append(target_u)
	g.grid.place_occupant(5, 6, target_u)
	g.set_relation(0, 1, "war")
	check(g.emp_aura_penalty(target_u) == 1, "EMP aura -1 move")
	# loot: courier kills guard -> +50% of cost
	var courier := Unit.new("armored_courier", 0, Vector2i(6, 6), g.grid)
	var victim := Unit.new("rust_guard", 1, Vector2i(6, 7), g.grid)
	var sol_loot: int = g.resources.sol
	g.on_kill(courier, victim)
	check(g.resources.sol == sol_loot + 5, "courier loots 50% of guard (10/2=5)")
	# crater gate: can_build restriction
	var crater_city: City = g.cities[0]
	if g.grid.terrain[crater_city.cell.x][crater_city.cell.y] in ["node_zone", "crater"]:
		check(not crater_city.can_build("assembly_forge", g.resources), "crater blocks non-validator")
	else:
		g.grid.terrain[crater_city.cell.x][crater_city.cell.y] = "crater"
		check(not crater_city.can_build("assembly_forge", g.resources), "crater blocks non-validator")
		check(crater_city.can_build("relic_validator", g.resources), "crater allows validator")

	# --- 26. Faction-local infrastructure energy components ---
	setup_energy_test(g)
	var powered_city: City = add_energy_test_city(g, "Powered", Vector2i(5, 5), true)
	var deficit_city: City = add_energy_test_city(g, "Deficit", Vector2i(15, 5))
	powered_city.buildings["steam_turbine"] = true
	deficit_city.buildings["assembly_forge"] = true
	var energy_state: Dictionary = g._player_energy_grid_state()
	check(energy_state.powered[powered_city] and not energy_state.powered[deficit_city],
		"isolated powered and deficit cities remain independent")
	check(int(energy_state.available_energy) == 20, "isolated deficit does not cause global blackout")
	for x in range(6, 15):
		g.grid.infra[x][5] = 1
	energy_state = g._player_energy_grid_state()
	check(energy_state.powered[powered_city] and energy_state.powered[deficit_city],
		"cable path pools city energy")
	check(int(energy_state.available_energy) == 19, "cable component applies building upkeep once")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "DiagonalSource", Vector2i(5, 5), true)
	deficit_city = add_energy_test_city(g, "DiagonalSink", Vector2i(8, 6))
	powered_city.buildings["steam_turbine"] = true
	deficit_city.buildings["assembly_forge"] = true
	g.grid.infra[6][5] = 1
	g.grid.infra[7][6] = 1
	energy_state = g._player_energy_grid_state()
	check(not energy_state.powered[deficit_city], "diagonal infrastructure does not connect")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "BrokenSource", Vector2i(5, 5), true)
	deficit_city = add_energy_test_city(g, "BrokenSink", Vector2i(10, 5))
	powered_city.buildings["steam_turbine"] = true
	deficit_city.buildings["assembly_forge"] = true
	for x in [6, 7, 9]:
		g.grid.infra[x][5] = 1
	energy_state = g._player_energy_grid_state()
	check(not energy_state.powered[deficit_city], "broken cable splits the component")
	g.grid.infra[8][5] = 2
	energy_state = g._player_energy_grid_state()
	check(energy_state.powered[deficit_city], "monorail joins cable into one network")

	setup_energy_test(g)
	var bridge_city: City = add_energy_test_city(g, "Bridge", Vector2i(10, 10), true)
	var left_city: City = add_energy_test_city(g, "Left", Vector2i(7, 10))
	var right_city: City = add_energy_test_city(g, "Right", Vector2i(13, 10))
	bridge_city.buildings["steam_turbine"] = true
	left_city.buildings["assembly_forge"] = true
	right_city.buildings["assembly_forge"] = true
	for x in [8, 9, 11, 12]:
		g.grid.infra[x][10] = 1
	energy_state = g._player_energy_grid_state()
	check(energy_state.powered[left_city] and energy_state.powered[right_city],
		"city bridges two infrastructure branches")
	check(int(energy_state.available_energy) == 18,
		"city attached through multiple tiles contributes energy once")

	setup_energy_test(g)
	var adjacent_source: City = add_energy_test_city(g, "AdjacentSource", Vector2i(5, 5), true)
	var adjacent_sink: City = add_energy_test_city(g, "AdjacentSink", Vector2i(6, 5))
	adjacent_source.buildings["steam_turbine"] = true
	adjacent_sink.buildings["assembly_forge"] = true
	energy_state = g._player_energy_grid_state()
	check(energy_state.powered[adjacent_sink], "orthogonally adjacent friendly cities connect directly")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "ForeignSource", Vector2i(5, 5), true)
	deficit_city = add_energy_test_city(g, "ForeignSink", Vector2i(9, 5))
	var foreign_city := City.new("ForeignBridge", 1, g.factions[1], Vector2i(7, 5), g.grid)
	g.cities.append(foreign_city)
	g.grid.place_occupant(7, 5, foreign_city)
	powered_city.buildings["steam_turbine"] = true
	deficit_city.buildings["assembly_forge"] = true
	for x in range(6, 9):
		g.grid.infra[x][5] = 1
	energy_state = g._player_energy_grid_state()
	check(not energy_state.powered[deficit_city],
		"foreign occupied city cell blocks continuous infrastructure traversal")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "UpkeepCapital", Vector2i(5, 5), true)
	deficit_city = add_energy_test_city(g, "UpkeepPeer", Vector2i(15, 5))
	powered_city.buildings["steam_turbine"] = true
	deficit_city.buildings["steam_turbine"] = true
	var upkeep_unit := Unit.new("heavy_mech", 0, Vector2i(20, 20), g.grid)
	g.units.append(upkeep_unit)
	energy_state = g._player_energy_grid_state()
	check(int(energy_state.available_energy) == 35,
		"unit upkeep is subtracted exactly once from capital component")
	check(int(energy_state.fatigue_surplus[powered_city]) == 15 \
		and int(energy_state.fatigue_surplus[deficit_city]) == 20,
		"remote component does not pay capital component unit upkeep")

	setup_energy_test(g)
	var upkeep_capital: City = add_energy_test_city(g, "UpkeepBlackout", Vector2i(5, 5), true)
	var remote_powered: City = add_energy_test_city(g, "RemotePowered", Vector2i(15, 5))
	upkeep_capital.buildings["steam_turbine"] = true
	upkeep_capital.buildings["genesis_node"] = true
	remote_powered.buildings["steam_turbine"] = true
	remote_powered.buildings["genesis_node"] = true
	upkeep_capital.add_to_queue("net_shrine")
	remote_powered.add_to_queue("net_shrine")
	upkeep_capital.food_stock = Data.FOOD_PER_POP - 2
	remote_powered.food_stock = Data.FOOD_PER_POP - 2
	for i in range(5):
		g.units.append(Unit.new("heavy_mech", 0, Vector2i(20 + i, 20), g.grid))
	energy_state = g._player_energy_grid_state()
	check(not energy_state.powered[upkeep_capital] and energy_state.powered[remote_powered],
		"anchor upkeep blackout leaves disconnected remote component powered")
	check(int(energy_state.available_energy) == 23,
		"remote component retains its full surplus after anchor upkeep blackout")
	g.resources = { "scrap": 100, "biomass": 0, "energy": 0, "sol": 0 }
	g.end_turn()
	check(not upkeep_capital.has_building("net_shrine") and remote_powered.has_building("net_shrine"),
		"anchor blackout blocks build while remote powered city builds")
	check(upkeep_capital.population == 1 and remote_powered.population == 2,
		"anchor blackout blocks growth while remote powered city grows")
	check(g.resources.sol == 5 and g.resources.energy == 23,
		"anchor validator is offline while remote validator and surplus remain active")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "QuantumTax", Vector2i(5, 5), true)
	powered_city.buildings["steam_turbine"] = true
	powered_city.buildings["genesis_node"] = true
	powered_city.buildings["relic_validator"] = true
	g.wonders["quantum_cooler"] = true
	g.council_law = "energy_tax"
	energy_state = g._player_energy_grid_state()
	check(int(energy_state.available_energy) == 21,
		"Quantum Cooler removes validator upkeep before Council energy tax")

	setup_energy_test(g)
	var offline_bridge: City = add_energy_test_city(g, "OfflineBridge", Vector2i(10, 10), true)
	left_city = add_energy_test_city(g, "OfflineLeft", Vector2i(7, 10))
	right_city = add_energy_test_city(g, "OfflineRight", Vector2i(13, 10))
	left_city.buildings["steam_turbine"] = true
	right_city.buildings["assembly_forge"] = true
	offline_bridge.buildings["assembly_forge"] = true
	offline_bridge.offline_turns = 2
	for x in [8, 9, 11, 12]:
		g.grid.infra[x][10] = 1
	energy_state = g._player_energy_grid_state()
	check(energy_state.powered[right_city] and int(energy_state.available_energy) == 19,
		"offline city bridges networks but contributes and consumes zero")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "Operating", Vector2i(5, 5), true)
	deficit_city = add_energy_test_city(g, "Blackout", Vector2i(15, 5))
	powered_city.buildings["steam_turbine"] = true
	powered_city.buildings["genesis_node"] = true
	deficit_city.buildings["assembly_forge"] = true
	deficit_city.buildings["genesis_node"] = true
	deficit_city.buildings["cyber_forge"] = true
	powered_city.add_to_queue("net_shrine")
	deficit_city.add_to_queue("net_shrine")
	powered_city.food_stock = Data.FOOD_PER_POP - 2
	deficit_city.food_stock = Data.FOOD_PER_POP - 2
	g.resources = { "scrap": 100, "biomass": 0, "energy": 0, "sol": 0 }
	g.recompute_city_worked_tiles()
	var powered_income: Dictionary = powered_city.gather_total()
	var powered_build_cost: int = powered_city.faction.building_cost(
		int(Data.BUILDINGS.net_shrine.scrap_cost))
	g.end_turn()
	check(powered_city.has_building("net_shrine") and not deficit_city.has_building("net_shrine"),
		"only powered component processes build queue")
	check(powered_city.population == 2 and deficit_city.population == 1,
		"only powered component processes growth")
	check(g.resources.sol == 5, "only powered component validator mints SOL")
	check(g.resources.biomass == int(powered_income.food) \
		and g.resources.scrap == 100 - powered_build_cost + int(powered_income.scrap),
		"unpowered city produces no non-energy tile resources")

	setup_energy_test(g)
	deficit_city = add_energy_test_city(g, "GlobalPassives", Vector2i(15, 5), true)
	deficit_city.buildings["assembly_forge"] = true
	deficit_city.buildings["genesis_node"] = true
	deficit_city.buildings["cyber_forge"] = true
	g.tech.researched["atomic_reactor"] = true
	g.tech.researched["firedancer"] = true
	g.tech.researched["smart_contracts"] = true
	g.end_turn()
	check(g.resources.energy == 5 and g.resources.sol == 1,
		"global energy techs apply after component gating without powering validator")

	setup_energy_test(g)
	powered_city = add_energy_test_city(g, "SaveSource", Vector2i(5, 5), true)
	deficit_city = add_energy_test_city(g, "SaveSink", Vector2i(10, 5))
	powered_city.buildings["steam_turbine"] = true
	powered_city.buildings["genesis_node"] = true
	deficit_city.buildings["assembly_forge"] = true
	for x in range(6, 10):
		g.grid.infra[x][5] = 1
	energy_state = g._player_energy_grid_state()
	var network_before_path := "user://smoke_network_before.json"
	var network_after_path := "user://smoke_network_after.json"
	check(g.save_to_file(network_before_path), "snapshot game before read-only network status")
	var network_snapshot: Dictionary = g.network_status_snapshot()
	check(g.save_to_file(network_after_path), "snapshot game after read-only network status")
	check(read_text(network_before_path) == read_text(network_after_path),
		"network status snapshot does not mutate game state")
	check(int(network_snapshot.component_count) == energy_state.component_surpluses.size()
		and int(network_snapshot.available_energy) == int(energy_state.available_energy)
		and int(network_snapshot.unit_upkeep) == int(energy_state.unit_upkeep),
		"network status matches the existing component calculation")
	check(int(network_snapshot.powered_validators) == 1
		and int(network_snapshot.total_validators) == 1
		and int(network_snapshot.validators[0].base_output) == 5
		and network_snapshot.validators[0].reason == "Operational",
		"network status reports validator output and operating reason")
	powered_city.offline_turns = 1
	network_snapshot = g.network_status_snapshot()
	check(int(network_snapshot.powered_validators) == 0
		and int(network_snapshot.validators[0].base_output) == 0
		and network_snapshot.validators[0].reason == "City fatigue offline",
		"network status explains an offline validator without promising output")
	powered_city.offline_turns = 0
	var saved_component_energy: int = int(energy_state.available_energy)
	var energy_save_path := "user://smoke_energy_grid.json"
	check(g.save_to_file(energy_save_path), "save infrastructure energy component")
	check(g.load_from_file(energy_save_path), "load infrastructure energy component")
	energy_state = g._player_energy_grid_state()
	check(int(energy_state.available_energy) == saved_component_energy \
		and energy_state.powered[g.cities[0]] and energy_state.powered[g.cities[1]],
		"save/load infrastructure preserves derived component result")

	# --- 27. Minimal naval transport ---
	check(bool(Data.UNITS.steam_cruiser.naval) and int(Data.UNITS.steam_cruiser.transport_capacity) == 2,
		"Steam Cruiser is a data-driven two-unit naval transport")
	check(Data.TECHS.steam_synthesis.units.has("steam_cruiser"),
		"Steam Synthesis unlocks Steam Cruiser")
	setup_naval_test(g)
	var domain_carrier := add_naval_test_unit(g, "steam_cruiser", 0, Vector2i(5, 5), "ocean")
	var domain_land := add_naval_test_unit(g, "rust_guard", 0, Vector2i(4, 5), "wasteland")
	g.grid.terrain[6][5] = "ocean"
	g.grid.terrain[4][6] = "wasteland"
	check(domain_carrier.can_move_to(Vector2i(6, 5)) and not domain_carrier.can_move_to(Vector2i(4, 6)),
		"Steam Cruiser enters only ocean")
	check(not domain_land.can_move_to(Vector2i(6, 5)) and domain_land.can_move_to(Vector2i(4, 6)),
		"land passenger remains land-only")

	setup_naval_test(g)
	var coastal_city: City = add_energy_test_city(g, "Coastal", Vector2i(5, 5), true)
	g.grid.terrain[6][5] = "ocean"
	var resources_before: Dictionary = g.resources.duplicate()
	check(not g.train_unit(coastal_city, "steam_cruiser") and g.resources == resources_before,
		"Steam Cruiser training is locked before Steam Synthesis")
	g.tech.researched["steam_synthesis"] = true
	check(g.train_unit(coastal_city, "steam_cruiser"), "coastal city trains Steam Cruiser")
	var trained_carrier: Unit = find_unit_type(g, "steam_cruiser")
	check(trained_carrier != null and trained_carrier.cell == Vector2i(6, 5),
		"trained cruiser spawns on orthogonally adjacent ocean")
	setup_naval_test(g)
	var inland_city: City = add_energy_test_city(g, "Inland", Vector2i(10, 10), true)
	g.tech.researched["steam_synthesis"] = true
	resources_before = g.resources.duplicate()
	check(not g.train_unit(inland_city, "steam_cruiser") and g.resources == resources_before,
		"inland cruiser training fails without charging resources")
	var sol_before_jito: int = int(g.resources.sol)
	check(not g.jito_rush(inland_city, "unit", "steam_cruiser") and int(g.resources.sol) == sol_before_jito,
		"inland Jito rush fails before charging its fee")
	setup_naval_test(g)
	coastal_city = add_energy_test_city(g, "Poor Coast", Vector2i(5, 5), true)
	g.grid.terrain[6][5] = "ocean"
	g.tech.researched["steam_synthesis"] = true
	g.resources.scrap = int(Data.UNITS.steam_cruiser.scrap_cost) - 1
	resources_before = g.resources.duplicate()
	check(not g.jito_rush(coastal_city, "unit", "steam_cruiser") and g.resources == resources_before,
		"Jito rush rejects unaffordable normal unit cost without charging")

	setup_naval_test(g)
	var carrier := add_naval_test_unit(g, "steam_cruiser", 0, Vector2i(5, 5), "ocean")
	var passenger_one := add_naval_test_unit(g, "rust_guard", 0, Vector2i(4, 5), "wasteland")
	var passenger_two := add_naval_test_unit(g, "heavy_mech", 0, Vector2i(6, 5), "wasteland")
	var passenger_three := add_naval_test_unit(g, "miner_quad", 0, Vector2i(5, 4), "wasteland")
	var diagonal_passenger := add_naval_test_unit(g, "rust_guard", 0, Vector2i(4, 4), "wasteland")
	var enemy_passenger := add_naval_test_unit(g, "rust_guard", 1, Vector2i(5, 6), "wasteland")
	var naval_passenger := Unit.new("steam_cruiser", 0, Vector2i(5, 6), g.grid)
	var nested_passenger := Unit.new("rust_guard", 0, Vector2i(5, 6), g.grid)
	nested_passenger.cargo.append(Unit.new("rust_guard", 0, nested_passenger.cell, g.grid))
	g.units.append(naval_passenger)
	g.units.append(nested_passenger)
	passenger_one.moves_left = 0.34
	passenger_one.veteran = true
	passenger_one.fortified = true
	check(not g.load_unit(diagonal_passenger, carrier), "diagonal passenger cannot load")
	check(not g.load_unit(enemy_passenger, carrier), "enemy passenger cannot load")
	check(not g.load_unit(naval_passenger, carrier), "naval unit cannot load as cargo")
	check(not g.load_unit(nested_passenger, carrier), "cargo-in-cargo is rejected")
	var map_view: Node = load("res://scripts/ui/MapView.gd").new()
	g.select(carrier)
	map_view._handle_click(passenger_one.cell)
	check(carrier.cargo.has(passenger_one),
		"carrier-selected passenger tap loads through the natural MapView flow")
	check(passenger_one.cell == carrier.cell,
		"runtime loading immediately moves passenger state to the carrier cell")
	map_view.free()
	check(not g.units.has(passenger_one) and g.grid.occupant_at(4, 5) == null \
		and g.units.has(carrier) and g.grid.occupant_at(5, 5) == carrier,
		"loaded passenger leaves top-level units and grid while carrier remains")
	check(is_equal_approx(carrier.cargo[0].moves_left, 0.34) and carrier.cargo[0].veteran \
		and carrier.cargo[0].fortified, "loading preserves passenger state")
	check(g.load_unit(passenger_two, carrier) and carrier.cargo.size() == 2,
		"transport accepts two passengers")
	check(not g.load_unit(passenger_three, carrier), "full transport rejects third passenger")
	var occupied_target := Vector2i(5, 4)
	check(not g.unload_unit(carrier, occupied_target), "occupied land rejects unload")
	g._remove_unit(passenger_three)
	g._remove_unit(diagonal_passenger)
	g._remove_unit(enemy_passenger)
	g._remove_unit(naval_passenger)
	g._remove_unit(nested_passenger)
	check(g._player_unit_energy_upkeep() == 7, "cargo continues to pay energy upkeep")
	g.grid.terrain[5][6] = "ocean"
	check(not g.unload_unit(carrier, Vector2i(5, 6)), "ocean rejects unload")
	check(not g.unload_unit(carrier, Vector2i(4, 4)), "diagonal land rejects unload")
	check(g.unload_unit(carrier, Vector2i(4, 5)), "free orthogonally adjacent land unloads")
	check(g.units.has(passenger_one) and g.grid.occupant_at(4, 5) == passenger_one \
		and passenger_one.moves_left == 0 and passenger_one.veteran and passenger_one.fortified,
		"unload restores passenger with preserved state and zero moves")
	var destroyed_cargo: Unit = carrier.cargo[0]
	g._remove_unit(carrier)
	check(carrier.cargo.is_empty() and not g.units.has(destroyed_cargo),
		"carrier destruction destroys nested cargo")

	setup_naval_test(g)
	carrier = add_naval_test_unit(g, "steam_cruiser", 0, Vector2i(5, 5), "ocean")
	passenger_one = add_naval_test_unit(g, "miner_quad", 0, Vector2i(4, 5), "wasteland")
	passenger_one.moves_left = 1.5
	passenger_one.veteran = true
	check(g.load_unit(passenger_one, carrier), "load passenger for nested save")
	var naval_save_path := "user://smoke_naval_save.json"
	check(g.save_to_file(naval_save_path), "save nested cargo immediately after loading")
	check(g.load_from_file(naval_save_path), "load cargo saved immediately after loading")
	carrier = find_unit_type(g, "steam_cruiser")
	check(carrier != null and carrier.cargo.size() == 1 and carrier.cargo[0].cell == carrier.cell,
		"loaded passenger cell is restored to carrier cell immediately")
	check(not g.scrap_unit(carrier) and not g.upgrade_unit(carrier),
		"loaded carrier cannot be scrapped or upgraded")
	g.grid.terrain[6][5] = "ocean"
	carrier.moves_left = carrier.max_moves()
	check(carrier.try_move(Vector2i(6, 5)) and carrier.cargo[0].cell == carrier.cell,
		"nested cargo position follows its carrier")
	check(g.save_to_file(naval_save_path), "save nested naval cargo")
	check(g.load_from_file(naval_save_path), "load nested naval cargo")
	carrier = find_unit_type(g, "steam_cruiser")
	check(carrier != null and carrier.cargo.size() == 1 and carrier.cargo[0].type_id == "miner_quad" \
		and is_equal_approx(carrier.cargo[0].moves_left, 1.5) and carrier.cargo[0].veteran,
		"nested cargo state round-trips")
	check(occupancy_is_exact(g), "nested cargo is absent from grid occupancy")
	var naval_file := FileAccess.open(naval_save_path, FileAccess.READ)
	var naval_v3_data: Dictionary = JSON.parse_string(naval_file.get_as_text())
	naval_file.close()
	var overflow_cargo_data: Dictionary = naval_v3_data.duplicate(true)
	overflow_cargo_data.units[0].cargo.append(overflow_cargo_data.units[0].cargo[0].duplicate(true))
	overflow_cargo_data.units[0].cargo.append(overflow_cargo_data.units[0].cargo[0].duplicate(true))
	load_rejected_without_mutation(g, "user://smoke_cargo_overflow.json", overflow_cargo_data,
		"transport cargo over capacity")
	var wrong_faction_cargo_data: Dictionary = naval_v3_data.duplicate(true)
	wrong_faction_cargo_data.units[0].cargo[0]["faction"] = 1
	load_rejected_without_mutation(g, "user://smoke_cargo_faction.json", wrong_faction_cargo_data,
		"cargo faction mismatch")
	var naval_cargo_data: Dictionary = naval_v3_data.duplicate(true)
	naval_cargo_data.units[0].cargo[0]["type"] = "steam_cruiser"
	load_rejected_without_mutation(g, "user://smoke_naval_cargo.json", naval_cargo_data,
		"naval unit nested as cargo")
	var nested_cargo_data: Dictionary = naval_v3_data.duplicate(true)
	nested_cargo_data.units[0].cargo[0]["cargo"] = []
	load_rejected_without_mutation(g, "user://smoke_nested_cargo.json", nested_cargo_data,
		"nested cargo field")
	var malformed_cargo_data: Dictionary = naval_v3_data.duplicate(true)
	malformed_cargo_data.units[0].cargo[0]["moves"] = {}
	load_rejected_without_mutation(g, "user://smoke_malformed_cargo.json", malformed_cargo_data,
		"malformed cargo state")
	var missing_v3_cargo_data: Dictionary = naval_v3_data.duplicate(true)
	missing_v3_cargo_data.units[0].erase("cargo")
	load_rejected_without_mutation(g, "user://smoke_missing_v3_cargo.json", missing_v3_cargo_data,
		"missing v3 cargo field")
	var inland_carrier_data: Dictionary = naval_v3_data.duplicate(true)
	var carrier_x: int = int(inland_carrier_data.units[0].x)
	var carrier_y: int = int(inland_carrier_data.units[0].y)
	var naval_dims: Vector2i = Data.MAP_DIMENSIONS[int(inland_carrier_data.map_size)]
	inland_carrier_data.terrain[carrier_x * naval_dims.y + carrier_y] = "wasteland"
	load_rejected_without_mutation(g, "user://smoke_inland_carrier.json", inland_carrier_data,
		"naval unit saved on land")
	var ocean_land_unit_data: Dictionary = naval_v3_data.duplicate(true)
	ocean_land_unit_data.units[0]["type"] = "rust_guard"
	ocean_land_unit_data.units[0]["cargo"] = []
	load_rejected_without_mutation(g, "user://smoke_land_unit_ocean.json", ocean_land_unit_data,
		"land unit saved on ocean")
	var overlapping_units_data: Dictionary = naval_v3_data.duplicate(true)
	var overlapping_unit: Dictionary = overlapping_units_data.units[0].duplicate(true)
	overlapping_unit["cargo"] = []
	overlapping_units_data.units.append(overlapping_unit)
	load_rejected_without_mutation(g, "user://smoke_overlapping_units.json", overlapping_units_data,
		"overlapping top-level units")
	var overlapping_city_data: Dictionary = naval_v3_data.duplicate(true)
	overlapping_city_data.cities.append({
		"name": "Overlap", "faction": 0, "x": carrier_x, "y": carrier_y,
		"pop": 1, "food": 0, "scrap_stock": 0, "capital": false,
		"buildings": [], "queue": [], "fatigue": 0, "offline": 0, "dos": 0,
	})
	load_rejected_without_mutation(g, "user://smoke_overlapping_city.json", overlapping_city_data,
		"top-level unit and city overlap")
	var legacy_naval_data: Dictionary = naval_v3_data.duplicate(true)
	legacy_naval_data["version"] = 2
	legacy_naval_data.erase("ai_agendas")
	legacy_naval_data.erase("monopoly_progress")
	legacy_naval_data["diplomacy"] = {"1": g.relation_status(0, 1)}
	legacy_naval_data["ping"] = {"1": g.relation_ping(0, 1)}
	for unit_data in legacy_naval_data.units:
		unit_data.erase("cargo")
	var legacy_naval_path := "user://smoke_naval_v2.json"
	check(write_json(legacy_naval_path, legacy_naval_data), "write v2 save without cargo")
	check(g.load_from_file(legacy_naval_path), "v2 save without cargo loads")
	carrier = find_unit_type(g, "steam_cruiser")
	check(carrier != null and carrier.cargo.is_empty(), "v2 cargo default is empty")

	g.start_game(Data.MapSize.SMALL, Data.MapType.ARCHIPELAGO, 6401, "rust_tech")
	g.units.clear()
	g.cities.clear()
	g.grid.clear_occupants()
	var crossing: Array = find_archipelago_crossing(g.grid)
	check(crossing.size() == 4, "deterministic Archipelago fixture has a cross-water route")
	if crossing.size() == 4:
		passenger_one = add_naval_test_unit(g, "rust_guard", 0, crossing[0], "wasteland")
		carrier = add_naval_test_unit(g, "steam_cruiser", 0, crossing[1], "ocean")
		check(g.load_unit(passenger_one, carrier), "Archipelago passenger boards at first shore")
		carrier.moves_left = carrier.max_moves()
		check(carrier.try_move(crossing[2]), "Archipelago cruiser crosses ocean")
		check(g.unload_unit(carrier, crossing[3]), "Archipelago passenger unloads on opposite shore")

	# --- 28. Save v3: faction roster round-trip ---
	var faction_save_path := "user://smoke_faction_save.json"
	for faction_key in Data.FACTIONS:
		var player_faction: String = str(faction_key)
		g.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 5100, player_faction)
		var roster_before: Array = g._faction_ids()
		check(g.save_to_file(faction_save_path), "save faction %s" % player_faction)
		check(g.load_from_file(faction_save_path), "load faction %s" % player_faction)
		check(g.factions[g.faction_id].id == player_faction, "player faction restored: %s" % player_faction)
		check(g._faction_ids() == roster_before, "full faction roster restored: %s" % player_faction)
	var all_faction_ids: Array = Data.FACTIONS.keys()
	g.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 5101, "dao", all_faction_ids)
	var canonical_faction_ids: Array = ["dao"]
	for faction_value in all_faction_ids:
		if str(faction_value) != "dao":
			canonical_faction_ids.append(str(faction_value))
	g.diplomacy[1] = "war"
	g.ping[1] = 23
	g.diplomacy[2] = "alliance"
	g.ping[2] = 88
	check(g.save_to_file(faction_save_path), "save five-faction roster")
	check(g.load_from_file(faction_save_path), "load five-faction roster")
	check(g._faction_ids() == canonical_faction_ids, "player-first five-faction roster restored")
	check(g.faction_id == 0 and g.factions[0].id == "dao" and g.factions[0].is_player,
		"player invariant restored at faction index 0")
	var ai_marked_player := false
	for faction_idx in range(1, g.factions.size()):
		if g.factions[faction_idx].is_player:
			ai_marked_player = true
	check(not ai_marked_player, "no AI faction is marked as player")
	check(g.diplomacy.has("0:1") and g.diplomacy["0:1"] == "war",
		"war status restores with canonical pair key")
	check(g.diplomacy.has("0:2") and g.diplomacy["0:2"] == "alliance", "alliance status round-trip")
	check(g.ping.has("0:1") and g.ping["0:1"] == 23 and g.ping["0:2"] == 88,
		"ping values restore with canonical pair keys")

	# --- 29. Random map resolution and identity ---
	var random_save_path := "user://smoke_random_save.json"
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.RANDOM, 5200)
	var resolved_type: int = g._map_type
	var terrain_before: String = JSON.stringify(g.grid.terrain)
	var terminals_before: Array = g.terminals.duplicate()
	var lairs_before: Array = g.lairs.duplicate()
	var city_cells_before: Array = []
	for random_city in g.cities:
		city_cells_before.append(random_city.cell)
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.RANDOM, 5200)
	check(g._map_type == resolved_type, "Random resolves deterministically")
	check(JSON.stringify(g.grid.terrain) == terrain_before, "Random terrain matches same seed")
	check(g.terminals == terminals_before, "Random terminals match same seed")
	check(g.lairs == lairs_before, "Random lairs match same seed")
	var city_cells_after: Array = []
	for random_city in g.cities:
		city_cells_after.append(random_city.cell)
	check(city_cells_after == city_cells_before, "Random faction spawns match same seed")
	check(g.save_to_file(random_save_path), "save resolved Random map")
	check(g.load_from_file(random_save_path), "load resolved Random map")
	check(g._map_type == resolved_type, "resolved map type restored")
	check(JSON.stringify(g.grid.terrain) == terrain_before, "saved terrain restored exactly")

	# --- 30. RNG continuation across save/load ---
	check(g.save_to_file(random_save_path), "save RNG state")
	var expected_random: Array = []
	for i in range(32):
		expected_random.append(g.gameplay_randi_range(-1000000, 1000000))
	check(g.load_from_file(random_save_path), "load RNG state")
	var actual_random: Array = []
	for i in range(32):
		actual_random.append(g.gameplay_randi_range(-1000000, 1000000))
	check(actual_random == expected_random, "next 32 RNG outcomes match after load")
	g.units[0].moves_left = 0.5
	check(g.save_to_file(random_save_path), "save fractional unit movement")
	check(g.load_from_file(random_save_path), "load fractional unit movement")
	check(is_equal_approx(g.units[0].moves_left, 0.5), "fractional unit movement round-trip")

	# --- 31. Real v1 shape and validation-before-mutation ---
	var source_file := FileAccess.open(random_save_path, FileAccess.READ)
	var valid_v2_data: Dictionary = JSON.parse_string(source_file.get_as_text())
	source_file.close()
	var legacy_data: Dictionary = valid_v2_data.duplicate(true)
	legacy_data["version"] = 1
	legacy_data["map_type"] = Data.MapType.RANDOM
	legacy_data.erase("rng_state")
	legacy_data.erase("resolved_map_type")
	legacy_data.erase("requested_map_type")
	legacy_data.erase("terrain")
	legacy_data.erase("trade_used")
	legacy_data.erase("ai_agendas")
	legacy_data.erase("monopoly_progress")
	var legacy_diplomacy := {}
	var legacy_ping := {}
	for legacy_idx in range(1, legacy_data.factions.size()):
		legacy_diplomacy[str(legacy_idx)] = g.relation_status(0, legacy_idx)
		legacy_ping[str(legacy_idx)] = g.relation_ping(0, legacy_idx)
	legacy_data["diplomacy"] = legacy_diplomacy
	legacy_data["ping"] = legacy_ping
	for legacy_unit_data in legacy_data.units:
		legacy_unit_data.erase("cargo")
	var legacy_path := "user://smoke_legacy_save.json"
	check(write_json(legacy_path, legacy_data), "write legacy v1 fixture")
	check(g.load_from_file(legacy_path), "legacy v1 save loads with defaults")
	var legacy_resolved_type: int = g._map_type
	var legacy_terrain: String = JSON.stringify(g.grid.terrain)
	check(g._faction_ids() == legacy_data.factions, "legacy v1 faction roster restored")
	check(g.load_from_file(legacy_path), "legacy v1 Random reloads")
	check(g._map_type == legacy_resolved_type and JSON.stringify(g.grid.terrain) == legacy_terrain,
		"legacy v1 Random uses deterministic fallback")
	var future_data: Dictionary = legacy_data.duplicate(true)
	future_data["version"] = g.SAVE_VERSION + 1
	var future_path := "user://smoke_future_save.json"
	load_rejected_without_mutation(g, future_path, future_data, "future save version")
	var unknown_faction_data: Dictionary = valid_v2_data.duplicate(true)
	unknown_faction_data.factions[1] = "unknown_faction"
	load_rejected_without_mutation(g, "user://smoke_unknown_faction.json", unknown_faction_data,
		"unknown faction ID")
	var nonzero_player_data: Dictionary = valid_v2_data.duplicate(true)
	nonzero_player_data["faction_id"] = 1
	load_rejected_without_mutation(g, "user://smoke_nonzero_player.json", nonzero_player_data,
		"nonzero player faction index")
	var invalid_map_size_data: Dictionary = valid_v2_data.duplicate(true)
	invalid_map_size_data["map_size"] = 99
	load_rejected_without_mutation(g, "user://smoke_invalid_map_size.json", invalid_map_size_data,
		"invalid map size")
	var map_size_object_data: Dictionary = valid_v2_data.duplicate(true)
	map_size_object_data["map_size"] = {}
	load_rejected_without_mutation(g, "user://smoke_object_map_size.json", map_size_object_data,
		"object map size")
	var invalid_map_type_data: Dictionary = valid_v2_data.duplicate(true)
	invalid_map_type_data["resolved_map_type"] = 99
	load_rejected_without_mutation(g, "user://smoke_invalid_map_type.json", invalid_map_type_data,
		"invalid resolved map type")
	var short_terrain_data: Dictionary = valid_v2_data.duplicate(true)
	short_terrain_data.terrain.pop_back()
	load_rejected_without_mutation(g, "user://smoke_short_terrain.json", short_terrain_data,
		"short terrain array")
	var unknown_terrain_data: Dictionary = valid_v2_data.duplicate(true)
	unknown_terrain_data.terrain[0] = "unknown_terrain"
	load_rejected_without_mutation(g, "user://smoke_unknown_terrain.json", unknown_terrain_data,
		"unknown terrain ID")
	var short_infra_data: Dictionary = valid_v2_data.duplicate(true)
	short_infra_data.infra.pop_back()
	load_rejected_without_mutation(g, "user://smoke_short_infra.json", short_infra_data,
		"short infrastructure array")
	var short_improvements_data: Dictionary = valid_v2_data.duplicate(true)
	short_improvements_data.improvements.pop_back()
	load_rejected_without_mutation(g, "user://smoke_short_improvements.json", short_improvements_data,
		"short improvements array")
	var array_unit_type_data: Dictionary = valid_v2_data.duplicate(true)
	array_unit_type_data.units[0]["type"] = []
	load_rejected_without_mutation(g, "user://smoke_array_unit_type.json", array_unit_type_data,
		"array unit type")
	var empty_resources_data: Dictionary = valid_v2_data.duplicate(true)
	empty_resources_data["resources"] = {}
	load_rejected_without_mutation(g, "user://smoke_empty_resources.json", empty_resources_data,
		"empty resources")
	var object_council_law_data: Dictionary = valid_v2_data.duplicate(true)
	object_council_law_data["council_law"] = {}
	load_rejected_without_mutation(g, "user://smoke_object_council_law.json", object_council_law_data,
		"object council law")

	print("=== SMOKE TEST %s (failures: %d) ===" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: " + msg)
	else:
		failures += 1
		print("  FAIL: " + msg)


func buttons_meet_accessibility(panel: Node) -> bool:
	var buttons: Array[Node] = panel.find_children("*", "Button", true, false)
	if buttons.is_empty():
		return false
	for node in buttons:
		var button := node as Button
		if button == null or button.size.y < 44.0 or button.get_theme_font_size("font_size") < 14:
			return false
	return true


func text_meets_accessibility(panel: Node) -> bool:
	var labels: Array[Node] = panel.find_children("*", "Label", true, false)
	for node in labels:
		var label := node as Label
		if label != null and label.is_visible_in_tree() \
				and label.get_theme_font_size("font_size") < 14:
			return false
	var rich_labels: Array[Node] = panel.find_children("*", "RichTextLabel", true, false)
	for node in rich_labels:
		var rich_label := node as RichTextLabel
		if rich_label != null and rich_label.is_visible_in_tree() \
				and rich_label.get_theme_font_size("normal_font_size") < 14:
			return false
	return true


func primary_panels_inside_viewport(ui: Node, viewport_size: Vector2i) -> bool:
	for panel_name in [
		"TopHUD", "SelectionPanel", "LogPanel", "BottomNav", "MenuPanel", "CityActions",
		"DipPanel", "TechPanel", "TechDetailPanel", "GlossaryPanel", "NetworkStatusPanel",
		"GameOverPanel",
	]:
		var panel := ui.get_node_or_null(panel_name) as Control
		if panel == null or not panel.is_visible_in_tree():
			continue
		var rect: Rect2 = panel.get_global_rect()
		if rect.position.x < -0.5 or rect.position.y < -0.5 \
				or rect.end.x > float(viewport_size.x) + 0.5 \
				or rect.end.y > float(viewport_size.y) + 0.5:
			return false
	return true


func interactive_controls_fit_width(ui: Node, viewport_size: Vector2i) -> bool:
	for control_type in ["Button", "LineEdit"]:
		var controls: Array[Node] = ui.find_children("*", control_type, true, false)
		for node in controls:
			var control := node as Control
			if control == null or not control.is_visible_in_tree():
				continue
			# Horizontally scrollable trees deliberately keep later-era controls offscreen;
			# their ScrollContainer clips them into the viewport.
			var ancestor := control.get_parent()
			var inside_horizontal_scroll := false
			while ancestor != null and ancestor != ui:
				if ancestor is ScrollContainer \
						and (ancestor as ScrollContainer).horizontal_scroll_mode \
						!= ScrollContainer.SCROLL_MODE_DISABLED:
					inside_horizontal_scroll = true
					break
				ancestor = ancestor.get_parent()
			if inside_horizontal_scroll:
				continue
			var rect: Rect2 = control.get_global_rect()
			if rect.position.x < -0.5 or rect.end.x > float(viewport_size.x) + 0.5:
				return false
	return true


func critical_panels_have_scroll(ui: Node) -> bool:
	var required := {
		"SelectionPanel": "SelectionScroll",
		"MenuPanel": "MenuScroll",
		"CityActions": "CityActionsScroll",
		"DipPanel": "DiplomacyScroll",
		"TechPanel": "TechScroll",
		"TechDetailPanel": "TechDetailScroll",
		"GlossaryPanel": "GlossaryScroll",
		"NetworkStatusPanel": "NetworkStatusScroll",
	}
	for panel_name in required:
		var panel := ui.get_node_or_null(panel_name)
		if panel == null or panel.find_child(required[panel_name], true, false) == null:
			return false
	return true


func direct_named_child_count(parent: Node, child_name: String) -> int:
	var count := 0
	for child in parent.get_children():
		if child.name == child_name:
			count += 1
	return count


func push_pointer_click(viewport: Viewport, position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		viewport.push_input(event, true)


func make_touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func make_drag(index: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	return event


func make_mouse_button(position: Vector2, button: MouseButton,
		pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	return event


func make_mouse_motion(position: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	return event


func controls_inside_rect(parent: Node, names: Array, bounds: Rect2) -> bool:
	for control_name in names:
		var control := parent.get_node_or_null(control_name) as Control
		if control != null and not control.is_visible_in_tree():
			continue
		if control == null or not bounds.encloses(control.get_global_rect()):
			print("    safe rect miss: %s rect=%s bounds=%s" % [
				control_name, control.get_global_rect() if control != null else Rect2(), bounds])
			return false
	return true


func hard_modal_contents_inside_rect(ui: Node, bounds: Rect2) -> bool:
	for panel_name in [
		"MenuPanel", "GameOverPanel", "TechPanel", "TechDetailPanel", "GlossaryPanel", "NetworkStatusPanel",
	]:
		var blocker := ui.get_node_or_null(panel_name)
		if blocker == null:
			continue
		var content := blocker.get_node_or_null("Content") as Control
		if content == null or not bounds.encloses(content.get_global_rect()):
			print("    hard content miss: %s rect=%s bounds=%s" % [
				panel_name, content.get_global_rect() if content != null else Rect2(), bounds])
			return false
	return true


func visible_hard_modals_cover_viewport(ui: Node, viewport_size: Vector2i) -> bool:
	for panel_name in [
		"MenuPanel", "GameOverPanel", "TechPanel", "TechDetailPanel", "GlossaryPanel", "NetworkStatusPanel",
	]:
		var blocker := ui.get_node_or_null(panel_name) as Control
		if blocker == null:
			continue
		var rect := blocker.get_global_rect()
		if blocker.mouse_filter != Control.MOUSE_FILTER_STOP \
				or rect.position.distance_to(Vector2.ZERO) > 0.5 \
				or rect.size.distance_to(Vector2(viewport_size)) > 0.5:
			return false
	return true


func hard_modals_block_full_viewport(ui: Node, viewport_size: Vector2i) -> bool:
	for panel_name in [
		"MenuPanel", "GameOverPanel", "TechPanel", "TechDetailPanel", "GlossaryPanel", "NetworkStatusPanel",
	]:
		var blocker := ui.get_node_or_null(panel_name) as Control
		if blocker == null or blocker.mouse_filter != Control.MOUSE_FILTER_STOP:
			return false
		var rect: Rect2 = blocker.get_global_rect()
		if rect.position.distance_to(Vector2.ZERO) > 0.5 \
				or absf(rect.size.x - float(viewport_size.x)) > 0.5 \
				or absf(rect.size.y - float(viewport_size.y)) > 0.5:
			return false
	return true


func occupancy_is_exact(g: Node) -> bool:
	var expected: Dictionary = {}
	for u in g.units:
		expected[u] = true
		if g.grid.occupant_at(u.cell.x, u.cell.y) != u:
			return false
	for c in g.cities:
		expected[c] = true
		if g.grid.occupant_at(c.cell.x, c.cell.y) != c:
			return false
	var observed: int = 0
	for x in g.grid.w:
		for y in g.grid.h:
			var occupant: Variant = g.grid.occupant_at(x, y)
			if occupant != null:
				observed += 1
				if not expected.has(occupant):
					return false
	return observed == expected.size()


func setup_energy_test(g: Node) -> void:
	g.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 6001, "rust_tech")
	g.units.clear()
	g.cities.clear()
	g.grid.clear_occupants()
	for x in g.grid.w:
		for y in g.grid.h:
			g.grid.infra[x][y] = 0
			g.grid.terrain[x][y] = "wasteland"
	g.resources = { "scrap": 0, "biomass": 0, "energy": 0, "sol": 0 }
	g.tech.researched.clear()
	g.tech.current = ""
	g.tech.points = 0
	g.protocol = "central"
	g.wonders.clear()
	g.artifacts.clear()
	g.council_law = ""
	g.event_active = ""
	g.next_event_turn = 1000000


func setup_naval_test(g: Node) -> void:
	setup_energy_test(g)
	g.resources = { "scrap": 1000, "biomass": 1000, "energy": 1000, "sol": 1000 }


func add_naval_test_unit(g: Node, type_id: String, faction: int, cell: Vector2i,
		terrain_id: String) -> Unit:
	g.grid.terrain[cell.x][cell.y] = terrain_id
	var unit := Unit.new(type_id, faction, cell, g.grid)
	g.units.append(unit)
	g.grid.place_occupant(cell.x, cell.y, unit)
	return unit


func find_unit_type(g: Node, type_id: String) -> Unit:
	for unit in g.units:
		if unit.type_id == type_id:
			return unit
	return null


func find_archipelago_crossing(grid: GridManager) -> Array:
	for y in grid.h:
		for x in range(grid.w - 3):
			if grid.is_land(x, y) and grid.is_water(x + 1, y) \
					and grid.is_water(x + 2, y) and grid.is_land(x + 3, y):
				return [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y), Vector2i(x + 3, y)]
	for x in grid.w:
		for y in range(grid.h - 3):
			if grid.is_land(x, y) and grid.is_water(x, y + 1) \
					and grid.is_water(x, y + 2) and grid.is_land(x, y + 3):
				return [Vector2i(x, y), Vector2i(x, y + 1), Vector2i(x, y + 2), Vector2i(x, y + 3)]
	return []


func add_energy_test_city(g: Node, city_name: String, cell: Vector2i, capital: bool = false) -> City:
	var city := City.new(city_name, 0, g.factions[0], cell, g.grid)
	city.is_capital = capital
	g.cities.append(city)
	g.grid.place_occupant(cell.x, cell.y, city)
	return city


func write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func load_rejected_without_mutation(g: Node, path: String, data: Dictionary, label: String) -> void:
	var before_path := "user://smoke_active_before.json"
	var after_path := "user://smoke_active_after.json"
	check(g.save_to_file(before_path), "snapshot active game before: %s" % label)
	var state_before: String = read_text(before_path)
	check(write_json(path, data), "write corrupt fixture: %s" % label)
	check(not g.load_from_file(path), "reject corrupt save: %s" % label)
	check(g.save_to_file(after_path), "snapshot active game after: %s" % label)
	check(read_text(after_path) == state_before, "failed load preserves full active game: %s" % label)


func read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
