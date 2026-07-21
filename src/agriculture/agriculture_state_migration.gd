class_name AgricultureStateMigration
extends RefCounted

const CropRegistryScript = preload("res://src/agriculture/crop_registry.gd")
const SoilPolicyScript = preload("res://src/agriculture/soil_moisture_policy.gd")

const VERSION := 2
const SOIL_VERSION := 1
const MAX_CROP_RECORDS := 4096
const MAX_SOIL_RECORDS := 4096
const MAX_ABS_COORDINATE := 1048576
const MAX_ELAPSED_SECONDS := 6.0 * 60.0 * 60.0
const MAX_MANUAL_HYDRATION_SECONDS := 6.0 * 60.0 * 60.0
const INVALID_POSITION := Vector3i(2147483647, 2147483647, 2147483647)


static func normalize_world_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	var raw_agriculture: Variant = state.get("agriculture", {})
	normalized["agriculture"] = normalize_agriculture_state(
		raw_agriculture if raw_agriculture is Dictionary else {}
	)
	return normalized


static func normalize_agriculture_state(raw_state: Dictionary) -> Dictionary:
	var crop_registry = CropRegistryScript.new()
	var soil_policy = SoilPolicyScript.new()
	var crops: Dictionary = {}
	var raw_crops: Variant = raw_state.get("crops", {})
	if raw_crops is Dictionary:
		var crop_keys: Array = raw_crops.keys()
		crop_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for raw_key: Variant in crop_keys:
			if crops.size() >= MAX_CROP_RECORDS:
				break
			var raw_crop: Variant = raw_crops.get(raw_key, {})
			if raw_crop is not Dictionary:
				continue
			var crop_id := str(raw_crop.get("crop_id", "")).strip_edges()
			var definition: Dictionary = crop_registry.get_crop(crop_id)
			var position := _position_from_value(raw_crop.get("position", []))
			var stage_blocks: Array = definition.get("stage_blocks", [])
			if definition.is_empty() or position == INVALID_POSITION or stage_blocks.is_empty():
				continue
			var key := _crop_key(position)
			if crops.has(key):
				continue
			crops[key] = {
				"crop_id": crop_id,
				"position": [position.x, position.y, position.z],
				"stage": clampi(int(raw_crop.get("stage", 0)), 0, stage_blocks.size() - 1),
				"elapsed_seconds": _bounded_seconds(
					raw_crop.get("elapsed_seconds", 0.0), MAX_ELAPSED_SECONDS
				),
			}
	var soils: Dictionary = {}
	var raw_soil_root: Variant = raw_state.get("soil_moisture", {})
	var raw_soils: Variant = (
		raw_soil_root.get("soils", {}) if raw_soil_root is Dictionary else {}
	)
	if raw_soils is Dictionary:
		var soil_keys: Array = raw_soils.keys()
		soil_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for raw_key: Variant in soil_keys:
			if soils.size() >= MAX_SOIL_RECORDS:
				break
			var raw_soil: Variant = raw_soils.get(raw_key, {})
			if raw_soil is not Dictionary:
				continue
			var position := _position_from_value(raw_soil.get("position", []))
			if position == INVALID_POSITION:
				continue
			var key := _soil_key(position)
			if soils.has(key):
				continue
			soils[key] = {
				"position": [position.x, position.y, position.z],
				"manual_remaining_seconds": _bounded_seconds(
					raw_soil.get("manual_remaining_seconds", 0.0),
					MAX_MANUAL_HYDRATION_SECONDS
				),
				"hydrated": bool(raw_soil.get("hydrated", false)),
			}
	return {
		"version": VERSION,
		"saved_at_unix": maxi(0, int(raw_state.get(
			"saved_at_unix", Time.get_unix_time_from_system()
		))),
		"crops": crops,
		"soil_moisture": {
			"version": SOIL_VERSION,
			"policy_version": int(soil_policy.schema_version),
			"soils": soils,
		},
	}


static func _bounded_seconds(value: Variant, maximum: float) -> float:
	var seconds := float(value)
	if not is_finite(seconds):
		return 0.0
	return clampf(seconds, 0.0, maxf(0.0, maximum))


static func _position_from_value(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value if _position_in_bounds(value) else INVALID_POSITION
	if value is not Array or value.size() < 3:
		return INVALID_POSITION
	var x := float(value[0])
	var y := float(value[1])
	var z := float(value[2])
	if not is_finite(x) or not is_finite(y) or not is_finite(z):
		return INVALID_POSITION
	var position := Vector3i(int(x), int(y), int(z))
	return position if _position_in_bounds(position) else INVALID_POSITION


static func _position_in_bounds(position: Vector3i) -> bool:
	return (
		absi(position.x) <= MAX_ABS_COORDINATE
		and absi(position.y) <= MAX_ABS_COORDINATE
		and absi(position.z) <= MAX_ABS_COORDINATE
	)


static func _crop_key(position: Vector3i) -> String:
	return "crop@%d,%d,%d" % [position.x, position.y, position.z]


static func _soil_key(position: Vector3i) -> String:
	return "soil@%d,%d,%d" % [position.x, position.y, position.z]
