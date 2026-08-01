class_name StarThemeFactory
extends RefCounted

const Tokens = preload("res://src/ui/design_tokens.gd")
const PixelTextures = preload("res://src/ui/pixel_ui_textures.gd")

# Preloaded pixel font forces Godot to include the imported resource in exports.
# Without this, FileAccess-based loading may succeed in the editor but miss the
# dependency at export time, producing a font-fallback warning (BUG-UI-001).
const PIXEL_FONT_IMPORT = preload("res://assets/fonts/fusion_pixel_12px_mono.ttf")

# Theme contexts: "overlay" floats over the 3D world or the menu dirt
# background (light text with pixel shadow, dark translucent panels), while
# "panel" renders classic light-gray Minecraft GUI surfaces (dark text).
const CONTEXT_OVERLAY := &"overlay"
const CONTEXT_PANEL := &"panel"

static var _pixel_font: FontFile
static var _font_loaded := false


static func create_theme(context: StringName = CONTEXT_OVERLAY) -> Theme:
	var result := Theme.new()
	_register_base_typography(result, context)
	_register_label_variations(result, context)
	_register_panel_variations(result, context)
	_register_button_variations(result, context)
	_register_inputs(result, context)
	_register_progress_and_scrolling(result, context)
	_register_miscellaneous(result, context)
	return result


static func get_ui_font() -> Font:
	if _font_loaded:
		return _pixel_font
	_font_loaded = true
	_pixel_font = null
	# Primary path: use the preloaded resource so Godot includes the font in
	# exports. Fall back to raw FileAccess loading for editor hot-reload edge cases.
	if PIXEL_FONT_IMPORT is FontFile:
		_pixel_font = (PIXEL_FONT_IMPORT as FontFile).duplicate()
		_pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_pixel_font.hinting = TextServer.HINTING_NONE
		_pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_pixel_font.oversampling = 1.0
		_pixel_font.multichannel_signed_distance_field = false
	elif FileAccess.file_exists(Tokens.PIXEL_FONT_PATH):
		var bytes := FileAccess.get_file_as_bytes(Tokens.PIXEL_FONT_PATH)
		if bytes.size() > 1024:
			var font := FontFile.new()
			font.data = bytes
			font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			font.hinting = TextServer.HINTING_NONE
			font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			font.oversampling = 1.0
			font.multichannel_signed_distance_field = false
			_pixel_font = font
	if _pixel_font == null:
		push_warning("Pixel font missing at %s; falling back to the default font." % Tokens.PIXEL_FONT_PATH)
	return _pixel_font


static func _register_base_typography(theme: Theme, context: StringName) -> void:
	var font := get_ui_font()
	if font != null:
		theme.default_font = font
	theme.set_default_font_size(Tokens.FONT_BODY)
	var text_color := _text_color(context, "body")
	for control_type: String in [
		"Label", "Button", "LineEdit", "TextEdit", "OptionButton", "CheckButton", "RichTextLabel"
	]:
		theme.set_color("font_color", control_type, text_color)
	theme.set_font_size("font_size", "Label", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "Button", Tokens.FONT_BUTTON)
	theme.set_font_size("font_size", "LineEdit", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "TextEdit", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "OptionButton", Tokens.FONT_BODY)
	theme.set_font_size("font_size", "CheckButton", Tokens.FONT_BODY)
	theme.set_font_size("normal_font_size", "RichTextLabel", Tokens.FONT_BODY)
	theme.set_color("default_color", "RichTextLabel", text_color)
	theme.set_color("font_placeholder_color", "LineEdit", _text_color(context, "subdued"))
	theme.set_color("font_uneditable_color", "LineEdit", _text_color(context, "muted"))
	theme.set_color("caret_color", "LineEdit", Tokens.color(Tokens.COLOR_ACCENT))
	theme.set_color("selection_color", "LineEdit", Color("#4E7A2866"))
	# Dark overlay buttons use the classic pixel shadow. Panel-context flat
	# buttons inherit a shadow-free base so dark text stays crisp on light gray.
	for button_type: String in ["Button", "OptionButton"]:
		var shadow_enabled := context != CONTEXT_PANEL
		theme.set_color(
			"font_shadow_color",
			button_type,
			Color("#101010CC") if shadow_enabled else Color.TRANSPARENT
		)
		theme.set_constant("shadow_offset_x", button_type, 1 if shadow_enabled else 0)
		theme.set_constant("shadow_offset_y", button_type, 1 if shadow_enabled else 0)
		theme.set_constant("shadow_outline_size", button_type, 2 if shadow_enabled else 0)


static func _text_color(context: StringName, role: String) -> Color:
	if context == CONTEXT_PANEL:
		match role:
			"body":
				return Tokens.color(Tokens.MC_PANEL_TEXT)
			"muted":
				return Tokens.color(Tokens.MC_PANEL_TEXT_MUTED)
			"subdued":
				return Tokens.color("#6E6E6E")
			"danger":
				return Tokens.color("#A02818")
			"success":
				return Tokens.color("#3E7A24")
			"accent":
				return Tokens.color(Tokens.MC_PANEL_ACCENT)
	match role:
		"body":
			return Tokens.color(Tokens.COLOR_TEXT)
		"muted":
			return Tokens.color(Tokens.COLOR_TEXT_MUTED)
		"subdued":
			return Tokens.color(Tokens.COLOR_TEXT_SUBDUED)
		"danger":
			return Tokens.color(Tokens.COLOR_DANGER)
		"success":
			return Tokens.color(Tokens.COLOR_SUCCESS)
		"accent":
			return Tokens.color(Tokens.COLOR_ACCENT_SOFT)
	return Tokens.color(Tokens.COLOR_TEXT)


static func _register_label_variations(theme: Theme, context: StringName) -> void:
	var use_pixel_shadow := context != CONTEXT_PANEL
	_register_label(theme, context, "DisplayTitle", Tokens.FONT_DISPLAY, "body", use_pixel_shadow)
	_register_label(theme, context, "PageTitle", Tokens.FONT_TITLE, "body", use_pixel_shadow)
	_register_label(theme, context, "SectionTitle", Tokens.FONT_SUBTITLE, "body", use_pixel_shadow)
	_register_label(theme, context, "EyebrowLabel", Tokens.FONT_CAPTION, "accent", context != CONTEXT_PANEL)
	_register_label(theme, context, "MutedLabel", Tokens.FONT_SMALL, "muted", context != CONTEXT_PANEL)
	_register_label(theme, context, "SubduedLabel", Tokens.FONT_CAPTION, "subdued", context != CONTEXT_PANEL)
	_register_label(theme, context, "CaptionLabel", Tokens.FONT_CAPTION, "muted", context != CONTEXT_PANEL)
	_register_label(theme, context, "MetricLabel", Tokens.FONT_SUBTITLE, "accent", context != CONTEXT_PANEL)
	_register_label(theme, context, "DangerLabel", Tokens.FONT_SMALL, "danger", context != CONTEXT_PANEL)
	_register_label(theme, context, "SuccessLabel", Tokens.FONT_SMALL, "success", context != CONTEXT_PANEL)
	_register_label(theme, context, "BadgeLabel", Tokens.FONT_CAPTION, "accent", context != CONTEXT_PANEL)
	if context == CONTEXT_PANEL:
		theme.set_stylebox(
			"normal",
			"BadgeLabel",
			Tokens.bevel_style("#B0B0B0", "#7A7A7A", 2, 6.0)
		)
	else:
		theme.set_stylebox(
			"normal",
			"BadgeLabel",
			Tokens.bevel_style("#241A10E8", Tokens.COLOR_BORDER_STRONG, 2, 6.0)
		)


static func _register_panel_variations(theme: Theme, context: StringName) -> void:
	if context == CONTEXT_PANEL:
		theme.set_stylebox("panel", "PanelContainer", PixelTextures.panel_style_box())
	else:
		theme.set_stylebox(
			"panel",
			"PanelContainer",
			Tokens.bevel_style("#181209F2", Tokens.COLOR_BORDER, 2, Tokens.SPACE_LG)
		)
	_register_panel(theme, context, "MenuCanvas", "#00000000", "#00000000", 0)
	_register_panel(theme, context, "GlassPanel", "", "", 0)
	_register_panel(theme, context, "ElevatedPanel", "", "", 0)
	_register_panel(theme, context, "CommandPanel", "", "", 0)
	_register_panel(theme, context, "CardPanel", "", "", 0)
	_register_panel(theme, context, "InsetPanel", "", "", 0, true)
	_register_panel(theme, context, "HudPanel", "#100C07E8", Tokens.COLOR_BORDER, 2)
	_register_panel(theme, context, "ModalPanel", "", "", 0)
	_register_panel(theme, context, "SuccessPanel", "#16240FF2", Tokens.COLOR_SUCCESS, 2)
	_register_panel(theme, context, "DangerPanel", "#2A0F0AF2", Tokens.COLOR_DANGER, 2)
	_register_panel(theme, context, "DiagnosticsBackdrop", Tokens.COLOR_OVERLAY, Tokens.COLOR_BORDER_STRONG, 2)
	_register_panel(theme, context, "DiagnosticsCard", "#100C07F5", Tokens.COLOR_BORDER, 2)


static func _register_panel(
	theme: Theme,
	context: StringName,
	variation: String,
	fill: String,
	border: String,
	border_width: int,
	inset: bool = false
) -> void:
	theme.set_type_variation(variation, "PanelContainer")
	if variation == "MenuCanvas":
		theme.set_stylebox("panel", variation, Tokens.empty_style())
		return
	if fill.is_empty():
		if context == CONTEXT_PANEL:
			theme.set_stylebox(
				"panel",
				variation,
				PixelTextures.slot_style_box() if inset else PixelTextures.panel_style_box()
			)
		else:
			theme.set_stylebox(
				"panel",
				variation,
				Tokens.bevel_style("#0D0905EE" if inset else "#1B130BF2", Tokens.COLOR_BORDER, 2, Tokens.SPACE_MD)
			)
		return
	theme.set_stylebox("panel", variation, Tokens.bevel_style(fill, border, border_width, Tokens.SPACE_MD))


static func _register_button_variations(theme: Theme, context: StringName) -> void:
	_register_textured_button(theme, "Button", "normal", "hover", "pressed", Tokens.FONT_BUTTON)
	_register_textured_button(theme, "PrimaryButton", "primary", "primary_hover", "primary_pressed", Tokens.FONT_BUTTON)
	_register_textured_button(theme, "SecondaryButton", "normal", "hover", "pressed", Tokens.FONT_BUTTON)
	_register_textured_button(theme, "DangerButton", "danger", "danger_hover", "danger_pressed", Tokens.FONT_BUTTON)
	_register_textured_button(theme, "MenuPrimaryButton", "primary", "primary_hover", "primary_pressed", Tokens.FONT_SUBTITLE)
	_register_textured_button(theme, "MenuButton", "normal", "hover", "pressed", Tokens.FONT_BUTTON)
	_register_textured_button(theme, "RecipeButton", "normal", "hover", "pressed", Tokens.FONT_BODY)
	_register_flat_button(
		theme, context, "GhostButton",
		"#00000000", "#00000066", "#00000088",
		Tokens.COLOR_BORDER_SUBTLE, Tokens.COLOR_BORDER_STRONG,
		"muted", "body", "accent",
		Tokens.FONT_BUTTON
	) if context != CONTEXT_PANEL else _register_flat_button(
		theme, context, "GhostButton",
		"#00000000", "#FFFFFF66", "#FFFFFF88",
		Tokens.COLOR_BORDER_SUBTLE, Tokens.COLOR_BORDER_STRONG,
		"muted", "body", "accent",
		Tokens.FONT_BUTTON
	)
	_register_flat_button(
		theme, context, "CardButton",
		"#100C07CC" if context != CONTEXT_PANEL else "#B4B4B4",
		"#241A10E8" if context != CONTEXT_PANEL else "#C6C6C6",
		"#0D0905E8" if context != CONTEXT_PANEL else "#B7B7B7",
		Tokens.COLOR_BORDER_SUBTLE, Tokens.COLOR_BORDER_STRONG,
		"body", "body", "body" if context == CONTEXT_PANEL else "accent",
		Tokens.FONT_BODY
	)
	_register_flat_button(
		theme, context, "SelectedCardButton",
		"#2E3410E8" if context != CONTEXT_PANEL else "#C9D89A",
		"#3A4214F2" if context != CONTEXT_PANEL else "#D8E6AC",
		"#2E3410F2" if context != CONTEXT_PANEL else "#B9C98A",
		Tokens.COLOR_ACCENT, Tokens.COLOR_BORDER_FOCUS,
		"body", "body", "body" if context == CONTEXT_PANEL else "accent",
		Tokens.FONT_BODY, 2
	)
	_register_flat_button(
		theme, context, "ToolbarButton",
		"#00000055", "#00000088", "#000000AA",
		Tokens.COLOR_BORDER_SUBTLE, Tokens.COLOR_BORDER,
		"muted", "body", "accent",
		Tokens.FONT_CAPTION, 1
	) if context != CONTEXT_PANEL else _register_flat_button(
		theme, context, "ToolbarButton",
		"#D0D0D0", "#E0E0E0", "#C8C8C8",
		Tokens.COLOR_BORDER_SUBTLE, Tokens.COLOR_BORDER,
		"muted", "body", "accent",
		Tokens.FONT_CAPTION, 1
	)
	_register_slot_buttons(theme)


static func _register_textured_button(
	theme: Theme,
	variation: String,
	normal_state: String,
	hover_state: String,
	pressed_state: String,
	font_size: int
) -> void:
	# Built-in type names receive direct styles; only custom names become variations.
	if variation not in ["Button", "MenuButton"]:
		theme.set_type_variation(variation, "Button")
	theme.set_font_size("font_size", variation, font_size)
	theme.set_color("font_color", variation, Color("#FFFFFF"))
	theme.set_color("font_hover_color", variation, Color("#FFFFA0"))
	theme.set_color("font_pressed_color", variation, Color("#FFFFFF"))
	theme.set_color("font_focus_color", variation, Color("#FFFFA0"))
	theme.set_color("font_disabled_color", variation, Color("#A0A0A0"))
	theme.set_color("font_shadow_color", variation, Color("#101010CC"))
	theme.set_constant("shadow_offset_x", variation, 1)
	theme.set_constant("shadow_offset_y", variation, 1)
	theme.set_constant("shadow_outline_size", variation, 2)
	theme.set_stylebox("normal", variation, PixelTextures.button_style(normal_state))
	theme.set_stylebox("hover", variation, PixelTextures.button_style(hover_state))
	theme.set_stylebox("pressed", variation, PixelTextures.button_style(pressed_state))
	theme.set_stylebox("hover_pressed", variation, PixelTextures.button_style(pressed_state))
	theme.set_stylebox("disabled", variation, PixelTextures.button_style("disabled"))
	theme.set_stylebox("focus", variation, Tokens.focus_style())


static func _register_flat_button(
	theme: Theme,
	context: StringName,
	variation: String,
	normal_fill: String,
	hover_fill: String,
	pressed_fill: String,
	border: String,
	hover_border: String,
	font_role: String,
	hover_font_role: String,
	pressed_font_role: String,
	font_size: int,
	border_width: int = 1
) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_font_size("font_size", variation, font_size)
	theme.set_color("font_color", variation, _text_color(context, font_role))
	theme.set_color("font_hover_color", variation, _text_color(context, hover_font_role))
	theme.set_color("font_pressed_color", variation, _text_color(context, pressed_font_role))
	theme.set_color("font_focus_color", variation, _text_color(context, hover_font_role))
	theme.set_color("font_disabled_color", variation, _text_color(context, "subdued"))
	theme.set_stylebox("normal", variation, Tokens.bevel_style(normal_fill, border, border_width, 9.0))
	theme.set_stylebox("hover", variation, Tokens.bevel_style(hover_fill, hover_border, border_width, 9.0))
	theme.set_stylebox("pressed", variation, Tokens.bevel_style(pressed_fill, hover_border, border_width, 9.0))
	theme.set_stylebox("hover_pressed", variation, Tokens.bevel_style(pressed_fill, hover_border, border_width, 9.0))
	theme.set_stylebox("disabled", variation, Tokens.bevel_style("#00000033", border, border_width, 9.0))
	theme.set_stylebox("focus", variation, Tokens.focus_style())


static func _register_slot_buttons(theme: Theme) -> void:
	for variation: String in [
		"InventorySlot", "InventorySlotSelected", "InventorySlotSwap",
		"MachineSlotButton", "OutputSlotButton"
	]:
		theme.set_type_variation(variation, "Button")
		theme.set_font_size("font_size", variation, Tokens.FONT_CAPTION)
		theme.set_color("font_color", variation, Color("#FFFFFF"))
		theme.set_color("font_hover_color", variation, Color("#FFFFFF"))
		theme.set_color("font_pressed_color", variation, Color("#FFFFFF"))
		theme.set_color("font_focus_color", variation, Color("#FFFFFF"))
		theme.set_color("font_disabled_color", variation, Color("#A0A0A0"))
		theme.set_color("font_shadow_color", variation, Color("#101010CC"))
		theme.set_constant("shadow_offset_x", variation, 1)
		theme.set_constant("shadow_offset_y", variation, 1)
		theme.set_stylebox("normal", variation, PixelTextures.slot_style_box())
		theme.set_stylebox("hover", variation, PixelTextures.slot_style_box())
		theme.set_stylebox("pressed", variation, PixelTextures.slot_style_box())
		theme.set_stylebox("hover_pressed", variation, PixelTextures.slot_style_box())
		theme.set_stylebox("disabled", variation, PixelTextures.slot_style_box())
		theme.set_stylebox("focus", variation, Tokens.focus_style())
	theme.set_stylebox(
		"normal", "InventorySlotSelected",
		Tokens.bevel_style(Tokens.MC_SLOT, Tokens.MC_HOTBAR_FRAME, 2, 4.0)
	)
	theme.set_stylebox(
		"hover", "InventorySlotSelected",
		Tokens.bevel_style(Tokens.MC_SLOT, Tokens.COLOR_ACCENT_WARM_BRIGHT, 2, 4.0)
	)
	theme.set_stylebox(
		"normal", "InventorySlotSwap",
		Tokens.bevel_style(Tokens.MC_SLOT, Tokens.COLOR_ACCENT, 2, 4.0)
	)
	theme.set_stylebox(
		"hover", "InventorySlotSwap",
		Tokens.bevel_style(Tokens.MC_SLOT, Tokens.COLOR_ACCENT_SOFT, 2, 4.0)
	)


static func _register_inputs(theme: Theme, context: StringName) -> void:
	var normal_fill := "#E8E8E8" if context == CONTEXT_PANEL else "#0D0905EE"
	var text_color := _text_color(context, "body")
	theme.set_stylebox("normal", "LineEdit", Tokens.bevel_style(normal_fill, "#555555", 2, 10.0))
	theme.set_stylebox("focus", "LineEdit", Tokens.bevel_style(normal_fill, Tokens.COLOR_BORDER_FOCUS, 2, 10.0))
	theme.set_stylebox("read_only", "LineEdit", Tokens.bevel_style("#B0B0B0" if context == CONTEXT_PANEL else "#100C07DD", "#555555", 2, 10.0))
	theme.set_color("font_color", "LineEdit", text_color)
	theme.set_stylebox("normal", "TextEdit", theme.get_stylebox("normal", "LineEdit"))
	theme.set_stylebox("focus", "TextEdit", theme.get_stylebox("focus", "LineEdit"))
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(style_name, "OptionButton", theme.get_stylebox(style_name, "Button"))
	theme.set_stylebox("focus", "OptionButton", Tokens.focus_style())
	theme.set_color("font_hover_color", "OptionButton", Color("#FFFFA0"))
	theme.set_color("font_pressed_color", "OptionButton", Color.WHITE)

	for style_name: String in ["normal", "pressed", "hover", "hover_pressed"]:
		var fill := "#00000000" if style_name == "normal" else "#00000044"
		theme.set_stylebox(style_name, "CheckButton", Tokens.bevel_style(fill, "#00000000", 0, 8.0))
	theme.set_stylebox("focus", "CheckButton", Tokens.focus_style())
	theme.set_color("font_color", "CheckButton", text_color)
	theme.set_color("font_hover_color", "CheckButton", _text_color(context, "accent"))
	theme.set_color("font_pressed_color", "CheckButton", _text_color(context, "accent"))
	theme.set_color("font_disabled_color", "CheckButton", _text_color(context, "subdued"))

	_register_popup_menu(theme, context)


static func _register_progress_and_scrolling(theme: Theme, context: StringName) -> void:
	var bar_bg := "#0D0905" if context != CONTEXT_PANEL else "#6E6E6E"
	theme.set_stylebox("background", "ProgressBar", Tokens.bevel_style(bar_bg, "#373737", 2, 2.0))
	theme.set_stylebox("fill", "ProgressBar", Tokens.bevel_style(Tokens.COLOR_ACCENT_DEEP, Tokens.COLOR_ACCENT, 1, 2.0))
	theme.set_color("font_color", "ProgressBar", Color.WHITE)

	for slider_type: String in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", slider_type, Tokens.bevel_style(bar_bg, "#373737", 2, 2.0))
		theme.set_stylebox("grabber_area", slider_type, Tokens.bevel_style(Tokens.COLOR_ACCENT_DEEP, Tokens.COLOR_ACCENT_DEEP, 0, 2.0))
		theme.set_stylebox("grabber_area_highlight", slider_type, Tokens.bevel_style(Tokens.COLOR_ACCENT, Tokens.COLOR_ACCENT, 0, 2.0))
		theme.set_icon("grabber", slider_type, PixelTextures.grabber_icon())
		theme.set_icon("grabber_highlight", slider_type, PixelTextures.grabber_icon(true))

	for scroll_type: String in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, Tokens.bevel_style("#00000066", "#00000000", 0, 1.0))
		theme.set_stylebox("grabber", scroll_type, Tokens.bevel_style(Tokens.MC_BUTTON, "#555555", 2, 1.0))
		theme.set_stylebox("grabber_highlight", scroll_type, Tokens.bevel_style(Tokens.MC_BUTTON_HOVER, "#555555", 2, 1.0))
		theme.set_stylebox("grabber_pressed", scroll_type, Tokens.bevel_style("#666666", "#555555", 2, 1.0))


static func _register_miscellaneous(theme: Theme, context: StringName) -> void:
	theme.set_stylebox(
		"panel",
		"TooltipPanel",
		Tokens.bevel_style("#100010F5", "#5030A0", 2, Tokens.SPACE_MD)
	)
	theme.set_color("font_color", "TooltipLabel", Tokens.color(Tokens.COLOR_TEXT))
	theme.set_font_size("font_size", "TooltipLabel", Tokens.FONT_CAPTION)
	theme.set_constant("separation", "VBoxContainer", Tokens.SPACE_MD)
	theme.set_constant("separation", "HBoxContainer", Tokens.SPACE_SM)
	theme.set_constant("h_separation", "GridContainer", Tokens.SPACE_SM)
	theme.set_constant("v_separation", "GridContainer", Tokens.SPACE_SM)

	theme.set_type_variation("SoftSeparator", "HSeparator")
	var separator := StyleBoxLine.new()
	separator.color = Tokens.color("#373737" if context == CONTEXT_PANEL else Tokens.COLOR_BORDER_SUBTLE)
	separator.thickness = 2
	theme.set_stylebox("separator", "SoftSeparator", separator)
	theme.set_stylebox("separator", "HSeparator", separator)
	var vertical_separator := StyleBoxLine.new()
	vertical_separator.color = separator.color
	vertical_separator.thickness = 2
	vertical_separator.vertical = true
	theme.set_stylebox("separator", "VSeparator", vertical_separator)


static func _register_popup_menu(theme: Theme, context: StringName) -> void:
	theme.set_stylebox(
		"panel",
		"PopupMenu",
		PixelTextures.panel_style_box() if context == CONTEXT_PANEL else Tokens.bevel_style("#1B130BF5", Tokens.COLOR_BORDER_STRONG, 2, Tokens.SPACE_SM)
	)
	theme.set_stylebox(
		"hover",
		"PopupMenu",
		Tokens.bevel_style("#B4B4B4" if context == CONTEXT_PANEL else "#3A2C1AF2", "#555555", 1, 5.0)
	)
	theme.set_color("font_color", "PopupMenu", _text_color(context, "body"))
	theme.set_color("font_hover_color", "PopupMenu", _text_color(context, "body"))
	theme.set_font_size("font_size", "PopupMenu", Tokens.FONT_BODY)


static func _register_label(
	theme: Theme,
	context: StringName,
	variation: String,
	font_size: int,
	role: String,
	shadow: bool
) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_font_size("font_size", variation, font_size)
	theme.set_color("font_color", variation, _text_color(context, role))
	if shadow:
		theme.set_color("font_shadow_color", variation, Color("#101010CC"))
		theme.set_constant("shadow_offset_x", variation, 1)
		theme.set_constant("shadow_offset_y", variation, 1)
		theme.set_constant("shadow_outline_size", variation, 2)
