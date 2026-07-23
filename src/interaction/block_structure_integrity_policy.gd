class_name BlockStructureIntegrityPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const LadderPolicyScript = preload("res://src/block/block_ladder_policy.gd")

const DOOR_ITEM_ID := "oak_door"
const LADDER_ITEM_ID := "ladder"
const CANDIDATE_OFFSETS: Array[Vector3i] = [
	Vector3i.ZERO,
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]


static func candidate_positions(changed_position: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for offset: Vector3i in CANDIDATE_OFFSETS:
		result.append(changed_position + offset)
	return result


static func is_structural_block(block_id: String) -> bool:
	return DoorPolicyScript.supports(block_id) or LadderPolicyScript.supports(block_id)


static func inspect(world: Node, block_position: Vector3i) -> Dictionary:
	if (
		world == null
		or not is_instance_valid(world)
		or not world.has_method("get_block")
	):
		return {}
	var block_id := str(world.call("get_block", block_position))
	if DoorPolicyScript.supports(block_id):
		return _inspect_door(world, block_position, block_id)
	if LadderPolicyScript.supports(block_id):
		return _inspect_ladder(world, block_position, block_id)
	return {}


static func _inspect_door(
	world: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	var lower_position := DoorPolicyScript.lower_position(block_position, block_id)
	var upper_position := lower_position + Vector3i.UP
	var support_position := lower_position + Vector3i.DOWN
	var lower_id := str(world.call("get_block", lower_position))
	var upper_id := str(world.call("get_block", upper_position))
	var support_id := str(world.call("get_block", support_position))
	var pair_valid := DoorPolicyScript.is_valid_pair(lower_id, upper_id)
	var support_valid := BlockRegistryScript.is_solid(support_id)
	var positions: Array[Vector3i] = []
	if DoorPolicyScript.supports(lower_id):
		positions.append(lower_position)
	if DoorPolicyScript.supports(upper_id) and upper_position not in positions:
		positions.append(upper_position)
	if positions.is_empty():
		return {}
	return {
		"kind": "door",
		"structure_key": "door:%s" % _position_key(lower_position),
		"supported": pair_valid and support_valid,
		"reason": _door_reason(pair_valid, support_valid),
		"positions": positions,
		"support_position": support_position,
		"support_block_id": support_id,
		"drop_item": DOOR_ITEM_ID,
		"drop_count": 1,
		"drop_position": Vector3(lower_position) + Vector3(0.5, 1.0, 0.5),
		"pair_valid": pair_valid,
		"support_valid": support_valid,
	}


static func _inspect_ladder(
	world: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	var support_position := block_position + LadderPolicyScript.support_offset(block_id)
	var support_id := str(world.call("get_block", support_position))
	var support_valid := LadderPolicyScript.is_valid_support(support_id)
	return {
		"kind": "ladder",
		"structure_key": "ladder:%s" % _position_key(block_position),
		"supported": support_valid,
		"reason": "ok" if support_valid else "support_missing",
		"positions": [block_position],
		"support_position": support_position,
		"support_block_id": support_id,
		"drop_item": LADDER_ITEM_ID,
		"drop_count": 1,
		"drop_position": Vector3(block_position) + Vector3(0.5, 0.65, 0.5),
		"support_valid": support_valid,
	}


static func _door_reason(pair_valid: bool, support_valid: bool) -> String:
	if pair_valid and support_valid:
		return "ok"
	if not pair_valid and not support_valid:
		return "pair_invalid_and_support_missing"
	return "pair_invalid" if not pair_valid else "support_missing"


static func _position_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]
