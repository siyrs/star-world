class_name ProspectingStateMigration
extends RefCounted

const VERSION := 2


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
	var raw_records: Variant = state.get("records", [])
	if raw_records is Array:
		for raw_record in raw_records:
			if raw_record is not Dictionary:
				continue
			var record := _normalize_record(raw_record)
			if not record.is_empty():
				result["records"].append(record)
	var raw_last: Variant = state.get("last_result", {})
	if raw_last is Dictionary:
		result["last_result"] = raw_last.duplicate(true)
	return result


static func _normalize_record(raw_record: Dictionary) -> Dictionary:
	var record_key := str(raw_record.get("record_key", "")).strip_edges()
	var chunk: Variant = raw_record.get("chunk", [])
	if record_key.is_empty() or chunk is not Array or chunk.size() < 2:
		return {}
	var raw_reasons: Variant = raw_record.get("danger_reasons", [])
	var danger_reasons: Array[String] = []
	if raw_reasons is Array:
		for raw_reason: Variant in raw_reasons:
			var reason := str(raw_reason).strip_edges()
			if not reason.is_empty() and danger_reasons.size() < 6:
				danger_reasons.append(reason)
	return {
		"record_key": record_key,
		"chunk": [int(chunk[0]), int(chunk[1])],
		"profile_id": str(raw_record.get("profile_id", "star_continent")),
		"depth_band_id": str(raw_record.get("depth_band_id", "unknown")),
		"depth_label": str(raw_record.get("depth_label", "未知")),
		"density_id": str(raw_record.get("density_id", "unknown")),
		"density_label": str(raw_record.get("density_label", "未知")),
		"ore_ratio": clampf(float(raw_record.get("ore_ratio", 0.0)), 0.0, 1.0),
		"dominant_block_id": str(raw_record.get("dominant_block_id", "")),
		"dominant_label": str(raw_record.get("dominant_label", "")),
		"danger_tier_id": str(raw_record.get("danger_tier_id", "unknown")),
		"danger_label": str(raw_record.get("danger_label", "未知")),
		"danger_score": clampi(int(raw_record.get("danger_score", 0)), 0, 100),
		"danger_reasons": danger_reasons,
		"message": str(raw_record.get("message", "")),
		"scanned_at_msec": maxi(0, int(raw_record.get("scanned_at_msec", 0))),
	}
