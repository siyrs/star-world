class_name PlacementPreviewPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const INVALID_COORD := Vector3i(2147483647,2147483647,2147483647)


func evaluate(
	focus: Dictionary,
	selected_block_id: String,
	player_bounds: AABB = AABB()
) -> Dictionary:
	var result := {
		"target_visible":false,
		"target_position":[],
		"target_block_id":"",
		"target_boxes":[],
		"target_connection_mask":0,
		"placement_visible":false,
		"placement_position":[],
		"placement_boxes":[],
		"placement_connection_mask":0,
		"placement_companion_position":[],
		"placement_companion_block_id":"",
		"selected_block_id":selected_block_id,
		"valid":false,
		"reason":"no_focus",
		"occupied_block_id":"",
	}
	if str(focus.get("type", "")) != "block":
		return result
	var target_position := _position_from(
		focus.get("hit_position", focus.get("position", []))
	)
	if target_position == INVALID_COORD:
		return result
	var target_block_id := str(
		focus.get("hit_block_id", focus.get("block_id", BlockRegistryScript.AIR))
	)
	var target_mask := ConnectionPolicyScript.resolve_mask(
		target_block_id,
		_neighbors_from(focus.get("target_neighbor_ids", {}))
	)
	result["target_visible"] = true
	result["target_position"] = _position_array(target_position)
	result["target_block_id"] = target_block_id
	result["target_connection_mask"] = target_mask
	result["target_boxes"] = ShapeGeometryScript.boxes_as_snapshot(
		target_block_id,
		target_mask
	)
	if selected_block_id.is_empty() or selected_block_id == BlockRegistryScript.AIR:
		result["reason"] = "no_block_selected"
		return result
	var placement_position := _position_from(focus.get("placement_position", []))
	if placement_position == INVALID_COORD:
		result["reason"] = "placement_unavailable"
		return result
	var placement_mask := ConnectionPolicyScript.resolve_mask(
		selected_block_id,
		_neighbors_from(focus.get("placement_neighbor_ids", {}))
	)
	result["placement_visible"] = true
	result["placement_position"] = _position_array(placement_position)
	result["placement_connection_mask"] = placement_mask
	if DoorPolicyScript.supports(selected_block_id):
		var lower_id := DoorPolicyScript.closed_lower_for_quarters(
			DoorPolicyScript.rotation_quarters(selected_block_id)
		)
		result["placement_boxes"] = DoorPolicyScript.placement_boxes_as_snapshot(lower_id)
		result["placement_companion_position"] = _position_array(
			placement_position + Vector3i.UP
		)
		result["placement_companion_block_id"] = DoorPolicyScript.upper_variant(lower_id)
	else:
		result["placement_boxes"] = ShapeGeometryScript.boxes_as_snapshot(
			selected_block_id,
			placement_mask
		)
	var occupied_block_id := str(
		focus.get("placement_target_block_id", BlockRegistryScript.AIR)
	)
	result["occupied_block_id"] = occupied_block_id
	if occupied_block_id != BlockRegistryScript.AIR:
		result["reason"] = "occupied"
		return result
	if DoorPolicyScript.supports(selected_block_id):
		var upper_block_id := str(
			focus.get("placement_upper_block_id", BlockRegistryScript.AIR)
		)
		if upper_block_id != BlockRegistryScript.AIR:
			result["occupied_block_id"] = upper_block_id
			result["reason"] = "door_upper_occupied"
			return result
		var support_block_id := str(
			focus.get("placement_support_block_id", BlockRegistryScript.AIR)
		)
		if not BlockRegistryScript.is_solid(support_block_id):
			result["reason"] = "door_support_missing"
			return result
	if player_bounds.size.length_squared() > 0.0:
		var world_boxes: Array[AABB] = (
			DoorPolicyScript.placement_world_boxes(selected_block_id, placement_position)
			if DoorPolicyScript.supports(selected_block_id)
			else ShapeGeometryScript.world_boxes(
				selected_block_id,
				placement_position,
				placement_mask
			)
		)
		for placement_bounds: AABB in world_boxes:
			if player_bounds.intersects(placement_bounds):
				result["reason"] = "player_overlap"
				return result
	result["valid"] = true
	result["reason"] = "ok"
	return result


static func reason_text(reason: String, occupied_name: String = "") -> String:
	match reason:
		"ok":
			return "可以放置"
		"occupied":
			return (
				"目标格已被%s占用" % occupied_name
				if not occupied_name.is_empty()
				else "目标格已被占用"
			)
		"door_upper_occupied":
			return (
				"木门上方已被%s占用" % occupied_name
				if not occupied_name.is_empty()
				else "木门上方空间被占用"
			)
		"door_support_missing":
			return "木门需要放在实体方块上"
		"player_overlap":
			return "不能放在角色身体内"
		"placement_unavailable":
			return "当前表面无法放置"
		"no_block_selected":
			return "当前未选中可放置方块"
		_:
			return "当前没有可用放置目标"


func _neighbors_from(value: Variant) -> Dictionary:
	var result := ConnectionPolicyScript.empty_neighbors()
	if value is not Dictionary:
		return result
	for direction_name in result.keys():
		result[direction_name] = str(value.get(direction_name, BlockRegistryScript.AIR))
	return result


func _position_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]),int(value[1]),int(value[2]))
	return INVALID_COORD


func _position_array(position: Vector3i) -> Array[int]:
	return [position.x,position.y,position.z]
