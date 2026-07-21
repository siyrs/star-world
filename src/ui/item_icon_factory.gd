class_name ItemIconFactory
extends RefCounted

# Procedurally generates crisp 16x16 pixel-art icons for every item.
# Icons are drawn on a 16x16 logical grid and upscaled x4 with nearest
# filtering, matching the voxel block atlas aesthetic.

const SIZE := 16
const SCALE := 4
const OUTLINE := Color("#1B1210")
const STICK := Color("#8A6238")
const STICK_DARK := Color("#5E3F22")
const FLAME := Color("#FFC44D")
const FLAME_HOT := Color("#FF7A2F")

static var _cache: Dictionary = {}


static func get_icon(item_id: String, item: Dictionary = {}) -> Texture2D:
	if _cache.has(item_id):
		return _cache[item_id]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var category := str(item.get("category", ""))
	var color := Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	match category:
		"block":
			_paint_cube(image, color)
		"tool":
			_paint_tool(image, item_id, color)
		"weapon":
			_paint_sword(image, color)
		"armor":
			_paint_armor(image, item_id, color)
		"food":
			_paint_food(image, item_id, color)
		"material":
			_paint_material(image, item_id, color)
		"utility":
			_paint_utility(image, item_id, color)
		_:
			_paint_orb(image, color)
	if item_id == "torch":
		_repaint(image)
		_paint_torch(image)
	var texture := _to_texture(image)
	_cache[item_id] = texture
	return texture


static func _to_texture(image: Image) -> Texture2D:
	var scaled := Image.create(SIZE * SCALE, SIZE * SCALE, false, Image.FORMAT_RGBA8)
	scaled.blit_rect(image, Rect2i(Vector2i.ZERO, Vector2i(SIZE, SIZE)), Vector2i.ZERO)
	for y in SIZE * SCALE:
		for x in SIZE * SCALE:
			scaled.set_pixel(x, y, image.get_pixel(x / SCALE, y / SCALE))
	var texture := ImageTexture.create_from_image(scaled)
	return texture


static func _repaint(image: Image) -> void:
	image.fill(Color.TRANSPARENT)


static func _shade(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0)
	)


static func _floor_shade(color: Color, minimum: float = 0.28) -> Color:
	# Very dark source colors vanish on dark slot backgrounds; lift them.
	return Color(
		maxf(color.r, minimum),
		maxf(color.g, minimum),
		maxf(color.b, minimum)
	)


static func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
		image.set_pixel(x, y, color)


static func _rect(image: Image, x0: int, y0: int, w: int, h: int, color: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(image, x, y, color)


static func _paint_cube(image: Image, color: Color) -> void:
	# Classic isometric cube: bright top rhombus, mid left face, dark right face.
	var top := _shade(color, 1.22)
	var left := _shade(color, 0.92)
	var right := _shade(color, 0.62)
	# Top face: rows 2-6 widening from the apex.
	var top_spans := [[7, 8], [5, 10], [4, 11], [3, 12], [2, 13]]
	for i in top_spans.size():
		var span: Array = top_spans[i]
		_rect(image, span[0], 2 + i, span[1] - span[0] + 1, 1, top)
	# Left face: rows 7-14, left edge slopes toward center.
	for y in range(7, 15):
		var x0: int = maxi(1, y - 6)
		_rect(image, x0, y, 8 - x0, 1, left)
	# Right face: rows 7-13, right edge slopes toward center.
	for y in range(7, 14):
		var x1: int = mini(14, 21 - y)
		_rect(image, 9, y, x1 - 9 + 1, 1, right)
	# Edge outlines for readability on dark slot backgrounds.
	_rect(image, 7, 1, 2, 1, OUTLINE)
	for y in range(7, 15):
		_px(image, maxi(0, y - 7), y, OUTLINE)
	for y in range(7, 14):
		_px(image, mini(15, 22 - y), y, OUTLINE)
	_rect(image, 8, 7, 1, 8, _shade(color, 0.45))


static func _paint_tool(image: Image, item_id: String, color: Color) -> void:
	for i in 9:
		var x := 3 + i
		var y := 12 - i
		_px(image, x, y, STICK_DARK)
		_px(image, x + 1, y, STICK)
	var head := _shade(color, 1.05)
	var edge := _shade(color, 1.3)
	if item_id.contains("pickaxe"):
		for i in 5:
			_px(image, 9 + i, 5 - 0, head)
			_px(image, 9, 5 + i, head)
			_px(image, 13, 5 + i, head)
		_px(image, 10, 4, edge)
		_px(image, 12, 4, edge)
	elif item_id.contains("axe"):
		_rect(image, 9, 3, 5, 4, head)
		_rect(image, 9, 3, 2, 2, edge)
	elif item_id.contains("shovel"):
		_rect(image, 9, 2, 3, 5, head)
		_px(image, 10, 1, edge)
	elif item_id.contains("hoe"):
		_rect(image, 9, 3, 5, 2, head)
		_rect(image, 9, 3, 2, 4, head)
	elif item_id.contains("shears"):
		_rect(image, 9, 3, 4, 1, head)
		_rect(image, 9, 5, 4, 1, head)
	else:
		_rect(image, 9, 3, 4, 4, head)


static func _paint_sword(image: Image, color: Color) -> void:
	var blade := _shade(color, 1.25)
	for i in 9:
		var x := 12 - i
		var y := 3 + i
		_px(image, x, y, blade)
		_px(image, x + 1, y, blade)
	_px(image, 12, 2, blade)
	_px(image, 13, 3, blade)
	_rect(image, 3, 11, 5, 2, _shade(color, 0.7))
	_px(image, 2, 13, STICK_DARK)
	_px(image, 3, 14, STICK_DARK)


static func _paint_armor(image: Image, item_id: String, color: Color) -> void:
	var base := _shade(color, 1.05)
	var trim := _shade(color, 1.35)
	if item_id.contains("helmet") or item_id.contains("hood"):
		_rect(image, 4, 4, 8, 6, base)
		_rect(image, 4, 4, 8, 2, trim)
		_rect(image, 5, 8, 6, 1, OUTLINE)
	elif item_id.contains("boot") or item_id.contains("greave"):
		_rect(image, 3, 8, 4, 5, base)
		_rect(image, 9, 8, 4, 5, base)
		_rect(image, 3, 12, 5, 2, trim)
		_rect(image, 9, 12, 5, 2, trim)
	else:
		_rect(image, 4, 3, 8, 10, base)
		_rect(image, 4, 3, 8, 2, trim)
		_rect(image, 6, 5, 4, 1, _shade(color, 0.75))


static func _paint_food(image: Image, item_id: String, color: Color) -> void:
	var base := _shade(color, 1.05)
	var dark := _shade(color, 0.72)
	var light := _shade(color, 1.4)
	for y in range(5, 13):
		var half := 4 - absi(8 - y) / 2
		_rect(image, 8 - half, y, half * 2, 1, base)
	_rect(image, 6, 6, 2, 2, light)
	_rect(image, 11, 10, 2, 2, dark)
	_px(image, 8, 4, STICK_DARK)
	_px(image, 9, 3, Color("#5FA34A"))


static func _paint_material(image: Image, item_id: String, color: Color) -> void:
	var base := _shade(color, 1.1)
	var light := _shade(color, 1.45)
	var dark := _shade(color, 0.7)
	if item_id.contains("ingot") or item_id.contains("brick"):
		_rect(image, 3, 7, 10, 5, base)
		_rect(image, 3, 7, 10, 1, light)
		_rect(image, 3, 11, 10, 1, dark)
	elif item_id.contains("coal"):
		var coal := _floor_shade(color)
		for y in range(5, 12):
			var half := 3 - absi(8 - y) / 2
			_rect(image, 8 - half, y, half * 2, 1, _shade(coal, 1.1))
		_rect(image, 6, 6, 2, 2, _shade(coal, 1.6))
	else:
		for i in 5:
			var w := 1 + i * 2
			_rect(image, 8 - i, 4 + i, w, 1, base)
		for i in 5:
			var w := 9 - i * 2
			_rect(image, 8 - (4 - i), 9 + i, w, 1, base)
		_px(image, 7, 6, light)
		_px(image, 8, 5, light)


static func _paint_utility(image: Image, item_id: String, color: Color) -> void:
	if item_id.contains("kit") or item_id.contains("scanner"):
		_rect(image, 4, 3, 8, 11, _shade(color, 0.8))
		_rect(image, 5, 4, 6, 5, Color("#233B4D"))
		_px(image, 6, 5, Color("#7EE3F0"))
		_px(image, 9, 7, Color("#7EE3F0"))
		_rect(image, 6, 11, 4, 1, _shade(color, 1.2))
	elif item_id.contains("book") or item_id.contains("journal"):
		_rect(image, 4, 3, 8, 11, _shade(color, 0.9))
		_rect(image, 5, 4, 6, 9, Color("#E8D9B0"))
		_rect(image, 6, 6, 4, 1, _shade(color, 0.6))
		_rect(image, 6, 8, 4, 1, _shade(color, 0.6))
	else:
		_paint_orb(image, color)


static func _paint_orb(image: Image, color: Color) -> void:
	for y in range(4, 13):
		var half := 4 - absi(8 - y) / 2
		_rect(image, 8 - half, y, half * 2, 1, _shade(color, 1.0))
	_rect(image, 6, 5, 2, 2, _shade(color, 1.45))


static func _paint_torch(image: Image) -> void:
	_rect(image, 7, 8, 2, 6, STICK)
	_px(image, 7, 14, STICK_DARK)
	_px(image, 8, 14, STICK_DARK)
	_rect(image, 6, 4, 4, 4, FLAME_HOT)
	_px(image, 7, 3, FLAME)
	_px(image, 8, 4, FLAME)
	_px(image, 7, 5, Color("#FFF3B0"))
