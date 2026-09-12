extends SceneTree

const BrandTheme = preload("res://scripts/ui/BrandTheme.gd")
const ITEM_COUNT := 5
const MIN_LOGICAL_ROW_HEIGHT := 60.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var option := OptionButton.new()
	option.theme = BrandTheme.build(false)
	root.add_child(option)
	for index in ITEM_COUNT:
		option.add_item("Faction %d" % index)
	option.show_popup()
	await process_frame
	var popup := option.get_popup()
	var panel := popup.get_theme_stylebox("panel", "PopupMenu")
	var chrome_height := panel.content_margin_top + panel.content_margin_bottom
	var rendered_row_height := (float(popup.size.y) - chrome_height) / ITEM_COUNT
	if rendered_row_height < MIN_LOGICAL_ROW_HEIGHT:
		push_error("Popup row %.1f px is below %.1f px logical floor." % [
			rendered_row_height, MIN_LOGICAL_ROW_HEIGHT])
		quit(1)
		return
	if popup.size.y > 400:
		push_error("Popup height %d px is oversized for five rows." % popup.size.y)
		quit(1)
		return
	print("POPUP_GEOMETRY_PASS row=%.1f height=%d" % [rendered_row_height, popup.size.y])
	quit(0)
