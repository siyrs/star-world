class_name BlockDoorInteractionService
extends Node

signal door_placed(lower_position: Vector3i, lower_block_id: String)
signal door_toggled(opened: bool, lower_position: Vector3i, lower_block_id: String)
signal door_removed(lower_position: Vector3i, lower_block_id: String)

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")

var placement_count := 0
var toggle_count := 0
var removal_count := 0
var rejection_count := 0
var last_result: Dictionary = {}
var _shutdown := false


func try_interact(
	world: Node,
	_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if not DoorPolicyScript.supports(block_id):
		return {}
	var pair: Dictionary = DoorPolicyScript.resolve_pair(world, block_position, block_id)
	if pair.is_empty():
		return _reject(
			"door_pair_invalid",
			"木门上下两部分状态不一致，请拆除后重新放置"
		)
	var lower_position: Vector3i = pair.get("lower_position", block_position)
	var upper_position: Vector3i = pair.get("upper_position", lower_position + Vector3i.UP)
	var old_lower := str(pair.get("lower_id", ""))
	var old_upper := str(pair.get("upper_id", ""))
	var next_lower := DoorPolicyScript.toggled_variant(old_lower)
	var next_upper := DoorPolicyScript.toggled_variant(old_upper)
	if not _replace_pair(
		world,
		lower_position,
		upper_position,
		old_lower,
		old_upper,
		next_lower,
		next_upper
	):
		return _reject("door_toggle_failed", "木门状态切换失败，原状态已保留")
	toggle_count += 1
	var opened := DoorPolicyScript.is_open(next_lower)
	last_result = {
		"action":"door_toggle",
		"success":true,
		"opened":opened,
		"lower_position":_position_array(lower_position),
		"lower_block_id":next_lower,
	}
	door_toggled.emit(opened, lower_position, next_lower)
	return {
		"handled":true,
		"success":true,
		"action":&"door_toggle",
		"message":"木门已%s" % ("打开" if opened else "关闭"),
		"severity":"info",
		"opened":opened,
		"lower_position":_position_array(lower_position),
		"lower_block_id":next_lower,
	}


func get_interaction_hint(block_id: String, _selected_item_id: String = "") -> String:
	if not DoorPolicyScript.supports(block_id):
		return ""
	return "右键%s木门" % ("关闭" if DoorPolicyScript.is_open(block_id) else "打开")


func can_break_block(
	_world: Node,
	_block_position: Vector3i,
	_block_id: String
) -> bool:
	return true


func try_place_block(
	world: Node,
	inventory: Node,
	block_position: Vector3i,
	block_id: String,
	previous_block: String = BlockRegistryScript.AIR
) -> Dictionary:
	if not DoorPolicyScript.supports(block_id):
		return {"handled":false}
	if _shutdown or world == null or inventory == null:
		return _reject("door_service_unavailable", "木门服务暂不可用")
	var lower_id := DoorPolicyScript.closed_lower_for_quarters(
		DoorPolicyScript.rotation_quarters(block_id)
	)
	var upper_id := DoorPolicyScript.upper_variant(lower_id)
	var upper_position := block_position + Vector3i.UP
	var support_position := block_position + Vector3i.DOWN
	var current_lower := str(world.call("get_block", block_position))
	var current_upper := str(world.call("get_block", upper_position))
	var support_id := str(world.call("get_block", support_position))
	if current_lower != BlockRegistryScript.AIR or previous_block != BlockRegistryScript.AIR:
		return _reject("door_lower_occupied", "木门下半位置已被占用")
	if current_upper != BlockRegistryScript.AIR:
		return _reject("door_upper_occupied", "木门上半位置已被占用")
	if not BlockRegistryScript.is_solid(support_id):
		return _reject("door_support_missing", "木门需要放在实体方块上")
	if not bool(world.call("set_block", block_position, lower_id)):
		return _reject("door_lower_place_failed", "木门下半放置失败")
	if not bool(world.call("set_block", upper_position, upper_id)):
		world.call("set_block", block_position, previous_block)
		return _reject("door_upper_place_failed", "木门上半放置失败，已回滚")
	var consumed: Dictionary = inventory.call("consume_selected", 1)
	if consumed.is_empty():
		world.call("set_block", upper_position, current_upper)
		world.call("set_block", block_position, current_lower)
		return _reject("door_inventory_race", "木门物品状态发生变化，放置已回滚")
	placement_count += 1
	last_result = {
		"action":"door_place",
		"success":true,
		"lower_position":_position_array(block_position),
		"lower_block_id":lower_id,
		"upper_block_id":upper_id,
	}
	door_placed.emit(block_position, lower_id)
	return {
		"handled":true,
		"success":true,
		"action":&"door_place",
		"block_id":lower_id,
		"lower_position":_position_array(block_position),
		"upper_position":_position_array(upper_position),
		"placed_blocks":[lower_id, upper_id],
	}


func remove_block_structure(
	world: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if not DoorPolicyScript.supports(block_id):
		return {"handled":false}
	if _shutdown or world == null:
		return _reject("door_service_unavailable", "木门服务暂不可用")
	var pair: Dictionary = DoorPolicyScript.resolve_pair(world, block_position, block_id)
	if pair.is_empty():
		var orphan_removed := str(world.call("remove_block", block_position))
		if orphan_removed == BlockRegistryScript.AIR:
			return _reject("door_orphan_remove_failed", "损坏的木门残片无法移除")
		removal_count += 1
		last_result = {
			"action":"door_remove_orphan",
			"success":true,
			"lower_position":_position_array(block_position),
			"lower_block_id":orphan_removed,
		}
		return {
			"handled":true,
			"success":true,
			"removed_block":orphan_removed,
			"removed_positions":[_position_array(block_position)],
		}
	var lower_position: Vector3i = pair.get("lower_position", block_position)
	var upper_position: Vector3i = pair.get("upper_position", lower_position + Vector3i.UP)
	var lower_id := str(pair.get("lower_id", ""))
	var upper_id := str(pair.get("upper_id", ""))
	if not bool(world.call("set_block", lower_position, BlockRegistryScript.AIR)):
		return _reject("door_lower_remove_failed", "木门下半拆除失败")
	if not bool(world.call("set_block", upper_position, BlockRegistryScript.AIR)):
		world.call("set_block", lower_position, lower_id)
		return _reject("door_upper_remove_failed", "木门上半拆除失败，已回滚")
	removal_count += 1
	last_result = {
		"action":"door_remove",
		"success":true,
		"lower_position":_position_array(lower_position),
		"lower_block_id":lower_id,
	}
	door_removed.emit(lower_position, lower_id)
	return {
		"handled":true,
		"success":true,
		"removed_block":block_id,
		"removed_positions":[
			_position_array(lower_position),
			_position_array(upper_position),
		],
		"lower_block_id":lower_id,
		"upper_block_id":upper_id,
	}


func get_snapshot() -> Dictionary:
	return {
		"shutdown":_shutdown,
		"placement_count":placement_count,
		"toggle_count":toggle_count,
		"removal_count":removal_count,
		"rejection_count":rejection_count,
		"last_result":last_result.duplicate(true),
	}


func clear() -> void:
	placement_count = 0
	toggle_count = 0
	removal_count = 0
	rejection_count = 0
	last_result.clear()


func shutdown() -> void:
	_shutdown = true
	clear()


func _replace_pair(
	world: Node,
	lower_position: Vector3i,
	upper_position: Vector3i,
	old_lower: String,
	old_upper: String,
	new_lower: String,
	new_upper: String
) -> bool:
	if not bool(world.call("set_block", lower_position, new_lower)):
		return false
	if bool(world.call("set_block", upper_position, new_upper)):
		return true
	world.call("set_block", lower_position, old_lower)
	world.call("set_block", upper_position, old_upper)
	return false


func _reject(reason: String, message: String) -> Dictionary:
	rejection_count += 1
	last_result = {
		"action":"door_rejected",
		"success":false,
		"reason":reason,
	}
	return {
		"handled":true,
		"success":false,
		"reason":reason,
		"message":message,
		"severity":"warning",
	}


func _position_array(position: Vector3i) -> Array[int]:
	return [position.x, position.y, position.z]
