class_name InventoryTransactionPolicy
extends RefCounted


static func plan(
	current_slots: Array,
	registry: Variant,
	removals: Dictionary = {},
	additions: Array = []
) -> Dictionary:
	if registry == null or not registry.has_method("has_item") or not registry.has_method("get_max_stack"):
		return _failure("registry_unavailable")
	var normalized_removals := _normalize_removals(removals, registry)
	if not bool(normalized_removals.get("success", false)):
		return normalized_removals
	var normalized_additions := _normalize_additions(additions, registry)
	if not bool(normalized_additions.get("success", false)):
		return normalized_additions
	var planned_slots: Array = []
	for raw_slot: Variant in current_slots:
		planned_slots.append(raw_slot.duplicate(true) if raw_slot is Dictionary else {})
	var changed_indices: Dictionary = {}
	var removal_totals: Dictionary = normalized_removals.get("items", {})
	var removal_ids: Array[String] = []
	for raw_item_id: Variant in removal_totals.keys():
		removal_ids.append(str(raw_item_id))
	removal_ids.sort()
	for item_id: String in removal_ids:
		var remaining := int(removal_totals.get(item_id, 0))
		for index in planned_slots.size():
			if remaining <= 0:
				break
			var slot: Dictionary = planned_slots[index]
			if str(slot.get("item_id", "")) != item_id:
				continue
			var removed := mini(remaining, maxi(0, int(slot.get("count", 0))))
			if removed <= 0:
				continue
			remaining -= removed
			slot["count"] = int(slot.get("count", 0)) - removed
			if int(slot.get("count", 0)) <= 0:
				slot = {}
			planned_slots[index] = slot
			changed_indices[index] = true
		if remaining > 0:
			return {
				"success": false,
				"reason": "requirements_missing",
				"missing": {item_id: remaining},
			}
	var addition_entries: Array[Dictionary] = normalized_additions.get("items", [])
	var addition_totals: Dictionary = {}
	for addition: Dictionary in addition_entries:
		var item_id := str(addition.get("item_id", ""))
		var metadata: Dictionary = addition.get("metadata", {})
		var remaining := int(addition.get("count", 0))
		var max_stack := maxi(1, int(registry.call("get_max_stack", item_id)))
		for index in planned_slots.size():
			if remaining <= 0:
				break
			var slot: Dictionary = planned_slots[index]
			if (
				str(slot.get("item_id", "")) != item_id
				or slot.get("metadata", {}) != metadata
				or int(slot.get("count", 0)) >= max_stack
			):
				continue
			var accepted := mini(remaining, max_stack - int(slot.get("count", 0)))
			if accepted <= 0:
				continue
			slot["count"] = int(slot.get("count", 0)) + accepted
			planned_slots[index] = slot
			remaining -= accepted
			changed_indices[index] = true
		for index in planned_slots.size():
			if remaining <= 0:
				break
			if not planned_slots[index].is_empty():
				continue
			var accepted := mini(remaining, max_stack)
			var new_slot := {"item_id": item_id, "count": accepted}
			if not metadata.is_empty():
				new_slot["metadata"] = metadata.duplicate(true)
			planned_slots[index] = new_slot
			remaining -= accepted
			changed_indices[index] = true
		if remaining > 0:
			return {
				"success": false,
				"reason": "inventory_full",
				"item_id": item_id,
				"remaining": remaining,
			}
		addition_totals[item_id] = int(addition_totals.get(item_id, 0)) + int(addition.get("count", 0))
	var sorted_indices: Array[int] = []
	for raw_index: Variant in changed_indices.keys():
		sorted_indices.append(int(raw_index))
	sorted_indices.sort()
	return {
		"success": true,
		"reason": "",
		"slots": planned_slots,
		"changed_indices": sorted_indices,
		"removed": removal_totals.duplicate(true),
		"added": addition_totals,
	}


static func _normalize_removals(removals: Dictionary, registry: Variant) -> Dictionary:
	var result: Dictionary = {}
	for raw_item_id: Variant in removals.keys():
		var item_id := str(raw_item_id).strip_edges()
		var count := int(removals[raw_item_id])
		if item_id.is_empty() or count <= 0:
			return _failure("invalid_removal", {"item_id": item_id, "count": count})
		if not bool(registry.call("has_item", item_id)):
			return _failure("unknown_item", {"item_id": item_id})
		result[item_id] = int(result.get(item_id, 0)) + count
	return {"success": true, "items": result}


static func _normalize_additions(additions: Array, registry: Variant) -> Dictionary:
	var result: Array[Dictionary] = []
	for raw_addition: Variant in additions:
		if raw_addition is not Dictionary:
			return _failure("invalid_addition")
		var addition: Dictionary = raw_addition
		var item_id := str(addition.get("item_id", addition.get("id", ""))).strip_edges()
		var count := int(addition.get("count", 0))
		if item_id.is_empty() or count <= 0:
			return _failure("invalid_addition", {"item_id": item_id, "count": count})
		if not bool(registry.call("has_item", item_id)):
			return _failure("unknown_item", {"item_id": item_id})
		var raw_metadata: Variant = addition.get("metadata", {})
		var metadata: Dictionary = raw_metadata.duplicate(true) if raw_metadata is Dictionary else {}
		result.append({"item_id": item_id, "count": count, "metadata": metadata})
	return {"success": true, "items": result}


static func _failure(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "reason": reason}
	result.merge(extra, true)
	return result
