class_name HeldItemVisualPolicy
extends RefCounted

const ACTION_SWING := &"swing"
const ACTION_USE := &"use"
const ACTION_NONE := &"none"


func classify(item_definition: Dictionary, block_id: String = "") -> String:
	if item_definition.is_empty() and block_id.is_empty():
		return "empty"
	if not block_id.is_empty() or str(item_definition.get("category", "")) == "block":
		return "block"
	if not str(item_definition.get("tool_type", "")).is_empty():
		return "tool"
	match str(item_definition.get("category", "")):
		"food":
			return "food"
		"utility":
			return "utility"
		"armor":
			return "armor"
		_:
			return "item"


func action_kind(action: StringName) -> StringName:
	match action:
		&"attack", &"mine", &"harvest_no_drop":
			return ACTION_SWING
		&"place", &"eat", &"interact", &"interact_entity", &"till", &"plant", &"harvest":
			return ACTION_USE
		_:
			return ACTION_NONE


func sample_transform(
	config: Dictionary,
	elapsed_seconds: float,
	movement_speed: float,
	on_floor: bool,
	swing_ratio: float = -1.0,
	use_ratio: float = -1.0,
	switch_ratio: float = 1.0,
	mining_active: bool = false
) -> Dictionary:
	var position_offset := Vector3.ZERO
	var rotation_degrees := Vector3.ZERO
	var scale_multiplier := 1.0
	var reference_speed := maxf(0.1, float(config.get("walk_reference_speed", 5.4)))
	var movement_ratio := clampf(movement_speed / reference_speed, 0.0, 1.25)
	if on_floor and movement_ratio > 0.01:
		var frequency := maxf(0.1, float(config.get("walk_bob_frequency", 8.5)))
		var amplitude := maxf(0.0, float(config.get("walk_bob_amplitude", 0.035)))
		var phase := elapsed_seconds * frequency
		position_offset.x += sin(phase) * amplitude * movement_ratio
		position_offset.y -= absf(cos(phase)) * amplitude * 0.58 * movement_ratio
		rotation_degrees.z += sin(phase) * 2.4 * movement_ratio
	if mining_active:
		var mining_frequency := maxf(0.1, float(config.get("mining_frequency", 5.5)))
		var mining_amplitude := maxf(0.0, float(config.get("mining_amplitude", 0.075)))
		var mining_wave := sin(elapsed_seconds * mining_frequency * TAU)
		var mining_pulse := absf(mining_wave)
		position_offset.x -= mining_pulse * mining_amplitude * 0.55
		position_offset.y -= mining_pulse * mining_amplitude
		rotation_degrees.x += mining_pulse * 30.0
		rotation_degrees.z += mining_wave * 5.0
	if swing_ratio >= 0.0:
		var curve := sin(clampf(swing_ratio, 0.0, 1.0) * PI)
		position_offset.x -= 0.18 * curve
		position_offset.y -= 0.08 * curve
		position_offset.z += 0.08 * curve
		rotation_degrees += _vector3_from(config.get("swing_rotation_degrees", [58.0, -18.0, -8.0])) * curve
	if use_ratio >= 0.0:
		var curve := sin(clampf(use_ratio, 0.0, 1.0) * PI)
		position_offset.x -= 0.05 * curve
		position_offset.y += 0.12 * curve
		position_offset.z += 0.14 * curve
		rotation_degrees += _vector3_from(config.get("use_rotation_degrees", [-22.0, 12.0, 6.0])) * curve
	var normalized_switch := clampf(switch_ratio, 0.0, 1.0)
	var switch_drop := (1.0 - ease(normalized_switch, -2.0)) * maxf(
		0.0, float(config.get("switch_drop_distance", 0.42))
	)
	position_offset.y -= switch_drop
	scale_multiplier = lerpf(0.82, 1.0, normalized_switch)
	return {
		"position_offset": position_offset,
		"rotation_degrees": rotation_degrees,
		"scale_multiplier": scale_multiplier,
		"movement_ratio": movement_ratio,
	}


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
