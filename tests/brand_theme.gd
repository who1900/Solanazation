extends SceneTree

const BrandTheme = preload("res://scripts/ui/BrandTheme.gd")

var _failures := 0


func _initialize() -> void:
	var theme := BrandTheme.build(false)
	_check(theme.default_font == BrandTheme.GEIST_REGULAR, "Geist is the default font")
	_check(theme.get_font("font", "Button") == BrandTheme.GEIST_MEDIUM,
		"buttons use Geist Medium")
	_check(theme.get_font("font", "ResourceLabel") == BrandTheme.GEIST_MONO_MEDIUM,
		"resource numerals use Geist Mono")
	_check(theme.get_color("font_color", "Label").is_equal_approx(BrandTheme.FOREGROUND),
		"foreground token is mapped")
	_check(theme.get_color("font_pressed_color", "Button").is_equal_approx(BrandTheme.PRIMARY),
		"primary token is mapped")
	var panel := theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	_check(panel != null and panel.corner_radius_top_left == BrandTheme.CORNER_RADIUS,
		"panels use the 4 px radius")
	_check(panel != null and panel.border_width_top == 1, "panels use hard one-pixel separators")
	_check(theme.get_icon("arrow", "OptionButton") == BrandTheme.CHEVRON_DOWN,
		"option buttons use the brand chevron")
	_check(theme.get_icon("radio_checked", "PopupMenu") == BrandTheme.RADIO_CHECKED,
		"popup menus use the branded selected marker")
	_check(theme.get_icon("radio_unchecked", "PopupMenu") == BrandTheme.RADIO_UNCHECKED,
		"popup menus use the branded unselected marker")
	var popup_panel := theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat
	_check(popup_panel != null and popup_panel.bg_color.is_equal_approx(BrandTheme.POPOVER),
		"popup menus use the popover token")
	var scroll_grabber := theme.get_stylebox("grabber", "VScrollBar") as StyleBoxFlat
	_check(scroll_grabber != null and scroll_grabber.bg_color.is_equal_approx(BrandTheme.PRIMARY),
		"visible scrollbars use semantic brand tokens")
	_check(scroll_grabber != null and scroll_grabber.content_margin_left == 4.0,
		"scrollbars keep a visible brand-owned thickness")
	_check(theme.get_stylebox("grabber_highlight", "VScrollBar") != null,
		"visible scrollbars have a branded interaction state")

	for character in "Solanazation Кириллица Ёё Жж Йй 0123456789":
		_check(BrandTheme.GEIST_REGULAR.has_char(character.unicode_at(0)),
			"Geist supports %s" % character)
		_check(BrandTheme.GEIST_MONO_MEDIUM.has_char(character.unicode_at(0)),
			"Geist Mono supports %s" % character)

	var background_gradient := BrandTheme.background_gradient_texture()
	_check(background_gradient.gradient.colors[0].is_equal_approx(BrandTheme.BACKGROUND),
		"background gradient starts at background")
	_check(background_gradient.gradient.colors[1].is_equal_approx(BrandTheme.BACKGROUND_GRADIENT_END),
		"background gradient uses its approved restrained end color")
	var accent_gradient := BrandTheme.accent_gradient_texture()
	_check(accent_gradient.gradient.colors[0].is_equal_approx(BrandTheme.PRIMARY),
		"accent gradient starts at primary")
	_check(accent_gradient.gradient.colors[1].is_equal_approx(BrandTheme.ACCENT_GRADIENT_END),
		"accent gradient uses its approved related hue")

	var source := FileAccess.get_file_as_string("res://scripts/ui/GameUI.gd")
	_check(not source.contains("⬆"), "production UI contains no emoji icon")
	_check(source.count("background_gradient_texture") == 1,
		"subtle gradient is restricted to the setup surface")
	_check(source.count("accent_gradient_texture") == 0,
		"accent gradient is reserved until a rare technology moment exists")
	_check(not source.contains("Color(0.7, 0.7, 0.7)"),
		"diplomacy contains no hardcoded stock gray")
	_check(not source.contains("Color(\"43515b\")"),
		"setup card uses the semantic border token")

	if _failures == 0:
		print("BRAND_THEME_PASS")
		quit(0)
	else:
		push_error("BRAND_THEME_FAIL failures=%d" % _failures)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Brand theme: %s" % description)
