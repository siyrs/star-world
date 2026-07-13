class_name AgricultureService
extends Node

signal soil_tilled(position: Vector3i, previous_block: String)
signal crop_planted(position: Vector3i, crop_id: String)
signal crop_stage_changed(position: Vector3i, crop_id: String, stage: int)
signal crop_harvested(position: Vector3i, crop_id: String, outputs: Array)
signal agriculture_rejected(reason: String, context: Dictionary)

const CropRegistryScript = preload("res://src/agriculture/crop_registry.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const SERIAL_VERSION := 1
const PROCESS_INTERVAL_SECONDS := 0.5
const MAX_OFFLINE_SECONDS := 6.0 * 60.0 * 60.0

var item_registry
var tool_service: Node
var crop_registry = CropRegistryScript.new()
var world: Node
var inventory: Node

var _crops: Dictionary = {}
var _process_accumulator := 0.0
var _offline_seconds := 0.0


func _ready() -> void:
	set_process(true)


func setup(p_item_registry, p_tool_service: Node) -> void:
	item_registry = p_item_registry
	tool_service = p_tool_service


func attach_world(p_world: Node, p_inventory: Node) -> void:
	world = p_world
	inventory = p_inventory
	_sync_world_from_state()
	if _offline_seconds > 0.0:
		advance_time(_offline_seconds)
		_offline_seconds = 0.0


func detach_world() -> void:
	world = null
	inventory = null
	_process_accumulator = 0.0


func clear() -> void:
	detach_world()
	_crops.clear()
	_offline_seconds = 0.0


func deserialize(data: Dictionary) -> bool:
	_crops.clear()
	_process_accumulator = 0.0
	var raw_crops = data.get("crops", {})
	if raw_crops is Dictionary:
		for raw_key in raw_crops:
			var raw_state = raw_crops[raw_key]
			if raw_state is not Dictionary:
				continue
			var crop_id := str(raw_state.get("crop_id", ""))
			var crop_definition: Dictionary = crop_registry.get_crop(crop_id)
			var position := _position_from_value(raw_state.get("position", []))
			if crop_definition.is_empty() or position == null:
				continue
			var stage_blocks: Array = crop_definition.get("stage_blocks", [])
			var stage := clampi(int(raw_state.get("stage", 0)), 0, stage_blocks.size() - 1)
			var key := _position_key(position)
			_crops[key] = {
				"crop_id": crop_id,
				"position": [position.x, position.y, position.z],
				"stage": stage,
				"elapsed_seconds": maxf(0.0, float(raw_state.get("elapsed_seconds", 0.0))),
			}
	var saved_at := int(data.get("saved_at_unix", Time.get_unix_time_from_system()))
	var now := int(Time.get_unix_time_from_system())
	_offline_seconds = clampf(float(now - saved_at), 0.0, MAX_OFFLINE_SECONDS)
	return true


func serialize() -> Dictionary:
	var saved_crops: Dictionary = {}
	for key in _crops:
		var state: Dictionary = _crops[key]
		saved_crops[str(key)] = state.duplicate(true)
	return {
		"version": SERIAL_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"crops": saved_crops,
	}


func get_crop_count() -> int:
	return _crops.size()


func get_crop_state(position: Vector3i) -> Dictionary:
	return _crops.get(_position_key(position), {}).duplicate(true)


func get_snapshot() -> Dictionary:
	return serialize()


func try_interact(
	p_world: Node,
	p_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if p_world == null or p_inventory == null:
		return {"handled": false}
	var selected_item_id := _selected_item_id(p_inventory)
	var tool_type := _tool_type(selected_item_id)
	if block_id in ["grass", "dirt"] and tool_type == "hoe":
		return _till_soil(p_world, p_inventory, block_position, block_id)
	if block_id == "farmland":
		var crop_definition: Dictionary = crop_registry.get_crop_by_seed(selected_item_id)
		if not crop_definition.is_empty():
			return _plant_crop(p_world, p_inventory, block_position, crop_definition)
		return {"handled": false}
	var focused_crop: Dictionary = crop_registry.get_crop_by_stage_block(block_id)
	if not focused_crop.is_empty():
		return _harvest_crop(p_world, p_inventory, block_position, focused_crop, block_id)
	return {"handled": false}


func get_interaction_hint(block_id: String, selected_item_id: String = "") -> String:
	if block_id in ["grass", "dirt"] and _tool_type(selected_item_id) == "hoe":
		return "右键开垦耕地"
	if block_id == "farmland":
		var crop_definition: Dictionary = crop_registry.get_crop_by_seed(selected_item_id)
		if not crop_definition.is_empty():
			return "右键播种%s" % str(crop_definition.get("name", "作物"))
	var crop_definition: Dictionary = crop_registry.get_crop_by_stage_block(block_id)
	if crop_definition.is_empty():
		return ""
	var crop_id := str(crop_definition.get("id", ""))
	var stage_blocks: Array = crop_definition.get("stage_blocks", [])
	var stage := crop_registry.get_stage_index(crop_id, block_id)
	if stage >= stage_blocks.size() - 1:
		return "右键收获并补种%s" % str(crop_definition.get("name", "作物"))
	var progress := roundi(100.0 * float(stage + 1) / float(stage_blocks.size()))
	return "右键查看%s生长 %d%%" % [str(crop_definition.get("name", "作物")), progress]


func on_block_removed(p_world: Node, block_position: Vector3i, block_id: String) -> void:
	if crop_registry.is_crop_block(block_id):
		_crops.erase(_position_key(block_position))
		return
	if block_id != "farmland":
		return
	var crop_position := block_position + Vector3i.UP
	if _crops.erase(_position_key(crop_position)) and p_world != null:
		if str(p_world.call("get_block", crop_position)) != BlockRegistryScript.AIR:
			p_world.call("set_block", crop_position, BlockRegistryScript.AIR)


func advance_time(seconds: float) -> void:
	if world == null or seconds <= 0.0:
		return
	var keys: Array = _crops.keys().duplicate()
	for key_value in keys:
		_advance_crop(str(key_value), seconds)


func _process(delta: float) -> void:
	if world == null or delta <= 0.0:
		return
	_process_accumulator += delta
	if _process_accumulator < PROCESS_INTERVAL_SECONDS:
		return
	var elapsed := _process_accumulator
	_process_accumulator = 0.0
	advance_time(elapsed)


func _till_soil(
	p_world: Node,
	p_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	var above := block_position + Vector3i.UP
	if str(p_world.call("get_block", above)) != BlockRegistryScript.AIR:
		return _reject("space_blocked", block_position, block_id, "上方空间被占用，无法开垦")
	if not bool(p_world.call("set_block", block_position, "farmland")):
		return _reject("world_update_failed", block_position, block_id, "耕地状态更新失败")
	var durability: Dictionary = {}
	if tool_service != null and tool_service.has_method("consume_selected_durability"):
		durability = tool_service.call(
			"consume_selected_durability", p_inventory, 1, "till_soil"
		)
	soil_tilled.emit(block_position, block_id)
	return {
		"handled": true,
		"success": true,
		"action": &"till_soil",
		"position": block_position,
		"previous_block": block_id,
		"durability": durability,
		"message": "已开垦耕地",
		"severity": "success",
	}


func _plant_crop(
	p_world: Node,
	p_inventory: Node,
	farmland_position: Vector3i,
	crop_definition: Dictionary
) -> Dictionary:
	var crop_position := farmland_position + Vector3i.UP
	if str(p_world.call("get_block", crop_position)) != BlockRegistryScript.AIR:
		return _reject("space_blocked", farmland_position, "farmland", "耕地上方已有方块")
	var seed_item := str(crop_definition.get("seed_item", ""))
	if _selected_item_id(p_inventory) != seed_item:
		return {"handled": false}
	var selected_slot := int(p_inventory.get("selected_slot"))
	var removed: Dictionary = p_inventory.call("remove_from_slot", selected_slot, 1)
	if removed.is_empty():
		return _reject("seed_remove_failed", farmland_position, "farmland", "种子消耗失败")
	var crop_id := str(crop_definition.get("id", ""))
	var stage_block := crop_registry.get_stage_block(crop_id, 0)
	if stage_block.is_empty() or not bool(p_world.call("set_block", crop_position, stage_block)):
		p_inventory.call(
			"add_item",
			seed_item,
			1,
			removed.get("metadata", {})
		)
		return _reject("world_update_failed", farmland_position, "farmland", "播种失败，种子已退回")
	var key := _position_key(crop_position)
	_crops[key] = {
		"crop_id": crop_id,
		"position": [crop_position.x, crop_position.y, crop_position.z],
		"stage": 0,
		"elapsed_seconds": 0.0,
	}
	crop_planted.emit(crop_position, crop_id)
	return {
		"handled": true,
		"success": true,
		"action": &"plant_crop",
		"position": crop_position,
		"crop_id": crop_id,
		"message": "已播种%s" % str(crop_definition.get("name", "作物")),
		"severity": "success",
	}


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
		return _reject("crop_state_invalid", crop_position, block_id, "作物状态无效")
	if stage < stage_blocks.size() - 1:
		var progress := roundi(100.0 * float(stage + 1) / float(stage_blocks.size()))
		return _reject(
			"crop_growing",
			crop_position,
			block_id,
			"%s仍在生长（%d%%）" % [str(crop_definition.get("name", "作物")), progress]
		)
	var harvest: Dictionary = crop_definition.get("harvest", {})
	var outputs: Array = [
		{
			"item_id": str(crop_definition.get("produce_item", "")),
			"count": maxi(1, int(harvest.get("produce_count", 1))),
		},
		{
			"item_id": str(crop_definition.get("seed_item", "")),
			"count": maxi(1, int(harvest.get("seed_count", 1))),
		},
	]
	if not _can_store_outputs(p_inventory, outputs):
		return _reject("inventory_full", crop_position, block_id, "背包空间不足，作物保持成熟状态")
	var first_stage := crop_registry.get_stage_block(crop_id, 0)
	if first_stage.is_empty() or not bool(p_world.call("set_block", crop_position, first_stage)):
		return _reject("world_update_failed", crop_position, block_id, "作物重置失败")
	var granted: Array = []
	for output_value in outputs:
		var output: Dictionary = output_value
		var item_id := str(output.get("item_id", ""))
		var count := maxi(0, int(output.get("count", 0)))
		if item_id.is_empty() or count <= 0:
			continue
		var remaining := int(p_inventory.call("add_item", item_id, count))
		var accepted := count - remaining
		if accepted > 0:
			granted.append({"item_id": item_id, "count": accepted})
		if remaining > 0:
			for granted_value in granted:
				var granted_output: Dictionary = granted_value
				p_inventory.call(
					"remove_item",
					str(granted_output.get("item_id", "")),
					int(granted_output.get("count", 0))
				)
			p_world.call("set_block", crop_position, block_id)
			return _reject("inventory_race", crop_position, block_id, "背包状态变化，收获已回滚")
	var key := _position_key(crop_position)
	_crops[key] = {
		"crop_id": crop_id,
		"position": [crop_position.x, crop_position.y, crop_position.z],
		"stage": 0,
		"elapsed_seconds": 0.0,
	}
	crop_harvested.emit(crop_position, crop_id, granted.duplicate(true))
	return {
		"handled": true,
		"success": true,
		"action": &"harvest_crop",
		"position": crop_position,
		"crop_id": crop_id,
		"outputs": granted,
		"message": "收获%s，并自动补种" % str(crop_definition.get("name", "作物")),
		"severity": "success",
	}


func _advance_crop(key: String, seconds: float) -> void:
	if not _crops.has(key):
		return
	var state: Dictionary = _crops[key]
	var position = _position_from_value(state.get("position", []))
	if position == null:
		_crops.erase(key)
		return
	var crop_id := str(state.get("crop_id", ""))
	var crop_definition: Dictionary = crop_registry.get_crop(crop_id)
	if crop_definition.is_empty():
		_crops.erase(key)
		return
	if str(world.call("get_block", position + Vector3i.DOWN)) != "farmland":
		_crops.erase(key)
		return
	var current_block := str(world.call("get_block", position))
	var current_stage := crop_registry.get_stage_index(crop_id, current_block)
	if current_stage < 0:
		_crops.erase(key)
		return
	var stage_blocks: Array = crop_definition.get("stage_blocks", [])
	var stage := clampi(maxi(current_stage, int(state.get("stage", 0))), 0, stage_blocks.size() - 1)
	var elapsed := maxf(0.0, float(state.get("elapsed_seconds", 0.0))) + seconds
	while stage < stage_blocks.size() - 1:
		var duration := crop_registry.get_stage_duration(crop_id, stage)
		if duration <= 0.0 or elapsed < duration:
			break
		elapsed -= duration
		stage += 1
		var next_block := crop_registry.get_stage_block(crop_id, stage)
		if str(world.call("get_block", position)) != next_block:
			world.call("set_block", position, next_block)
		crop_stage_changed.emit(position, crop_id, stage)
	state["stage"] = stage
	state["elapsed_seconds"] = elapsed if stage < stage_blocks.size() - 1 else 0.0
	_crops[key] = state


func _sync_world_from_state() -> void:
	if world == null:
		return
	var keys: Array = _crops.keys().duplicate()
	for key_value in keys:
		var key := str(key_value)
		var state: Dictionary = _crops[key]
		var position = _position_from_value(state.get("position", []))
		var crop_id := str(state.get("crop_id", ""))
		var crop_definition: Dictionary = crop_registry.get_crop(crop_id)
		if position == null or crop_definition.is_empty():
			_crops.erase(key)
			continue
		if str(world.call("get_block", position + Vector3i.DOWN)) != "farmland":
			_crops.erase(key)
			continue
		var stage_blocks: Array = crop_definition.get("stage_blocks", [])
		var stage := clampi(int(state.get("stage", 0)), 0, stage_blocks.size() - 1)
		var stage_block := crop_registry.get_stage_block(crop_id, stage)
		if str(world.call("get_block", position)) != stage_block:
			world.call("set_block", position, stage_block)


func _can_store_outputs(p_inventory: Node, outputs: Array) -> bool:
	if p_inventory == null or not p_inventory.has_method("serialize"):
		return false
	var inventory_state: Dictionary = p_inventory.call("serialize")
	var raw_slots = inventory_state.get("slots", [])
	if raw_slots is not Array:
		return false
	var slots: Array = raw_slots.duplicate(true)
	var registry = p_inventory.get("registry")
	if registry == null or not registry.has_method("get_max_stack"):
		return false
	for output_value in outputs:
		if output_value is not Dictionary:
			continue
		var output: Dictionary = output_value
		var item_id := str(output.get("item_id", ""))
		var remaining := maxi(0, int(output.get("count", 0)))
		if item_id.is_empty() or remaining <= 0:
			continue
		var maximum := maxi(1, int(registry.call("get_max_stack", item_id)))
		for index in slots.size():
			if remaining <= 0:
				break
			var slot: Dictionary = slots[index] if slots[index] is Dictionary else {}
			if str(slot.get("item_id", "")) != item_id:
				continue
			var accepted := mini(remaining, maximum - int(slot.get("count", 0)))
			if accepted <= 0:
				continue
			slot["count"] = int(slot.get("count", 0)) + accepted
			slots[index] = slot
			remaining -= accepted
		for index in slots.size():
			if remaining <= 0:
				break
			var slot: Dictionary = slots[index] if slots[index] is Dictionary else {}
			if not slot.is_empty():
				continue
			var accepted := mini(remaining, maximum)
			slots[index] = {"item_id": item_id, "count": accepted}
			remaining -= accepted
		if remaining > 0:
			return false
	return true


func _selected_item_id(p_inventory: Node) -> String:
	if p_inventory == null or not p_inventory.has_method("get_selected_item"):
		return ""
	var selected: Dictionary = p_inventory.call("get_selected_item")
	return str(selected.get("item_id", ""))


func _tool_type(item_id: String) -> String:
	if item_registry == null or not item_registry.has_method("get_item"):
		return "hand"
	var definition: Dictionary = item_registry.call("get_item", item_id)
	return str(definition.get("tool_type", "hand"))


func _reject(
	reason: String,
	position: Vector3i,
	block_id: String,
	message: String
) -> Dictionary:
	var context := {
		"position": [position.x, position.y, position.z],
		"block_id": block_id,
		"message": message,
	}
	agriculture_rejected.emit(reason, context.duplicate(true))
	return {
		"handled": true,
		"success": false,
		"action": &"agriculture",
		"reason": reason,
		"position": position,
		"block_id": block_id,
		"message": message,
		"severity": "warning",
	}


func _position_key(position: Vector3i) -> String:
	return "crop@%d,%d,%d" % [position.x, position.y, position.z]


func _position_from_value(value: Variant) -> Variant:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return null
