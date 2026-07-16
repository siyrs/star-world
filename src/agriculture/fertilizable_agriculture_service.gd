class_name FertilizableAgricultureService
extends "res://src/agriculture/agriculture_service.gd"

signal crop_fertilized(
	position: Vector3i,
	crop_id: String,
	fertilizer_item_id: String,
	from_stage: int,
	to_stage: int
)

const FertilizerRegistryScript = preload(
	"res://src/agriculture/fertilizer_registry.gd"
)
const FertilizerPolicyScript = preload(
	"res://src/agriculture/fertilizer_policy.gd"
)

var fertilizer_registry = FertilizerRegistryScript.new()
var fertilizer_policy = FertilizerPolicyScript.new()


func try_interact(
	p_world: Node,
	p_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	var fertilizer_result: Dictionary = _try_apply_fertilizer(
		p_world, p_inventory, block_position, block_id
	)
	if bool(fertilizer_result.get("handled", false)):
		return fertilizer_result
	return super.try_interact(p_world, p_inventory, block_position, block_id)


func get_interaction_hint(block_id: String, selected_item_id: String = "") -> String:
	var profile: Dictionary = fertilizer_registry.get_profile(selected_item_id)
	var crop_definition: Dictionary = crop_registry.get_crop_by_stage_block(block_id)
	if not profile.is_empty() and not crop_definition.is_empty():
		var crop_id := str(crop_definition.get("id", ""))
		var current_stage := crop_registry.get_stage_index(crop_id, block_id)
		var evaluation: Dictionary = fertilizer_policy.evaluate(
			profile, crop_definition, current_stage
		)
		if bool(evaluation.get("success", false)):
			return "右键施用%s（推进 %d 阶段）" % [
				str(profile.get("name", "肥料")),
				int(evaluation.get("actual_advances", 1)),
			]
		if str(evaluation.get("reason", "")) == "crop_mature":
			return "作物已成熟，请先收获"
	return super.get_interaction_hint(block_id, selected_item_id)


func get_fertilizer_profile(item_id: String) -> Dictionary:
	return fertilizer_registry.get_profile(item_id)


func _try_apply_fertilizer(
	p_world: Node,
	p_inventory: Node,
	crop_position: Vector3i,
	block_id: String
) -> Dictionary:
	if p_world == null or p_inventory == null:
		return {"handled": false}
	var selected_item_id: String = _selected_item_id(p_inventory)
	var profile: Dictionary = fertilizer_registry.get_profile(selected_item_id)
	if profile.is_empty():
		return {"handled": false}
	var crop_definition: Dictionary = crop_registry.get_crop_by_stage_block(block_id)
	if crop_definition.is_empty():
		return {"handled": false}
	var crop_id := str(crop_definition.get("id", ""))
	var current_stage := crop_registry.get_stage_index(crop_id, block_id)
	var evaluation: Dictionary = fertilizer_policy.evaluate(
		profile, crop_definition, current_stage
	)
	if not bool(evaluation.get("success", false)):
		return _reject(
			str(evaluation.get("reason", "fertilizer_rejected")),
			crop_position,
			block_id,
			str(evaluation.get("message", "无法施用肥料"))
		)
	var key: String = _position_key(crop_position)
	var state: Dictionary = _crops.get(key, {})
	if state.is_empty() or str(state.get("crop_id", "")) != crop_id:
		return _reject(
			"crop_state_missing", crop_position, block_id, "作物没有可恢复的生长状态"
		)
	var selected_slot := int(p_inventory.get("selected_slot"))
	var removed: Dictionary = p_inventory.call("remove_from_slot", selected_slot, 1)
	if removed.is_empty() or str(removed.get("item_id", "")) != selected_item_id:
		return _reject(
			"fertilizer_remove_failed", crop_position, block_id, "肥料消耗失败"
		)
	var target_stage := int(evaluation.get("target_stage", current_stage))
	if not _commit_fertilizer_stage(
		p_world, crop_position, crop_id, current_stage, target_stage, state
	):
		var remaining := int(
			p_inventory.call(
				"add_item",
				selected_item_id,
				1,
				removed.get("metadata", {})
			)
		)
		if remaining > 0:
			push_error("Fertilizer rollback could not restore %s" % selected_item_id)
		return _reject(
			"fertilizer_commit_failed",
			crop_position,
			block_id,
			"作物状态更新失败，肥料已退回"
		)
	crop_fertilized.emit(
		crop_position,
		crop_id,
		selected_item_id,
		current_stage,
		target_stage
	)
	return {
		"handled": true,
		"success": true,
		"action": &"fertilize_crop",
		"position": crop_position,
		"crop_id": crop_id,
		"fertilizer_item_id": selected_item_id,
		"from_stage": current_stage,
		"to_stage": target_stage,
		"message": "已对%s施用%s，生长推进至下一阶段" % [
			str(crop_definition.get("name", "作物")),
			str(profile.get("name", "肥料")),
		],
		"severity": "success",
	}


func _commit_fertilizer_stage(
	p_world: Node,
	crop_position: Vector3i,
	crop_id: String,
	current_stage: int,
	target_stage: int,
	state: Dictionary
) -> bool:
	if target_stage <= current_stage:
		return false
	var target_block: String = crop_registry.get_stage_block(crop_id, target_stage)
	if target_block.is_empty() or not bool(
		p_world.call("set_block", crop_position, target_block)
	):
		return false
	var next_state: Dictionary = state.duplicate(true)
	next_state["stage"] = target_stage
	next_state["elapsed_seconds"] = 0.0
	_crops[_position_key(crop_position)] = next_state
	for stage_index in range(current_stage + 1, target_stage + 1):
		crop_stage_changed.emit(crop_position, crop_id, stage_index)
	return true
