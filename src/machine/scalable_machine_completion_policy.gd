class_name ScalableMachineCompletionPolicy
extends RefCounted

const MAX_VISIBLE_OUTPUT_TYPES := 3


static func build_counts(
	output_counts: Dictionary,
	completed_jobs: int,
	item_total: int,
	machine_count: int,
	machine_types: Dictionary,
	recipe_count: int,
	item_registry: Variant = null,
	sampled_events: int = 0,
	dropped_event_samples: int = 0,
	unclassified_jobs: int = 0,
	unclassified_items: int = 0
) -> Dictionary:
	var normalized_jobs := maxi(0, completed_jobs)
	if normalized_jobs <= 0:
		return {}
	var item_ids: Array[String] = []
	for raw_item_id: Variant in output_counts.keys():
		var item_id := str(raw_item_id).strip_edges()
		if not item_id.is_empty() and int(output_counts.get(raw_item_id, 0)) > 0:
			item_ids.append(item_id)
	item_ids.sort()
	var visible: Array[String] = []
	for item_id: String in item_ids:
		if visible.size() >= MAX_VISIBLE_OUTPUT_TYPES:
			break
		visible.append(
			"%s ×%d"
			% [
				_display_name(item_id, item_registry),
				int(output_counts.get(item_id, 0)),
			]
		)
	var hidden_types := maxi(0, item_ids.size() - visible.size())
	if hidden_types > 0:
		visible.append("等 %d 类" % hidden_types)
	if unclassified_items > 0:
		visible.append("其他产出 ×%d" % unclassified_items)
	if visible.is_empty():
		visible.append("%d 项产出" % maxi(0, item_total))
	var type_ids: Array[String] = []
	for raw_type: Variant in machine_types.keys():
		var machine_type := str(raw_type).strip_edges()
		if not machine_type.is_empty():
			type_ids.append(machine_type)
	type_ids.sort()
	return {
		"message": "机器加工完成：%s" % "、".join(visible),
		"completed_jobs": normalized_jobs,
		"machine_count": maxi(0, machine_count),
		"machine_type_count": type_ids.size(),
		"machine_types": type_ids,
		"recipe_count": maxi(0, recipe_count),
		"item_total": maxi(0, item_total),
		"output_type_count": item_ids.size(),
		"output_counts": output_counts.duplicate(true),
		"sampled_event_count": maxi(0, sampled_events),
		"dropped_event_samples": maxi(0, dropped_event_samples),
		"unclassified_jobs": maxi(0, unclassified_jobs),
		"unclassified_items": maxi(0, unclassified_items),
	}


static func _display_name(item_id: String, item_registry: Variant) -> String:
	if item_registry != null and item_registry.has_method("get_display_name"):
		var resolved := str(
			item_registry.call("get_display_name", item_id)
		).strip_edges()
		if not resolved.is_empty():
			return resolved
	return item_id
