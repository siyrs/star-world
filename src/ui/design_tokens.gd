class_name StarDesignTokens
extends RefCounted

# Eight-point spatial rhythm with compact aliases kept for existing call sites.
const SPACE_2XS := 2
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 24
const SPACE_2XL := 32
const SPACE_3XL := 40

const RADIUS_XS := 6
const RADIUS_SM := 8
const RADIUS_MD := 12
const RADIUS_LG := 18
const RADIUS_XL := 24

const FONT_MICRO := 12
const FONT_CAPTION := 14
const FONT_SMALL := 15
const FONT_BODY := 17
const FONT_BUTTON := 17
const FONT_SUBTITLE := 20
const FONT_TITLE := 30
const FONT_DISPLAY := 56
const FONT_HERO := 64

const CONTROL_HEIGHT_SM := 36
const CONTROL_HEIGHT_MD := 44
const CONTROL_HEIGHT_LG := 52
const PANEL_SAFE_MARGIN := 18
const CONTENT_MAX_WIDTH := 1180

# Celestial Expedition palette. All screens consume these semantic values instead
# of owning independent hard-coded blues.
const COLOR_BACKGROUND_DEEP := "#040B13"
const COLOR_BACKGROUND := "#071421"
const COLOR_BACKGROUND_ALT := "#0A1B2B"
const COLOR_SURFACE := "#0B1826F2"
const COLOR_SURFACE_GLASS := "#0C1A29E8"
const COLOR_SURFACE_RAISED := "#10243AF5"
const COLOR_SURFACE_SOFT := "#132A40E8"
const COLOR_SURFACE_INTERACTIVE := "#17354EF2"
const COLOR_SURFACE_SELECTED := "#163E57F5"
const COLOR_INSET := "#07111CEE"
const COLOR_OVERLAY := "#02070DD9"

const COLOR_TEXT := "#F4F8FC"
const COLOR_TEXT_MUTED := "#A4B7C7"
const COLOR_TEXT_SUBDUED := "#728A9D"
const COLOR_TEXT_DISABLED := "#536879"

const COLOR_BORDER_SUBTLE := "#1C3447"
const COLOR_BORDER := "#2B536D"
const COLOR_BORDER_STRONG := "#58BFE5"
const COLOR_BORDER_FOCUS := "#8DE5FF"
const COLOR_ACCENT := "#5BD7FF"
const COLOR_ACCENT_DEEP := "#1785AD"
const COLOR_ACCENT_SOFT := "#79E0FF"
const COLOR_ACCENT_WARM := "#F5C760"
const COLOR_ACCENT_WARM_BRIGHT := "#FFE39B"
const COLOR_SUCCESS := "#72D9A0"
const COLOR_WARNING := "#F1BB58"
const COLOR_DANGER := "#EF737C"
const COLOR_DANGER_DEEP := "#8E3342"
const COLOR_HEALTH := "#F06F78"
const COLOR_HUNGER := "#E9B755"

const SHADOW_COLOR := "#00050ACC"
const SHADOW_SOFT := "#00050A80"


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
	box.border_blend = true
	box.anti_aliasing = true
	return box


static func elevated_panel_style(
	fill: String = COLOR_SURFACE_RAISED,
	border: String = COLOR_BORDER,
	border_width: int = 1,
	radius: int = RADIUS_LG,
	padding: float = 16.0,
	shadow_size: int = 10,
	shadow_offset: Vector2 = Vector2(0.0, 5.0)
) -> StyleBoxFlat:
	var box := panel_style(fill, border, border_width, radius, padding)
	box.shadow_color = color(SHADOW_COLOR)
	box.shadow_size = maxi(0, shadow_size)
	box.shadow_offset = shadow_offset
	return box


static func focus_style(radius: int = RADIUS_MD, padding: float = 0.0) -> StyleBoxFlat:
	return panel_style("#00000000", COLOR_BORDER_FOCUS, 2, radius, padding)


static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func severity_color(severity: String) -> Color:
	match severity:
		"success":
			return color(COLOR_SUCCESS)
		"warning":
			return color(COLOR_WARNING)
		"error", "critical":
			return color(COLOR_DANGER)
		_:
			return color(COLOR_ACCENT)


static func tone_border(tone: String) -> String:
	match tone:
		"success":
			return COLOR_SUCCESS
		"warning":
			return COLOR_WARNING
		"danger", "error", "critical":
			return COLOR_DANGER
		"warm", "primary":
			return COLOR_ACCENT_WARM
		_:
			return COLOR_BORDER_STRONG
