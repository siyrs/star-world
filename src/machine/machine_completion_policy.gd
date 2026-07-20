class_name MachineCompletionPolicy
extends RefCounted

const MAX_VISIBLE_OUTPUT_TYPES := 3


static func build(events: Array[Dictionary], item_registry: Variant = null) -> Dictionary:
	var output_counts: Dictionary = {}
	var machine_ids: Dictionary = {}
	var recipe_ids: Dictionary = {}
	var machine_types: Dictionary = {}
	var completed_jobs := 0
	for event: Dictionary in events:
		var raw_output: Variant = event.get("output", {})
		if raw_output is not Dictionary:
			continue
		var output: Dictionary = raw_output
		var item_id := str(output.get("item_id", "")).strip_edges()
		var count := maxi(0, int(output.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		output_counts[item_id] = int(output_counts.get(item_id, 0)) + count
		var machine_id := str(event.get("machine_id", "")).strip_edges()
		if not machine_id.is_empty():
			machine_ids[machine_id] = true
		var recipe_id := str(event.get("recipe_id", "")).strip_edges()
		if not recipe_id.is_empty():
			recipe_ids[recipe_id] = true
		var machine_type := str(event.get("machine_type", "")).strip_edges()
		if not machine_type.is_empty():
			machine_types[machine_type] = true
		completed_jobs += 1
	if completed_jobs <= 0:
		return {}
	var item_ids: Array[String] = []
	for raw_item_id: Variant in output_counts.keys():
		item_ids.append(str(raw_item_id))
	item_ids.sort()
	var visible: Array[String] = []
	var visible_limit := mini(MAX_VISIBLE_OUTPUT_TYPES, item_ids.size())
	for index in range(visible_limit):
		var item_id: String = item_ids[index]
		visible.append(
			"%s ×%d"
			% [
				_display_name(item_id, item_registry),
				int(output_counts.get(item_id, 0)),
			]
		)
	if item_ids.size() > visible_limit:
		visible.append("等 %d 类" % (item_ids.size() - visible_limit))
	var item_total := 0
	for count: Variant in output_counts.values():
		item_total += maxi(0, int(count))
	var type_ids: Array[String] = []
	for raw_type: Variant in machine_types.keys():
		type_ids.append(str(raw_type))
	type_ids.sort()
	return {
		"message": "机器加工完成：%s" % "、".join(visible),
		"completed_jobs": completed_jobs,
		"machine_count": machine_ids.size(),
		"machine_type_count": machine_types.size(),
		"machine_types": type_ids,
		"recipe_count": recipe_ids.size(),
		"item_total": item_total,
		"output_type_count": output_counts.size(),
		"output_counts": output_counts.duplicate(true),
	}


static func _display_name(item_id: String, item_registry: Variant) -> String:
	if item_registry != null and item_registry.has_method("get_display_name"):
		var resolved := str(
			item_registry.call("get_display_name", item_id)
		).strip_edges()
		if not resolved.is_empty():
			return resolved
	return item_id
