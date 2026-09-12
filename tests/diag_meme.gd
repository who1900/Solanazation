extends SceneTree
## Diagnostics: meme + turbine.

func _init() -> void:
	await process_frame
	var g = root.get_node_or_null("Game")
	if g == null:
		g = load("res://scripts/GameRoot.gd").new()
		root.add_child(g)
	await process_frame
	g.start_game(Data.MapSize.MEDIUM, Data.MapType.PANGAEA, 3003)
	await process_frame
	var c: City = g.cities[0]
	c.buildings["steam_turbine"] = true
	print("energy_prod=%d upkeep=%d" % [c.energy_production(), c.energy_upkeep_total()])
	g.event_active = "meme"
	g.event_turns_left = 2
	g.meme_city_idx = 0
	print("sol before=%d" % g.resources.sol)
	g.end_turn()
	await process_frame
	print("sol after=%d" % g.resources.sol)
	print("protocol=%s prot_data=%s" % [g.protocol, Data.PROTOCOLS[g.protocol]])
	quit(0)
