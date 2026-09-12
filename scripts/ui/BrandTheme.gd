class_name BrandTheme
extends RefCounted
## Quantum Lab semantic UI theme. World rendering is intentionally out of scope.

const BACKGROUND := Color("030407")
const FOREGROUND := Color("f1f5fc")
const CARD := Color("090d14")
const POPOVER := Color("0e1218")
const PRIMARY := Color("9da0ff")
const PRIMARY_SOFT := Color("c0c7ff")
const PRIMARY_FOREGROUND := Color("020202")
const SECONDARY := Color("0f1621")
const MUTED := Color("0e1218")
const MUTED_FOREGROUND := Color("a0a5ac")
const ACCENT := Color("181928")
const DESTRUCTIVE := Color("bb061e")
const DESTRUCTIVE_FOREGROUND := Color("fcfcfc")
const BORDER := Color("2d3035")
const INPUT := Color("090d14")
const RING := Color("9da0ff")
const WARNING := Color("d5a642")
const BACKGROUND_GRADIENT_END := Color("07090f")
const ACCENT_GRADIENT_END := Color("dc90ff")
const CORNER_RADIUS := 4

const GEIST_REGULAR: FontFile = preload("res://assets/fonts/Geist-Regular.ttf")
const GEIST_MEDIUM: FontFile = preload("res://assets/fonts/Geist-Medium.ttf")
const GEIST_SEMIBOLD: FontFile = preload("res://assets/fonts/Geist-SemiBold.ttf")
const GEIST_MONO_MEDIUM: FontFile = preload("res://assets/fonts/GeistMono-Medium.ttf")
const CHEVRON_DOWN: Texture2D = preload("res://assets/icons/ui/chevron-down.svg")
const RADIO_CHECKED: Texture2D = preload("res://assets/icons/ui/radio-checked.svg")
const RADIO_UNCHECKED: Texture2D = preload("res://assets/icons/ui/radio-unchecked.svg")


static func panel_style(
		fill: Color,
		border: Color = BORDER,
		radius: int = CORNER_RADIUS,
		content_margin: float = 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style


static func build(compact_mobile: bool = false) -> Theme:
	var result := Theme.new()
	result.default_font = GEIST_REGULAR
	result.default_font_size = 20 if compact_mobile else 16

	result.set_font("font", "Label", GEIST_REGULAR)
	result.set_color("font_color", "Label", FOREGROUND)
	result.set_font("normal_font", "RichTextLabel", GEIST_REGULAR)
	result.set_font("bold_font", "RichTextLabel", GEIST_SEMIBOLD)
	result.set_color("default_color", "RichTextLabel", FOREGROUND)
	result.set_color("font_color", "RichTextLabel", FOREGROUND)

	result.set_type_variation("DisplayLabel", "Label")
	result.set_font("font", "DisplayLabel", GEIST_SEMIBOLD)
	result.set_font_size("font_size", "DisplayLabel", 30)
	result.set_type_variation("ScreenTitleLabel", "Label")
	result.set_font("font", "ScreenTitleLabel", GEIST_SEMIBOLD)
	result.set_font_size("font_size", "ScreenTitleLabel", 24)
	result.set_type_variation("SectionLabel", "Label")
	result.set_font("font", "SectionLabel", GEIST_SEMIBOLD)
	result.set_font_size("font_size", "SectionLabel", 18)
	result.set_type_variation("MutedLabel", "Label")
	result.set_color("font_color", "MutedLabel", MUTED_FOREGROUND)
	result.set_type_variation("ResourceLabel", "Label")
	result.set_font("font", "ResourceLabel", GEIST_MONO_MEDIUM)
	result.set_font_size("font_size", "ResourceLabel", 16)

	result.set_stylebox("panel", "PanelContainer", panel_style(CARD))
	result.set_font("font", "Button", GEIST_MEDIUM)
	result.set_font_size("font_size", "Button", 16)
	result.set_color("font_color", "Button", FOREGROUND)
	result.set_color("font_hover_color", "Button", FOREGROUND)
	result.set_color("font_pressed_color", "Button", PRIMARY)
	result.set_color("font_disabled_color", "Button", MUTED_FOREGROUND.darkened(0.25))
	result.set_stylebox("normal", "Button", panel_style(SECONDARY, BORDER, CORNER_RADIUS, 10.0))
	result.set_stylebox("hover", "Button", panel_style(ACCENT, RING, CORNER_RADIUS, 10.0))
	result.set_stylebox("pressed", "Button", panel_style(ACCENT, PRIMARY, CORNER_RADIUS, 10.0))
	result.set_stylebox("focus", "Button", panel_style(SECONDARY, RING, CORNER_RADIUS, 10.0))
	result.set_stylebox("disabled", "Button", panel_style(MUTED, BORDER, CORNER_RADIUS, 10.0))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		result.set_stylebox(state, "OptionButton", result.get_stylebox(state, "Button"))
	result.set_font("font", "OptionButton", GEIST_MEDIUM)
	result.set_font_size("font_size", "OptionButton", 16)
	result.set_color("font_color", "OptionButton", FOREGROUND)
	result.set_color("font_hover_color", "OptionButton", FOREGROUND)
	result.set_color("font_pressed_color", "OptionButton", PRIMARY)
	result.set_color("font_disabled_color", "OptionButton", MUTED_FOREGROUND.darkened(0.25))
	result.set_icon("arrow", "OptionButton", CHEVRON_DOWN)
	result.set_constant("arrow_margin", "OptionButton", 8)

	result.set_font("font", "PopupMenu", GEIST_REGULAR)
	result.set_font_size("font_size", "PopupMenu", 16)
	result.set_color("font_color", "PopupMenu", FOREGROUND)
	result.set_color("font_hover_color", "PopupMenu", FOREGROUND)
	result.set_color("font_disabled_color", "PopupMenu", MUTED_FOREGROUND.darkened(0.25))
	result.set_color("font_accelerator_color", "PopupMenu", MUTED_FOREGROUND)
	result.set_stylebox("panel", "PopupMenu", panel_style(POPOVER, BORDER, CORNER_RADIUS, 6.0))
	result.set_stylebox("hover", "PopupMenu", panel_style(ACCENT, RING, CORNER_RADIUS, 8.0))
	result.set_stylebox("separator", "PopupMenu", panel_style(BORDER, BORDER, 0, 0.0))
	for icon_name: String in ["checked", "radio_checked"]:
		result.set_icon(icon_name, "PopupMenu", RADIO_CHECKED)
	for icon_name: String in ["unchecked", "radio_unchecked"]:
		result.set_icon(icon_name, "PopupMenu", RADIO_UNCHECKED)
	result.set_constant("item_start_padding", "PopupMenu", 12)
	result.set_constant("item_end_padding", "PopupMenu", 12)
	# 60 logical px per row keeps at least 48 physical px after 720 -> 575 scaling.
	result.set_constant("v_separation", "PopupMenu", 40)

	result.set_font("font", "LineEdit", GEIST_REGULAR)
	result.set_font_size("font_size", "LineEdit", 16)
	result.set_color("font_color", "LineEdit", FOREGROUND)
	result.set_color("font_placeholder_color", "LineEdit", MUTED_FOREGROUND)
	result.set_stylebox("normal", "LineEdit", panel_style(INPUT, BORDER, CORNER_RADIUS, 10.0))
	result.set_stylebox("focus", "LineEdit", panel_style(INPUT, RING, CORNER_RADIUS, 10.0))

	result.set_stylebox("background", "ProgressBar", panel_style(INPUT, BORDER, 0, 0.0))
	result.set_stylebox("fill", "ProgressBar", panel_style(PRIMARY, PRIMARY, 0, 0.0))
	for scroll_type: String in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", scroll_type, panel_style(MUTED, BORDER, CORNER_RADIUS, 4.0))
		result.set_stylebox("scroll_focus", scroll_type, panel_style(MUTED, RING, CORNER_RADIUS, 4.0))
		result.set_stylebox("grabber", scroll_type,
			panel_style(PRIMARY, PRIMARY, CORNER_RADIUS, 4.0))
		result.set_stylebox("grabber_highlight", scroll_type,
			panel_style(PRIMARY_SOFT, PRIMARY_SOFT, CORNER_RADIUS, 4.0))
		result.set_stylebox("grabber_pressed", scroll_type,
			panel_style(PRIMARY, PRIMARY, CORNER_RADIUS, 4.0))
		result.set_constant("minimum_grab_thickness", scroll_type, 24)
	return result


static func background_gradient_texture() -> GradientTexture2D:
	return _gradient_texture(BACKGROUND, BACKGROUND_GRADIENT_END)


static func accent_gradient_texture() -> GradientTexture2D:
	return _gradient_texture(PRIMARY, ACCENT_GRADIENT_END)


static func _gradient_texture(start: Color, finish: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([start, finish])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.ONE
	return texture
