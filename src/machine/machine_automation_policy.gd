class_name MachineAutomationPolicy
extends RefCounted

const CYCLE_INTERVAL_SECONDS := 0.5
const MAX_MACHINES_PER_CYCLE := 16
const MAX_ITEMS_PER_CYCLE := 64
const MAX_ITEMS_PER_TRANSFER := 8
const MAX_CONTAINER_SLOTS_PER_CYCLE := 256
const MAX_TRANSFER_ATTEMPTS_PER_CYCLE := 128
const INPUT_OFFSET := Vector3i.UP
const OUTPUT_OFFSET := Vector3i.DOWN
const CONTAINER_BLOCK_ID := "chest"
const CONTAINER_PREFIX := "chest"
const CONTAINER_SLOT_COUNT := 27


static func parse_machine_position(machine_type: StringName, machine_id: String) -> Dictionary:
	var normalized_type := str(machine_type).strip_edges()
	var normalized_id := machine_id.strip_edges()
	var prefix := "%s@" % normalized_type
	if normalized_type.is_empty() or not normalized_id.begins_with(prefix):
		return failure("machine_id_prefix")
	var coordinate_text := normalized_id.trim_prefix(prefix)
	var parts := coordinate_text.split(",", false)
	if parts.size() != 3:
		return failure("machine_id_coordinates")
	for part: String in parts:
		if not part.is_valid_int():
			return failure("machine_id_coordinates")
	return {
		"success": true,
		"reason": "",
		"position": Vector3i(int(parts[0]), int(parts[1]), int(parts[2])),
	}


static func container_id(position: Vector3i) -> String:
	return "%s@%d,%d,%d" % [CONTAINER_PREFIX, position.x, position.y, position.z]


static func input_position(machine_position: Vector3i) -> Vector3i:
	return machine_position + INPUT_OFFSET


static func output_position(machine_position: Vector3i) -> Vector3i:
	return machine_position + OUTPUT_OFFSET


static func transfer_count(available: int, remaining_budget: int, transaction_limit: int) -> int:
	return mini(
		maxi(0, available),
		mini(
			maxi(0, remaining_budget),
			mini(MAX_ITEMS_PER_TRANSFER, maxi(0, transaction_limit))
		)
	)


static func cycle_due(accumulator: float) -> bool:
	return is_finite(accumulator) and accumulator + 0.000001 >= CYCLE_INTERVAL_SECONDS


static func normalized_accumulator(accumulator: float) -> float:
	if not is_finite(accumulator) or accumulator <= 0.0:
		return 0.0
	return fmod(accumulator, CYCLE_INTERVAL_SECONDS)


static func failure(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["reason"] = reason
	return result
