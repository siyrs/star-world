class_name PixelUiTextures
extends RefCounted

# Procedural Minecraft-classic UI textures: beveled button faces, inset
# slots, panel fills, dirt menu background and the hurt vignette. Everything
# is generated at runtime and cached, extending the project's zero-external-
# asset philosophy from voxels to the interface layer.

static var _cache: Dictionary = {}

const BEVEL := 3
const BUTTON_W := 48
const BUTTON_H := 16
const FACE_NORMAL := Color("#686868")
const FACE_HOVER := Color("#4D6388")
const FACE_PRESSED := Color("#545454")
const FACE_DISABLED := Color("#5A5A5A")
const FACE_PRIMARY := Color("#487329")
const FACE_PRIMARY_HOVER := Color("#3E6F2B")
const FACE_PRIMARY_PRESSED := Color("#31561D")
const FACE_DANGER := Color("#78352A")
const FACE_DANGER_HOVER := Color("#84372B")
const FACE_DANGER_PRESSED := Color("#61261D")
const FRAME_DARK := Color("#1A1A1A")
const BEVEL_LIGHT := Color("#B9B9B9")
const BEVEL_DARK := Color("#4A4A4A")
const PANEL_FACE := Color("#C6C6C6")
const SLOT_FACE := Color("#8B8B8B")
const SLOT_DARK := Color("#373737")
const SLOT_LIGHT := Color("#FFFFFF")
const DIRT_PALETTE := [
	Color("#6F4B2E"), Color("#7D5734"), Color("#8A6540"), Color("#5A3A22")
]


static func button_face(state: String = "normal") -> Texture2D:
	var key := "button_%s" % state
	if not _cache.has(key):
		_cache[key] = _build_button(state)
	return _cache[key]


static func panel_fill() -> Texture2D:
	if not _cache.has("panel_fill"):
		_cache["panel_fill"] = _build_panel_fill()
	return _cache["panel_fill"]


static func slot_inset() -> Texture2D:
	if not _cache.has("slot_inset"):
		_cache["slot_inset"] = _build_slot_inset()
	return _cache["slot_inset"]


static func hud_slot() -> Texture2D:
	if not _cache.has("hud_slot"):
		_cache["hud_slot"] = _build_hud_slot()
	return _cache["hud_slot"]


static func dirt_background() -> Texture2D:
	if not _cache.has("dirt_background"):
		_cache["dirt_background"] = _build_dirt_tile()
	return _cache["dirt_background"]


static func stone_background() -> Texture2D:
	if not _cache.has("stone_background"):
		_cache["stone_background"] = _build_stone_tile()
	return _cache["stone_background"]


static func hurt_vignette() -> Texture2D:
	if not _cache.has("hurt_vignette"):
		_cache["hurt_vignette"] = _build_vignette()
	return _cache["hurt_vignette"]


static func grabber_icon(highlight: bool = false) -> Texture2D:
	var key := "grabber_highlight" if highlight else "grabber"
	if not _cache.has(key):
		var image := Image.create(8, 12, false, Image.FORMAT_RGBA8)
		var face := FACE_HOVER if highlight else FACE_NORMAL
		for y in 12:
			for x in 8:
				image.set_pixel(x, y, face)
		for i in 8:
			image.set_pixel(i, 0, FRAME_DARK)
			image.set_pixel(i, 11, FRAME_DARK)
		for j in 12:
			image.set_pixel(0, j, FRAME_DARK)
			image.set_pixel(7, j, FRAME_DARK)
		for i in range(1, 7):
			image.set_pixel(i, 1, BEVEL_LIGHT)
			image.set_pixel(i, 10, BEVEL_DARK)
		for j in range(1, 11):
			image.set_pixel(1, j, BEVEL_LIGHT)
			image.set_pixel(6, j, BEVEL_DARK)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


static func button_style(state: String = "normal") -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = button_face(state)
	_set_patch_margins(style, 4.0)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


static func panel_style_box() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = panel_fill()
	_set_patch_margins(style, 5.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


static func slot_style_box() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = slot_inset()
	_set_patch_margins(style, 4.0)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


static func hud_slot_style_box() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = hud_slot()
	_set_patch_margins(style, 4.0)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


static func _set_patch_margins(style: StyleBoxTexture, margin: float) -> void:
	style.texture_margin_left = margin
	style.texture_margin_right = margin
	style.texture_margin_top = margin
	style.texture_margin_bottom = margin


static func _build_button(state: String) -> ImageTexture:
	var image := Image.create(BUTTON_W, BUTTON_H, false, Image.FORMAT_RGBA8)
	var face := FACE_NORMAL
	match state:
		"hover":
			face = FACE_HOVER
		"pressed", "hover_pressed":
			face = FACE_PRESSED
		"disabled":
			face = FACE_DISABLED
		"primary":
			face = FACE_PRIMARY
		"primary_hover":
			face = FACE_PRIMARY_HOVER
		"primary_pressed":
			face = FACE_PRIMARY_PRESSED
		"danger":
			face = FACE_DANGER
		"danger_hover":
			face = FACE_DANGER_HOVER
		"danger_pressed":
			face = FACE_DANGER_PRESSED
	var seed := 17
	for y in BUTTON_H:
		for x in BUTTON_W:
			var noise := (_hash01(x, y, seed) - 0.5) * 10.0 / 255.0
			var pixel := Color(
				clampf(face.r + noise, 0.0, 1.0),
				clampf(face.g + noise, 0.0, 1.0),
				clampf(face.b + noise, 0.0, 1.0)
			)
			image.set_pixel(x, y, pixel)
	# Outer frame.
	for x in BUTTON_W:
		image.set_pixel(x, 0, FRAME_DARK)
		image.set_pixel(x, BUTTON_H - 1, FRAME_DARK)
	for y in BUTTON_H:
		image.set_pixel(0, y, FRAME_DARK)
		image.set_pixel(BUTTON_W - 1, y, FRAME_DARK)
	# Bevels: light top/left, dark bottom/right (inverted while pressed).
	var light := BEVEL_LIGHT
	var dark := BEVEL_DARK
	if state in ["pressed", "hover_pressed", "primary_pressed", "danger_pressed"]:
		light = BEVEL_DARK
		dark = BEVEL_LIGHT
	if state == "disabled":
		light = face.lightened(0.08)
		dark = face.darkened(0.18)
	for x in range(1, BUTTON_W - 1):
		for inset in range(1, BEVEL):
			image.set_pixel(x, inset, light)
			image.set_pixel(x, BUTTON_H - 1 - inset, dark)
	for y in range(1, BUTTON_H - 1):
		for inset in range(1, BEVEL):
			image.set_pixel(inset, y, light)
			image.set_pixel(BUTTON_W - 1 - inset, y, dark)
	return ImageTexture.create_from_image(image)


static func _build_panel_fill() -> ImageTexture:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var seed := 91
	for y in size:
		for x in size:
			var noise := (_hash01(x, y, seed) - 0.5) * 6.0 / 255.0
			var pixel := Color(
				clampf(PANEL_FACE.r + noise, 0.0, 1.0),
				clampf(PANEL_FACE.g + noise, 0.0, 1.0),
				clampf(PANEL_FACE.b + noise, 0.0, 1.0)
			)
			image.set_pixel(x, y, pixel)
	# Classic GUI frame: bright top/left, dark bottom/right.
	for i in size:
		for inset in range(0, 2):
			image.set_pixel(i, inset, Color("#FFFFFF"))
			image.set_pixel(inset, i, Color("#FFFFFF"))
			image.set_pixel(i, size - 1 - inset, Color("#555555"))
			image.set_pixel(size - 1 - inset, i, Color("#555555"))
	return ImageTexture.create_from_image(image)


static func _build_slot_inset() -> ImageTexture:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			image.set_pixel(x, y, SLOT_FACE)
	for i in size:
		for inset in range(0, 2):
			image.set_pixel(i, inset, SLOT_DARK)
			image.set_pixel(inset, i, SLOT_DARK)
			image.set_pixel(i, size - 1 - inset, SLOT_LIGHT)
			image.set_pixel(size - 1 - inset, i, SLOT_LIGHT)
	return ImageTexture.create_from_image(image)


static func _build_hud_slot() -> ImageTexture:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.45))
	for i in size:
		image.set_pixel(i, 0, Color(1.0, 1.0, 1.0, 0.28))
		image.set_pixel(0, i, Color(1.0, 1.0, 1.0, 0.28))
		image.set_pixel(i, size - 1, Color(0.0, 0.0, 0.0, 0.55))
		image.set_pixel(size - 1, i, Color(0.0, 0.0, 0.0, 0.55))
	return ImageTexture.create_from_image(image)


static func _build_dirt_tile() -> ImageTexture:
	# 16 logical pixels upscaled 3x so the menu backdrop reads as chunky
	# blocks on a 720p canvas instead of fine grain.
	var logical := 16
	var scale := 3
	var image := Image.create(logical * scale, logical * scale, false, Image.FORMAT_RGBA8)
	var seed := 7331
	for y in logical * scale:
		for x in logical * scale:
			var lx := x / scale
			var ly := y / scale
			var cell := _hash01(lx >> 1, ly >> 1, seed)
			var grain := _hash01(lx, ly, seed ^ 0x5F3A)
			var index := 1
			var value := cell * 0.7 + grain * 0.3
			if value < 0.22:
				index = 3
			elif value < 0.48:
				index = 0
			elif value > 0.85:
				index = 2
			image.set_pixel(x, y, DIRT_PALETTE[index].darkened(0.25))
	return ImageTexture.create_from_image(image)


static func _build_stone_tile() -> ImageTexture:
	var size := 16
	var palette := [
		Color("#5F5F5F"), Color("#6E6E6E"), Color("#7D7D7D"), Color("#494949")
	]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var seed := 4409
	for y in size:
		for x in size:
			var value := _hash01(x >> 1, y >> 1, seed) * 0.7 + _hash01(x, y, seed ^ 0x3B1F) * 0.3
			var index := 1
			if value < 0.25:
				index = 3
			elif value < 0.5:
				index = 0
			elif value > 0.84:
				index = 2
			image.set_pixel(x, y, palette[index])
	return ImageTexture.create_from_image(image)


static func _build_vignette() -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var uv := Vector2(float(x) / float(size - 1), float(y) / float(size - 1))
			var dist := uv.distance_to(Vector2(0.5, 0.5)) * 1.42
			var alpha := clampf((dist - 0.45) * 1.9, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.62, 0.04, 0.04, alpha * 0.78))
	return ImageTexture.create_from_image(image)


static func _hash01(x: int, y: int, seed: int) -> float:
	var value := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	value = value ^ (value >> 13)
	value = value * 1274126177
	value = value ^ (value >> 16)
	return float(absi(value % 10000)) / 9999.0
