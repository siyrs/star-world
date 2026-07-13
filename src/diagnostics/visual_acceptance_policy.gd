class_name VisualAcceptancePolicy
extends RefCounted

const DEFAULT_MINIMUM_UNIQUE_COLORS := 12
const DEFAULT_MINIMUM_WORLD_COLORS := 6
const DEFAULT_MAX_WORLD_DOMINANT_RATIO := 0.94
const DEFAULT_WORLD_REGION := Rect2(0.12, 0.16, 0.76, 0.48)


static func evaluate(
	image: Image,
	minimum_unique_colors: int = DEFAULT_MINIMUM_UNIQUE_COLORS,
	minimum_world_colors: int = DEFAULT_MINIMUM_WORLD_COLORS,
	maximum_world_dominant_ratio: float = DEFAULT_MAX_WORLD_DOMINANT_RATIO
) -> Dictionary:
	if image == null or image.is_empty():
		return {
			"ok": false,
			"reason": "image_missing",
			"unique_color_buckets": 0,
			"world_unique_color_buckets": 0,
			"world_dominant_ratio": 1.0,
			"width": 0,
			"height": 0,
		}
	var full_stats := _sample_region(
		image, Rect2i(Vector2i.ZERO, image.get_size()), 40, 24
	)
	var world_rect := _normalized_region_to_pixels(image, DEFAULT_WORLD_REGION)
	var world_stats := _sample_region(image, world_rect, 36, 22)
	var full_ok := int(full_stats.get("unique", 0)) >= maxi(2, minimum_unique_colors)
	var world_ok := (
		int(world_stats.get("unique", 0)) >= maxi(2, minimum_world_colors)
		and float(world_stats.get("dominant_ratio", 1.0))
		<= clampf(maximum_world_dominant_ratio, 0.5, 1.0)
	)
	var reason := ""
	if not full_ok:
		reason = "flat_or_blank_frame"
	elif not world_ok:
		reason = "world_region_flat_or_sky_only"
	return {
		"ok": full_ok and world_ok,
		"reason": reason,
		"unique_color_buckets": int(full_stats.get("unique", 0)),
		"dominant_ratio": float(full_stats.get("dominant_ratio", 1.0)),
		"world_unique_color_buckets": int(world_stats.get("unique", 0)),
		"world_dominant_ratio": float(world_stats.get("dominant_ratio", 1.0)),
		"world_region": [world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y],
		"width": image.get_width(),
		"height": image.get_height(),
	}


static func _sample_region(
	image: Image, region: Rect2i, target_columns: int, target_rows: int
) -> Dictionary:
	var counts: Dictionary = {}
	var sample_count := 0
	var step_x := maxi(1, region.size.x / maxi(1, target_columns))
	var step_y := maxi(1, region.size.y / maxi(1, target_rows))
	var end_x := region.position.x + region.size.x
	var end_y := region.position.y + region.size.y
	for y in range(region.position.y, end_y, step_y):
		for x in range(region.position.x, end_x, step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [
				int(color.r * 31.0),
				int(color.g * 31.0),
				int(color.b * 31.0),
			]
			counts[key] = int(counts.get(key, 0)) + 1
			sample_count += 1
	var dominant_count := 0
	for raw_count in counts.values():
		dominant_count = maxi(dominant_count, int(raw_count))
	return {
		"unique": counts.size(),
		"samples": sample_count,
		"dominant_ratio": (
			float(dominant_count) / float(sample_count) if sample_count > 0 else 1.0
		),
	}


static func _normalized_region_to_pixels(image: Image, normalized: Rect2) -> Rect2i:
	var width := image.get_width()
	var height := image.get_height()
	var x := clampi(int(round(normalized.position.x * width)), 0, maxi(0, width - 1))
	var y := clampi(int(round(normalized.position.y * height)), 0, maxi(0, height - 1))
	var region_width := clampi(
		int(round(normalized.size.x * width)), 1, maxi(1, width - x)
	)
	var region_height := clampi(
		int(round(normalized.size.y * height)), 1, maxi(1, height - y)
	)
	return Rect2i(x, y, region_width, region_height)
