class_name StarUiKit
extends RefCounted

const Tokens = preload("res://src/ui/design_tokens.gd")


static func style_button(
	button: Button,
	variation: String = "SecondaryButton",
	minimum_size: Vector2 = Vector2(0.0, Tokens.CONTROL_HEIGHT_MD)
) -> Button:
	if button == null:
		return button
	button.theme_type_variation = variation
	button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, minimum_size.x)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, minimum_size.y)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	return button


static func style_panel(panel: PanelContainer, variation: String = "GlassPanel") -> PanelContainer:
	if panel != null:
		panel.theme_type_variation = variation
	return panel


static func style_label(label: Label, variation: String) -> Label:
	if label != null:
		label.theme_type_variation = variation
	return label


static func make_eyebrow(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = "EyebrowLabel"
	return label


static func make_title(text: String, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "DisplayTitle" if display else "PageTitle"
	return label


static func make_subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func make_badge(text: String, tone: String = "info") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "BadgeLabel"
	label.add_theme_color_override("font_color", _tone_text_color(tone))
	label.add_theme_stylebox_override(
		"normal",
		Tokens.panel_style(
			_tone_fill(tone),
			Tokens.tone_border(tone),
			1,
			Tokens.RADIUS_XL,
			6.0
		)
	)
	return label


static func make_section_header(title: String, subtitle: String = "") -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_XS)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "SectionTitle"
	root.add_child(label)
	if not subtitle.is_empty():
		root.add_child(make_subtitle(subtitle))
	return root


static func make_divider() -> HSeparator:
	var separator := HSeparator.new()
	separator.theme_type_variation = "SoftSeparator"
	return separator


static func make_card(
	variation: String = "CardPanel",
	minimum_size: Vector2 = Vector2.ZERO
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	panel.custom_minimum_size = minimum_size
	return panel


static func set_selected_card(button: Button, selected: bool) -> void:
	if button == null:
		return
	button.theme_type_variation = "SelectedCardButton" if selected else "CardButton"
	button.button_pressed = selected


static func set_margin(
	container: MarginContainer,
	left: int,
	top: int,
	right: int,
	bottom: int
) -> void:
	if container == null:
		return
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)


static func format_bytes(value: int) -> String:
	var safe_value := maxi(0, value)
	if safe_value < 1024:
		return "%d B" % safe_value
	if safe_value < 1024 * 1024:
		return "%.1f KB" % (float(safe_value) / 1024.0)
	if safe_value < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(safe_value) / float(1024 * 1024))
	return "%.1f GB" % (float(safe_value) / float(1024 * 1024 * 1024))


static func _tone_fill(tone: String) -> String:
	match tone:
		"success":
			return "#123528E8"
		"warning", "warm", "primary":
			return "#3A2E16E8"
		"danger", "error", "critical":
			return "#3B1A23E8"
		_:
			return "#0E3042E8"


static func _tone_text_color(tone: String) -> Color:
	match tone:
		"success":
			return Tokens.color(Tokens.COLOR_SUCCESS)
		"warning", "warm", "primary":
			return Tokens.color(Tokens.COLOR_ACCENT_WARM_BRIGHT)
		"danger", "error", "critical":
			return Tokens.color(Tokens.COLOR_DANGER)
		_:
			return Tokens.color(Tokens.COLOR_ACCENT_SOFT)
