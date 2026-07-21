class_name HudIconFactory
extends RefCounted

# Procedurally generated 9x9 pixel status icons (hearts, drumsticks)
# with full / half / empty states, upscaled x2 for the HUD.

const SIZE := 9
const SCALE := 2
const HEART := Color("#E5484D")
const HEART_DARK := Color("#A42832")
const DRUM := Color("#D9A03F")
const DRUM_DARK := Color("#9C6B24")
const BONE := Color("#F5EDDC")
const EMPTY := Color("#2A3540")
const EMPTY_EDGE := Color("#46545F")

static var _cache: Dictionary = {}


static func texture(name: String) -> Texture2D:
	return _cached(name)


static func heart_full() -> Texture2D:
	return _cached("heart_full")


static func heart_half() -> Texture2D:
	return _cached("heart_half")


static func heart_empty() -> Texture2D:
	return _cached("heart_empty")


static func drumstick_full() -> Texture2D:
	return _cached("drumstick_full")


static func drumstick_half() -> Texture2D:
	return _cached("drumstick_half")


static func drumstick_empty() -> Texture2D:
	return _cached("drumstick_empty")


static func _cached(key: String) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = _build(key)
	return _cache[key]


static func _build(key: String) -> Texture2D:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if key.begins_with("heart"):
		_paint_heart(image, key)
	else:
		_paint_drumstick(image, key)
	var scaled := Image.create(SIZE * SCALE, SIZE * SCALE, false, Image.FORMAT_RGBA8)
	for y in SIZE * SCALE:
		for x in SIZE * SCALE:
			scaled.set_pixel(x, y, image.get_pixel(x / SCALE, y / SCALE))
	return ImageTexture.create_from_image(scaled)


static func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
		image.set_pixel(x, y, color)


static func _heart_rows() -> Array:
	# 9 rows of a pixel heart, x ranges per row.
	return [
		[[1, 2], [6, 7]],
		[[0, 3], [5, 8]],
		[[0, 8]],
		[[0, 8]],
		[[1, 7]],
		[[2, 6]],
		[[3, 5]],
		[[4, 4]],
	]


static func _paint_heart(image: Image, key: String) -> void:
	var rows := _heart_rows()
	for y in rows.size():
		for span: Array in rows[y]:
			for x in range(span[0], span[1] + 1):
				var color := EMPTY_EDGE
				if key != "heart_empty":
					color = HEART_DARK if y >= 5 else HEART
					if key == "heart_half" and x >= 4:
						color = EMPTY_EDGE if y < 5 else EMPTY
				_px(image, x, y, color)
		if key == "heart_empty":
			for span: Array in rows[y]:
				for x in range(span[0], span[1] + 1):
					if y >= 2:
						_px(image, x, y, EMPTY)
		if key == "heart_half":
			for span: Array in rows[y]:
				for x in range(span[0], span[1] + 1):
					if x >= 4 and y >= 2:
						_px(image, x, y, EMPTY)
	_px(image, 1, 1, Color("#FF9AA0") if key == "heart_full" else Color.TRANSPARENT)


static func _paint_drumstick(image: Image, key: String) -> void:
	# Meat blob top-right, bone handle bottom-left.
	for y in range(1, 6):
		for x in range(3, 8):
			if (x == 3 and y == 1) or (x == 7 and y == 5):
				continue
			var color := EMPTY
			if key != "drumstick_empty":
				color = DRUM_DARK if y >= 4 else DRUM
				if key == "drumstick_half" and x >= 5:
					color = EMPTY
			_px(image, x, y, color)
	for i in 4:
		var bone_color := EMPTY_EDGE if key == "drumstick_empty" else BONE
		if key == "drumstick_half":
			bone_color = EMPTY_EDGE
		_px(image, 1 + i, 8 - i, bone_color)
		_px(image, 2 + i, 8 - i, bone_color)
	_px(image, 4, 1, EMPTY_EDGE if key == "drumstick_empty" else Color("#F0C267"))
