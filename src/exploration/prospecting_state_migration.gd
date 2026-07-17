class_name ProspectingStateMigration
extends RefCounted

const VERSION := 3
const MAX_DANGER_REASONS := 6
const MAX_MESSAGE_LENGTH := 320


static func normalize_world_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	normalized["exploration"] = normalize_exploration_state(state.get("exploration", {}))
	return normalized


static func normalize_exploration_state(raw_state: Variant) -> Dictionary:
	var result := {
		"version": VERSION,
		"records": [],
		"last_result": {},
	}
	if raw_state is not Dictionary:
		return result
	var state: Dictionary = raw_state
	var records_by_key: Dictionary = {}
	var record_order: Array[String] = []
	var raw_records: Variant = state.get("records", [])
	if raw_records is Array:
		for raw_record: Variant in raw_records:
			if raw_record is not Dictionary:
				continue
			var record := _normalize_record(raw_record)
			if record.is_empty():
				continue
			var record_key := str(record.get("record_key", ""))
			if record_key in record_order:
				record_order.erase(record_key)
			records_by_key[record_key] = record
			record_order.append(record_key)
	var final_records_by_key: Dictionary = {}
	var sequence := 1
	for record_key: String in record_order:
		var record: Dictionary = records_by_key.get(record_key, {}).duplicate(true)
		record["sequence"] = sequence
		sequence += 1
		result["records"].append(record)
		final_records_by_key[record_key] = record
	var raw_last: Variant = state.get("last_result", {})
	if raw_last is Dictionary:
		var last_result := _normalize_last_result(raw_last)
		var last_key := str(last_result.get("record_key", ""))
		if not last_key.is_empty() and final_records_by_key.has(last_key):
			var matching_record: Dictionary = final_records_by_key[last_key]
			for field_name: String in [
				"sequence",
				"world_day",
				"world_time",
				"scanned_at_msec",
			]:
				last_result[field_name] = matching_record.get(field_name)
		result["last_result"] = last_result
	return result


static func _normalize_record(raw_record: Dictionary) -> Dictionary:
	var record_key := str(raw_record.get("record_key", "")).strip_edges()
	var chunk := _normalize_chunk(raw_record.get("chunk", []))
	if record_key.is_empty() or chunk.is_empty():
		return {}
	var record := _normalize_discovery_fields(raw_record)
	record["record_key"] = record_key
	record["chunk"] = chunk
	return record


static func _normalize_last_result(raw_result: Dictionary) -> Dictionary:
	var result := {
		"handled": bool(raw_result.get("handled", false)),
		"success": bool(raw_result.get("success", false)),
		"reason": _bounded_text(raw_result.get("reason", ""), 80),
		"message": _bounded_text(raw_result.get("message", ""), MAX_MESSAGE_LENGTH),
	}
	for numeric_field: String in ["sample_count", "geology_samples"]:
		if raw_result.has(numeric_field):
			result[numeric_field] = maxi(0, int(raw_result.get(numeric_field, 0)))
	if raw_result.has("remaining_seconds"):
		result["remaining_seconds"] = maxf(0.0, float(raw_result.get("remaining_seconds", 0.0)))
	var record_key := str(raw_result.get("record_key", "")).strip_edges()
	var chunk := _normalize_chunk(raw_result.get("chunk", []))
	if not record_key.is_empty() and not chunk.is_empty():
		var discovery := _normalize_discovery_fields(raw_result)
		for key: Variant in discovery:
			result[str(key)] = discovery[key]
		result["record_key"] = record_key
		result["chunk"] = chunk
	return result


static func _normalize_discovery_fields(raw_value: Dictionary) -> Dictionary:
	var world_time := float(raw_value.get("world_time", 0.0))
	if not is_finite(world_time):
		world_time = 0.0
	return {
		"profile_id": _bounded_text(raw_value.get("profile_id", "star_continent"), 64),
		"depth_band_id": _bounded_text(raw_value.get("depth_band_id", "unknown"), 48),
		"depth_label": _bounded_text(raw_value.get("depth_label", "未知"), 48),
		"density_id": _bounded_text(raw_value.get("density_id", "unknown"), 48),
		"density_label": _bounded_text(raw_value.get("density_label", "未知"), 48),
		"ore_ratio": clampf(float(raw_value.get("ore_ratio", 0.0)), 0.0, 1.0),
		"dominant_block_id": _bounded_text(raw_value.get("dominant_block_id", ""), 64),
		"dominant_label": _bounded_text(raw_value.get("dominant_label", ""), 64),
		"danger_tier_id": _bounded_text(raw_value.get("danger_tier_id", "unknown"), 48),
		"danger_label": _bounded_text(raw_value.get("danger_label", "未知"), 48),
		"danger_score": clampi(int(raw_value.get("danger_score", 0)), 0, 100),
		"danger_reasons": _normalize_reasons(raw_value.get("danger_reasons", [])),
		"message": _bounded_text(raw_value.get("message", ""), MAX_MESSAGE_LENGTH),
		"sequence": maxi(0, int(raw_value.get("sequence", 0))),
		"world_day": maxi(1, int(raw_value.get("world_day", 1))),
		"world_time": fposmod(world_time, 24.0),
		"scanned_at_msec": maxi(0, int(raw_value.get("scanned_at_msec", 0))),
	}


static func _normalize_chunk(raw_chunk: Variant) -> Array[int]:
	if raw_chunk is not Array or raw_chunk.size() < 2:
		return []
	return [int(raw_chunk[0]), int(raw_chunk[1])]


static func _normalize_reasons(raw_reasons: Variant) -> Array[String]:
	var reasons: Array[String] = []
	if raw_reasons is not Array:
		return reasons
	for raw_reason: Variant in raw_reasons:
		var reason := _bounded_text(raw_reason, 100)
		if not reason.is_empty() and reason not in reasons:
			reasons.append(reason)
		if reasons.size() >= MAX_DANGER_REASONS:
			break
	return reasons


static func _bounded_text(raw_value: Variant, maximum_length: int) -> String:
	var value := str(raw_value).strip_edges()
	return value.substr(0, maxi(0, maximum_length))
