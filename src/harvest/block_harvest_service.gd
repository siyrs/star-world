class_name BlockHarvestService
extends Node

signal harvest_progress_changed(snapshot: Dictionary)
signal harvest_cancelled(reason: String)
signal harvest_completed(result: Dictionary)
signal harvest_rejected(reason: String, snapshot: Dictionary)

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const RegistryScript = preload("res://src/harvest/block_harvest_registry.gd")
const PolicyScript = preload("res://src/harvest/block_harvest_policy.gd")

const MAX_STEP_SECONDS := 0.25
const MAX_IMMEDIATE_STEPS := 64
const COMPLETION_EPSILON := 0.0001

var tool_service: Node
var interaction_service: Node
var registry = RegistryScript.new()
var policy = PolicyScript.new()
var _active: Dictionary = {}
var _last_rejection_key := ""


func setup(p_tool_service: Node, p_interaction_service: Node = null) -> void:
	tool_service = p_tool_service
	interaction_service = p_interaction_service


func clear() -> void:
	cancel("cleared")
	_last_rejection_key = ""


func get_preview(block_id: String, inventory: Node) -> Dictionary:
	var block_profile: Dictionary = registry.get_profile(block_id)
	if block_profile.is_empty():
		return {"breakable": false, "reason": "unknown_block"}
	var tool_profile: Dictionary = _selected_tool_context(inventory)
	var evaluation: Dictionary = policy.evaluate(block_profile, tool_profile)
	var preview := block_profile.duplicate(true)
	preview.merge(evaluation, true)
	preview["tool"] = tool_profile.duplicate(true)
	preview["tool_item_id"] = str(tool_profile.get("item_id", ""))
	preview["tool_display_name"] = str(tool_profile.get("display_name", "空手"))
	preview["recommended_tool_label"] = PolicyScript.tool_type_label(
		str(evaluation.get("required_tool", evaluation.get("preferred_tool", "")))
	)
	preview["minimum_power_label"] = PolicyScript.power_label(
		int(evaluation.get("minimum_power", 0))
	)
	return preview


func advance(
	world: Node,
	inventory: Node,
	block_position: Vector3i,
	block_id: String,
	delta: float
) -> Dictionary:
	if world == null or inventory == null:
		return _reject_once("service_missing", block_position, block_id, {})
	var preview := get_preview(block_id, inventory)
	var target_key := _target_key(block_position, block_id, preview)
	if not bool(preview.get("breakable", false)):
		return _reject_once("unbreakable", block_position, block_id, preview, target_key)
	if _active.is_empty() or str(_active.get("target_key", "")) != target_key:
		_reset_active(false)
		if not _interaction_allows_break(world, block_position, block_id):
			return _reject_once("protected", block_position, block_id, preview, target_key)
		_active = preview.duplicate(true)
		_active["target_key"] = target_key
		_active["position"] = [block_position.x, block_position.y, block_position.z]
		_active["elapsed_seconds"] = 0.0
		_active["ratio"] = 0.0
		_active["status"] = "progress"
		_last_rejection_key = ""
	var elapsed := float(_active.get("elapsed_seconds", 0.0))
	elapsed += clampf(maxf(0.0, delta), 0.0, MAX_STEP_SECONDS)
	var duration := maxf(
		PolicyScript.MIN_BREAK_SECONDS,
		float(_active.get("duration_seconds", PolicyScript.MIN_BREAK_SECONDS))
	)
	_active["elapsed_seconds"] = elapsed
	_active["ratio"] = clampf(elapsed / duration, 0.0, 1.0)
	_active["status"] = "progress"
	harvest_progress_changed.emit(_active.duplicate(true))
	if elapsed + COMPLETION_EPSILON < duration:
		return _active.duplicate(true)
	return _commit(world, inventory, block_position, block_id)


func harvest_immediately(
	world: Node, inventory: Node, block_position: Vector3i, block_id: String
) -> Dictionary:
	_reset_active(false)
	var preview := get_preview(block_id, inventory)
	var remaining := maxf(
		PolicyScript.MIN_BREAK_SECONDS,
		float(preview.get("duration_seconds", PolicyScript.MIN_BREAK_SECONDS))
	) + COMPLETION_EPSILON
	var result: Dictionary = {}
	var steps := 0
	while remaining > 0.0 and steps < MAX_IMMEDIATE_STEPS:
		steps += 1
		var step := minf(MAX_STEP_SECONDS, remaining)
		result = advance(world, inventory, block_position, block_id, step)
		var status := str(result.get("status", ""))
		if status in ["completed", "rejected"]:
			return result
		remaining = maxf(0.0, remaining - step)
	if str(result.get("status", "")) == "progress":
		return _reject_once("simulation_limit", block_position, block_id, result)
	return result


func cancel(reason: String = "cancelled") -> void:
	if _active.is_empty():
		return
	_active.clear()
	harvest_progress_changed.emit({})
	harvest_cancelled.emit(reason)


func get_active_snapshot() -> Dictionary:
	return _active.duplicate(true)


func _commit(
	world: Node, inventory: Node, block_position: Vector3i, block_id: String
) -> Dictionary:
	if not world.has_method("get_block") or str(world.call("get_block", block_position)) != block_id:
		return _reject_once("target_changed", block_position, block_id, _active)
	if not _interaction_allows_break(world, block_position, block_id):
		return _reject_once("protected", block_position, block_id, _active)
	if bool(_active.get("can_drop", false)) and not _can_store_drop(inventory, _active):
		return _reject_once("inventory_full", block_position, block_id, _active)
	if not world.has_method("remove_block"):
		return _reject_once("world_missing_contract", block_position, block_id, _active)
	var removed_block := str(world.call("remove_block", block_position))
	if removed_block == BlockRegistryScript.AIR:
		return _reject_once("remove_failed", block_position, block_id, _active)
	if interaction_service != null and interaction_service.has_method("on_block_removed"):
		interaction_service.call("on_block_removed", world, block_position, removed_block)
	var drop_granted := false
	var drop_item := str(_active.get("drop_item", ""))
	var drop_count := maxi(0, int(_active.get("drop_count", 0)))
	if bool(_active.get("can_drop", false)) and not drop_item.is_empty() and drop_count > 0:
		var remaining := int(inventory.call("add_item", drop_item, drop_count))
		drop_granted = remaining == 0
	var durability_result: Dictionary = {}
	var durability_cost := maxi(0, int(_active.get("durability_cost", 0)))
	if durability_cost > 0 and tool_service != null:
		durability_result = tool_service.call(
			"consume_selected_durability", inventory, durability_cost, "harvest"
		)
	var result := _active.duplicate(true)
	result["status"] = "completed"
	result["block_id"] = removed_block
	result["position"] = [block_position.x, block_position.y, block_position.z]
	result["drop_granted"] = drop_granted
	result["drop_item"] = drop_item if drop_granted else ""
	result["drop_count"] = drop_count if drop_granted else 0
	result["durability"] = durability_result.duplicate(true)
	_active.clear()
	_last_rejection_key = ""
	harvest_progress_changed.emit({})
	harvest_completed.emit(result.duplicate(true))
	return result


func _interaction_allows_break(world: Node, block_position: Vector3i, block_id: String) -> bool:
	if interaction_service == null or not interaction_service.has_method("can_break_block"):
		return true
	return bool(
		interaction_service.call("can_break_block", world, block_position, block_id)
	)


func _can_store_drop(inventory: Node, preview: Dictionary) -> bool:
	var drop_item := str(preview.get("drop_item", ""))
	var drop_count := maxi(0, int(preview.get("drop_count", 0)))
	if drop_item.is_empty() or drop_count <= 0:
		return true
	if inventory.has_method("can_add_item"):
		return bool(inventory.call("can_add_item", drop_item, drop_count, {}))
	return true


func _selected_tool_context(inventory: Node) -> Dictionary:
	if tool_service != null and tool_service.has_method("get_selected_context"):
		return tool_service.call("get_selected_context", inventory)
	return {
		"item_id": "",
		"display_name": "空手",
		"tool_type": "hand",
		"power": 0,
		"mining_speed": 1.0,
		"is_durable": false,
	}


func _target_key(block_position: Vector3i, block_id: String, preview: Dictionary) -> String:
	return "%s@%d,%d,%d|%s" % [
		block_id,
		block_position.x,
		block_position.y,
		block_position.z,
		str(preview.get("tool_item_id", "hand")),
	]


func _reject_once(
	reason: String,
	block_position: Vector3i,
	block_id: String,
	preview: Dictionary,
	target_key: String = ""
) -> Dictionary:
	var snapshot := preview.duplicate(true)
	snapshot["status"] = "rejected"
	snapshot["reason"] = reason
	snapshot["block_id"] = block_id
	snapshot["position"] = [block_position.x, block_position.y, block_position.z]
	var rejection_key := target_key if not target_key.is_empty() else "%s:%s" % [reason, block_id]
	_reset_active(false)
	if _last_rejection_key != rejection_key:
		_last_rejection_key = rejection_key
		harvest_progress_changed.emit({})
		harvest_rejected.emit(reason, snapshot.duplicate(true))
	return snapshot


func _reset_active(emit_cancelled: bool) -> void:
	if _active.is_empty():
		return
	_active.clear()
	harvest_progress_changed.emit({})
	if emit_cancelled:
		harvest_cancelled.emit("reset")
