class_name VisualAcceptancePolicy
extends RefCounted

const DEFAULT_MINIMUM_UNIQUE_COLORS := 12


static func evaluate(image: Image, minimum_unique_colors: int = DEFAULT_MINIMUM_UNIQUE_COLORS) -> Dictionary:
	if image == null or image.is_empty():
		return {
			"ok": false,
			"reason": "image_missing",
			"unique_color_buckets": 0,
			"width": 0,
			"height": 0,
		}
	var unique: Dictionary = {}
	var step_x := maxi(1, image.get_width() / 40)
	var step_y := maxi(1, image.get_height() / 24)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [
				int(color.r * 31.0),
				int(color.g * 31.0),
				int(color.b * 31.0),
			]
			unique[key] = true
	var unique_count := unique.size()
	return {
		"ok": unique_count >= maxi(2, minimum_unique_colors),
		"reason": "" if unique_count >= maxi(2, minimum_unique_colors) else "flat_or_blank_frame",
		"unique_color_buckets": unique_count,
		"width": image.get_width(),
		"height": image.get_height(),
	}
