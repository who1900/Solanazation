extends SceneTree
## ASCII map preview (generation check without rendering).
## Run: godot --headless --path . -s res://tests/map_preview.gd

func _init() -> void:
	await process_frame
	var g = root.get_node_or_null("Game")
	if g == null:
		g = load("res://scripts/GameRoot.gd").new()
		root.add_child(g)
	await process_frame

	var size := Data.MapSize.MEDIUM
	var mtype := Data.MapType.EARTH
	if OS.get_cmdline_user_args().size() > 0:
		var t: String = OS.get_cmdline_user_args()[0]
		for k in Data.MAP_TYPE_NAMES:
			if Data.MAP_TYPE_NAMES[k].to_lower() == t.to_lower():
				mtype = k
				break
	g.start_game(size, mtype, 42)
	await process_frame

	print("=== MAP: %s (%dx%d) seed 42 ===" % [Data.MAP_TYPE_NAMES[mtype], g.grid.w, g.grid.h])
	var chars := {"ocean": "~", "wasteland": ".", "ruins": "R", "swamp": "S", "node_zone": "N"}
	var out := ""
	for y in g.grid.h:
		var line := ""
		for x in g.grid.w:
			line += chars[g.grid.terrain[x][y]]
		out += line + "\n"
	print(out)
	quit(0)
