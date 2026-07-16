class_name PlacementPreviewPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const INVALID_COORD := Vector3i(2147483647, 2147483647, 2147483647)


func evaluate(
	focus: Dictionary,
	selected_block_id: String,
	player_bounds: AABB = AABB()
) -> Dictionary:
	var result := {
		"target_visible": false,
		"target_position": [],
		"target_block_id": "",
		"target_boxes": [],
		"placement_visible": false,
		"placement_position": [],
		"placement_boxes": [],
		"selected_block_id": selected_block_id,
		"valid": false,
		"reason": "no_focus",
		"occupied_block_id": "",
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
	result["target_visible"] = true
	result["target_position"] = _position_array(target_position)
	result["target_block_id"] = target_block_id
	result["target_boxes"] = ShapeGeometryScript.boxes_as_snapshot(target_block_id)
	if selected_block_id.is_empty() or selected_block_id == BlockRegistryScript.AIR:
		result["reason"] = "no_block_selected"
		return result
	var placement_position := _position_from(focus.get("placement_position", []))
	if placement_position == INVALID_COORD:
		result["reason"] = "placement_unavailable"
		return result
	result["placement_visible"] = true
	result["placement_position"] = _position_array(placement_position)
	result["placement_boxes"] = ShapeGeometryScript.boxes_as_snapshot(selected_block_id)
	var occupied_block_id := str(
		focus.get("placement_target_block_id", BlockRegistryScript.AIR)
	)
	result["occupied_block_id"] = occupied_block_id
	if occupied_block_id != BlockRegistryScript.AIR:
		result["reason"] = "occupied"
		return result
	if player_bounds.size.length_squared() > 0.0:
		for placement_bounds: AABB in ShapeGeometryScript.world_boxes(
			selected_block_id, placement_position
		):
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
		"player_overlap":
			return "不能放在角色身体内"
		"placement_unavailable":
			return "当前表面无法放置"
		"no_block_selected":
			return "当前未选中可放置方块"
		_:
			return "当前没有可用放置目标"


func _position_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return INVALID_COORD


func _position_array(position: Vector3i) -> Array[int]:
	return [position.x, position.y, position.z]
