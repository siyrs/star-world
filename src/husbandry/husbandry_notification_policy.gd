class_name HusbandryNotificationPolicy
extends RefCounted

const MAX_VISIBLE_TYPES := 3


static func lifecycle_batch(events: Array[Dictionary]) -> Dictionary:
	var newborn_counts: Dictionary = {}
	var grown_counts: Dictionary = {}
	var animal_ids: Dictionary = {}
	var newborn_total := 0
	var grown_total := 0
	for event: Dictionary in events:
		var kind := str(event.get("kind", ""))
		if kind not in ["newborn", "grown"]:
			continue
		var raw_result: Variant = event.get("result", {})
		var result: Dictionary = raw_result if raw_result is Dictionary else {}
		var count := maxi(1, int(event.get("count", 1)))
		var display_name := _display_name(result, kind)
		var target: Dictionary = newborn_counts if kind == "newborn" else grown_counts
		target[display_name] = int(target.get(display_name, 0)) + count
		if kind == "newborn":
			newborn_total += count
		else:
			grown_total += count
		var husbandry_id := str(result.get("husbandry_id", "")).strip_edges()
		if not husbandry_id.is_empty():
			animal_ids[husbandry_id] = true
	var total := newborn_total + grown_total
	if total <= 0:
		return {}
	var parts: Array[String] = []
	if newborn_total > 0:
		parts.append("新生：%s" % _format_counts(newborn_counts))
	if grown_total > 0:
		parts.append("成年：%s" % _format_counts(grown_counts))
	return {
		"message": "牧场生命更新：%s" % "；".join(parts),
		"severity": "success" if newborn_total > 0 else "info",
		"duration": 3.4 if newborn_total > 0 else 2.8,
		"audio": "craft" if newborn_total > 0 else "none",
		"total_count": total,
		"newborn_count": newborn_total,
		"grown_count": grown_total,
		"animal_count": animal_ids.size(),
		"newborn_types": newborn_counts.size(),
		"grown_types": grown_counts.size(),
	}


static func _display_name(result: Dictionary, kind: String) -> String:
	var raw_name := str(result.get("display_name", "动物")).strip_edges()
	if raw_name.is_empty():
		raw_name = "动物"
	if kind == "grown" and raw_name.begins_with("幼年"):
		raw_name = raw_name.trim_prefix("幼年")
	if kind == "newborn" and not raw_name.begins_with("幼年"):
		raw_name = "幼年%s" % raw_name
	return raw_name


static func _format_counts(counts: Dictionary) -> String:
	var names: Array[String] = []
	for raw_name: Variant in counts.keys():
		names.append(str(raw_name))
	names.sort()
	var visible: Array[String] = []
	var limit := mini(MAX_VISIBLE_TYPES, names.size())
	for index in range(limit):
		var name: String = names[index]
		visible.append("%s ×%d" % [name, int(counts.get(name, 0))])
	if names.size() > limit:
		visible.append("等 %d 类" % (names.size() - limit))
	return "、".join(visible)
