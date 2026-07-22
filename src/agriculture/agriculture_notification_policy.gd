class_name AgricultureNotificationPolicy
extends RefCounted

const MAX_VISIBLE_CROP_TYPES := 3


static func maturity_batch(events: Array, crop_registry: Variant) -> Dictionary:
	if events.is_empty():
		return {}
	var counts: Dictionary = {}
	var positions: Array = []
	for raw_event: Variant in events:
		if raw_event is not Dictionary:
			continue
		var crop_id := str(raw_event.get("crop_id", "")).strip_edges()
		if crop_id.is_empty():
			continue
		counts[crop_id] = int(counts.get(crop_id, 0)) + 1
		var raw_position: Variant = raw_event.get("position", [])
		if raw_position is Vector3i:
			positions.append([raw_position.x, raw_position.y, raw_position.z])
		elif raw_position is Array and raw_position.size() >= 3:
			positions.append([
				int(raw_position[0]), int(raw_position[1]), int(raw_position[2])
			])
	return maturity_counts(counts, crop_registry, positions)


static func maturity_counts(
	raw_counts: Dictionary,
	crop_registry: Variant,
	positions: Array = [],
	dropped_position_samples: int = 0,
	unclassified_count: int = 0
) -> Dictionary:
	var counts: Dictionary = {}
	for raw_id: Variant in raw_counts.keys():
		var crop_id := str(raw_id).strip_edges()
		var count := maxi(0, int(raw_counts.get(raw_id, 0)))
		if crop_id.is_empty() or count <= 0:
			continue
		counts[crop_id] = count
	var unclassified := maxi(0, unclassified_count)
	if counts.is_empty() and unclassified <= 0:
		return {}
	var crop_ids: Array[String] = []
	for raw_id: Variant in counts.keys():
		crop_ids.append(str(raw_id))
	crop_ids.sort()
	var visible: Array[String] = []
	for crop_id: String in crop_ids:
		if visible.size() >= MAX_VISIBLE_CROP_TYPES:
			break
		var display_name := crop_id
		if crop_registry != null and crop_registry.has_method("get_crop"):
			var definition: Dictionary = crop_registry.call("get_crop", crop_id)
			display_name = str(definition.get("name", crop_id))
		visible.append("%s ×%d" % [display_name, int(counts.get(crop_id, 0))])
	var unclassified_visible := false
	if unclassified > 0 and visible.size() < MAX_VISIBLE_CROP_TYPES:
		visible.append("其他作物 ×%d" % unclassified)
		unclassified_visible = true
	var hidden_types := maxi(0, crop_ids.size() - mini(crop_ids.size(), MAX_VISIBLE_CROP_TYPES))
	if unclassified > 0 and not unclassified_visible:
		hidden_types += 1
	var message := "农田成熟：%s" % "、".join(visible)
	if hidden_types > 0:
		message += "，另有 %d 种作物" % hidden_types
	var total := unclassified
	for raw_count: Variant in counts.values():
		total += maxi(0, int(raw_count))
	return {
		"matured_count": total,
		"crop_type_count": crop_ids.size() + (1 if unclassified > 0 else 0),
		"counts": counts.duplicate(true),
		"unclassified_count": unclassified,
		"positions": positions.duplicate(true),
		"sampled_position_count": positions.size(),
		"dropped_position_samples": maxi(0, dropped_position_samples),
		"message": message,
		"severity": "success",
		"duration": 3.0,
		"audio": "pickup",
	}
