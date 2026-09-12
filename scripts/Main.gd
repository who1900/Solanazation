extends Node2D
## Main — root scene: game start, city selection -> action panel.


func _ready() -> void:
	Game.selection_changed.connect(_on_selection)
	Game.game_over.connect(func(wn, r): $UI.show_game_over(wn, r))
	# Background + star dust
	RenderingServer.set_default_clear_color(Color(0.07, 0.08, 0.1))
	var dust := CPUParticles2D.new()
	dust.amount = 60
	dust.lifetime = 6.0
	dust.one_shot = false
	dust.emitting = true
	dust.position = Vector2(360, 640)
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 14.0
	dust.gravity = Vector2(0, 0)
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.4
	dust.color = Color(0.8, 0.9, 1.0, 0.35)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(720, 1280)
	add_child(dust)
	# Music (if ambient.ogg exists)
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.start_music()
	# Main menu first
	$UI.show_menu()


func _on_selection(obj) -> void:
	# Selection details live in the conditional bottom sheet. City actions open
	# explicitly from that sheet instead of covering the map on every city tap.
	if not (obj is City):
		$UI.build_city_actions(null)
