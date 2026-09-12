extends SceneTree
## Focused acceptance for the unified, progressive-disclosure secondary surfaces.

var failures := 0
var game: Node
var ui_script: GDScript


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	ui_script = load("res://scripts/ui/GameUI.gd")
	for size in [Vector2i(575, 1280), Vector2i(720, 1280)]:
		await _run_size(size)
	print("SECONDARY_SURFACES_%s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _run_size(size: Vector2i) -> void:
	game.start_game(Data.MapSize.SMALL, Data.MapType.CONTINENTS, 94400 + size.x,
		"rust_tech", ["rust_tech", "global_net", "dao"])
	game.resources.sol = 1000
	game.resources.scrap = 1000
	game.tech.researched["primitive_coding"] = true
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var ui = ui_script.new()
	ui.name = "UI"
	viewport.add_child(ui)
	await process_frame
	ui._set_match_chrome_visible(true)
	ui._close_overlay("MenuPanel")
	await process_frame

	var unit: Unit = _player_unit()
	game.select(unit)
	game.set_relation_ping(0, 1, 20)
	await process_frame
	var before := _snapshot()
	var selection: Node = ui.get_node("SelectionPanel")
	var info := selection.find_child("SelectionInfo", true, false) as Button
	_check(info != null and info.visible and info.size.y >= 48.0,
		"%d unit uses one touch-sized i disclosure" % size.x)
	_check(selection.find_child("FounderAction", true, false) != null,
		"%d unit sheet retains one contextual action slot" % size.x)
	info.emit_signal("pressed")
	await process_frame
	_check((selection.find_child("SelectionScroll", true, false) as Control).visible,
		"%d unit i reveals supporting detail" % size.x)
	info.emit_signal("pressed")

	ui._toggle_tech_panel()
	await process_frame
	var manual: Node = ui.get_node("TechPanel")
	await _press_text(manual, "PROTOCOLS")
	_check(manual.find_children("ProtocolCard_*", "PanelContainer", true, false).size()
		== Data.PROTOCOL_NAMES.size(), "%d protocols are concise cards" % size.x)
	for card in manual.find_children("ProtocolCard_*", "PanelContainer", true, false):
		_check(card.find_children("ProtocolAction", "Button", true, false).size() == 1,
			"%d protocol card has one primary action" % size.x)
	await _press_text(manual, "WONDERS")
	_check(manual.find_children("WonderCard_*", "PanelContainer", true, false).size()
		== Data.WONDERS.size(), "%d wonders are concise cards" % size.x)
	ui._close_overlay("TechPanel")

	ui._show_glossary()
	await process_frame
	var glossary: Node = ui.get_node("GlossaryPanel")
	_check(glossary.find_children("GlossaryCard_*", "PanelContainer", true, false).size()
		== EducationData.GLOSSARY.size(), "%d glossary preserves every verified term" % size.x)
	_check(glossary.find_children("GlossarySource", "LinkButton", true, false).size()
		== EducationData.GLOSSARY.size(), "%d glossary sources live behind i" % size.x)
	ui._close_overlay("GlossaryPanel")

	ui._show_network_status()
	await process_frame
	var network: Node = ui.get_node("NetworkStatusPanel")
	_check(network.find_child("NetworkSummary", true, false) != null,
		"%d network begins with operational summary" % size.x)
	_check(network.find_children("NetworkComponent_*", "PanelContainer", true, false).size() > 0,
		"%d network exposes component rows" % size.x)
	ui._close_overlay("NetworkStatusPanel")

	ui._toggle_diplomacy_panel()
	await process_frame
	var diplomacy: Node = ui.get_node("DipPanel")
	var rival_cards: Array[Node] = diplomacy.find_children("RivalCard_*", "PanelContainer", true, false)
	_check(rival_cards.size() == game.factions.size() - 1,
		"%d diplomacy has one card per rival" % size.x)
	for card in rival_cards:
		_check(card.find_children("DiplomacyPrimaryAction", "Button", true, false).size() == 1,
			"%d rival first level has one primary action" % size.x)
	var first_primary := rival_cards[0].find_child("DiplomacyPrimaryAction", true, false) as Button
	_check(first_primary.disabled and first_primary.text == "PROPOSE ALLIANCE",
		"%d diplomacy exposes the ping gate before action" % size.x)
	_check(_buttons_with_text(diplomacy, "DECLARE WAR") == 0,
		"%d diplomacy removed the six-button action wall" % size.x)
	ui._close_overlay("DipPanel")

	ui.show_game_over(game.factions[0].name, "all validators controlled")
	await process_frame
	var game_over: Node = ui.get_node("GameOverPanel")
	_check(game_over.find_child("OutcomeStats", true, false) != null,
		"%d game over shows concise match stats" % size.x)
	_check(game_over.find_children("*Button", "Button", true, false).size() == 2,
		"%d game over exposes only two recovery actions" % size.x)
	ui._handle_ui_cancel()
	_check(ui.get_node_or_null("GameOverPanel") != null,
		"%d Back cannot dismiss terminal outcome" % size.x)
	_check(_snapshot() == before, "%d browsing secondary surfaces never mutates simulation" % size.x)
	_check(_touch_targets_ok(ui), "%d visible controls meet 48px touch targets" % size.x)
	viewport.queue_free()
	await process_frame


func _press_text(root_node: Node, text: String) -> void:
	for node in root_node.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			(node as Button).emit_signal("pressed")
			await process_frame
			return


func _buttons_with_text(root_node: Node, text: String) -> int:
	var count := 0
	for node in root_node.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			count += 1
	return count


func _touch_targets_ok(root_node: Node) -> bool:
	for node in root_node.find_children("*", "BaseButton", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.size.y < 48.0:
			return false
	return true


func _player_unit() -> Unit:
	for unit in game.units:
		if unit.faction_id == game.faction_id:
			return unit
	return null


func _snapshot() -> Dictionary:
	return {
		"turn": game.turn,
		"resources": game.resources.duplicate(true),
		"protocol": game.protocol,
		"wonders": game.wonders.duplicate(true),
		"diplomacy": game.diplomacy.duplicate(true),
		"ping": game.ping.duplicate(true),
		"trade": game.trade_used,
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok: " + message)
	else:
		failures += 1
		print("  FAIL: " + message)
