class_name BlockDoorPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const FAMILY := "oak_door"
const THICKNESS := 0.125
const CENTER_MIN := 0.4375

const CLOSED_LOWER: Array[String] = [
	"oak_door",
	"oak_door_east",
	"oak_door_north",
	"oak_door_west",
]
const CLOSED_UPPER: Array[String] = [
	"oak_door_upper",
	"oak_door_upper_east",
	"oak_door_upper_north",
	"oak_door_upper_west",
]
const OPEN_LOWER: Array[String] = [
	"oak_door_open",
	"oak_door_open_east",
	"oak_door_open_north",
	"oak_door_open_west",
]
const OPEN_UPPER: Array[String] = [
	"oak_door_upper_open",
	"oak_door_upper_open_east",
	"oak_door_upper_open_north",
	"oak_door_upper_open_west",
]


static func supports(block_id: String) -> bool:
	return str(BlockRegistryScript.get_definition(block_id).get("door_family", "")) == FAMILY


static func is_upper(block_id: String) -> bool:
	return supports(block_id) and str(
		BlockRegistryScript.get_definition(block_id).get("door_half", "lower")
	) == "upper"


static func is_open(block_id: String) -> bool:
	return supports(block_id) and bool(
		BlockRegistryScript.get_definition(block_id).get("door_open", false)
	)


static func rotation_quarters(block_id: String) -> int:
	return posmod(
		int(BlockRegistryScript.get_definition(block_id).get("rotation_quarters", 0)),
		4
	)


static func variant(quarters: int, upper: bool, opened: bool) -> String:
	var normalized := posmod(quarters, 4)
	if upper:
		return OPEN_UPPER[normalized] if opened else CLOSED_UPPER[normalized]
	return OPEN_LOWER[normalized] if opened else CLOSED_LOWER[normalized]


static func closed_lower_for_quarters(quarters: int) -> String:
	return variant(quarters, false, false)


static func lower_variant(block_id: String) -> String:
	return variant(rotation_quarters(block_id), false, is_open(block_id)) if supports(block_id) else block_id


static func upper_variant(block_id: String) -> String:
	return variant(rotation_quarters(block_id), true, is_open(block_id)) if supports(block_id) else block_id


static func toggled_variant(block_id: String) -> String:
	return (
		variant(rotation_quarters(block_id), is_upper(block_id), not is_open(block_id))
		if supports(block_id)
		else block_id
	)


static func lower_position(block_position: Vector3i, block_id: String) -> Vector3i:
	return block_position + Vector3i.DOWN if is_upper(block_id) else block_position


static func upper_position(block_position: Vector3i, block_id: String) -> Vector3i:
	return lower_position(block_position, block_id) + Vector3i.UP


static func is_valid_pair(lower_id: String, upper_id: String) -> bool:
	return (
		supports(lower_id)
		and supports(upper_id)
		and not is_upper(lower_id)
		and is_upper(upper_id)
		and rotation_quarters(lower_id) == rotation_quarters(upper_id)
		and is_open(lower_id) == is_open(upper_id)
	)


static func resolve_pair(world: Node, block_position: Vector3i, block_id: String) -> Dictionary:
	if (
		world == null
		or not is_instance_valid(world)
		or not world.has_method("get_block")
		or not supports(block_id)
	):
		return {}
	var lower_pos := lower_position(block_position, block_id)
	var upper_pos := lower_pos + Vector3i.UP
	var lower_id := str(world.call("get_block", lower_pos))
	var upper_id := str(world.call("get_block", upper_pos))
	if not is_valid_pair(lower_id, upper_id):
		return {}
	return {
		"lower_position":lower_pos,
		"upper_position":upper_pos,
		"lower_id":lower_id,
		"upper_id":upper_id,
		"open":is_open(lower_id),
		"rotation_quarters":rotation_quarters(lower_id),
	}


static func local_box(block_id: String) -> AABB:
	var quarters := rotation_quarters(block_id)
	if not is_open(block_id):
		return (
			AABB(Vector3(0.0, 0.0, CENTER_MIN), Vector3(1.0, 1.0, THICKNESS))
			if quarters % 2 == 0
			else AABB(Vector3(CENTER_MIN, 0.0, 0.0), Vector3(THICKNESS, 1.0, 1.0))
		)
	match quarters:
		1:
			return AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, THICKNESS))
		2:
			return AABB(Vector3(1.0 - THICKNESS, 0.0, 0.0), Vector3(THICKNESS, 1.0, 1.0))
		3:
			return AABB(Vector3(0.0, 0.0, 1.0 - THICKNESS), Vector3(1.0, 1.0, THICKNESS))
		_:
			return AABB(Vector3(0.0, 0.0, 0.0), Vector3(THICKNESS, 1.0, 1.0))


static func placement_boxes(lower_block_id: String) -> Array[AABB]:
	var lower_id := closed_lower_for_quarters(rotation_quarters(lower_block_id))
	var lower_box := local_box(lower_id)
	var upper_box := local_box(upper_variant(lower_id))
	return [
		lower_box,
		AABB(upper_box.position + Vector3.UP, upper_box.size),
	]


static func placement_boxes_as_snapshot(lower_block_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for box: AABB in placement_boxes(lower_block_id):
		result.append(
			{
				"position":[box.position.x, box.position.y, box.position.z],
				"size":[box.size.x, box.size.y, box.size.z],
			}
		)
	return result


static func placement_world_boxes(
	lower_block_id: String,
	lower_position_value: Vector3i
) -> Array[AABB]:
	var result: Array[AABB] = []
	for box: AABB in placement_boxes(lower_block_id):
		result.append(AABB(Vector3(lower_position_value) + box.position, box.size))
	return result


static func state_name(block_id: String) -> String:
	if not supports(block_id):
		return ""
	return "%s_%s_%s" % [
		"upper" if is_upper(block_id) else "lower",
		"open" if is_open(block_id) else "closed",
		["south", "east", "north", "west"][rotation_quarters(block_id)],
	]
