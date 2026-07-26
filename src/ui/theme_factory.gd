class_name StarThemeFactory
extends RefCounted

const Tokens = preload("res://src/ui/design_tokens.gd")


static func create_theme() -> Theme:
	var result := Theme.new()
	_register_base_typography(result)
	_register_label_variations(result)
	_register_panel_variations(result)
	_register_button_variations(result)
	_register_inputs(result)
	_register_progress_and_scrolling(result)
	_register_miscellaneous(result)
	return result


static func _register_base_typography(theme: Theme) -> void:
	theme.set_default_font_size(Tokens.FONT_BODY)
	for control_type: String in [
		"Label", "Button", "LineEdit", "TextEdit", "OptionButton", "CheckButton", "RichTextLabel"
	]:
		theme.set_color("font_color", control_type, Tokens.color(Tokens.COLOR_TEXT))
	theme.set_font_size("font_size", "Label", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "Button", Tokens.FONT_BUTTON)
	theme.set_font_size("font_size", "LineEdit", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "TextEdit", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "OptionButton", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "CheckButton", Tokens.FONT_BODY)
	theme.set_font_size("normal_font_size", "RichTextLabel", Tokens.FONT_BODY)
	theme.set_color("default_color", "RichTextLabel", Tokens.color(Tokens.COLOR_TEXT))
	theme.set_color("font_placeholder_color", "LineEdit", Tokens.color(Tokens.COLOR_TEXT_SUBDUED))
	theme.set_color("font_uneditable_color", "LineEdit", Tokens.color(Tokens.COLOR_TEXT_MUTED))
	theme.set_color("caret_color", "LineEdit", Tokens.color(Tokens.COLOR_ACCENT))
	theme.set_color("selection_color", "LineEdit", Color("#1E7197AA"))


static func _register_label_variations(theme: Theme) -> void:
	_register_label(theme, "DisplayTitle", Tokens.FONT_DISPLAY, Tokens.COLOR_TEXT)
	_register_label(theme, "PageTitle", Tokens.FONT_TITLE, Tokens.COLOR_TEXT)
	_register_label(theme, "SectionTitle", Tokens.FONT_SUBTITLE, Tokens.COLOR_TEXT)
	_register_label(theme, "EyebrowLabel", Tokens.FONT_CAPTION, Tokens.COLOR_ACCENT)
	_register_label(theme, "MutedLabel", Tokens.FONT_SMALL, Tokens.COLOR_TEXT_MUTED)
	_register_label(theme, "SubduedLabel", Tokens.FONT_CAPTION, Tokens.COLOR_TEXT_SUBDUED)
	_register_label(theme, "CaptionLabel", Tokens.FONT_CAPTION, Tokens.COLOR_TEXT_MUTED)
	_register_label(theme, "MetricLabel", Tokens.FONT_BUTTON, Tokens.COLOR_ACCENT_SOFT)
	_register_label(theme, "DangerLabel", Tokens.FONT_SMALL, Tokens.COLOR_DANGER)
	_register_label(theme, "SuccessLabel", Tokens.FONT_SMALL, Tokens.COLOR_SUCCESS)
	_register_label(theme, "BadgeLabel", Tokens.FONT_CAPTION, Tokens.COLOR_ACCENT_SOFT)
	theme.set_stylebox(
		"normal",
		"BadgeLabel",
		Tokens.panel_style("#0E3042E8", Tokens.COLOR_BORDER_STRONG, 1, Tokens.RADIUS_XL, 6.0)
	)


static func _register_panel_variations(theme: Theme) -> void:
	theme.set_stylebox(
		"panel",
		"PanelContainer",
		Tokens.elevated_panel_style(
			Tokens.COLOR_SURFACE_GLASS,
			Tokens.COLOR_BORDER,
			1,
			Tokens.RADIUS_LG,
			Tokens.SPACE_LG,
			8,
			Vector2(0.0, 4.0)
		)
	)
	_register_panel(theme, "MenuCanvas", "#00000000", "#00000000", 0, 0, 0.0, 0)
	_register_panel(
		theme, "GlassPanel", Tokens.COLOR_SURFACE_GLASS, Tokens.COLOR_BORDER, 1,
		Tokens.RADIUS_LG, Tokens.SPACE_LG, 8
	)
	_register_panel(
		theme, "ElevatedPanel", Tokens.COLOR_SURFACE_RAISED, Tokens.COLOR_BORDER_STRONG, 1,
		Tokens.RADIUS_XL, Tokens.SPACE_XL, 12
	)
	_register_panel(
		theme, "CommandPanel", "#0A1B2BF7", Tokens.COLOR_BORDER_STRONG, 1,
		Tokens.RADIUS_XL, Tokens.SPACE_XL, 16
	)
	_register_panel(
		theme, "CardPanel", Tokens.COLOR_SURFACE_SOFT, Tokens.COLOR_BORDER_SUBTLE, 1,
		Tokens.RADIUS_MD, Tokens.SPACE_MD, 4
	)
	_register_panel(
		theme, "InsetPanel", Tokens.COLOR_INSET, Tokens.COLOR_BORDER_SUBTLE, 1,
		Tokens.RADIUS_MD, Tokens.SPACE_MD, 0
	)
	_register_panel(
		theme, "HudPanel", "#071522E8", Tokens.COLOR_BORDER, 1,
		Tokens.RADIUS_LG, Tokens.SPACE_MD, 7
	)
	_register_panel(
		theme, "ModalPanel", "#091827FA", Tokens.COLOR_BORDER_STRONG, 1,
		Tokens.RADIUS_XL, Tokens.SPACE_XL, 18
	)
	_register_panel(
		theme, "SuccessPanel", "#0E2A22F2", Tokens.COLOR_SUCCESS, 1,
		Tokens.RADIUS_LG, Tokens.SPACE_MD, 7
	)
	_register_panel(
		theme, "DangerPanel", "#2B131AF2", Tokens.COLOR_DANGER, 1,
		Tokens.RADIUS_LG, Tokens.SPACE_MD, 7
	)
	_register_panel(
		theme, "DiagnosticsBackdrop", Tokens.COLOR_OVERLAY, Tokens.COLOR_BORDER_STRONG, 1,
		Tokens.RADIUS_LG, Tokens.SPACE_LG, 0
	)
	_register_panel(
		theme, "DiagnosticsCard", "#071522F5", Tokens.COLOR_BORDER, 1,
		Tokens.RADIUS_MD, Tokens.SPACE_MD, 5
	)


static func _register_button_variations(theme: Theme) -> void:
	_register_button(
		theme,
		"Button",
		Tokens.COLOR_SURFACE_SOFT,
		Tokens.COLOR_SURFACE_INTERACTIVE,
		Tokens.COLOR_SURFACE_SELECTED,
		Tokens.COLOR_BORDER,
		Tokens.COLOR_BORDER_STRONG,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_WARM_BRIGHT,
		Tokens.FONT_BUTTON,
		Tokens.RADIUS_MD,
		9.0
	)
	_register_button(
		theme,
		"PrimaryButton",
		"#D6A63BEF",
		"#E6BB55F5",
		"#B98527F5",
		Tokens.COLOR_ACCENT_WARM,
		Tokens.COLOR_ACCENT_WARM_BRIGHT,
		Tokens.COLOR_BACKGROUND_DEEP,
		Tokens.COLOR_BACKGROUND_DEEP,
		"#07111C",
		Tokens.FONT_BUTTON,
		Tokens.RADIUS_MD,
		10.0
	)
	_register_button(
		theme,
		"SecondaryButton",
		"#103149F2",
		"#174864F5",
		"#0C293DF5",
		Tokens.COLOR_BORDER_STRONG,
		Tokens.COLOR_BORDER_FOCUS,
		Tokens.COLOR_TEXT,
		Color.WHITE.to_html(),
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_BUTTON,
		Tokens.RADIUS_MD,
		10.0
	)
	_register_button(
		theme,
		"GhostButton",
		"#0A172400",
		"#153047D9",
		"#10263ADB",
		Tokens.COLOR_BORDER_SUBTLE,
		Tokens.COLOR_BORDER,
		Tokens.COLOR_TEXT_MUTED,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_BUTTON,
		Tokens.RADIUS_MD,
		9.0
	)
	_register_button(
		theme,
		"DangerButton",
		"#391820E8",
		"#52222CF2",
		"#281118F2",
		Tokens.COLOR_DANGER_DEEP,
		Tokens.COLOR_DANGER,
		Tokens.COLOR_DANGER,
		"#FFB2B8",
		"#FFB2B8",
		Tokens.FONT_BUTTON,
		Tokens.RADIUS_MD,
		9.0
	)
	_register_button(
		theme,
		"MenuPrimaryButton",
		"#D9A73FF5",
		"#EDC35EF8",
		"#B98422F8",
		Tokens.COLOR_ACCENT_WARM,
		Tokens.COLOR_ACCENT_WARM_BRIGHT,
		Tokens.COLOR_BACKGROUND_DEEP,
		Tokens.COLOR_BACKGROUND_DEEP,
		"#07111C",
		Tokens.FONT_SUBTITLE,
		Tokens.RADIUS_LG,
		12.0
	)
	_register_button(
		theme,
		"MenuButton",
		"#0C2032E8",
		"#143A53F2",
		"#0C293DF5",
		Tokens.COLOR_BORDER,
		Tokens.COLOR_BORDER_STRONG,
		Tokens.COLOR_TEXT,
		Color.WHITE.to_html(),
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_BUTTON,
		Tokens.RADIUS_LG,
		11.0
	)
	_register_button(
		theme,
		"CardButton",
		Tokens.COLOR_SURFACE_SOFT,
		Tokens.COLOR_SURFACE_INTERACTIVE,
		Tokens.COLOR_SURFACE_SELECTED,
		Tokens.COLOR_BORDER_SUBTLE,
		Tokens.COLOR_BORDER,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_BODY,
		Tokens.RADIUS_MD,
		10.0
	)
	_register_button(
		theme,
		"SelectedCardButton",
		Tokens.COLOR_SURFACE_SELECTED,
		"#1A4C68F5",
		Tokens.COLOR_SURFACE_SELECTED,
		Tokens.COLOR_BORDER_STRONG,
		Tokens.COLOR_BORDER_FOCUS,
		Tokens.COLOR_TEXT,
		Color.WHITE.to_html(),
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_BODY,
		Tokens.RADIUS_MD,
		10.0,
		2
	)
	_register_button(
		theme,
		"ToolbarButton",
		"#0B1B2A99",
		"#153047DD",
		"#0B2234EE",
		Tokens.COLOR_BORDER_SUBTLE,
		Tokens.COLOR_BORDER,
		Tokens.COLOR_TEXT_MUTED,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_CAPTION,
		Tokens.RADIUS_SM,
		7.0
	)
	_register_button(
		theme,
		"RecipeButton",
		Tokens.COLOR_SURFACE_SOFT,
		Tokens.COLOR_SURFACE_INTERACTIVE,
		Tokens.COLOR_SURFACE_SELECTED,
		Tokens.COLOR_BORDER_SUBTLE,
		Tokens.COLOR_BORDER_STRONG,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_WARM_BRIGHT,
		Tokens.FONT_BODY,
		Tokens.RADIUS_MD,
		12.0
	)
	_register_button(
		theme,
		"InventorySlot",
		"#071421F0",
		"#102C42F2",
		"#0A1C2BF5",
		Tokens.COLOR_BORDER_SUBTLE,
		Tokens.COLOR_BORDER,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.FONT_CAPTION,
		Tokens.RADIUS_SM,
		4.0
	)
	_register_button(
		theme,
		"InventorySlotSelected",
		"#22341AF5",
		"#2B4520F5",
		"#1A2814F5",
		Tokens.COLOR_ACCENT_WARM,
		Tokens.COLOR_ACCENT_WARM_BRIGHT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_WARM_BRIGHT,
		Tokens.FONT_CAPTION,
		Tokens.RADIUS_SM,
		4.0,
		2
	)
	_register_button(
		theme,
		"InventorySlotSwap",
		"#123345F5",
		"#174A61F5",
		"#0F2B3BF5",
		Tokens.COLOR_ACCENT,
		Tokens.COLOR_BORDER_FOCUS,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_CAPTION,
		Tokens.RADIUS_SM,
		4.0,
		2
	)
	_register_button(
		theme,
		"MachineSlotButton",
		"#0B1C2CF5",
		"#15364FF5",
		"#0A1825F5",
		Tokens.COLOR_BORDER,
		Tokens.COLOR_BORDER_STRONG,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_ACCENT_SOFT,
		Tokens.FONT_BODY,
		Tokens.RADIUS_MD,
		10.0
	)
	_register_button(
		theme,
		"OutputSlotButton",
		"#123126F5",
		"#194633F5",
		"#0D281DF5",
		Tokens.COLOR_SUCCESS,
		"#A0F1BE",
		Tokens.COLOR_TEXT,
		Tokens.COLOR_TEXT,
		Tokens.COLOR_SUCCESS,
		Tokens.FONT_BODY,
		Tokens.RADIUS_MD,
		10.0
	)


static func _register_inputs(theme: Theme) -> void:
	theme.set_stylebox(
		"normal",
		"LineEdit",
		Tokens.panel_style(Tokens.COLOR_INSET, Tokens.COLOR_BORDER_SUBTLE, 1, Tokens.RADIUS_MD, 10.0)
	)
	theme.set_stylebox(
		"focus",
		"LineEdit",
		Tokens.panel_style("#0B2031F8", Tokens.COLOR_BORDER_FOCUS, 2, Tokens.RADIUS_MD, 10.0)
	)
	theme.set_stylebox(
		"read_only",
		"LineEdit",
		Tokens.panel_style("#0A141FDD", Tokens.COLOR_BORDER_SUBTLE, 1, Tokens.RADIUS_MD, 10.0)
	)
	theme.set_stylebox("normal", "TextEdit", theme.get_stylebox("normal", "LineEdit"))
	theme.set_stylebox("focus", "TextEdit", theme.get_stylebox("focus", "LineEdit"))
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(style_name, "OptionButton", theme.get_stylebox(style_name, "Button"))
	theme.set_stylebox("focus", "OptionButton", Tokens.focus_style(Tokens.RADIUS_MD))
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	theme.set_color("font_pressed_color", "OptionButton", Tokens.color(Tokens.COLOR_ACCENT_SOFT))

	for style_name: String in ["normal", "pressed", "hover", "hover_pressed"]:
		var fill := "#00000000" if style_name == "normal" else "#153047A8"
		theme.set_stylebox(
			style_name,
			"CheckButton",
			Tokens.panel_style(fill, "#00000000", 0, Tokens.RADIUS_MD, 8.0)
		)
	theme.set_stylebox("focus", "CheckButton", Tokens.focus_style(Tokens.RADIUS_MD))
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckButton", Tokens.color(Tokens.COLOR_ACCENT_SOFT))
	theme.set_color("font_disabled_color", "CheckButton", Tokens.color(Tokens.COLOR_TEXT_DISABLED))

	_register_popup_menu(theme)


static func _register_progress_and_scrolling(theme: Theme) -> void:
	theme.set_stylebox(
		"background",
		"ProgressBar",
		Tokens.panel_style("#050D15", Tokens.COLOR_BORDER_SUBTLE, 1, Tokens.RADIUS_XL, 2.0)
	)
	theme.set_stylebox(
		"fill",
		"ProgressBar",
		Tokens.panel_style(Tokens.COLOR_ACCENT_DEEP, Tokens.COLOR_ACCENT, 0, Tokens.RADIUS_XL, 2.0)
	)
	theme.set_color("font_color", "ProgressBar", Tokens.color(Tokens.COLOR_TEXT))

	for slider_type: String in ["HSlider", "VSlider"]:
		theme.set_stylebox(
			"slider",
			slider_type,
			Tokens.panel_style("#06101A", Tokens.COLOR_BORDER_SUBTLE, 1, Tokens.RADIUS_XL, 2.0)
		)
		theme.set_stylebox(
			"grabber_area",
			slider_type,
			Tokens.panel_style(Tokens.COLOR_ACCENT_DEEP, Tokens.COLOR_ACCENT_DEEP, 0, Tokens.RADIUS_XL, 2.0)
		)
		theme.set_stylebox(
			"grabber_area_highlight",
			slider_type,
			Tokens.panel_style(Tokens.COLOR_ACCENT, Tokens.COLOR_ACCENT, 0, Tokens.RADIUS_XL, 2.0)
		)

	for scroll_type: String in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox(
			"scroll",
			scroll_type,
			Tokens.panel_style("#030A11AA", "#00000000", 0, Tokens.RADIUS_XL, 1.0)
		)
		theme.set_stylebox(
			"grabber",
			scroll_type,
			Tokens.panel_style("#24455AE6", "#00000000", 0, Tokens.RADIUS_XL, 1.0)
		)
		theme.set_stylebox(
			"grabber_highlight",
			scroll_type,
			Tokens.panel_style("#3A718DEB", "#00000000", 0, Tokens.RADIUS_XL, 1.0)
		)
		theme.set_stylebox(
			"grabber_pressed",
			scroll_type,
			Tokens.panel_style(Tokens.COLOR_ACCENT_DEEP, "#00000000", 0, Tokens.RADIUS_XL, 1.0)
		)


static func _register_miscellaneous(theme: Theme) -> void:
	theme.set_stylebox(
		"panel",
		"TooltipPanel",
		Tokens.elevated_panel_style(
			Tokens.COLOR_SURFACE_RAISED,
			Tokens.COLOR_BORDER_STRONG,
			1,
			Tokens.RADIUS_MD,
			Tokens.SPACE_MD,
			8
		)
	)
	theme.set_color("font_color", "TooltipLabel", Tokens.color(Tokens.COLOR_TEXT))
	theme.set_font_size("font_size", "TooltipLabel", Tokens.FONT_CAPTION)
	theme.set_constant("separation", "VBoxContainer", Tokens.SPACE_MD)
	theme.set_constant("separation", "HBoxContainer", Tokens.SPACE_SM)
	theme.set_constant("h_separation", "GridContainer", Tokens.SPACE_SM)
	theme.set_constant("v_separation", "GridContainer", Tokens.SPACE_SM)

	theme.set_type_variation("SoftSeparator", "HSeparator")
	var separator := StyleBoxLine.new()
	separator.color = Tokens.color(Tokens.COLOR_BORDER_SUBTLE)
	separator.thickness = 1
	theme.set_stylebox("separator", "SoftSeparator", separator)
	theme.set_stylebox("separator", "HSeparator", separator)
	var vertical_separator := StyleBoxLine.new()
	vertical_separator.color = Tokens.color(Tokens.COLOR_BORDER_SUBTLE)
	vertical_separator.thickness = 1
	vertical_separator.vertical = true
	theme.set_stylebox("separator", "VSeparator", vertical_separator)


static func _register_label(
	theme: Theme,
	variation: String,
	font_size: int,
	font_color: String
) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_font_size("font_size", variation, font_size)
	theme.set_color("font_color", variation, Tokens.color(font_color))


static func _register_panel(
	theme: Theme,
	variation: String,
	fill: String,
	border: String,
	border_width: int,
	radius: int,
	padding: float,
	shadow_size: int
) -> void:
	theme.set_type_variation(variation, "PanelContainer")
	var style := Tokens.elevated_panel_style(
		fill, border, border_width, radius, padding, shadow_size,
		Vector2(0.0, 4.0 if shadow_size > 0 else 0.0)
	)
	theme.set_stylebox("panel", variation, style)


static func _register_button(
	theme: Theme,
	variation: String,
	normal_fill: String,
	hover_fill: String,
	pressed_fill: String,
	border: String,
	hover_border: String,
	font: String,
	hover_font: String,
	pressed_font: String,
	font_size: int,
	radius: int,
	padding: float,
	border_width: int = 1
) -> void:
	if variation != "Button":
		theme.set_type_variation(variation, "Button")
	theme.set_font_size("font_size", variation, font_size)
	theme.set_color("font_color", variation, Tokens.color(font))
	theme.set_color("font_hover_color", variation, Tokens.color(hover_font))
	theme.set_color("font_pressed_color", variation, Tokens.color(pressed_font))
	theme.set_color("font_focus_color", variation, Tokens.color(hover_font))
	theme.set_color("font_disabled_color", variation, Tokens.color(Tokens.COLOR_TEXT_DISABLED))
	theme.set_stylebox(
		"normal", variation,
		Tokens.panel_style(normal_fill, border, border_width, radius, padding)
	)
	theme.set_stylebox(
		"hover", variation,
		Tokens.elevated_panel_style(
			hover_fill, hover_border, maxi(1, border_width), radius, padding, 5, Vector2(0.0, 2.0)
		)
	)
	theme.set_stylebox(
		"pressed", variation,
		Tokens.panel_style(pressed_fill, hover_border, maxi(1, border_width), radius, padding)
	)
	theme.set_stylebox(
		"hover_pressed", variation,
		Tokens.panel_style(pressed_fill, hover_border, maxi(1, border_width), radius, padding)
	)
	theme.set_stylebox(
		"disabled", variation,
		Tokens.panel_style("#0B141ED9", Tokens.COLOR_BORDER_SUBTLE, 1, radius, padding)
	)
	theme.set_stylebox("focus", variation, Tokens.focus_style(radius))


static func _register_popup_menu(theme: Theme) -> void:
	theme.set_stylebox(
		"panel",
		"PopupMenu",
		Tokens.elevated_panel_style(
			Tokens.COLOR_SURFACE_RAISED,
			Tokens.COLOR_BORDER_STRONG,
			1,
			Tokens.RADIUS_MD,
			Tokens.SPACE_SM,
			10
		)
	)
	theme.set_stylebox(
		"hover",
		"PopupMenu",
		Tokens.panel_style(Tokens.COLOR_SURFACE_INTERACTIVE, Tokens.COLOR_BORDER_STRONG, 1, Tokens.RADIUS_SM, 5.0)
	)
	theme.set_color("font_color", "PopupMenu", Tokens.color(Tokens.COLOR_TEXT))
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_font_size("font_size", "PopupMenu", Tokens.FONT_BODY)
