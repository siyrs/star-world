class_name StarThemeFactory
extends RefCounted


static func create_theme() -> Theme:
	var result := Theme.new()
	result.set_default_font_size(18)
	result.set_font_size("font_size", "Label", 18)
	result.set_font_size("font_size", "Button", 18)
	result.set_color("font_color", "Label", Color("#EAF5FF"))
	result.set_color("font_color", "Button", Color("#F4FAFF"))
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("#788591"))
	result.set_stylebox("panel", "PanelContainer", _box(Color("#101826E8"), Color("#4FA2C8"), 2, 10))
	result.set_stylebox("normal", "Button", _box(Color("#24364C"), Color("#426682"), 2, 7))
	result.set_stylebox("hover", "Button", _box(Color("#315673"), Color("#65C8EB"), 2, 7))
	result.set_stylebox("pressed", "Button", _box(Color("#183044"), Color("#FFD66B"), 2, 7))
	result.set_stylebox("disabled", "Button", _box(Color("#17212D"), Color("#34404B"), 1, 7))
	result.set_stylebox("background", "ProgressBar", _box(Color("#111821"), Color("#3C4B5B"), 1, 4))
	result.set_stylebox("fill", "ProgressBar", _box(Color("#53B5DB"), Color("#83DAFA"), 1, 4))
	return result


static func _box(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box
