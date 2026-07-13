class_name StarDesignTokens
extends RefCounted

const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 18
const SPACE_XL := 26

const RADIUS_SM := 5
const RADIUS_MD := 9
const RADIUS_LG := 13

const FONT_CAPTION := 14
const FONT_BODY := 17
const FONT_BUTTON := 18
const FONT_TITLE := 30
const FONT_HERO := 48

const COLOR_TEXT := "#EAF5FF"
const COLOR_TEXT_MUTED := "#91AABD"
const COLOR_TEXT_DISABLED := "#647583"
const COLOR_SURFACE := "#0D1724EE"
const COLOR_SURFACE_RAISED := "#142538F2"
const COLOR_SURFACE_SOFT := "#172B3DEB"
const COLOR_BORDER := "#3C7699"
const COLOR_BORDER_STRONG := "#69C8EE"
const COLOR_ACCENT := "#62C7E9"
const COLOR_ACCENT_WARM := "#FFD36C"
const COLOR_SUCCESS := "#75D28B"
const COLOR_WARNING := "#F0BE62"
const COLOR_DANGER := "#F27B82"
const COLOR_HEALTH := "#F06F78"
const COLOR_HUNGER := "#E9B755"


static func color(value: String) -> Color:
	return Color(value)


static func panel_style(
	fill: String = COLOR_SURFACE,
	border: String = COLOR_BORDER,
	border_width: int = 1,
	radius: int = RADIUS_MD,
	padding: float = 10.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color(fill)
	box.border_color = color(border)
	box.set_border_width_all(border_width)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box


static func severity_color(severity: String) -> Color:
	match severity:
		"success":
			return color(COLOR_SUCCESS)
		"warning":
			return color(COLOR_WARNING)
		"error":
			return color(COLOR_DANGER)
		_:
			return color(COLOR_ACCENT)
