class_name MiningCrackTextureFactory
extends RefCounted

const TILE_SIZE := 16
const STAGE_COUNT := 10
const CRACK_COLOR := Color(0.055, 0.060, 0.070, 0.92)
const CRACK_HIGHLIGHT := Color(0.44, 0.46, 0.50, 0.42)
const CRACK_PATHS := [
	[Vector2i(8, 8), Vector2i(8, 6), Vector2i(7, 5)],
	[Vector2i(8, 8), Vector2i(10, 8), Vector2i(11, 7)],
	[Vector2i(8, 8), Vector2i(7, 10), Vector2i(6, 11)],
	[Vector2i(8, 8), Vector2i(9, 10), Vector2i(10, 12)],
	[Vector2i(7, 5), Vector2i(5, 4), Vector2i(4, 2)],
	[Vector2i(11, 7), Vector2i(13, 6), Vector2i(14, 4)],
	[Vector2i(6, 11), Vector2i(4, 12), Vector2i(2, 13)],
	[Vector2i(10, 12), Vector2i(11, 14), Vector2i(13, 15)],
	[Vector2i(8, 6), Vector2i(10, 4), Vector2i(11, 2), Vector2i(13, 1)],
	[Vector2i(7, 10), Vector2i(5, 9), Vector2i(3, 8), Vector2i(1, 6)],
]

static var _images: Array[Image] = []
static var _textures: Array[ImageTexture] = []


static func get_texture(stage: int) -> Texture2D:
	_ensure_built()
	return _textures[clampi(stage, 0, STAGE_COUNT - 1)]


static func get_image(stage: int) -> Image:
	_ensure_built()
	return _images[clampi(stage, 0, STAGE_COUNT - 1)]


static func reset_cache_for_tests() -> void:
	_images.clear()
	_textures.clear()


static func _ensure_built() -> void:
	if _images.size() == STAGE_COUNT and _textures.size() == STAGE_COUNT:
		return
	_images.clear()
	_textures.clear()
	for stage in STAGE_COUNT:
		var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		_paint_stage(image, stage)
		_images.append(image)
		_textures.append(ImageTexture.create_from_image(image))


static func _paint_stage(image: Image, stage: int) -> void:
	var path_count := mini(stage + 1, CRACK_PATHS.size())
	for path_index in path_count:
		var path: Array = CRACK_PATHS[path_index]
		for point_index in range(path.size() - 1):
			_draw_line(image, path[point_index], path[point_index + 1], CRACK_COLOR)
		if stage >= 5:
			for point_value in path:
				var point: Vector2i = point_value
				var highlight := point + Vector2i(1, 0)
				if _inside(highlight) and image.get_pixelv(highlight).a <= 0.01:
					image.set_pixelv(highlight, CRACK_HIGHLIGHT)
	if stage >= 8:
		for point in [Vector2i(5, 7), Vector2i(12, 10), Vector2i(4, 14), Vector2i(14, 12)]:
			image.set_pixelv(point, CRACK_COLOR)


static func _draw_line(image: Image, from: Vector2i, to: Vector2i, color: Color) -> void:
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		var point := Vector2i(x0, y0)
		if _inside(point):
			image.set_pixelv(point, color)
		if x0 == x1 and y0 == y1:
			break
		var doubled := 2 * error
		if doubled >= dy:
			error += dy
			x0 += sx
		if doubled <= dx:
			error += dx
			y0 += sy


static func _inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.x < TILE_SIZE and point.y >= 0 and point.y < TILE_SIZE
