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

# Pixel-font sizes snap to the 12px design grid of the bundled Fusion Pixel
# typeface so glyphs always render on whole pixels (12/24/36/48/60/72).
const FONT_MICRO := 12
const FONT_CAPTION := 12
const FONT_SMALL := 12
const FONT_BODY := 12
const FONT_BUTTON := 12
const FONT_SUBTITLE := 24
const FONT_TITLE := 36
const FONT_DISPLAY := 60
const FONT_HERO := 72

const CONTROL_HEIGHT_SM := 36
const CONTROL_HEIGHT_MD := 44
const CONTROL_HEIGHT_LG := 52
const PANEL_SAFE_MARGIN := 18
const CONTENT_MAX_WIDTH := 1180

# Voxel Classic palette. Semantic values now speak the same material language
# as the 16x16 pixel world: dark stone HUD surfaces, dirt menu backgrounds,
# grass-green primary actions and torch-yellow highlights.
const COLOR_BACKGROUND_DEEP := "#120C07"
const COLOR_BACKGROUND := "#1B130B"
const COLOR_BACKGROUND_ALT := "#241910"
const COLOR_SURFACE := "#15100AF2"
const COLOR_SURFACE_GLASS := "#181209E8"
const COLOR_SURFACE_RAISED := "#211810F5"
const COLOR_SURFACE_SOFT := "#2A1F13E8"
const COLOR_SURFACE_INTERACTIVE := "#3A2C1AF2"
const COLOR_SURFACE_SELECTED := "#46511FF5"
const COLOR_INSET := "#0D0905EE"
const COLOR_OVERLAY := "#090603D9"

const COLOR_TEXT := "#F8F4EC"
const COLOR_TEXT_MUTED := "#C9BCA4"
const COLOR_TEXT_SUBDUED := "#968972"
const COLOR_TEXT_DISABLED := "#5F5646"

const COLOR_BORDER_SUBTLE := "#3A2F20"
const COLOR_BORDER := "#6B5B40"
const COLOR_BORDER_STRONG := "#B9A06A"
const COLOR_BORDER_FOCUS := "#FFFF8D"
const COLOR_ACCENT := "#8BC34A"
const COLOR_ACCENT_DEEP := "#4E7A28"
const COLOR_ACCENT_SOFT := "#B2E383"
const COLOR_ACCENT_WARM := "#F5C760"
const COLOR_ACCENT_WARM_BRIGHT := "#FFE39B"
const COLOR_SUCCESS := "#7ED957"
const COLOR_WARNING := "#F1BB58"
const COLOR_DANGER := "#E5533D"
const COLOR_DANGER_DEEP := "#8E2B1E"
const COLOR_HEALTH := "#F06F78"
const COLOR_HUNGER := "#E9B755"

const SHADOW_COLOR := "#000000CC"
const SHADOW_SOFT := "#00000080"

# Minecraft-classic GUI tokens (panel greys, bevels, slot inset).
const MC_PANEL := "#C6C6C6"
const MC_PANEL_TEXT := "#3F3F3F"
const MC_PANEL_TEXT_MUTED := "#5C5C5C"
const MC_BEVEL_LIGHT := "#FFFFFF"
const MC_BEVEL_DARK := "#555555"
const MC_SLOT := "#8B8B8B"
const MC_BUTTON := "#828282"
const MC_BUTTON_HOVER := "#8E9CC4"
const MC_TEXT_SHADOW := "#3F3F3F"
const MC_SPLASH := "#FFFF00"
const MC_HOTBAR_FRAME := "#FFFFFFFF"

# Bundled pixel typeface (Fusion Pixel Font, SIL OFL 1.1).
const PIXEL_FONT_PATH := "res://assets/fonts/fusion_pixel_12px_mono.ttf"
const PIXEL_FONT_LICENSE_PATH := "res://assets/fonts/OFL.txt"


static func color(value: String) -> Color:
	return Color(value)


static func panel_style(
	fill: String = COLOR_SURFACE,
	border: String = COLOR_BORDER,
	border_width: int = 1,
	radius: int = RADIUS_MD,
	padding: float = 10.0
) -> StyleBoxFlat:
	# The voxel-classic restyle squares every surface: the radius argument is
	# kept for source compatibility but no longer produces rounded corners.
	var box := StyleBoxFlat.new()
	box.bg_color = color(fill)
	box.border_color = color(border)
	box.set_border_width_all(border_width)
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	box.border_blend = true
	box.anti_aliasing = false
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


# Sharp-corner flat style used for semantic HUD chips (success/warning/danger)
# where the full two-tone bevel texture would be visually heavy. The real
# Minecraft bevels live in PixelUiTextures StyleBoxTexture resources.
static func bevel_style(
	fill: String,
	border: String = MC_BEVEL_DARK,
	bevel: int = 2,
	padding: float = 10.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color(fill)
	box.border_color = color(border)
	box.set_border_width_all(bevel)
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	box.anti_aliasing = false
	return box


# Recessed inset look (slot wells) for flat-style call sites; the textured
# variant is PixelUiTextures.slot_style_box().
static func inset_style(fill: String = MC_SLOT, bevel: int = 2, padding: float = 4.0) -> StyleBoxFlat:
	return bevel_style(fill, "#373737", bevel, padding)


static func focus_style(radius: int = RADIUS_MD, padding: float = 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = color(COLOR_BORDER_FOCUS)
	box.set_border_width_all(2)
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	box.anti_aliasing = false
	return box


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
