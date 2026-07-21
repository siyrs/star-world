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
const StateMigrationScript = preload(
	"res://src/agriculture/agriculture_state_migration.gd"
)

var fertilizer_registry = FertilizerRegistryScript.new()
var fertilizer_policy = FertilizerPolicyScript.new()
var _runtime_active := true
var _shutdown := false
var _runtime_process_count := 0
var _runtime_elapsed_seconds := 0.0
var _atomic_harvest_count := 0
var _atomic_harvest_rejection_count := 0
var _last_atomic_harvest: Dictionary = {}


func _ready() -> void:
	super._ready()
	# GameplayServiceHub is PROCESS_MODE_ALWAYS. Agriculture must explicitly
	# override inheritance so pause/death freezes crops and moisture timers.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)


func setup(p_item_registry, p_tool_service: Node) -> void:
	super.setup(p_item_registry, p_tool_service)
	_shutdown = false
	_runtime_active = true
	set_process(true)


func is_ready() -> bool:
	return (
		item_registry != null
		and crop_registry.crop_count() > 0
		and fertilizer_registry.profile_count() > 0
	)


func activate() -> void:
	if _shutdown:
		return
	_runtime_active = true
	set_process(true)


func deactivate() -> void:
	_runtime_active = false
	set_process(false)


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	deactivate()
	clear()
	item_registry = null
	tool_service = null


func clear() -> void:
	super.clear()
	_runtime_process_count = 0
	_runtime_elapsed_seconds = 0.0
	_atomic_harvest_count = 0
	_atomic_harvest_rejection_count = 0
	_last_atomic_harvest.clear()


func deserialize(data: Dictionary) -> bool:
	return super.deserialize(StateMigrationScript.normalize_agriculture_state(data))


func get_runtime_snapshot() -> Dictionary:
	var mature_count := 0
	var crop_counts: Dictionary = {}
	for raw_key: Variant in _crops.keys():
		var state: Dictionary = _crops.get(raw_key, {})
		var crop_id := str(state.get("crop_id", ""))
		if crop_id.is_empty():
			continue
		crop_counts[crop_id] = int(crop_counts.get(crop_id, 0)) + 1
		var definition: Dictionary = crop_registry.get_crop(crop_id)
		var stages: Array = definition.get("stage_blocks", [])
		if not stages.is_empty() and int(state.get("stage", 0)) >= stages.size() - 1:
			mature_count += 1
	return {
		"active": _runtime_active,
		"shutdown": _shutdown,
		"world_attached": world != null and is_instance_valid(world),
		"process_mode": process_mode,
		"processing": is_processing(),
		"crop_count": _crops.size(),
		"mature_crop_count": mature_count,
		"crop_counts": crop_counts,
		"soil_count": soil_moisture.get_soil_count(),
		"runtime_process_count": _runtime_process_count,
		"runtime_elapsed_seconds": _runtime_elapsed_seconds,
		"atomic_harvest_count": _atomic_harvest_count,
		"atomic_harvest_rejection_count": _atomic_harvest_rejection_count,
		"last_atomic_harvest": _last_atomic_harvest.duplicate(true),
	}


func _process(delta: float) -> void:
	if _shutdown or not _runtime_active:
		return
	if world != null and delta > 0.0:
		_runtime_process_count += 1
		_runtime_elapsed_seconds += delta
	super._process(delta)


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


func _harvest_crop(
	p_world: Node,
	p_inventory: Node,
	crop_position: Vector3i,
	crop_definition: Dictionary,
	block_id: String
) -> Dictionary:
	var crop_id := str(crop_definition.get("id", ""))
	var stage_blocks: Array = crop_definition.get("stage_blocks", [])
	var stage := crop_registry.get_stage_index(crop_id, block_id)
	if stage < 0:
		return _reject_atomic_harvest(
			"crop_state_invalid", crop_position, block_id, "作物状态无效"
		)
	if stage < stage_blocks.size() - 1:
		var progress := roundi(
			100.0 * float(stage + 1) / float(maxi(1, stage_blocks.size()))
		)
		return _reject_atomic_harvest(
			"crop_growing",
			crop_position,
			block_id,
			"%s仍在生长（%d%%）" % [str(crop_definition.get("name", "作物")), progress]
		)
	if (
		p_inventory == null
		or not p_inventory.has_method("can_transact_items")
		or not p_inventory.has_method("transact_items")
	):
		return _reject_atomic_harvest(
			"inventory_contract", crop_position, block_id, "背包暂不支持原子收获"
		)
	var raw_outputs: Array[Dictionary] = crop_registry.get_harvest_outputs(crop_id)
	var additions: Array = []
	for output: Dictionary in raw_outputs:
		var item_id := str(output.get("item_id", ""))
		var count := maxi(0, int(output.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		additions.append({
			"item_id": item_id,
			"count": count,
			"metadata": output.get("metadata", {}).duplicate(true),
		})
	if additions.is_empty():
		return _reject_atomic_harvest(
			"harvest_outputs_missing", crop_position, block_id, "作物没有有效收获配置"
		)
	if not bool(p_inventory.call("can_transact_items", {}, additions)):
		return _reject_atomic_harvest(
			"inventory_full", crop_position, block_id, "背包空间不足，作物保持成熟状态"
		)
	var auto_replant := crop_registry.should_auto_replant(crop_id)
	var replacement_block := (
		crop_registry.get_stage_block(crop_id, 0)
		if auto_replant
		else BlockRegistryScript.AIR
	)
	if replacement_block.is_empty() or not bool(
		p_world.call("set_block", crop_position, replacement_block)
	):
		return _reject_atomic_harvest(
			"world_update_failed", crop_position, block_id, "作物收获状态更新失败"
		)
	var transaction: Dictionary = p_inventory.call("transact_items", {}, additions)
	if not bool(transaction.get("success", false)):
		var restored := bool(p_world.call("set_block", crop_position, block_id))
		if not restored and str(p_world.call("get_block", crop_position)) != block_id:
			push_error("Agriculture harvest rollback could not restore %s" % block_id)
		return _reject_atomic_harvest(
			"inventory_race", crop_position, block_id, "背包状态变化，收获已回滚"
		)
	var key := _position_key(crop_position)
	if auto_replant:
		_crops[key] = {
			"crop_id": crop_id,
			"position": [crop_position.x, crop_position.y, crop_position.z],
			"stage": 0,
			"elapsed_seconds": 0.0,
		}
	else:
		_crops.erase(key)
	_atomic_harvest_count += 1
	_last_atomic_harvest = {
		"crop_id": crop_id,
		"position": [crop_position.x, crop_position.y, crop_position.z],
		"outputs": additions.duplicate(true),
		"auto_replant": auto_replant,
		"transaction": transaction.duplicate(true),
	}
	crop_harvested.emit(crop_position, crop_id, additions.duplicate(true))
	return {
		"handled": true,
		"success": true,
		"action": &"harvest_crop",
		"position": crop_position,
		"crop_id": crop_id,
		"outputs": additions.duplicate(true),
		"transaction": transaction,
		"message": (
			"收获%s，并自动补种" if auto_replant else "收获%s"
		) % str(crop_definition.get("name", "作物")),
		"severity": "success",
	}


func _reject_atomic_harvest(
	reason: String,
	position: Vector3i,
	block_id: String,
	message: String
) -> Dictionary:
	_atomic_harvest_rejection_count += 1
	return _reject(reason, position, block_id, message)


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
