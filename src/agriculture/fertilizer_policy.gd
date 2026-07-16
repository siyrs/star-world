class_name FertilizerPolicy
extends RefCounted


func evaluate(
	profile: Dictionary,
	crop_definition: Dictionary,
	current_stage: int
) -> Dictionary:
	if profile.is_empty():
		return {"handled": false}
	if crop_definition.is_empty():
		return {
			"handled": true,
			"success": false,
			"reason": "crop_invalid",
			"message": "只能对正在生长的作物施肥",
		}
	var crop_id := str(crop_definition.get("id", ""))
	var allowed_crops: Array = profile.get("allowed_crops", [])
	if not allowed_crops.is_empty() and crop_id not in allowed_crops:
		return {
			"handled": true,
			"success": false,
			"reason": "fertilizer_incompatible",
			"message": "%s不适用于这种作物" % str(profile.get("name", "肥料")),
		}
	var stage_blocks: Array = crop_definition.get("stage_blocks", [])
	if stage_blocks.size() < 2 or current_stage < 0:
		return {
			"handled": true,
			"success": false,
			"reason": "crop_state_invalid",
			"message": "作物生长状态无效",
		}
	var maximum_stage := stage_blocks.size() - 1
	if current_stage >= maximum_stage:
		return {
			"handled": true,
			"success": false,
			"reason": "crop_mature",
			"message": "%s已经成熟，请先收获" % str(crop_definition.get("name", "作物")),
		}
	var requested_advances := clampi(int(profile.get("stage_advances", 1)), 1, 3)
	var target_stage := mini(maximum_stage, current_stage + requested_advances)
	return {
		"handled": true,
		"success": true,
		"crop_id": crop_id,
		"current_stage": current_stage,
		"target_stage": target_stage,
		"actual_advances": target_stage - current_stage,
		"fertilizer_id": str(profile.get("id", "")),
		"fertilizer_item_id": str(profile.get("item_id", "")),
		"fertilizer_name": str(profile.get("name", "肥料")),
	}
