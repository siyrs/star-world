class_name BlockTextureAtlas
extends RefCounted

const RegistryScript = preload("res://src/block/block_visual_registry.gd")
const UV_INSET_PIXELS := 0.02

static var _registry: RefCounted
static var _atlas_image: Image
static var _atlas_texture: ImageTexture


static func ensure_built() -> bool:
	if _atlas_image != null and not _atlas_image.is_empty() and _atlas_texture != null:
		return true
	var registry := _get_registry()
	if registry == null or not bool(registry.call("ensure_loaded")):
		return false
	var atlas_size: Vector2i = registry.call("get_atlas_pixel_size")
	if atlas_size.x <= 0 or atlas_size.y <= 0:
		return false
	_atlas_image = Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	_atlas_image.fill(Color.TRANSPARENT)
	var tile_size: int = int(registry.call("get_tile_size"))
	var columns: int = int(registry.call("get_atlas_columns"))
	var tile_ids: Array = registry.call("get_tile_ids")
	for tile_index in tile_ids.size():
		var tile_id := str(tile_ids[tile_index])
		var style: Dictionary = registry.call("get_tile_style", tile_id)
		var tile := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		_paint_tile(tile, tile_id, style)
		var destination := Vector2i(
			(tile_index % columns) * tile_size,
			int(tile_index / columns) * tile_size
		)
		_atlas_image.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), destination)
	_atlas_texture = ImageTexture.create_from_image(_atlas_image)
	return _atlas_texture != null


static func get_texture() -> Texture2D:
	ensure_built()
	return _atlas_texture


static func get_image() -> Image:
	ensure_built()
	return _atlas_image


static func get_registry() -> RefCounted:
	return _get_registry()


static func get_tile_id(block_id: String, face_index: int) -> String:
	var registry := _get_registry()
	return str(registry.call("get_tile_id", block_id, face_index))


static func get_tile_rect(block_id: String, face_index: int) -> Rect2i:
	var registry := _get_registry()
	registry.call("ensure_loaded")
	var tile_id := str(registry.call("get_tile_id", block_id, face_index))
	var tile_index := int(registry.call("get_tile_index", tile_id))
	var tile_size := int(registry.call("get_tile_size"))
	var columns := int(registry.call("get_atlas_columns"))
	return Rect2i(
		(tile_index % columns) * tile_size,
		int(tile_index / columns) * tile_size,
		tile_size,
		tile_size
	)


static func get_uvs(block_id: String, face_index: int) -> Array[Vector2]:
	ensure_built()
	var rect := get_tile_rect(block_id, face_index)
	var atlas_size := _atlas_image.get_size()
	var left := (float(rect.position.x) + UV_INSET_PIXELS) / float(atlas_size.x)
	var right := (float(rect.end.x) - UV_INSET_PIXELS) / float(atlas_size.x)
	var top := (float(rect.position.y) + UV_INSET_PIXELS) / float(atlas_size.y)
	var bottom := (float(rect.end.y) - UV_INSET_PIXELS) / float(atlas_size.y)
	return [
		Vector2(left, bottom),
		Vector2(right, bottom),
		Vector2(right, top),
		Vector2(left, top),
	]


static func reset_cache_for_tests() -> void:
	_registry = null
	_atlas_image = null
	_atlas_texture = null


static func _get_registry() -> RefCounted:
	if _registry == null:
		_registry = RegistryScript.new()
	_registry.call("ensure_loaded")
	return _registry


static func _paint_tile(image: Image, tile_id: String, style: Dictionary) -> void:
	var palette := _palette(style)
	var pattern := str(style.get("pattern", "noise"))
	var seed := _string_seed(tile_id)
	match pattern:
		"transparent":
			image.fill(Color.TRANSPARENT)
		"noise":
			_paint_noise(image, palette, float(style.get("density", 0.35)), seed)
		"grass_side":
			_paint_grass_side(image, palette, seed, bool(style.get("no_grass", false)))
		"cobble":
			_paint_cobble(image, palette, seed)
		"bark":
			_paint_bark(image, palette, seed)
		"rings":
			_paint_rings(image, palette, seed)
		"leaves":
			_paint_leaves(image, palette, seed)
		"water":
			_paint_water(image, palette, seed)
		"lava":
			_paint_lava(image, palette, seed)
		"boards":
			_paint_boards(image, palette, seed)
		"bricks":
			_paint_bricks(image, palette, seed)
		"glass":
			_paint_glass(image, palette)
		"ore":
			_paint_ore(image, palette, Color(str(style.get("accent", "#FFFFFF"))), seed)
		"crafting_top":
			_paint_crafting_top(image, palette, seed)
		"crafting_side":
			_paint_crafting_side(image, palette, seed)
		"furnace":
			_paint_furnace(image, palette, seed)
		"chest":
			_paint_chest(image, palette, seed)
		"door":
			_paint_door(image, palette, seed)
		"fence":
			_paint_fence(image, palette)
		"ladder":
			_paint_ladder(image, palette)
		"torch":
			_paint_torch(image, palette)
		"weave":
			_paint_weave(image, palette, seed)
		"ice":
			_paint_ice(image, palette, seed)
		"furrows":
			_paint_furrows(image, palette, seed)
		"crop":
			_paint_crop(image, palette, style, seed)
		"bed_top":
			_paint_bed_top(image, palette, seed)
		"bed_side":
			_paint_bed_side(image, palette, seed)
		"repair_top":
			_paint_repair_top(image, palette, seed)
		"repair_side":
			_paint_repair_side(image, palette, seed)
		_:
			_paint_noise(image, palette, 0.35, seed)


static func _paint_noise(image: Image, palette: Array[Color], density: float, seed: int) -> void:
	image.fill(_pick(palette, 1))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var noise := _hash01(x, y, seed)
			var color_index := 1
			if noise < density * 0.34:
				color_index = 0
			elif noise > 1.0 - density * 0.28:
				color_index = 2
			elif noise > 0.48 and noise < 0.48 + density * 0.12:
				color_index = 3
			image.set_pixel(x, y, _pick(palette, color_index))


static func _paint_grass_side(
	image: Image, palette: Array[Color], seed: int, no_grass: bool
) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var dirt_index := 0 if _hash01(x, y, seed) < 0.42 else 1
			image.set_pixel(x, y, _pick(palette, dirt_index))
	if no_grass:
		for x in range(1, image.get_width(), 4):
			for y in range(2, image.get_height(), 6):
				image.set_pixel(x, y, _pick(palette, 2))
		return
	for x in range(image.get_width()):
		var depth := 3 + int(floor(_hash01(x, 91, seed) * 3.0))
		for y in range(depth):
			image.set_pixel(x, y, _pick(palette, 2 if (x + y) % 3 else 3))
		if x % 5 == 1:
			for root_y in range(depth, mini(image.get_height(), depth + 4)):
				image.set_pixel(x, root_y, _pick(palette, 3))


static func _paint_cobble(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_noise(image, palette, 0.28, seed)
	for y in [0, 5, 10, 15]:
		for x in range(image.get_width()):
			image.set_pixel(x, y, _pick(palette, 0))
	for row in range(3):
		var y_start := row * 5
		var offset := 3 if row % 2 else 7
		for x in range(offset, image.get_width(), 8):
			for y in range(y_start, mini(y_start + 6, image.get_height())):
				image.set_pixel(x, y, _pick(palette, 0))
	for y in range(2, image.get_height(), 5):
		for x in range(2, image.get_width(), 6):
			if _hash01(x, y, seed) > 0.45:
				image.set_pixel(x, y, _pick(palette, 3))


static func _paint_bark(image: Image, palette: Array[Color], seed: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var band := (x + int(_hash01(x, 0, seed) * 2.0)) % 5
			var index := 1
			if band == 0:
				index = 3
			elif band in [2, 3] and _hash01(x, y, seed) > 0.58:
				index = 2
			elif _hash01(x, y, seed) < 0.2:
				index = 0
			image.set_pixel(x, y, _pick(palette, index))
	for center in [Vector2i(4, 5), Vector2i(11, 12)]:
		image.set_pixel(center.x, center.y, _pick(palette, 3))
		image.set_pixel(center.x + 1, center.y, _pick(palette, 0))


static func _paint_rings(image: Image, palette: Array[Color], seed: int) -> void:
	var center := Vector2(7.5, 7.5)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var delta := Vector2(float(x), float(y)) - center
			var radius := maxi(int(absf(delta.x)), int(absf(delta.y)))
			var index := 1 if radius % 3 else 0
			if radius in [2, 6]:
				index = 2
			if _hash01(x, y, seed) > 0.93:
				index = 3
			image.set_pixel(x, y, _pick(palette, index))
	image.fill_rect(Rect2i(7, 7, 2, 2), _pick(palette, 2))


static func _paint_leaves(image: Image, palette: Array[Color], seed: int) -> void:
	image.fill(Color.TRANSPARENT)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var noise := _hash01(x, y, seed)
			if noise < 0.16 and x not in [0, 15] and y not in [0, 15]:
				continue
			var index := 1
			if noise < 0.38:
				index = 0
			elif noise > 0.78:
				index = 2
			elif (x + y) % 7 == 0:
				index = 3
			image.set_pixel(x, y, _pick(palette, index))


static func _paint_water(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_noise(image, palette, 0.18, seed)
	for y in range(2, image.get_height(), 4):
		var shift := int(_hash01(0, y, seed) * 5.0)
		for x in range(image.get_width()):
			if (x + shift) % 7 in [0, 1, 2]:
				image.set_pixel(x, y, _pick(palette, 2))
			elif (x + shift) % 7 == 5:
				image.set_pixel(x, y + 1 if y + 1 < image.get_height() else y, _pick(palette, 3))


static func _paint_lava(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_noise(image, palette, 0.32, seed)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var cell := posmod(x * 3 + y * 5 + seed, 13)
			if cell in [0, 1]:
				image.set_pixel(x, y, _pick(palette, 0))
			elif cell in [7, 8] and _hash01(x, y, seed) > 0.5:
				image.set_pixel(x, y, _pick(palette, 3))


static func _paint_boards(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_noise(image, palette, 0.20, seed)
	for y in [0, 5, 10, 15]:
		for x in range(image.get_width()):
			image.set_pixel(x, y, _pick(palette, 3))
	for row in range(3):
		var seam_x := 8 if row % 2 == 0 else 4
		for y in range(row * 5, mini(row * 5 + 6, image.get_height())):
			image.set_pixel(seam_x, y, _pick(palette, 0))
	for knot in [Vector2i(3, 3), Vector2i(12, 8), Vector2i(6, 13)]:
		image.set_pixel(knot.x, knot.y, _pick(palette, 3))
		if knot.x + 1 < image.get_width():
			image.set_pixel(knot.x + 1, knot.y, _pick(palette, 2))


static func _paint_bricks(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_noise(image, palette, 0.18, seed)
	for y in [0, 5, 10, 15]:
		for x in range(image.get_width()):
			image.set_pixel(x, y, _pick(palette, 3))
	for row in range(3):
		var offset := 4 if row % 2 else 8
		for x in range(offset, image.get_width(), 8):
			for y in range(row * 5, mini(row * 5 + 6, image.get_height())):
				image.set_pixel(x, y, _pick(palette, 3))


static func _paint_glass(image: Image, palette: Array[Color]) -> void:
	image.fill(Color.TRANSPARENT)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if x in [0, 1, 14, 15] or y in [0, 1, 14, 15]:
				image.set_pixel(x, y, _pick(palette, 0 if (x + y) % 3 else 1))
	for p in range(3, 12):
		image.set_pixel(p, p - 1, _pick(palette, 2))
		if p in [4, 8, 11]:
			image.set_pixel(p + 1, p - 1, _pick(palette, 1))


static func _paint_ore(
	image: Image, palette: Array[Color], accent: Color, seed: int
) -> void:
	_paint_noise(image, palette, 0.23, seed)
	var centers := [
		Vector2i(3, 4), Vector2i(11, 3), Vector2i(7, 8),
		Vector2i(13, 11), Vector2i(4, 13), Vector2i(9, 14)
	]
	for index in centers.size():
		var center: Vector2i = centers[index]
		var color := accent if index % 2 == 0 else accent.darkened(0.22)
		_set_safe(image, center.x, center.y, color)
		_set_safe(image, center.x + 1, center.y, color)
		_set_safe(image, center.x, center.y + 1, color)
		if _hash01(center.x, center.y, seed) > 0.42:
			_set_safe(image, center.x - 1, center.y, accent.lightened(0.12))


static func _paint_crafting_top(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_boards(image, palette, seed)
	for p in range(2, 14):
		image.set_pixel(p, 2, _pick(palette, 0))
		image.set_pixel(p, 13, _pick(palette, 0))
		image.set_pixel(2, p, _pick(palette, 0))
		image.set_pixel(13, p, _pick(palette, 0))
	for x in [6, 10]:
		for y in range(4, 12):
			image.set_pixel(x, y, _pick(palette, 3))
	for y in [6, 10]:
		for x in range(4, 12):
			image.set_pixel(x, y, _pick(palette, 3))


static func _paint_crafting_side(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_boards(image, palette, seed)
	for y in range(3, 13):
		image.set_pixel(4, y, _pick(palette, 0))
		if y >= 8:
			image.set_pixel(5, y, _pick(palette, 0))
	for x in range(9, 13):
		image.set_pixel(x, 5, _pick(palette, 3))
		image.set_pixel(x, 10, _pick(palette, 3))
	image.set_pixel(11, 6, _pick(palette, 3))
	image.set_pixel(10, 9, _pick(palette, 3))


static func _paint_furnace(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_bricks(image, palette, seed)
	image.fill_rect(Rect2i(3, 6, 10, 7), _pick(palette, 0))
	image.fill_rect(Rect2i(5, 8, 6, 4), _pick(palette, 3))
	for x in range(5, 11):
		image.set_pixel(x, 7, _pick(palette, 2))


static func _paint_chest(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_boards(image, palette, seed)
	for x in range(image.get_width()):
		image.set_pixel(x, 5, _pick(palette, 0))
	for y in range(image.get_height()):
		image.set_pixel(0, y, _pick(palette, 0))
		image.set_pixel(15, y, _pick(palette, 0))
	image.fill_rect(Rect2i(7, 5, 3, 4), _pick(palette, 3))
	image.set_pixel(8, 6, _pick(palette, 2))


static func _paint_door(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_boards(image, palette, seed)
	for p in range(1, 15):
		image.set_pixel(1, p, _pick(palette, 0))
		image.set_pixel(14, p, _pick(palette, 0))
		image.set_pixel(p, 1, _pick(palette, 0))
		image.set_pixel(p, 14, _pick(palette, 0))
	image.fill_rect(Rect2i(5, 3, 6, 4), Color.TRANSPARENT)
	for x in range(5, 11):
		image.set_pixel(x, 3, _pick(palette, 3))
		image.set_pixel(x, 6, _pick(palette, 3))
	image.set_pixel(12, 9, _pick(palette, 3))


static func _paint_fence(image: Image, palette: Array[Color]) -> void:
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(3, 0, 4, 16), _pick(palette, 1))
	image.fill_rect(Rect2i(10, 0, 3, 16), _pick(palette, 1))
	image.fill_rect(Rect2i(0, 4, 16, 3), _pick(palette, 2))
	image.fill_rect(Rect2i(0, 10, 16, 3), _pick(palette, 0))
	for y in range(0, 16, 4):
		image.set_pixel(4, y, _pick(palette, 2))
		image.set_pixel(11, y, _pick(palette, 0))


static func _paint_ladder(image: Image, palette: Array[Color]) -> void:
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(3, 0, 2, 16), _pick(palette, 1))
	image.fill_rect(Rect2i(11, 0, 2, 16), _pick(palette, 1))
	for y in [2, 6, 10, 14]:
		image.fill_rect(Rect2i(3, y, 10, 2), _pick(palette, 2 if y % 4 == 2 else 0))


static func _paint_torch(image: Image, palette: Array[Color]) -> void:
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(7, 6, 2, 10), _pick(palette, 1))
	image.fill_rect(Rect2i(6, 2, 4, 5), _pick(palette, 2))
	image.fill_rect(Rect2i(7, 1, 2, 4), _pick(palette, 3))
	image.set_pixel(6, 4, _pick(palette, 0))
	image.set_pixel(9, 5, _pick(palette, 0))


static func _paint_weave(image: Image, palette: Array[Color], seed: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var index := 1
			if (x + y) % 4 == 0:
				index = 2
			elif (x - y) % 5 == 0:
				index = 0
			elif _hash01(x, y, seed) > 0.94:
				index = 3
			image.set_pixel(x, y, _pick(palette, index))


static func _paint_ice(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_noise(image, palette, 0.14, seed)
	var points := [
		Vector2i(2, 4), Vector2i(5, 6), Vector2i(7, 9),
		Vector2i(10, 8), Vector2i(12, 12), Vector2i(14, 14)
	]
	for index in range(points.size() - 1):
		_draw_pixel_line(image, points[index], points[index + 1], _pick(palette, 3))
	_draw_pixel_line(image, Vector2i(7, 9), Vector2i(4, 13), _pick(palette, 2))


static func _paint_furrows(image: Image, palette: Array[Color], seed: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var band := x % 4
			var index := 1
			if band == 0:
				index = 3
			elif band == 3:
				index = 2
			elif _hash01(x, y, seed) < 0.22:
				index = 0
			image.set_pixel(x, y, _pick(palette, index))


static func _paint_crop(
	image: Image, palette: Array[Color], style: Dictionary, seed: int
) -> void:
	image.fill(Color.TRANSPARENT)
	var stage := clampi(int(style.get("stage", 0)), 0, 3)
	var top_y := 12 - stage * 3
	var stems := [6, 8, 10]
	for stem_index in stems.size():
		var x: int = stems[stem_index]
		for y in range(top_y, 16):
			image.set_pixel(x, y, _pick(palette, 1 if stem_index != 1 else 0))
		for leaf_y in range(top_y + 2, 15, 3):
			var direction := -1 if (leaf_y + stem_index) % 2 == 0 else 1
			_set_safe(image, x + direction, leaf_y, _pick(palette, 2))
			_set_safe(image, x + direction * 2, leaf_y + 1, _pick(palette, 1))
	if stage >= 2:
		for x in stems:
			_set_safe(image, x, top_y, _pick(palette, 2))
			_set_safe(image, x - 1, top_y + 1, _pick(palette, 2))
	if style.has("flower"):
		var flower := Color(str(style.get("flower", "#FFFFFF")))
		for point in [Vector2i(5, top_y), Vector2i(9, top_y + 1), Vector2i(11, top_y)]:
			_set_safe(image, point.x, point.y, flower)
	if style.has("produce") and stage >= 3:
		var produce := Color(str(style.get("produce", "#FFFFFF")))
		for point in [Vector2i(5, 12), Vector2i(9, 13), Vector2i(11, 11)]:
			_set_safe(image, point.x, point.y, produce)
			_set_safe(image, point.x + 1, point.y, produce.darkened(0.18))
	if _hash01(2, 3, seed) > 0.5:
		_set_safe(image, 7, top_y + 1, _pick(palette, 2))


static func _paint_bed_top(image: Image, palette: Array[Color], seed: int) -> void:
	image.fill(_pick(palette, 1))
	image.fill_rect(Rect2i(0, 0, 16, 5), _pick(palette, 2))
	for x in range(0, 16, 4):
		image.set_pixel(x, 5, _pick(palette, 0))
	for y in range(7, 16, 4):
		for x in range(2, 15, 5):
			if _hash01(x, y, seed) > 0.35:
				image.set_pixel(x, y, _pick(palette, 0))


static func _paint_bed_side(image: Image, palette: Array[Color], seed: int) -> void:
	image.fill(_pick(palette, 0))
	image.fill_rect(Rect2i(0, 0, 16, 8), _pick(palette, 2))
	image.fill_rect(Rect2i(0, 0, 16, 5), _pick(palette, 3))
	image.fill_rect(Rect2i(1, 8, 3, 8), _pick(palette, 1))
	image.fill_rect(Rect2i(12, 8, 3, 8), _pick(palette, 1))
	for x in range(4, 12):
		if _hash01(x, 9, seed) > 0.7:
			image.set_pixel(x, 9, _pick(palette, 0))


static func _paint_repair_top(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_bricks(image, palette, seed)
	image.fill_rect(Rect2i(3, 3, 10, 10), _pick(palette, 1))
	for point in [Vector2i(4, 4), Vector2i(11, 4), Vector2i(4, 11), Vector2i(11, 11)]:
		image.fill_rect(Rect2i(point, Vector2i(2, 2)), _pick(palette, 3))
	image.fill_rect(Rect2i(6, 6, 4, 4), _pick(palette, 0))


static func _paint_repair_side(image: Image, palette: Array[Color], seed: int) -> void:
	_paint_bricks(image, palette, seed)
	image.fill_rect(Rect2i(2, 3, 12, 3), _pick(palette, 2))
	image.fill_rect(Rect2i(4, 7, 8, 6), _pick(palette, 0))
	image.fill_rect(Rect2i(6, 8, 4, 4), _pick(palette, 3))


static func _draw_pixel_line(image: Image, start: Vector2i, end: Vector2i, color: Color) -> void:
	var x0 := start.x
	var y0 := start.y
	var x1 := end.x
	var y1 := end.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		_set_safe(image, x0, y0, color)
		if x0 == x1 and y0 == y1:
			break
		var doubled := 2 * error
		if doubled >= dy:
			error += dy
			x0 += sx
		if doubled <= dx:
			error += dx
			y0 += sy


static func _palette(style: Dictionary) -> Array[Color]:
	var result: Array[Color] = []
	var raw_palette: Variant = style.get("palette", [])
	if raw_palette is Array:
		for raw_color: Variant in raw_palette:
			result.append(Color(str(raw_color)))
	if result.is_empty():
		result = [Color.MAGENTA, Color("#222222"), Color.WHITE, Color.BLACK]
	while result.size() < 4:
		result.append(result[result.size() - 1])
	return result


static func _pick(palette: Array[Color], index: int) -> Color:
	return palette[clampi(index, 0, palette.size() - 1)]


static func _set_safe(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
		image.set_pixel(x, y, color)


static func _hash01(x: int, y: int, seed: int) -> float:
	var value := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	value = value ^ (value >> 13)
	value = value * 1274126177
	value = value ^ (value >> 16)
	return float(absi(value % 10000)) / 9999.0


static func _string_seed(value: String) -> int:
	var seed := 17
	for byte: int in value.to_utf8_buffer():
		seed = posmod(seed * 31 + byte, 2147483)
	return seed
