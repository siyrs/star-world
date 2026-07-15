class_name MiningFeedbackPolicy
extends RefCounted

const STAGE_COUNT := 10


static func evaluate(progress_snapshot: Dictionary, input_enabled: bool = true) -> Dictionary:
	if not input_enabled:
		return _hidden("input_blocked")
	if progress_snapshot.is_empty():
		return _hidden("no_progress")
	if str(progress_snapshot.get("status", "progress")) != "progress":
		return _hidden("not_progressing")
	var position := _vector3i_from(progress_snapshot.get("position", []))
	if position == null:
		return _hidden("invalid_position")
	var ratio := clampf(float(progress_snapshot.get("ratio", 0.0)), 0.0, 1.0)
	return {
		"visible": true,
		"reason": "progress",
		"ratio": ratio,
		"stage": stage_for_ratio(ratio),
		"block_id": str(progress_snapshot.get("block_id", "")),
		"block_position": position,
		"target_key": str(progress_snapshot.get("target_key", "")),
	}


static func stage_for_ratio(ratio: float) -> int:
	return clampi(floori(clampf(ratio, 0.0, 0.999999) * float(STAGE_COUNT)), 0, STAGE_COUNT - 1)


static func _hidden(reason: String) -> Dictionary:
	return {
		"visible": false,
		"reason": reason,
		"ratio": 0.0,
		"stage": -1,
		"block_id": "",
		"block_position": Vector3i.ZERO,
		"target_key": "",
	}


static func _vector3i_from(value: Variant) -> Variant:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return null
