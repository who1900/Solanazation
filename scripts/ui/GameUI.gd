extends CanvasLayer
## GameUI — HUD: resources, turn, selection, buttons, log.

const BrandTheme = preload("res://scripts/ui/BrandTheme.gd")
const WorldArt = preload("res://scripts/ui/WorldArt.gd")
const MotionFeedback = preload("res://scripts/ui/MotionFeedback.gd")
const TechTreeView = preload("res://scripts/ui/TechTreeView.gd")
const FONT_SIZE := 16
const PAUSE_AUTOSAVE_PATH := "user://pause_autosave.json"
const BOTTOM_NAV_CLEARANCE := 168.0
const COLOR_VOID := BrandTheme.BACKGROUND
const COLOR_GRAPHITE := BrandTheme.CARD
const COLOR_STEEL := BrandTheme.SECONDARY
const COLOR_BONE := BrandTheme.FOREGROUND
const COLOR_MUTED := BrandTheme.MUTED_FOREGROUND
const COLOR_CYAN := BrandTheme.PRIMARY
const COLOR_AMBER := BrandTheme.WARNING
const COLOR_RED := BrandTheme.DESTRUCTIVE
## Android Back/UI_CANCEL closes the first visible entry, then selection.
## Game Over is terminal: Back is consumed until Restart or New Game is chosen.
const BACK_PANEL_PRIORITY := [
	"GlossaryPanel", "NetworkStatusPanel", "TechDetailPanel",
	"DipPanel", "TechPanel", "CityActions",
]

var _resource_labels: Dictionary = {}
var _turn_label: Label
var _detail: RichTextLabel
var _log_label: Label
var _log_lines: Array = []
var event_label: Label
var _end_hold: Button
var _end_progress: ProgressBar
var _holding_end := false
var _hold_timer := 0.0
var _safe_rect_override: Variant = null
var _application_paused := false
var _ui_theme: Theme
var _top_hud: PanelContainer
var _selection_panel: PanelContainer
var _selection_title: Label
var _selection_toggle: Button
var _selection_actions: Button
var _selection_city_action: Button
var _selection_scroll: ScrollContainer
var _selection_summary_detail: RichTextLabel
var _selection_box: VBoxContainer
var _queue_feedback: VBoxContainer
var _queue_label: Label
var _queue_progress: ProgressBar
var _selection_expanded := false
var _selection_full_text := ""
var _selection_summary_text := ""
var _selection_has_actions := false
var _log_panel: PanelContainer
var _bottom_nav: PanelContainer
var _next_action: Button
var _log_generation := 0
var _turn_cue: PanelContainer
var _turn_cue_row: HBoxContainer
var _turn_progress_label: Label
var _turn_cue_generation := 0
var _suppress_next_turn_summary := false
var _suppress_selected_build_log := ""
var _last_animated_turn := -1
var _turn_label_tween: Tween
var _external_url_opener: Callable


func _ready() -> void:
	if not _external_url_opener.is_valid():
		_external_url_opener = Callable(OS, "shell_open")
	_ui_theme = _build_theme()
	_build_ui()
	_apply_responsive_metrics()
	get_viewport().size_changed.connect(_apply_safe_area)
	Game.resources_changed.connect(_update_resources)
	Game.turn_changed.connect(_update_turn)
	Game.selection_changed.connect(_update_selection)
	Game.unit_moved.connect(func(_unit): _refresh_next_action())
	Game.unit_orders_changed.connect(func(_unit): _refresh_next_action())
	Game.city_changed.connect(func(_city): _refresh_next_action())
	Game.log_message.connect(_add_log)
	Game.match_ready.connect(func():
		_cancel_motion_feedback()
		_last_animated_turn = Game.turn
		_refresh_next_action())
	_update_resources()
	_update_turn()
	_update_selection(null)
	_set_match_chrome_visible(false)
	call_deferred("_apply_safe_area")


func _panel_style(
		fill: Color,
		border: Color = COLOR_STEEL,
		radius: int = BrandTheme.CORNER_RADIUS) -> StyleBoxFlat:
	return BrandTheme.panel_style(fill, border, radius)


func _build_theme() -> Theme:
	return BrandTheme.build(_uses_compact_mobile_metrics())


func _uses_compact_mobile_metrics() -> bool:
	var window_width := float(DisplayServer.window_get_size().x)
	if window_width <= 0.0:
		window_width = get_viewport().get_visible_rect().size.x
	return window_width <= 575.0


func _apply_responsive_metrics() -> void:
	var compact := _uses_compact_mobile_metrics()
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		if not control.has_meta("responsive_base_minimum"):
			control.set_meta("responsive_base_minimum", control.custom_minimum_size)
		var base_minimum: Vector2 = control.get_meta("responsive_base_minimum")
		control.custom_minimum_size = base_minimum
		if compact and (control is BaseButton or control is LineEdit):
			control.custom_minimum_size.y = maxf(base_minimum.y, 60.0)
		for font_key: String in ["font_size", "normal_font_size"]:
			if not control.has_theme_font_size_override(font_key):
				continue
			var meta_key: String = "responsive_base_" + font_key
			if not control.has_meta(meta_key):
				control.set_meta(meta_key, control.get_theme_font_size(font_key))
			var base_font: int = int(control.get_meta(meta_key))
			control.add_theme_font_size_override(font_key,
				maxi(base_font, 20) if compact else base_font)


func control_theme() -> Theme:
	return _ui_theme


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_handle_application_paused()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_handle_application_resumed()
	elif what == NOTIFICATION_WM_SIZE_CHANGED:
		call_deferred("_apply_safe_area")
		call_deferred("_apply_responsive_metrics")


func _handle_application_paused() -> void:
	_cancel_end_turn_hold()
	_cancel_map_gestures()
	_cancel_motion_feedback()
	if _application_paused:
		return
	_application_paused = true
	if Game.grid != null and Game.tech != null and not Game.factions.is_empty() \
			and get_node_or_null("GameOverPanel") == null:
		Game.save_to_file(PAUSE_AUTOSAVE_PATH)


func _handle_application_resumed() -> void:
	_application_paused = false
	_cancel_end_turn_hold()
	_cancel_map_gestures()
	_update_resources()
	_update_turn()
	_update_selection(Game.selected_unit if Game.selected_unit != null else Game.selected_city)
	var map_view := get_node_or_null("../MapView")
	if map_view != null:
		map_view.queue_redraw()
	UnitsView.sync()
	call_deferred("_apply_safe_area")


func _cancel_end_turn_hold() -> void:
	_holding_end = false
	_hold_timer = 0.0
	if _end_progress != null:
		_end_progress.value = 0.0


func _cancel_map_gestures() -> void:
	var map_view := get_node_or_null("../MapView")
	if map_view != null and map_view.has_method("cancel_touch_gestures"):
		map_view.cancel_touch_gestures()


func _cancel_motion_feedback() -> void:
	if _turn_label_tween != null and _turn_label_tween.is_valid():
		_turn_label_tween.kill()
	if _turn_label != null:
		_turn_label.modulate = Color.WHITE
		_turn_label.scale = Vector2.ONE
	var map_view := get_node_or_null("../MapView")
	if map_view != null and map_view.has_method("cancel_motion_feedback"):
		map_view.cancel_motion_feedback()
	if UnitsView.instance != null:
		UnitsView.instance.cancel_motion_feedback()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_ui_cancel()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	var released: bool = event is InputEventScreenTouch and not event.pressed
	released = released or (event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
	if released and _ui_consumes_point(event.position):
		_cancel_map_gestures()


func _ui_consumes_point(point: Vector2) -> bool:
	for child in get_children():
		if child is Control and child.visible and child.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and child.get_global_rect().has_point(point):
			return true
	return false


func _handle_ui_cancel() -> bool:
	if get_node_or_null("GameOverPanel") != null:
		return true
	for panel_name in BACK_PANEL_PRIORITY:
		var panel := get_node_or_null(panel_name)
		if panel != null:
			_close_overlay(panel_name)
			return true
	# The first-screen menu consumes Back instead of exposing an unstarted match or quitting.
	if get_node_or_null("MenuPanel") != null:
		return true
	var broker_menu := get_node_or_null("../MapView/BrokerMenu")
	if broker_menu != null:
		broker_menu.queue_free()
		return true
	if Game.selected_unit != null or Game.selected_city != null:
		Game.select(null)
		return true
	return true


func _build_ui() -> void:
	# Slim status strip; the map remains the primary surface.
	_top_hud = PanelContainer.new()
	_top_hud.name = "TopHUD"
	_top_hud.theme = _ui_theme
	_top_hud.anchor_right = 1.0
	_top_hud.offset_left = 8.0
	_top_hud.offset_top = 8.0
	_top_hud.offset_right = -8.0
	_top_hud.offset_bottom = 88.0
	add_child(_top_hud)
	_remember_safe_layout(_top_hud)
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 2)
	_top_hud.add_child(top_box)
	var primary_row := HBoxContainer.new()
	primary_row.add_theme_constant_override("separation", 8)
	top_box.add_child(primary_row)

	var resource_row := HBoxContainer.new()
	resource_row.name = "ResourceRow"
	resource_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_row.add_theme_constant_override("separation", 8)
	primary_row.add_child(resource_row)
	for resource_id in ["scrap", "biomass", "energy", "sol"]:
		var item := HBoxContainer.new()
		item.tooltip_text = resource_id.capitalize()
		item.add_theme_constant_override("separation", 2)
		resource_row.add_child(item)
		var icon := TextureRect.new()
		icon.texture = WorldArt.resource_icon(resource_id)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
		var value := Label.new()
		value.theme_type_variation = "ResourceLabel"
		value.add_theme_font_size_override("font_size", 16)
		item.add_child(value)
		_resource_labels[resource_id] = value

	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.custom_minimum_size = Vector2(72, 48)
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.pressed.connect(func():
		if Game.save_to_file("user://save.json"):
			Game.game_log("Game saved")
		else:
			Game.game_log("Save failed"))
	primary_row.add_child(save_btn)

	var dip_btn := Button.new()
	dip_btn.text = "DIP"
	dip_btn.custom_minimum_size = Vector2(64, 48)
	dip_btn.add_theme_font_size_override("font_size", 16)
	dip_btn.pressed.connect(_toggle_diplomacy_panel)
	primary_row.add_child(dip_btn)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	top_box.add_child(status_row)
	_turn_label = Label.new()
	_turn_label.theme_type_variation = "ResourceLabel"
	_turn_label.add_theme_font_size_override("font_size", 14)
	_turn_label.modulate = COLOR_MUTED
	status_row.add_child(_turn_label)
	event_label = Label.new()
	event_label.add_theme_font_size_override("font_size", 14)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_label.modulate = COLOR_AMBER
	status_row.add_child(event_label)

	# Brief, non-modal turn delta. It occupies map chrome for only a moment.
	_turn_cue = PanelContainer.new()
	_turn_cue.name = "TurnDeltaCue"
	_turn_cue.theme = _ui_theme
	_turn_cue.anchor_right = 1.0
	_turn_cue.offset_left = 20.0
	_turn_cue.offset_top = 96.0
	_turn_cue.offset_right = -20.0
	_turn_cue.offset_bottom = 166.0
	_turn_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_cue.visible = false
	add_child(_turn_cue)
	_remember_safe_layout(_turn_cue)
	var turn_cue_box := VBoxContainer.new()
	turn_cue_box.add_theme_constant_override("separation", 0)
	_turn_cue.add_child(turn_cue_box)
	_turn_cue_row = HBoxContainer.new()
	_turn_cue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_turn_cue_row.add_theme_constant_override("separation", 8)
	turn_cue_box.add_child(_turn_cue_row)
	_turn_progress_label = Label.new()
	_turn_progress_label.theme_type_variation = "MutedLabel"
	_turn_progress_label.add_theme_font_size_override("font_size", 13)
	_turn_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_progress_label.clip_text = true
	_turn_progress_label.visible = false
	turn_cue_box.add_child(_turn_progress_label)

	# Conditional bottom sheet; hidden when nothing is selected.
	_selection_panel = PanelContainer.new()
	_selection_panel.name = "SelectionPanel"
	_selection_panel.theme = _ui_theme
	_selection_panel.anchor_top = 1.0
	_selection_panel.anchor_right = 1.0
	_selection_panel.anchor_bottom = 1.0
	_selection_panel.offset_left = 8.0
	_selection_panel.offset_top = -304.0
	_selection_panel.offset_right = -8.0
	_selection_panel.offset_bottom = -BOTTOM_NAV_CLEARANCE
	add_child(_selection_panel)
	_remember_safe_layout(_selection_panel)
	_selection_box = VBoxContainer.new()
	_selection_box.add_theme_constant_override("separation", 6)
	_selection_panel.add_child(_selection_box)
	var selection_header := HBoxContainer.new()
	_selection_box.add_child(selection_header)
	_selection_title = Label.new()
	_selection_title.theme_type_variation = "SectionLabel"
	_selection_title.text = "SELECTION"
	_selection_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_title.add_theme_font_size_override("font_size", 16)
	selection_header.add_child(_selection_title)
	_selection_toggle = Button.new()
	_selection_toggle.name = "SelectionInfo"
	_selection_toggle.text = "i"
	_selection_toggle.tooltip_text = "Unit details"
	_selection_toggle.custom_minimum_size = Vector2(48, 48)
	_selection_toggle.pressed.connect(func(): _set_selection_expanded(not _selection_expanded))
	_selection_toggle.visible = false
	selection_header.add_child(_selection_toggle)
	var selection_close := Button.new()
	selection_close.text = "CLOSE"
	selection_close.custom_minimum_size = Vector2(80, 48)
	selection_close.pressed.connect(func(): Game.select(null))
	selection_close.visible = false
	selection_header.add_child(selection_close)
	_selection_scroll = ScrollContainer.new()
	_selection_scroll.name = "SelectionScroll"
	_selection_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_selection_box.add_child(_selection_scroll)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 16)
	_selection_scroll.add_child(_detail)
	_selection_summary_detail = RichTextLabel.new()
	_selection_summary_detail.name = "SelectionSummary"
	_selection_summary_detail.bbcode_enabled = true
	_selection_summary_detail.fit_content = true
	_selection_summary_detail.scroll_active = false
	_selection_summary_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_summary_detail.add_theme_font_size_override("normal_font_size", 16)
	_selection_box.add_child(_selection_summary_detail)
	_queue_feedback = VBoxContainer.new()
	_queue_feedback.name = "QueueFeedback"
	_queue_feedback.add_theme_constant_override("separation", 3)
	_queue_feedback.visible = false
	_selection_box.add_child(_queue_feedback)
	_queue_label = Label.new()
	_queue_label.name = "QueueLabel"
	_queue_label.theme_type_variation = "MutedLabel"
	_queue_label.add_theme_font_size_override("font_size", 14)
	_queue_label.clip_text = true
	_queue_feedback.add_child(_queue_label)
	_queue_progress = ProgressBar.new()
	_queue_progress.name = "QueueProgress"
	_queue_progress.custom_minimum_size.y = 8.0
	_queue_progress.show_percentage = false
	_queue_feedback.add_child(_queue_progress)
	_selection_actions = Button.new()
	_selection_actions.name = "FounderAction"
	_selection_actions.text = "FOUND CITY"
	_selection_actions.custom_minimum_size.y = 48.0
	_selection_actions.visible = false
	_selection_actions.pressed.connect(_run_selection_action)
	_selection_box.add_child(_selection_actions)
	_selection_city_action = Button.new()
	_selection_city_action.name = "CityAction"
	_selection_city_action.text = "PRODUCTION"
	_selection_city_action.custom_minimum_size.y = 48.0
	_selection_city_action.visible = false
	_selection_city_action.pressed.connect(_run_selection_action)
	_selection_box.add_child(_selection_city_action)
	# Keep the one contextual action above the clipped detail scroll.
	_selection_box.move_child(_selection_city_action, 1)
	_selection_box.move_child(_selection_actions, 1)
	_selection_box.move_child(_queue_feedback, 2)

	# === Log (above bottom nav) ===
	_log_panel = PanelContainer.new()
	_log_panel.name = "LogPanel"
	_log_panel.theme = _ui_theme
	_log_panel.anchor_top = 1.0
	_log_panel.anchor_right = 1.0
	_log_panel.anchor_bottom = 1.0
	_log_panel.offset_left = 12.0
	_log_panel.offset_top = -240.0
	_log_panel.offset_right = -12.0
	_log_panel.offset_bottom = -BOTTOM_NAV_CLEARANCE
	add_child(_log_panel)
	_remember_safe_layout(_log_panel)
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 14)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.clip_text = true
	_log_label.modulate = COLOR_AMBER
	_log_panel.add_child(_log_label)
	_log_panel.visible = false

	# === Bottom one-hand navigator ===
	_bottom_nav = PanelContainer.new()
	_bottom_nav.name = "BottomNav"
	_bottom_nav.theme = _ui_theme
	_bottom_nav.anchor_top = 1.0
	_bottom_nav.anchor_right = 1.0
	_bottom_nav.anchor_bottom = 1.0
	_bottom_nav.offset_left = 8.0
	_bottom_nav.offset_top = -160.0
	_bottom_nav.offset_right = -8.0
	_bottom_nav.offset_bottom = -16.0
	add_child(_bottom_nav)
	_remember_safe_layout(_bottom_nav)
	var nav_box := VBoxContainer.new()
	nav_box.add_theme_constant_override("separation", 6)
	_bottom_nav.add_child(nav_box)
	_next_action = Button.new()
	_next_action.name = "NextActionButton"
	_next_action.custom_minimum_size.y = 48.0
	_next_action.add_theme_font_size_override("font_size", 16)
	_next_action.pressed.connect(_run_next_action)
	nav_box.add_child(_next_action)
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 8)
	nav_box.add_child(nav_row)

	var tech_btn := Button.new()
	tech_btn.text = "TECH"
	tech_btn.custom_minimum_size.y = 48.0
	tech_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tech_btn.add_theme_font_size_override("font_size", 16)
	tech_btn.pressed.connect(func(): _toggle_tech_panel())
	nav_row.add_child(tech_btn)

	var cities_btn := Button.new()
	cities_btn.text = "CITIES"
	cities_btn.custom_minimum_size.y = 48.0
	cities_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cities_btn.add_theme_font_size_override("font_size", 16)
	cities_btn.pressed.connect(func(): _cycle_cities())
	nav_row.add_child(cities_btn)

	# Hold-to-end-turn (prevents accidental taps)
	_end_hold = Button.new()
	_end_hold.name = "EndTurnButton"
	_end_hold.text = "END TURN / HOLD"
	_end_hold.custom_minimum_size.y = 48.0
	_end_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_hold.add_theme_font_size_override("font_size", 16)
	_end_hold.button_down.connect(_hold_start)
	_end_hold.button_up.connect(_hold_cancel)
	nav_row.add_child(_end_hold)

	# Progress bar for the hold gesture
	_end_progress = ProgressBar.new()
	_end_progress.custom_minimum_size.y = 8.0
	_end_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_progress.max_value = 0.8
	_end_progress.show_percentage = false
	nav_box.add_child(_end_progress)


func _set_match_chrome_visible(active: bool) -> void:
	for control in [_top_hud, _bottom_nav]:
		if control != null:
			control.visible = active
	if not active:
		_selection_panel.visible = false
		_log_panel.visible = false
		_turn_cue.visible = false
	else:
		_refresh_next_action()
	var map_view := get_node_or_null("../MapView") as CanvasItem
	var units_view := get_node_or_null("../UnitsView") as CanvasItem
	if map_view != null:
		map_view.visible = active
	if units_view != null:
		units_view.visible = active


func _set_selection_expanded(expanded: bool) -> void:
	_selection_expanded = expanded
	if _selection_panel == null:
		return
	_selection_toggle.text = "×" if expanded else "i"
	_selection_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO \
		if expanded else ScrollContainer.SCROLL_MODE_DISABLED
	_selection_scroll.visible = expanded
	_selection_summary_detail.visible = not expanded
	_detail.text = _selection_full_text if expanded else _selection_summary_text
	_selection_summary_detail.text = _selection_summary_text
	call_deferred("_layout_selection_sheet")


func _layout_selection_sheet() -> void:
	if _selection_panel == null or _selection_box == null:
		return
	var visible_detail := _detail if _selection_expanded else _selection_summary_detail
	var detail_height := clampf(float(visible_detail.get_content_height()) + 8.0, 40.0, 94.0)
	_selection_scroll.custom_minimum_size.y = 0.0
	_selection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sheet_height := 68.0 + detail_height
	if _selection_actions.visible or _selection_city_action.visible:
		sheet_height += 54.0
	if _queue_feedback.visible:
		sheet_height += 38.0
	if _selection_expanded:
		var content_height := sheet_height - detail_height + float(_detail.get_content_height()) + 8.0
		sheet_height = minf(get_viewport().get_visible_rect().size.y * 0.5,
			maxf(content_height, 220.0))
	_selection_panel.anchor_top = 1.0
	_selection_panel.offset_left = 8.0
	_selection_panel.offset_top = -BOTTOM_NAV_CLEARANCE - sheet_height
	_selection_panel.offset_right = -8.0
	_selection_panel.offset_bottom = -BOTTOM_NAV_CLEARANCE
	_remember_safe_layout(_selection_panel)
	_apply_safe_area()
	var map_view := get_node_or_null("../MapView")
	if map_view != null and map_view.has_method("keep_cell_in_playable_rect"):
		var selected = Game.selected_city if Game.selected_city != null else Game.selected_unit
		if selected != null:
			map_view.keep_cell_in_playable_rect(selected.cell)


func _hold_start() -> void:
	if _end_hold.disabled:
		return
	_holding_end = true
	_hold_timer = 0.0


func _hold_cancel() -> void:
	if _holding_end:
		_holding_end = false
		_end_progress.value = 0.0
		if _hold_timer >= 0.8:
			Game._sfx("end_turn")
			_commit_end_turn()


func _set_safe_rect_for_test(rect: Rect2i) -> void:
	_safe_rect_override = rect
	_apply_safe_area()


func _clear_safe_rect_for_test() -> void:
	_safe_rect_override = null
	_apply_safe_area()


func _remember_safe_layout(control: Control) -> void:
	control.set_meta("safe_base_offsets", Vector4(
		control.offset_left, control.offset_top, control.offset_right, control.offset_bottom))


func _safe_insets() -> Vector4:
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)
	if _safe_rect_override is Rect2i:
		safe_rect = Rect2(_safe_rect_override)
	elif OS.has_feature("android"):
		var display_safe := DisplayServer.get_display_safe_area()
		var window_size := Vector2(DisplayServer.window_get_size())
		if window_size.x > 0.0 and window_size.y > 0.0:
			var scale := viewport_size / window_size
			safe_rect = Rect2(Vector2(display_safe.position) * scale,
				Vector2(display_safe.size) * scale)
	safe_rect = safe_rect.intersection(Rect2(Vector2.ZERO, viewport_size))
	return Vector4(
		maxf(safe_rect.position.x, 0.0),
		maxf(safe_rect.position.y, 0.0),
		maxf(viewport_size.x - safe_rect.end.x, 0.0),
		maxf(viewport_size.y - safe_rect.end.y, 0.0))


func current_safe_rect() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	var insets := _safe_insets()
	return Rect2(Vector2(insets.x, insets.y),
		viewport_size - Vector2(insets.x + insets.z, insets.y + insets.w))


func playable_map_rect() -> Rect2:
	var safe := current_safe_rect().grow(-8.0)
	var top := safe.position.y
	var bottom := safe.end.y
	if _top_hud != null and _top_hud.visible:
		top = maxf(top, _top_hud.get_global_rect().end.y + 8.0)
	if _bottom_nav != null and _bottom_nav.visible:
		bottom = minf(bottom, _bottom_nav.get_global_rect().position.y - 8.0)
	if _selection_panel != null and _selection_panel.visible:
		bottom = minf(bottom, _selection_panel.get_global_rect().position.y - 8.0)
	return Rect2(Vector2(safe.position.x, top),
		Vector2(safe.size.x, maxf(bottom - top, 96.0)))


func _apply_safe_area() -> void:
	var insets := _safe_insets()
	var setup_card := find_child("SetupCard", true, false) as Control
	if setup_card != null:
		var card_minimum := setup_card.custom_minimum_size
		card_minimum.x = minf(680.0, current_safe_rect().size.x - 48.0)
		setup_card.custom_minimum_size = card_minimum
		setup_card.set_meta("responsive_base_minimum", card_minimum)
	_apply_safe_insets(get_node_or_null("TopHUD") as Control,
		Vector4(insets.x, insets.y, insets.z, 0.0))
	_apply_safe_insets(get_node_or_null("TurnDeltaCue") as Control,
		Vector4(insets.x, insets.y, insets.z, 0.0))
	var bottom_insets := Vector4(insets.x, -insets.w, insets.z, insets.w)
	_apply_safe_insets(get_node_or_null("LogPanel") as Control, bottom_insets)
	_apply_safe_insets(get_node_or_null("BottomNav") as Control, bottom_insets)
	for child in get_children():
		if not (child is Control):
			continue
		var hard_content := child.get_node_or_null("Content") as Control
		if hard_content != null:
			_apply_safe_insets(hard_content, insets)
		elif child.has_meta("safe_base_offsets") \
				and child.name not in ["TopHUD", "LogPanel", "BottomNav"]:
			_apply_safe_insets(child, insets)


func _apply_safe_insets(control: Control, insets: Vector4) -> void:
	if control == null or not control.has_meta("safe_base_offsets"):
		return
	var base: Vector4 = control.get_meta("safe_base_offsets")
	control.offset_left = base.x + insets.x
	control.offset_top = base.y + insets.y
	control.offset_right = base.z - insets.z
	control.offset_bottom = base.w - insets.w


func _process(delta: float) -> void:
	if _holding_end:
		_hold_timer += delta
		_end_progress.value = _hold_timer
		if _hold_timer >= 0.8:
			_holding_end = false
			_end_progress.value = 0.0
			Game._sfx("end_turn")
			_commit_end_turn()


func _cycle_cities() -> void:
	var mine: Array = []
	for c in Game.cities:
		if c.faction_id == Game.faction_id:
			mine.append(c)
	if mine.is_empty():
		return
	Game.select(mine[Game.turn % mine.size()])


func _update_resources() -> void:
	if Game.resources.is_empty():
		return
	var r := Game.resources
	_resource_labels.scrap.text = str(r.scrap)
	_resource_labels.biomass.text = str(r.biomass)
	_resource_labels.energy.text = str(r.energy)
	_resource_labels.sol.text = str(r.sol)
	_refresh_next_action()


func _update_turn(t: int = Game.turn) -> void:
	_turn_label.text = "Turn %d · %s" % [t, Game.era_name()]
	if _last_animated_turn >= 0 and t > _last_animated_turn \
			and MotionFeedback.scale() > 0.0 and not _suppress_next_turn_summary \
			and get_node_or_null("MenuPanel") == null:
		if _turn_label_tween != null and _turn_label_tween.is_valid():
			_turn_label_tween.kill()
		_turn_label.pivot_offset = _turn_label.size * 0.5
		_turn_label.modulate = Color("c8baff")
		_turn_label.scale = Vector2(1.04, 1.04)
		_turn_label_tween = create_tween()
		_turn_label_tween.set_parallel(true)
		_turn_label_tween.tween_property(_turn_label, "modulate", Color.WHITE,
			MotionFeedback.duration(0.28))
		_turn_label_tween.tween_property(_turn_label, "scale", Vector2.ONE,
			MotionFeedback.duration(0.28)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_last_animated_turn = t
	_refresh_next_action()


func _update_selection(obj) -> void:
	var text := ""
	var summary := ""
	if obj is Unit:
		var u: Unit = obj
		var d := u.data()
		_selection_title.text = str(d.name).to_upper()
		text = "[b]ROLE[/b]\n%s\n\n[b]OPERATING COST[/b]\n%d Energy per turn" % [
			d.desc, u.energy_upkeep(),
		]
		summary = "[b]%s[/b]  ·  MOVE %d/%d\nATK %d  DEF %d  ·  UPKEEP %d" % [
			d.name, u.moves_left, u.max_moves(), u.attack(), u.defense(), u.energy_upkeep(),
		]
		if u.transport_capacity() > 0:
			text += "\nCargo: %d/%d" % [u.cargo.size(), u.transport_capacity()]
	elif obj is City:
		var c: City = obj
		if Game.grid != null and Game.cities.has(c):
			Game.recompute_city_worked_tiles()
		var g := c.gather_total()
		_selection_title.text = c.name.to_upper()
		text = "[b]%s[/b] (population %d)\nGather: %d Bio  %d Scrap  %d Energy  %d SOL\nEnergy: +%d (upkeep %d)\nSOL: +%d/turn" % [
			c.name, c.population, g.food, g.scrap, g.energy, g.sol,
			c.energy_production(), c.energy_upkeep_total(), c.sol_production() + c.sol_from_population(),
		]
		summary = "[b]%s[/b]  POP %d\nBIO %d  SCRAP %d  ENERGY %d  SOL %d" % [
			c.name, c.population, g.food, g.scrap, g.energy, g.sol,
		]
		var secured_turns := Game.occupation_remaining(c)
		if secured_turns > 0:
			text += "\nSECURED %dT — ownership lock" % secured_turns
			summary += "  ·  [b]SECURED %dT[/b]" % secured_turns
		if not c.buildings.is_empty():
			text += "\n\nBuildings:"
			for b in c.buildings:
				var bd: Dictionary = c.building_data(b)
				text += "\n  - %s (+%d SOL)" % [bd.name, bd.sol_gen]
	else:
		text = ""
		summary = ""
	_selection_full_text = text
	_selection_summary_text = summary
	_selection_has_actions = false
	_selection_actions.disabled = false
	_selection_actions.visible = false
	_selection_city_action.visible = false
	_selection_toggle.visible = obj is Unit
	_queue_feedback.visible = false
	if obj is City and obj.faction_id == Game.faction_id:
		_selection_has_actions = true
		_selection_city_action.visible = true
		_update_queue_feedback(obj)
	elif obj is Unit and obj.faction_id == Game.faction_id and obj.type_id == "founder":
		_selection_has_actions = Game.can_found_city(obj)
		var site: Dictionary = Game.founding_site_preview(obj.cell, obj.faction_id, obj)
		if bool(site.get("legal", false)):
			var site_yields: Dictionary = site.yields
			summary += "\nSITE  BIO %d  SCRAP %d  ENERGY %d  SOL %d" % [
				site_yields.food, site_yields.scrap, site_yields.energy, site_yields.sol]
			_selection_summary_text = summary
			_detail.text = summary
		else:
			summary += "\nSITE  %s" % str(site.get("reason", "UNAVAILABLE"))
			_selection_summary_text = summary
		_selection_actions.text = "FOUND CITY  ·  %d SCRAP" % Data.SCRAP_PER_CITY
		_selection_actions.visible = _selection_has_actions
	_detail.text = _selection_full_text if _selection_expanded else _selection_summary_text
	_selection_summary_detail.text = _selection_summary_text
	_selection_scroll.visible = _selection_expanded
	_selection_summary_detail.visible = not _selection_expanded
	_selection_panel.visible = obj != null and get_node_or_null("MenuPanel") == null
	if _selection_panel.visible:
		_log_panel.visible = false
	if obj == null:
		_set_selection_expanded(false)
	else:
		call_deferred("_layout_selection_sheet")
	_refresh_next_action()


func _refresh_next_action() -> void:
	if _next_action == null or _end_hold == null or Game.grid == null:
		return
	var action: Dictionary = Game.next_required_action()
	var kind := str(action.get("kind", "end_turn"))
	match kind:
		"unit":
			var unit: Unit = action.target
			if Game.selected_unit == unit:
				_next_action.text = Game.unit_order_label(unit)
				_next_action.tooltip_text = "Finish this unit's orders"
			else:
				_next_action.text = "UNIT NEEDS ORDERS"
				_next_action.tooltip_text = "Focus the next unit"
		"research":
			_next_action.text = "CHOOSE RESEARCH"
			_next_action.tooltip_text = "Open the technology tree"
		"production":
			_next_action.text = "CHOOSE PRODUCTION"
			_next_action.tooltip_text = "Open the next idle city"
		_:
			_next_action.text = "TURN READY"
			_next_action.tooltip_text = "Hold End Turn to continue"
	_next_action.disabled = kind == "end_turn"
	_end_hold.disabled = kind != "end_turn"
	_end_hold.text = "END TURN · HOLD" if kind == "end_turn" else "END TURN · LOCKED"
	if _end_hold.disabled:
		_cancel_end_turn_hold()


func _run_next_action() -> void:
	var action: Dictionary = Game.next_required_action()
	match str(action.get("kind", "end_turn")):
		"unit":
			var unit: Unit = action.target
			if Game.selected_unit == unit:
				Game.complete_unit_orders(unit)
			else:
				Game.select(unit)
				var map_view := get_node_or_null("../MapView")
				if map_view != null and map_view.has_method("keep_cell_in_playable_rect"):
					map_view.keep_cell_in_playable_rect(unit.cell)
		"research":
			if get_node_or_null("TechPanel") == null:
				_toggle_tech_panel()
		"production":
			var city: City = action.target
			Game.select(city)
			build_city_actions(city)
	_refresh_next_action()


func _update_queue_feedback(city: City) -> void:
	if city.build_queue.is_empty():
		_queue_feedback.visible = false
		return
	var building_id: String = city.build_queue[0]
	var data: Dictionary = Faction.building_data(building_id)
	var cost := int(data.scrap_cost)
	if city.faction != null:
		cost = city.faction.building_cost(cost)
	var status := _building_timing_status(city, cost, int(data.sol_cost), city.scrap_stock)
	_queue_label.text = "%s  %d/%d SCRAP  %s" % [
		data.name, city.scrap_stock, cost, status,
	]
	_queue_progress.max_value = maxi(cost, 1)
	_queue_progress.value = mini(city.scrap_stock, cost)
	_queue_feedback.visible = true


func _estimated_build_turns(city: City, cost: int, stock: int = 0) -> int:
	var remaining := maxi(cost - stock, 0)
	if remaining <= int(Game.resources.get("scrap", 0)):
		return 1
	var income := maxi(int(city.gather_total().scrap), 1)
	return 1 + ceili(float(remaining - int(Game.resources.get("scrap", 0))) / income)


func _building_timing_status(city: City, scrap_cost: int, sol_cost: int,
		stock: int = 0) -> String:
	if int(Game.resources.get("sol", 0)) < sol_cost:
		return "NEEDS %d SOL" % sol_cost
	var turns := _estimated_build_turns(city, scrap_cost, stock)
	return "~%d %s" % [turns, "TURN" if turns == 1 else "TURNS"]


func _run_selection_action() -> void:
	if Game.selected_city != null and Game.selected_city.faction_id == Game.faction_id:
		build_city_actions(Game.selected_city)
		return
	var founder: Unit = Game.selected_unit
	if founder == null or not Game.can_found_city(founder):
		return
	var cell := founder.cell
	if Game.found_city(founder):
		Game.select(Game.city_at(cell))
		UnitsView.sync()


func _commit_end_turn() -> void:
	if Game.resources.is_empty() or str(Game.next_required_action().get("kind", "")) != "end_turn":
		return
	var before_resources: Dictionary = Game.resources.duplicate(true)
	var city: City = Game.selected_city
	var queue_before := _queue_snapshot(city)
	_suppress_next_turn_summary = true
	if not queue_before.is_empty() and city != null:
		_suppress_selected_build_log = "Built: %s in %s" % [queue_before.name, city.name]
	Game.end_turn()
	_suppress_selected_build_log = ""
	if city != null and is_instance_valid(city):
		_update_selection(city)
	_show_turn_delta(before_resources, Game.resources, queue_before, _queue_snapshot(city))


func _queue_snapshot(city: City) -> Dictionary:
	if city == null or not is_instance_valid(city) or city.build_queue.is_empty():
		return {}
	var building_id: String = city.build_queue[0]
	var data: Dictionary = Faction.building_data(building_id)
	var cost := int(data.scrap_cost)
	if city.faction != null:
		cost = city.faction.building_cost(cost)
	return {"id": building_id, "name": str(data.name),
		"stock": city.scrap_stock, "cost": cost}


func _show_turn_delta(before: Dictionary, after: Dictionary,
		queue_before: Dictionary, queue_after: Dictionary) -> void:
	for child in _turn_cue_row.get_children():
		_turn_cue_row.remove_child(child)
		child.queue_free()
	var turn := Label.new()
	turn.theme_type_variation = "SectionLabel"
	turn.text = "TURN %d" % Game.turn
	_turn_cue_row.add_child(turn)
	for resource_id in ["scrap", "biomass", "energy", "sol"]:
		var delta := int(after.get(resource_id, 0)) - int(before.get(resource_id, 0))
		if delta == 0:
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		var icon := TextureRect.new()
		icon.texture = WorldArt.resource_icon(resource_id)
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item.add_child(icon)
		var value := Label.new()
		value.theme_type_variation = "ResourceLabel"
		value.text = "%+d" % delta
		item.add_child(value)
		_turn_cue_row.add_child(item)
	var progress_text := ""
	if not queue_before.is_empty():
		if queue_after.is_empty() or queue_after.id != queue_before.id:
			progress_text = "%s COMPLETE" % queue_before.name
		else:
			var progress_delta := int(queue_after.stock) - int(queue_before.stock)
			if progress_delta != 0:
				progress_text = "%s %+d" % [queue_before.name, progress_delta]
	_turn_progress_label.text = progress_text
	_turn_progress_label.visible = progress_text != ""
	_turn_cue.visible = get_node_or_null("MenuPanel") == null
	_turn_cue_generation += 1
	var generation := _turn_cue_generation
	get_tree().create_timer(2.4).timeout.connect(func():
		if generation == _turn_cue_generation and _turn_cue != null:
			_turn_cue.visible = false)


func _add_log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 4:
		_log_lines.pop_front()
	if text.begins_with("In queue for "):
		return
	if _suppress_selected_build_log != "" and text == _suppress_selected_build_log:
		_suppress_selected_build_log = ""
		return
	if _suppress_next_turn_summary and text.begins_with("Turn "):
		_suppress_next_turn_summary = false
		return
	_log_label.text = text
	_log_panel.visible = get_node_or_null("MenuPanel") == null \
		and not (_selection_panel != null and _selection_panel.visible)
	_log_generation += 1
	var generation := _log_generation
	get_tree().create_timer(5.0).timeout.connect(func():
		if generation == _log_generation and _log_panel != null:
			_log_panel.visible = false)


## City workspace: overview and one-level production picker.
func build_city_actions(city: City) -> void:
	var old := get_node_or_null("CityActions")
	if old != null:
		old.queue_free()
		old.name = "CityActionsClosing"
	if city == null or city.faction_id != Game.faction_id:
		_selection_panel.visible = Game.selected_unit != null or Game.selected_city != null
		return

	var panel := PanelContainer.new()
	panel.name = "CityActions"
	panel.theme = _ui_theme
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_top = -1056.0
	panel.offset_right = -12.0
	panel.offset_bottom = -BOTTOM_NAV_CLEARANCE
	panel.clip_contents = true
	add_child(panel)
	_remember_safe_layout(panel)
	_selection_panel.visible = false
	call_deferred("_apply_safe_area")

	var workspace := VBoxContainer.new()
	workspace.add_theme_constant_override("separation", 8)
	panel.add_child(workspace)
	var header := HBoxContainer.new()
	header.name = "CityWorkspaceHeader"
	workspace.add_child(header)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	header.add_child(title_box)
	var title := Label.new()
	title.name = "CityWorkspaceTitle"
	title.theme_type_variation = "ScreenTitleLabel"
	title.text = city.name.to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title_box.add_child(title)
	var faction_label := Label.new()
	faction_label.theme_type_variation = "MutedLabel"
	faction_label.text = city.faction.name.to_upper() if city.faction != null else "CITY"
	faction_label.add_theme_font_size_override("font_size", 14)
	title_box.add_child(faction_label)
	_add_header_button(header, "CLOSE", func(): _close_overlay("CityActions"))

	var city_card := PanelContainer.new()
	city_card.name = "CityIllustration"
	city_card.custom_minimum_size.y = 112.0
	city_card.add_theme_stylebox_override("panel", _panel_style(
		BrandTheme.POPOVER, BrandTheme.BORDER))
	workspace.add_child(city_card)
	var city_row := HBoxContainer.new()
	city_row.add_theme_constant_override("separation", 12)
	city_card.add_child(city_row)
	var illustration := TextureRect.new()
	illustration.texture = WorldArt.entity_texture("city_era_1")
	illustration.custom_minimum_size = Vector2(104, 96)
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	city_row.add_child(illustration)
	var city_state_box := VBoxContainer.new()
	city_state_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	city_state_box.alignment = BoxContainer.ALIGNMENT_CENTER
	city_state_box.add_theme_constant_override("separation", 4)
	city_row.add_child(city_state_box)
	var population := Label.new()
	population.theme_type_variation = "SectionLabel"
	population.text = "POP %d" % city.population
	population.add_theme_font_size_override("font_size", 16)
	city_state_box.add_child(population)
	var state := Label.new()
	state.name = "CityOperationalState"
	state.text = _city_operational_state(city)
	state.modulate = COLOR_RED if city.is_offline() or city.is_dos() else COLOR_CYAN
	state.add_theme_font_size_override("font_size", 16)
	city_state_box.add_child(state)
	var secured_turns := Game.occupation_remaining(city)
	if secured_turns > 0:
		var secured := Label.new()
		secured.name = "CitySecuredState"
		secured.text = "SECURED %dT" % secured_turns
		secured.modulate = COLOR_AMBER
		secured.add_theme_font_size_override("font_size", 14)
		city_state_box.add_child(secured)

	_add_current_production(workspace, city)
	_add_city_yields(workspace, city)

	var tabs := HBoxContainer.new()
	tabs.name = "CityWorkspaceTabs"
	tabs.add_theme_constant_override("separation", 6)
	workspace.add_child(tabs)
	var production_tab := Button.new()
	production_tab.name = "CityTabProduction"
	production_tab.text = "PRODUCTION"
	production_tab.toggle_mode = true
	production_tab.button_pressed = true
	production_tab.custom_minimum_size.y = 48.0
	production_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	production_tab.add_theme_font_size_override("font_size", 16)
	tabs.add_child(production_tab)
	var city_tab := Button.new()
	city_tab.name = "CityTabOverview"
	city_tab.text = "CITY"
	city_tab.toggle_mode = true
	city_tab.custom_minimum_size.y = 48.0
	city_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	city_tab.add_theme_font_size_override("font_size", 16)
	tabs.add_child(city_tab)

	var scroll := ScrollContainer.new()
	scroll.name = "CityActionsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(scroll)
	var tab_content := VBoxContainer.new()
	tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tab_content)
	var actions := VBoxContainer.new()
	actions.name = "CityProductionContent"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 6)
	tab_content.add_child(actions)
	var city_content := VBoxContainer.new()
	city_content.name = "CityOverviewContent"
	city_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	city_content.add_theme_constant_override("separation", 6)
	city_content.visible = false
	tab_content.add_child(city_content)
	_add_city_overview(city_content, city)
	production_tab.pressed.connect(func():
		production_tab.button_pressed = true
		city_tab.button_pressed = false
		actions.visible = true
		city_content.visible = false)
	city_tab.pressed.connect(func():
		production_tab.button_pressed = false
		city_tab.button_pressed = true
		actions.visible = false
		city_content.visible = true)

	var shown_actions := 0
	# Only choices that can be acted on now; locked content belongs in Tech.
	for b_id in Data.BUILDINGS:
		if b_id in ["nuclear_plant", "fusion_plant"]:
			continue
		var bd: Dictionary = Data.BUILDINGS[b_id]
		if not city.can_queue_build(b_id, Game.tech) \
				or shown_actions >= 5:
			continue
		var btn := Button.new()
		var cost := int(bd.scrap_cost)
		if city.faction != null:
			cost = city.faction.building_cost(cost)
		var sol_cost := int(bd.sol_cost)
		var status := _building_timing_status(city, cost, sol_cost)
		var sol_price := " + %d SOL" % sol_cost \
			if sol_cost > 0 and int(Game.resources.get("sol", 0)) >= sol_cost else ""
		btn.name = "ProductionChoice_%s" % b_id
		btn.text = "%s\n%s  ·  %d Scrap%s  ·  %s" % [
			bd.name, _building_role(bd), cost, sol_price, status,
		]
		var icon_path := "res://assets/icons/blds/%s.svg" % b_id
		if ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
			btn.add_theme_constant_override("icon_max_width", 42)
			btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 72.0
		btn.add_theme_font_size_override("font_size", 16)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func(): _start_build(city, b_id))
		actions.add_child(btn)
		shown_actions += 1

	# Unit buttons (standard + faction uniques)
	var unit_ids: Array = []
	for u_id in Data.UNITS:
		unit_ids.append(u_id)
	# Building upgrade (turbine -> reactor -> fusion)
	if shown_actions < 5 and Game.can_upgrade_city_building(city):
		var up_btn := Button.new()
		up_btn.name = "ProductionChoice_upgrade"
		up_btn.text = "POWER CORE UPGRADE\nMORE ENERGY  ·  1 TURN"
		up_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		up_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		up_btn.custom_minimum_size.y = 72.0
		up_btn.add_theme_font_size_override("font_size", 16)
		up_btn.pressed.connect(func(): Game.upgrade_city_building(city))
		actions.add_child(up_btn)
		shown_actions += 1

	var uu: Dictionary = Faction.UNIQUE_UNITS.get(Game.factions[Game.faction_id].id, {})
	for u_id in uu:
		unit_ids.append(u_id)
	for u_id in unit_ids:
		if shown_actions >= 5:
			break
		if u_id in ["virus_pickup", "auto_mech"]:
			continue
		var ud: Dictionary = Game._unit_data(u_id)
		var required_tech := str(ud.get("requires_tech", ""))
		if not Game.can_train_unit(city, str(u_id)) \
				or (required_tech != "" and not Game.tech.is_researched(required_tech)):
			continue
		var btn := Button.new()
		btn.name = "ProductionChoice_unit_%s" % u_id
		btn.text = "%s\n%s  ·  %d Scrap%s  ·  1 TURN" % [
			ud.name, _unit_role(ud), int(ud.scrap_cost),
			" + %d SOL" % int(ud.sol_cost) if int(ud.sol_cost) > 0 else "",
		]
		var unit_icon := UnitsView.unit_texture(u_id)
		if unit_icon != null:
			btn.icon = unit_icon
			btn.add_theme_constant_override("icon_max_width", 42)
			btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 72.0
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func(): Game.train_unit(city, u_id))
		actions.add_child(btn)
		shown_actions += 1
	if shown_actions == 0:
		var empty := Label.new()
		empty.text = "NO AFFORDABLE PRODUCTION"
		empty.modulate = COLOR_MUTED
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		actions.add_child(empty)
	var panel_height := minf(get_viewport().get_visible_rect().size.y * 0.58, 744.0)
	panel.offset_top = -BOTTOM_NAV_CLEARANCE - panel_height
	_remember_safe_layout(panel)
	call_deferred("_apply_safe_area")
	call_deferred("_apply_responsive_metrics")


func _city_operational_state(city: City) -> String:
	if city.is_offline():
		return "OFFLINE · %dT" % city.offline_turns
	if city.is_dos():
		return "DoS · %dT" % city.dos_turns
	var energy_state: Dictionary = Game._player_energy_grid_state()
	return "POWERED" if bool(energy_state.powered.get(city, false)) else "UNPOWERED"


func _add_current_production(parent: VBoxContainer, city: City) -> void:
	var card := PanelContainer.new()
	card.name = "CurrentProduction"
	card.add_theme_stylebox_override("panel", _panel_style(COLOR_GRAPHITE, COLOR_STEEL))
	parent.add_child(card)
	_refresh_current_production(card, city)


func _refresh_current_production(card: PanelContainer, city: City) -> void:
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var heading := Label.new()
	heading.theme_type_variation = "MutedLabel"
	heading.text = "CURRENT PRODUCTION"
	heading.add_theme_font_size_override("font_size", 14)
	box.add_child(heading)
	var value := Label.new()
	value.name = "CurrentProductionLabel"
	value.theme_type_variation = "SectionLabel"
	value.add_theme_font_size_override("font_size", 16)
	box.add_child(value)
	if city.build_queue.is_empty():
		value.text = "NO PRODUCTION"
		return
	var building_id: String = city.build_queue[0]
	var data: Dictionary = Faction.building_data(building_id)
	var cost := int(data.scrap_cost)
	if city.faction != null:
		cost = city.faction.building_cost(cost)
	var timing := _building_timing_status(city, cost, int(data.sol_cost), city.scrap_stock)
	if city.is_offline() or city.is_dos() \
			or not bool(Game._player_energy_grid_state().powered.get(city, false)):
		timing = "HALTED"
	value.text = "%s  ·  %s" % [data.name, timing]
	var progress := ProgressBar.new()
	progress.name = "CurrentProductionProgress"
	progress.max_value = maxi(cost, 1)
	progress.value = mini(city.scrap_stock, cost)
	progress.show_percentage = false
	progress.custom_minimum_size.y = 8.0
	box.add_child(progress)


func _add_city_yields(parent: VBoxContainer, city: City) -> void:
	var row := HBoxContainer.new()
	row.name = "CityYieldRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var gathered: Dictionary = city.gather_total()
	var powered := bool(Game._player_energy_grid_state().powered.get(city, false))
	var operational := powered and not city.is_offline() and not city.is_dos()
	var yields := {
		"biomass": int(gathered.food) if operational else 0,
		"scrap": int(gathered.scrap) if operational else 0,
		"energy": int(gathered.energy) + city.energy_production() - city.energy_upkeep_total()
			if operational else 0,
		"sol": int(gathered.sol) + city.sol_production() + city.sol_from_population() if operational else 0,
	}
	for resource_id in ["biomass", "scrap", "energy", "sol"]:
		var item := HBoxContainer.new()
		item.tooltip_text = resource_id.capitalize() + " per turn"
		item.add_theme_constant_override("separation", 4)
		row.add_child(item)
		var icon := TextureRect.new()
		icon.texture = WorldArt.resource_icon(resource_id)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
		var value := Label.new()
		value.theme_type_variation = "ResourceLabel"
		value.text = "+%d" % int(yields.get(resource_id, 0))
		value.add_theme_font_size_override("font_size", 16)
		item.add_child(value)


func _add_city_overview(parent: VBoxContainer, city: City) -> void:
	var focus_choice: Dictionary = Game.next_effective_city_focus(city)
	var focus_button := Button.new()
	focus_button.name = "CityFocus"
	focus_button.custom_minimum_size.y = 52.0
	focus_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_button.add_theme_font_size_override("font_size", 15)
	if focus_choice.is_empty():
		focus_button.text = "FOCUS  %s  ·  BEST AVAILABLE" % city.focus.to_upper()
		focus_button.disabled = true
	else:
		focus_button.text = "FOCUS  %s  →  %s\n%s" % [city.focus.to_upper(),
			str(focus_choice.focus).to_upper(), _focus_delta_text(focus_choice.before, focus_choice.after)]
		focus_button.pressed.connect(func():
			if Game.set_city_focus(city, str(focus_choice.focus)):
				build_city_actions(city))
	parent.add_child(focus_button)
	var status := Label.new()
	status.theme_type_variation = "SectionLabel"
	status.text = "CITY SYSTEMS"
	status.add_theme_font_size_override("font_size", 16)
	parent.add_child(status)
	if city.buildings.is_empty():
		var empty := Label.new()
		empty.text = "NO CITY SYSTEMS YET"
		empty.modulate = COLOR_MUTED
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 48.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		parent.add_child(empty)
		return
	for building_id in city.buildings:
		var data: Dictionary = Faction.building_data(building_id)
		var row := HBoxContainer.new()
		row.name = "CityBuilding_%s" % building_id
		row.custom_minimum_size.y = 56.0
		row.add_theme_constant_override("separation", 10)
		parent.add_child(row)
		var icon := TextureRect.new()
		var icon_path := "res://assets/icons/blds/%s.svg" % building_id
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(42, 42)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s\n%s" % [data.name, _building_role(data)]
		label.add_theme_font_size_override("font_size", 16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)


func _focus_delta_text(before: Dictionary, after: Dictionary) -> String:
	var changes: Array[String] = []
	for item in [["food", "Bio"], ["scrap", "Scrap"], ["energy", "Energy"], ["sol", "SOL"]]:
		var delta := int(after[item[0]]) - int(before[item[0]])
		if delta != 0:
			changes.append("%+d %s" % [delta, item[1]])
	return "  ·  ".join(changes)


func _building_role(data: Dictionary) -> String:
	if int(data.get("energy_gen", 0)) > 0:
		return "ENERGY +%d" % int(data.energy_gen)
	if int(data.get("sol_gen", 0)) > 0:
		return "SOL +%d" % int(data.sol_gen)
	if int(data.get("scrap_gen", 0)) > 0:
		return "SCRAP +%d" % int(data.scrap_gen)
	if int(data.get("food_gen", 0)) > 0:
		return "BIOMASS +%d" % int(data.food_gen)
	var description := str(data.get("desc", "")).to_lower()
	if "veteran" in description:
		return "VETERAN UNITS"
	if "fatigue" in description:
		return "LOWER FATIGUE"
	if "population" in description or "1 pop" in description:
		return "SOL FROM POPULATION"
	if "tech" in description:
		return "TECH +50%"
	if "radiation" in description:
		return "NO RADIATION PENALTY"
	if "cyborg" in description:
		return "CHEAPER CYBORGS"
	if "defense" in description:
		return "CITY DEFENSE"
	if "diplomatic victory" in description:
		return "COUNCIL VICTORY"
	return "CITY SYSTEM"


func _unit_role(data: Dictionary) -> String:
	if bool(data.get("naval", false)):
		return "TRANSPORT · DEF %d" % int(data.def)
	if int(data.get("atk", 0)) <= 0:
		return "SUPPORT · MOVE %d" % int(data.moves)
	return "ATK %d · DEF %d · MOVE %d" % [int(data.atk), int(data.def), int(data.moves)]


func _start_build(city: City, b_id: String) -> void:
	city.add_to_queue(b_id)
	Game.game_log("In queue for %s: %s" % [city.name, Data.BUILDINGS[b_id].name])
	_update_selection(city)
	_refresh_next_action()
	var workspace := get_node_or_null("CityActions")
	if workspace == null:
		return
	var card := workspace.find_child("CurrentProduction", true, false) as PanelContainer
	if card != null:
		_refresh_current_production(card, city)
	var queued_row := workspace.find_child("ProductionChoice_%s" % b_id, true, false)
	if queued_row != null:
		queued_row.queue_free()


## ---------- Tech ----------

func _toggle_tech_panel() -> void:
	var existing := get_node_or_null("TechPanel")
	if existing != null:
		_close_overlay("TechPanel")
		return
	var panel := _create_overlay("TechPanel", true)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	panel.add_child(page)
	var title_row := HBoxContainer.new()
	page.add_child(title_row)
	var title := Label.new()
	title.theme_type_variation = "ScreenTitleLabel"
	title.text = "SOLANA FIELD MANUAL"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_add_header_button(title_row, "CLOSE", func(): _close_overlay("TechPanel"))

	var segment_row := HBoxContainer.new()
	segment_row.add_theme_constant_override("separation", 6)
	page.add_child(segment_row)
	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 6)
	page.add_child(utility_row)
	var glossary_button := Button.new()
	glossary_button.text = "GLOSSARY"
	glossary_button.custom_minimum_size.y = 48.0
	glossary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glossary_button.pressed.connect(_show_glossary)
	utility_row.add_child(glossary_button)
	var network_button := Button.new()
	network_button.text = "NETWORK STATUS"
	network_button.custom_minimum_size.y = 48.0
	network_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	network_button.pressed.connect(_show_network_status)
	utility_row.add_child(network_button)

	var section_label := Label.new()
	section_label.theme_type_variation = "ResourceLabel"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.modulate = COLOR_MUTED
	page.add_child(section_label)
	var scroll := ScrollContainer.new()
	scroll.name = "TechScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	for section in ["TECH", "PROTOCOLS", "WONDERS"]:
		var tab := Button.new()
		tab.text = section
		tab.custom_minimum_size.y = 48.0
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func():
			_populate_manual_section(content, section_label, utility_row, section)
		)
		segment_row.add_child(tab)
	_populate_manual_section(content, section_label, utility_row, "TECH")


func _populate_manual_section(content: VBoxContainer, section_label: Label,
		utility_row: HBoxContainer, section: String) -> void:
	for child in content.get_children():
		child.queue_free()
	utility_row.visible = section != "TECH"
	section_label.text = "TECH TREE  ·  SWIPE ACROSS ERAS" if section == "TECH" else section
	if section == "TECH":
		var tree := TechTreeView.new()
		tree.name = "DependencyTree"
		tree.research_requested.connect(_start_research)
		tree.info_requested.connect(_show_tech_detail)
		content.add_child(tree)
	elif section == "PROTOCOLS":
		for p_id in Data.PROTOCOL_NAMES:
			_add_protocol_card(content, str(p_id))
	else:
		for w_id in Data.WONDERS:
			_add_wonder_card(content, str(w_id))


func _surface_card(parent: Container, card_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = card_name
	panel.add_theme_stylebox_override("panel",
		_panel_style(COLOR_GRAPHITE, BrandTheme.BORDER, BrandTheme.CORNER_RADIUS))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _surface_heading(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "SectionLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _surface_meta(parent: Container, text: String, node_name: String = "") -> Label:
	var label := Label.new()
	if not node_name.is_empty():
		label.name = node_name
	label.theme_type_variation = "ResourceLabel"
	label.text = text
	label.modulate = COLOR_MUTED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_inline_disclosure(parent: VBoxContainer, body: String,
		node_name: String = "Details") -> Button:
	var toggle := Button.new()
	toggle.name = node_name + "Info"
	toggle.text = "i"
	toggle.tooltip_text = "More information"
	toggle.custom_minimum_size = Vector2(48, 48)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	parent.add_child(toggle)
	var detail := Label.new()
	detail.name = node_name
	detail.text = body
	detail.theme_type_variation = "MutedLabel"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.visible = false
	parent.add_child(detail)
	toggle.pressed.connect(func():
		detail.visible = not detail.visible
		toggle.text = "×" if detail.visible else "i"
	)
	return toggle


func _add_protocol_card(parent: VBoxContainer, protocol_id: String) -> void:
	var data: Dictionary = Data.PROTOCOLS[protocol_id]
	var box := _surface_card(parent, "ProtocolCard_%s" % protocol_id)
	var active := protocol_id == Game.protocol
	_surface_meta(box, "ACTIVE" if active else "AVAILABLE", "ProtocolStatus")
	_surface_heading(box, str(data.name))
	var effect := Label.new()
	effect.text = str(data.desc)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(effect)
	var action := Button.new()
	action.name = "ProtocolAction"
	action.text = "ACTIVE PROTOCOL" if active else "ACTIVATE"
	action.custom_minimum_size.y = 48.0
	action.disabled = active
	action.pressed.connect(func():
		Game.switch_protocol(protocol_id)
		_toggle_tech_panel()
	)
	box.add_child(action)
	_add_inline_disclosure(box,
		"A protocol changes your faction economy immediately. It is a game policy, not a Solana consensus setting.",
		"ProtocolDetails")


func _add_wonder_card(parent: VBoxContainer, wonder_id: String) -> void:
	var data: Dictionary = Data.WONDERS[wonder_id]
	var box := _surface_card(parent, "WonderCard_%s" % wonder_id)
	var built := Game.wonders.has(wonder_id)
	var available := Game.can_build_wonder(wonder_id)
	var status := "BUILT" if built else "AVAILABLE" if available else "LOCKED"
	_surface_meta(box, "%s  ·  ◎%d" % [status, int(data.sol_cost)], "WonderStatus")
	_surface_heading(box, str(data.name))
	var effect := Label.new()
	effect.text = str(data.desc)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(effect)
	var action := Button.new()
	action.name = "WonderAction"
	action.text = "COMPLETED" if built else "BUILD"
	action.custom_minimum_size.y = 48.0
	action.disabled = not available
	action.pressed.connect(func(): _build_wonder(wonder_id))
	box.add_child(action)
	var requirement := "Requires %s and ◎%d." % [
		Data.TECHS[data.tech].name, int(data.sol_cost),
	]
	_add_inline_disclosure(box, requirement, "WonderDetails")


func _create_overlay(panel_name: String, hard_modal: bool = false) -> PanelContainer:
	if hard_modal:
		var blocker := Control.new()
		blocker.name = panel_name
		blocker.theme = _ui_theme
		blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(blocker)
		var shade := ColorRect.new()
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.color = COLOR_VOID
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blocker.add_child(shade)
		var modal_content := PanelContainer.new()
		modal_content.name = "Content"
		modal_content.theme = _ui_theme
		modal_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		modal_content.offset_left = 12.0
		modal_content.offset_top = 48.0
		modal_content.offset_right = -12.0
		modal_content.offset_bottom = -12.0
		modal_content.clip_contents = true
		modal_content.mouse_filter = Control.MOUSE_FILTER_STOP
		blocker.add_child(modal_content)
		_remember_safe_layout(modal_content)
		call_deferred("_apply_safe_area")
		call_deferred("_apply_responsive_metrics")
		return modal_content
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.theme = _ui_theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 12.0
	panel.offset_top = 48.0
	panel.offset_right = -12.0
	panel.offset_bottom = -12.0
	panel.clip_contents = true
	add_child(panel)
	_remember_safe_layout(panel)
	call_deferred("_apply_safe_area")
	call_deferred("_apply_responsive_metrics")
	return panel


func _add_header_button(parent: HBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48.0
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)


func _close_overlay(panel_name: String) -> void:
	var panel := get_node_or_null(panel_name)
	if panel != null:
		panel.queue_free()
	if panel_name == "CityActions" and _selection_panel != null:
		_selection_panel.visible = Game.selected_unit != null or Game.selected_city != null


func _show_tech_detail(t_id: String) -> void:
	if get_node_or_null("TechDetailPanel") != null:
		return
	var panel := _create_overlay("TechDetailPanel", true)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.theme_type_variation = "SectionLabel"
	title.text = Data.TECHS[t_id].name
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_header_button(header, "Glossary", _show_glossary)
	_add_header_button(header, "Back", func(): _close_overlay("TechDetailPanel"))

	var scroll := ScrollContainer.new()
	scroll.name = "TechDetailScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var education: Dictionary = EducationData.TECHS[t_id]
	_add_detail_section(content, "IN GAME", education.game_effect)
	_add_detail_section(content, "REAL SOLANA", education.real_solana)
	_add_detail_section(content, "FICTION BOUNDARY", education.fiction)
	_add_disclosure_section(content, "TERMS", ", ".join(education.terms))
	_add_official_links(content, education.source_urls)


func _research_disabled_reason(t_id: String) -> String:
	if Game.tech.researched.has(t_id):
		return "Already researched."
	if Game.tech.current == t_id:
		return "Research in progress."
	if Game.tech.current != "":
		return "Unavailable: researching %s." % Data.TECHS[Game.tech.current].name
	var unmet_names: Array[String] = []
	for required_id in Data.TECHS[t_id].requires:
		if not Game.tech.researched.has(required_id):
			unmet_names.append(Data.TECHS[required_id].name)
	if not unmet_names.is_empty():
		return "Requires: %s." % ", ".join(unmet_names)
	var required_sol: int = int(Data.TECHS[t_id].sol_cost)
	var current_sol: int = int(Game.resources.sol)
	if current_sol < required_sol:
		return "Insufficient SOL: need ◎%d, have ◎%d." % [required_sol, current_sol]
	return ""


func _add_detail_section(parent: VBoxContainer, heading: String, body: String) -> void:
	var label := Label.new()
	label.text = heading + "\n" + body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)


func _add_disclosure_section(parent: VBoxContainer, heading: String, body: String) -> void:
	var toggle := Button.new()
	toggle.text = "%s  +" % heading
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.y = 48.0
	parent.add_child(toggle)
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.visible = false
	parent.add_child(label)
	toggle.pressed.connect(func():
		label.visible = not label.visible
		toggle.text = "%s  %s" % [heading, "−" if label.visible else "+"]
	)


func _add_official_links(parent: VBoxContainer, urls: Array) -> void:
	var toggle := Button.new()
	toggle.text = "OFFICIAL LINKS  +"
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.y = 48.0
	parent.add_child(toggle)
	var links := VBoxContainer.new()
	links.name = "OfficialLinks"
	links.visible = false
	links.add_theme_constant_override("separation", 6)
	parent.add_child(links)
	for index in urls.size():
		var url := str(urls[index])
		if not EducationData.is_official_source_url(url):
			continue
		var link := LinkButton.new()
		link.name = "OfficialSource%d" % (index + 1)
		link.text = "SOURCE %d · %s  ↗" % [index + 1, url.get_slice("/", 2)]
		link.tooltip_text = url
		link.custom_minimum_size.y = 48.0
		link.pressed.connect(func(): _open_official_url(url))
		links.add_child(link)
	toggle.pressed.connect(func():
		links.visible = not links.visible
		toggle.text = "OFFICIAL LINKS  %s" % ["−" if links.visible else "+"]
	)


func _open_official_url(url: String) -> bool:
	if not EducationData.is_official_source_url(url):
		return false
	if not _external_url_opener.is_valid():
		return false
	_external_url_opener.call(url)
	return true


func _show_glossary() -> void:
	if get_node_or_null("GlossaryPanel") != null:
		return
	var panel := _create_overlay("GlossaryPanel", true)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.theme_type_variation = "ScreenTitleLabel"
	title.text = "Solana glossary"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_header_button(header, "Back", func(): _close_overlay("GlossaryPanel"))
	var scroll := ScrollContainer.new()
	scroll.name = "GlossaryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	for group_name in ["CORE STATE", "CONSENSUS & NETWORK", "TRANSACTIONS & ASSETS"]:
		var group := Label.new()
		group.theme_type_variation = "ResourceLabel"
		group.text = group_name
		group.modulate = COLOR_MUTED
		content.add_child(group)
		for entry_id in EducationData.GLOSSARY:
			if _glossary_group(str(entry_id)) == group_name:
				_add_glossary_card(content, str(entry_id))


func _glossary_group(entry_id: String) -> String:
	if entry_id in ["account", "program", "pda", "cpi", "parallel_compute"]:
		return "CORE STATE"
	if entry_id in ["poh_slot", "tower", "validator", "commitment", "turbine", "qos", "client_diversity"]:
		return "CONSENSUS & NETWORK"
	return "TRANSACTIONS & ASSETS"


func _add_glossary_card(parent: VBoxContainer, entry_id: String) -> void:
	var entry: Dictionary = EducationData.GLOSSARY[entry_id]
	var box := _surface_card(parent, "GlossaryCard_%s" % entry_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	_surface_heading(copy, str(entry.name))
	var definition := Label.new()
	definition.text = str(entry.definition)
	definition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	definition.max_lines_visible = 2
	definition.modulate = COLOR_MUTED
	copy.add_child(definition)
	var info := Button.new()
	info.name = "GlossaryInfo"
	info.text = "i"
	info.tooltip_text = "Official source"
	info.custom_minimum_size = Vector2(48, 48)
	row.add_child(info)
	var source := LinkButton.new()
	source.name = "GlossarySource"
	source.text = "OFFICIAL SOURCE  ↗"
	source.tooltip_text = str(entry.source)
	source.custom_minimum_size.y = 48.0
	source.visible = false
	source.pressed.connect(func(): _open_official_url(str(entry.source)))
	box.add_child(source)
	info.pressed.connect(func():
		source.visible = not source.visible
		info.text = "×" if source.visible else "i"
	)


func _show_network_status() -> void:
	if get_node_or_null("NetworkStatusPanel") != null:
		return
	var panel := _create_overlay("NetworkStatusPanel", true)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.theme_type_variation = "ScreenTitleLabel"
	title.text = "Network status"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_header_button(header, "Back", func(): _close_overlay("NetworkStatusPanel"))
	var scroll := ScrollContainer.new()
	scroll.name = "NetworkStatusScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var snapshot: Dictionary = Game.network_status_snapshot()
	var summary := _surface_card(content, "NetworkSummary")
	_surface_meta(summary, "PLAYER NETWORK")
	_surface_heading(summary, "%d/%d validators powered" % [
		int(snapshot.powered_validators), int(snapshot.total_validators)])
	var totals := Label.new()
	totals.theme_type_variation = "ResourceLabel"
	totals.text = "%d COMPONENTS  ·  %d ENERGY  ·  %d UPKEEP" % [
		int(snapshot.component_count), int(snapshot.available_energy), int(snapshot.unit_upkeep)]
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_child(totals)
	_add_inline_disclosure(summary,
		"This is the game's simplified power model, not live Solana network telemetry.",
		"NetworkAnalogy")
	if not snapshot.component_surpluses.is_empty():
		var components_title := Label.new()
		components_title.theme_type_variation = "ResourceLabel"
		components_title.text = "ENERGY COMPONENTS"
		components_title.modulate = COLOR_MUTED
		content.add_child(components_title)
	for index in snapshot.component_surpluses.size():
		var component := _surface_card(content, "NetworkComponent_%d" % (index + 1))
		var surplus := int(snapshot.component_surpluses[index])
		_surface_heading(component, "Component %d" % (index + 1))
		_surface_meta(component, "%+d ENERGY  ·  %s" % [surplus,
			"POWERED" if surplus > 0 else "OFFLINE"], "ComponentState")
	if not snapshot.validators.is_empty():
		var validators_title := Label.new()
		validators_title.theme_type_variation = "ResourceLabel"
		validators_title.text = "VALIDATORS"
		validators_title.modulate = COLOR_MUTED
		content.add_child(validators_title)
	for validator in snapshot.validators:
		var validator_box := _surface_card(content, "Validator_%s" % str(validator.city))
		_surface_heading(validator_box, str(validator.city))
		var building_name := str(Faction.building_data(validator.building).name)
		_surface_meta(validator_box, "%s  ·  %s  ·  OUTPUT +%d SOL" % [
			building_name, "POWERED" if bool(validator.powered) else "OFFLINE",
			int(validator.base_output)], "ValidatorState")
		if not bool(validator.powered):
			_add_inline_disclosure(validator_box, str(validator.reason), "ValidatorDetails")


func _start_research(t_id: String) -> void:
	if Game.tech.start_research(t_id, Game.resources):
		Game.game_log("Research started: %s" % Data.TECHS[t_id].name)
		Game.emit_signal("resources_changed")
		_toggle_tech_panel()
		_refresh_next_action()


## ---------- Diplomacy ----------

func _toggle_diplomacy_panel() -> void:
	var panel := get_node_or_null("DipPanel")
	if panel != null:
		panel.queue_free()
		return
	var p := _create_overlay("DipPanel")
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	p.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.theme_type_variation = "ScreenTitleLabel"
	title.text = "Diplomacy"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_header_button(header, "BACK", func(): _close_overlay("DipPanel"))
	var scroll := ScrollContainer.new()
	scroll.name = "DiplomacyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	for f in range(1, Game.factions.size()):
		_add_diplomacy_card(content, f)


func _add_diplomacy_card(parent: VBoxContainer, faction_index: int) -> void:
	var faction: Faction = Game.factions[faction_index]
	var status: String = Game.diplomatic_status(faction_index)
	var agenda: String = Game.ai.agenda_for(faction_index, Game.factions) if Game.ai != null else "Unknown"
	var box := _surface_card(parent, "RivalCard_%d" % faction_index)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	box.add_child(title_row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(identity)
	_surface_heading(identity, faction.name)
	_surface_meta(identity, "%s  ·  %s" % [str(agenda).to_upper(), status.to_upper()], "RelationState")
	var info := Button.new()
	info.name = "DiplomacyInfo"
	info.text = "i"
	info.tooltip_text = "Relation details"
	info.custom_minimum_size = Vector2(48, 48)
	title_row.add_child(info)
	var pair := Game.relation_key(Game.faction_id, faction_index)
	var exhaustion := int(Game.war_exhaustion.get(pair, 0))
	var ping_value := Game.relation_ping(Game.faction_id, faction_index)
	var relation_detail := Label.new()
	relation_detail.name = "DiplomacyDetails"
	relation_detail.theme_type_variation = "MutedLabel"
	relation_detail.text = ("WAR EXHAUSTION %d/%d  ·  PEACE NEEDS PING 30" % [
		exhaustion, Game.WAR_EXHAUSTION_LIMIT]) if status == "war" \
		else "RELATION PING %d/100  ·  ALLIANCE NEEDS 60" % ping_value
	relation_detail.visible = false
	box.add_child(relation_detail)
	var primary := Button.new()
	primary.name = "DiplomacyPrimaryAction"
	primary.custom_minimum_size.y = 48.0
	if status == "war":
		primary.text = "PROPOSE PEACE"
		primary.disabled = ping_value < 30
		primary.pressed.connect(func(): _run_diplomacy_action(faction_index, "peace"))
	elif status == "alliance":
		primary.text = "GIFT 10 SOL"
		primary.disabled = int(Game.resources.get("sol", 0)) < 10
		primary.pressed.connect(func(): _run_diplomacy_action(faction_index, "gift"))
	else:
		primary.text = "PROPOSE ALLIANCE"
		primary.disabled = ping_value < 60
		primary.pressed.connect(func(): _run_diplomacy_action(faction_index, "alliance"))
	box.add_child(primary)
	var more := OptionButton.new()
	more.name = "DiplomacyMoreActions"
	more.custom_minimum_size.y = 48.0
	more.add_item("MORE ACTIONS", 0)
	more.set_item_disabled(0, true)
	if status != "alliance":
		more.add_item("Gift 10 SOL", 1)
		more.set_item_disabled(more.item_count - 1, int(Game.resources.get("sol", 0)) < 10)
	if status != "war" and Game.can_start_war(Game.faction_id, faction_index):
		more.add_item("Declare war", 2)
	if Game.tech != null and Game.tech.researched.has("primitive_coding"):
		more.add_item("Buy 50 Scrap / 10 SOL", 3)
		more.set_item_disabled(more.item_count - 1,
			int(Game.resources.get("sol", 0)) < 10 or Game.trade_used >= 3)
		more.add_item("Sell 50 Scrap / 10 SOL", 4)
		more.set_item_disabled(more.item_count - 1,
			int(Game.resources.get("scrap", 0)) < 50 or Game.trade_used >= 3)
	more.selected = 0
	more.visible = false
	more.item_selected.connect(func(index: int):
		_run_diplomacy_menu_action(faction_index, more.get_item_id(index))
	)
	box.add_child(more)
	info.pressed.connect(func():
		var expanded := not relation_detail.visible
		relation_detail.visible = expanded
		more.visible = expanded
		info.text = "×" if expanded else "i"
	)


func _run_diplomacy_action(faction_index: int, action: String) -> void:
	match action:
		"peace": Game.propose_peace(faction_index)
		"gift": Game.gift_sol(faction_index, 10)
		"alliance": Game.propose_alliance(faction_index)
	_refresh_diplomacy()


func _run_diplomacy_menu_action(faction_index: int, action_id: int) -> void:
	match action_id:
		1: Game.gift_sol(faction_index, 10)
		2: Game.declare_war(faction_index)
		3: Game.trade_resources(faction_index, true)
		4: Game.trade_resources(faction_index, false)
	_refresh_diplomacy()


func _refresh_diplomacy() -> void:
	_close_overlay("DipPanel")
	call_deferred("_toggle_diplomacy_panel")


func _build_wonder(w_id: String) -> void:
	if Game.build_wonder(w_id):
		Game.game_log("Wonder completed: %s" % Data.WONDERS[w_id].name)
		_toggle_tech_panel()


## ---------- Main menu ----------

func show_menu() -> void:
	var panel := get_node_or_null("MenuPanel")
	if panel != null:
		return
	_set_match_chrome_visible(false)
	var p := _create_overlay("MenuPanel", true)
	p.add_theme_stylebox_override("panel", _panel_style(Color(COLOR_VOID, 0.0), Color(COLOR_VOID, 0.0), 0))
	var background_gradient := TextureRect.new()
	background_gradient.name = "SetupBackgroundGradient"
	background_gradient.texture = BrandTheme.background_gradient_texture()
	background_gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_gradient.stretch_mode = TextureRect.STRETCH_SCALE
	background_gradient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(background_gradient)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(center)
	var card := PanelContainer.new()
	card.name = "SetupCard"
	card.theme = _ui_theme
	card.custom_minimum_size = Vector2(
		minf(680.0, current_safe_rect().size.x - 32.0),
		minf(680.0 if _uses_compact_mobile_metrics() else 560.0,
			current_safe_rect().size.y - 32.0))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel",
		_panel_style(COLOR_GRAPHITE, BrandTheme.BORDER, BrandTheme.CORNER_RADIUS))
	center.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = "SOLANAZATION"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = "MutedLabel"
	sub.text = "Control the Consensus — capture and build Validators"
	sub.add_theme_font_size_override("font_size", 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	# Faction
	content.add_child(_menu_label("Faction:"))
	var fac_opt := OptionButton.new()
	for f_id in Data.FACTIONS:
		fac_opt.add_item(Data.FACTIONS[f_id].name + " — " + Data.FACTIONS[f_id].desc)
	fac_opt.select(0)
	_style_menu_control(fac_opt)
	content.add_child(fac_opt)

	# Rivals
	content.add_child(_menu_label("Rivals:"))
	var rivals_opt := OptionButton.new()
	for rival_count in range(1, 4):
		rivals_opt.add_item(str(rival_count))
	rivals_opt.select(1)
	_style_menu_control(rivals_opt)
	content.add_child(rivals_opt)

	# Map size
	content.add_child(_menu_label("Map size:"))
	var size_opt := OptionButton.new()
	for sz in Data.MapSize.size():
		var d: Vector2i = Data.MAP_DIMENSIONS[sz]
		size_opt.add_item("Small %dx%d" % [d.x, d.y] if sz == Data.MapSize.SMALL else "Medium %dx%d" % [d.x, d.y] if sz == Data.MapSize.MEDIUM else "Large %dx%d" % [d.x, d.y])
	size_opt.select(Data.MapSize.MEDIUM)
	_style_menu_control(size_opt)
	content.add_child(size_opt)

	# Map type
	content.add_child(_menu_label("Map type:"))
	var type_opt := OptionButton.new()
	for mt in Data.MapType.size():
		type_opt.add_item(Data.MAP_TYPE_NAMES[mt])
	type_opt.select(Data.MapType.CONTINENTS)
	_style_menu_control(type_opt)
	content.add_child(type_opt)

	# Seed
	content.add_child(_menu_label("Seed (0 = random):"))
	var seed_edit := LineEdit.new()
	seed_edit.text = "0"
	_style_menu_control(seed_edit)
	content.add_child(seed_edit)

	# Start
	var start_btn := Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "START GAME"
	start_btn.custom_minimum_size.y = 48.0
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(func():
		var f_ids: Array = Data.FACTIONS.keys()
		var player_id: String = str(f_ids[fac_opt.selected])
		var roster: Array = [player_id]
		for candidate in f_ids:
			if str(candidate) != player_id and roster.size() <= rivals_opt.selected + 1:
				roster.append(str(candidate))
		Game.start_game(size_opt.selected, type_opt.selected, int(seed_edit.text), player_id, roster)
		_set_match_chrome_visible(true)
		_close_overlay("MenuPanel"))
	vbox.add_child(start_btn)

	# Load
	var load_btn := Button.new()
	load_btn.name = "LoadButton"
	load_btn.text = "LOAD SAVE"
	load_btn.custom_minimum_size.y = 48.0
	load_btn.add_theme_font_size_override("font_size", 16)
	load_btn.pressed.connect(func():
		if Game.load_from_file("user://save.json"):
			Game.game_log("Game loaded")
			_set_match_chrome_visible(true)
			_close_overlay("MenuPanel")
		else:
			Game.game_log("No save found"))
	vbox.add_child(load_btn)


func _menu_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l


func _style_menu_control(control: Control) -> void:
	control.custom_minimum_size.y = 48.0
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.add_theme_font_size_override("font_size", 16)


## ---------- Game over ----------

func show_game_over(winner_name: String, reason: String) -> void:
	if get_node_or_null("GameOverPanel") != null:
		return
	var panel := _create_overlay("GameOverPanel", true)
	panel.add_theme_stylebox_override("panel",
		BrandTheme.panel_style(COLOR_VOID, COLOR_VOID, 0, 0.0))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var card := PanelContainer.new()
	card.name = "GameOverCard"
	card.custom_minimum_size = Vector2(
		minf(620.0, current_safe_rect().size.x - 32.0), 460.0)
	card.add_theme_stylebox_override("panel",
		BrandTheme.panel_style(COLOR_GRAPHITE, BrandTheme.BORDER,
			BrandTheme.CORNER_RADIUS, 20.0))
	center.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)
	var player_name := ""
	if not Game.factions.is_empty() and Game.faction_id >= 0 \
			and Game.faction_id < Game.factions.size():
		player_name = Game.factions[Game.faction_id].name
	var victory := winner_name == player_name
	var outcome := Label.new()
	outcome.name = "OutcomeLabel"
	outcome.theme_type_variation = "ResourceLabel"
	outcome.text = "VICTORY" if victory else "DEFEAT"
	outcome.modulate = COLOR_CYAN if victory else COLOR_RED
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(outcome)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = winner_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	if MotionFeedback.scale() > 0.0:
		card.scale = Vector2(0.96, 0.96)
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, MotionFeedback.duration(0.3)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var sub := Label.new()
	sub.name = "OutcomeReason"
	sub.text = reason.capitalize()
	sub.theme_type_variation = "MutedLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)
	var owned_cities := 0
	for city in Game.cities:
		if city.faction_id == Game.faction_id:
			owned_cities += 1
	var network: Dictionary = Game.network_status_snapshot()
	var stats := Label.new()
	stats.name = "OutcomeStats"
	stats.theme_type_variation = "ResourceLabel"
	stats.text = "TURN %d  ·  %d CITIES  ·  %d/%d VALIDATORS\n%s" % [
		Game.turn, owned_cities, int(network.powered_validators),
		int(network.total_validators), Game.era_name().to_upper(),
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(stats)
	var recovery_row := HBoxContainer.new()
	recovery_row.add_theme_constant_override("separation", 8)
	vbox.add_child(recovery_row)
	var restart := Button.new()
	restart.name = "RestartButton"
	restart.text = "RESTART MATCH"
	restart.custom_minimum_size.y = 48.0
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart.add_theme_font_size_override("font_size", 16)
	restart.pressed.connect(_restart_current_match)
	recovery_row.add_child(restart)
	var new_game := Button.new()
	new_game.name = "NewGameButton"
	new_game.text = "NEW GAME"
	new_game.custom_minimum_size.y = 48.0
	new_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game.add_theme_font_size_override("font_size", 16)
	new_game.pressed.connect(_show_new_game_from_game_over)
	recovery_row.add_child(new_game)


func _restart_current_match() -> void:
	var roster: Array = Game._faction_ids().duplicate()
	if roster.is_empty():
		return
	var map_size: int = Game._map_size
	var requested_map_type: int = Game._requested_map_type
	var seed_value: int = Game._game_seed
	var player_faction_id := str(roster[0])
	Game.start_game(map_size, requested_map_type, seed_value, player_faction_id, roster)
	_close_overlay("GameOverPanel")


func _show_new_game_from_game_over() -> void:
	show_menu()
	if get_node_or_null("MenuPanel") != null:
		_close_overlay("GameOverPanel")
