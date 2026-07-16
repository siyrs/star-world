class_name StarThemeFactory
extends RefCounted

const Tokens = preload("res://src/ui/design_tokens.gd")


static func create_theme() -> Theme:
	var result := Theme.new()
	result.set_default_font_size(Tokens.FONT_BODY)
	result.set_font_size("font_size", "Label", Tokens.FONT_BODY)
	result.set_font_size("font_size", "Button", Tokens.FONT_BUTTON)
	result.set_font_size("font_size", "LineEdit", Tokens.FONT_BODY)
	result.set_font_size("font_size", "OptionButton", Tokens.FONT_BODY)
	result.set_color("font_color", "Label", Tokens.color(Tokens.COLOR_TEXT))
	result.set_color("font_color", "Button", Tokens.color(Tokens.COLOR_TEXT))
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Tokens.color(Tokens.COLOR_ACCENT_WARM))
	result.set_color("font_disabled_color", "Button", Tokens.color(Tokens.COLOR_TEXT_DISABLED))
	result.set_color("font_color", "LineEdit", Tokens.color(Tokens.COLOR_TEXT))
	result.set_color("font_placeholder_color", "LineEdit", Tokens.color(Tokens.COLOR_TEXT_MUTED))
	result.set_color("font_color", "OptionButton", Tokens.color(Tokens.COLOR_TEXT))
	result.set_color("font_hover_color", "OptionButton", Color.WHITE)
	result.set_color("font_color", "CheckButton", Tokens.color(Tokens.COLOR_TEXT))
	result.set_color("default_color", "RichTextLabel", Tokens.color(Tokens.COLOR_TEXT))
	result.set_stylebox(
		"panel",
		"PanelContainer",
		Tokens.panel_style(Tokens.COLOR_SURFACE, Tokens.COLOR_BORDER, 1, Tokens.RADIUS_LG, 12.0)
	)
	result.set_stylebox(
		"normal",
		"Button",
		Tokens.panel_style(Tokens.COLOR_SURFACE_SOFT, Tokens.COLOR_BORDER, 1, Tokens.RADIUS_MD, 9.0)
	)
	result.set_stylebox(
		"hover",
		"Button",
		Tokens.panel_style(
			Tokens.COLOR_SURFACE_RAISED,
			Tokens.COLOR_BORDER_STRONG,
			2,
			Tokens.RADIUS_MD,
			9.0
		)
	)
	result.set_stylebox(
		"pressed",
		"Button",
		Tokens.panel_style("#102335", Tokens.COLOR_ACCENT_WARM, 2, Tokens.RADIUS_MD, 9.0)
	)
	result.set_stylebox(
		"disabled",
		"Button",
		Tokens.panel_style("#111A24D9", "#30404D", 1, Tokens.RADIUS_MD, 9.0)
	)
	result.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		result.set_stylebox(style_name, "OptionButton", result.get_stylebox(style_name, "Button"))
	result.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	result.set_stylebox(
		"normal",
		"LineEdit",
		Tokens.panel_style("#0B1521F2", Tokens.COLOR_BORDER, 1, Tokens.RADIUS_SM, 8.0)
	)
	result.set_stylebox(
		"focus",
		"LineEdit",
		Tokens.panel_style("#0F2030F7", Tokens.COLOR_BORDER_STRONG, 2, Tokens.RADIUS_SM, 8.0)
	)
	result.set_stylebox(
		"read_only",
		"LineEdit",
		Tokens.panel_style("#101820D9", "#30404D", 1, Tokens.RADIUS_SM, 8.0)
	)
	result.set_stylebox(
		"background",
		"ProgressBar",
		Tokens.panel_style("#0B121A", "#30404D", 1, Tokens.RADIUS_SM, 2.0)
	)
	result.set_stylebox(
		"fill",
		"ProgressBar",
		Tokens.panel_style(Tokens.COLOR_ACCENT, Tokens.COLOR_BORDER_STRONG, 0, Tokens.RADIUS_SM, 2.0)
	)
	result.set_stylebox(
		"panel",
		"TooltipPanel",
		Tokens.panel_style(Tokens.COLOR_SURFACE_RAISED, Tokens.COLOR_BORDER_STRONG, 1, Tokens.RADIUS_SM, 8.0)
	)
	result.set_color("font_color", "TooltipLabel", Tokens.color(Tokens.COLOR_TEXT))
	result.set_constant("separation", "VBoxContainer", Tokens.SPACE_MD)
	result.set_constant("separation", "HBoxContainer", Tokens.SPACE_SM)
	return result
