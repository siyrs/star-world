class_name SoilMoistureService
extends RefCounted

signal soil_hydration_changed(position: Vector3i, hydrated: bool, source: String)
signal soil_watered(position: Vector3i, duration_seconds: float)

const PolicyScript = preload("res://src/agriculture/soil_moisture_policy.gd")
const SERIAL_VERSION := 1
const INVALID_POSITION := Vector3i(2147483647, 2147483647, 2147483647)
const WATER_BUCKET_ITEM := "water_bucket"
const EMPTY_BUCKET_ITEM := "bucket"

var policy = PolicyScript.new()
var world: Node

var _soils: Dictionary = {}
var _refresh_keys: Array[String] = []
var _refresh_cursor: int = 0
var _refresh_accumulator: float = 0.0


func attach_world(p_world: Node) -> void:
	world = p_world
	_refresh_accumulator = policy.refresh_interval_seconds
	_rebuild_refresh_keys()
	refresh_all()


func detach_world() -> void:
	world = null
	_refresh_accumulator = 0.0
	_refresh_cursor = 0


func clear() -> void:
	detach_world()
	_soils.clear()
	_refresh_keys.clear()


func deserialize(data: Dictionary) -> bool:
	_soils.clear()
	_refresh_keys.clear()
	_refresh_cursor = 0
	var raw_soils_value: Variant = data.get("soils", {})
	if raw_soils_value is Dictionary:
		var raw_soils: Dictionary = raw_soils_value
		for raw_key in raw_soils:
			var raw_state_value: Variant = raw_soils[raw_key]
			if raw_state_value is not Dictionary:
				continue
			var raw_state: Dictionary = raw_state_value
			var position: Vector3i = _position_from_value(raw_state.get("position", []))
			if position == INVALID_POSITION:
				continue
			var key: String = _position_key(position)
			_soils[key] = {
				"position": [position.x, position.y, position.z],
				"manual_remaining_seconds": maxf(
					0.0, float(raw_state.get("manual_remaining_seconds", 0.0))
				),
				"nearby_water": false,
				"hydrated": bool(raw_state.get("hydrated", false)),
			}
	_rebuild_refresh_keys()
	return true


func serialize() -> Dictionary:
	var serialized_soils: Dictionary = {}
	for raw_key in _soils:
		var key: String = str(raw_key)
		var state: Dictionary = _soils[key]
		serialized_soils[key] = {
			"position": state.get("position", []).duplicate(),
			"manual_remaining_seconds": maxf(
				0.0, float(state.get("manual_remaining_seconds", 0.0))
			),
			"hydrated": bool(state.get("hydrated", false)),
		}
	return {
		"version": SERIAL_VERSION,
		"policy_version": policy.schema_version,
		"soils": serialized_soils,
	}


func register_soil(position: Vector3i, refresh_immediately: bool = true) -> Dictionary:
	var key: String = _position_key(position)
	if not _soils.has(key):
		_soils[key] = {
			"position": [position.x, position.y, position.z],
			"manual_remaining_seconds": 0.0,
			"nearby_water": false,
			"hydrated": false,
		}
		_rebuild_refresh_keys()
	if refresh_immediately and world != null:
		_refresh_soil(key, "environment")
	return get_state(position)


func remove_soil(position: Vector3i) -> bool:
	var removed: bool = _soils.erase(_position_key(position))
	if removed:
		_rebuild_refresh_keys()
	return removed


func get_soil_count() -> int:
	return _soils.size()


func get_state(position: Vector3i) -> Dictionary:
	return _soils.get(_position_key(position), {}).duplicate(true)


func is_farmland_block(block_id: String) -> bool:
	return policy.is_farmland_block(block_id)


func try_interact(
	p_world: Node,
	p_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if not policy.is_farmland_block(block_id) or _selected_item_id(p_inventory) != WATER_BUCKET_ITEM:
		return {"handled": false}
	world = p_world
	var state: Dictionary = register_soil(block_position, true)
	if bool(state.get("nearby_water", false)):
		return {
			"handled": true,
			"success": true,
			"action": &"inspect_irrigation",
			"position": block_position,
			"message": "附近水源正在持续灌溉，无需消耗水桶",
			"severity": "info",
		}
	if float(state.get("manual_remaining_seconds", 0.0)) >= policy.manual_hydration_seconds - 0.1:
		return {
			"handled": true,
			"success": true,
			"action": &"inspect_irrigation",
			"position": block_position,
			"message": "耕地已经充分湿润",
			"severity": "info",
		}
	return _water_soil(p_world, p_inventory, block_position, block_id)


func get_interaction_hint(block_id: String, selected_item_id: String = "") -> String:
	if policy.is_farmland_block(block_id) and selected_item_id == WATER_BUCKET_ITEM:
		return "右键浇灌耕地"
	return ""


func consume_growth_seconds(position: Vector3i, elapsed_seconds: float) -> float:
	if elapsed_seconds <= 0.0:
		return 0.0
	var key: String = _position_key(position)
	if not _soils.has(key):
		register_soil(position, true)
	if not _soils.has(key):
		return elapsed_seconds * policy.dry_growth_multiplier
	var state: Dictionary = _soils[key]
	var nearby_water: bool = bool(state.get("nearby_water", false))
	var manual_remaining: float = maxf(
		0.0, float(state.get("manual_remaining_seconds", 0.0))
	)
	var effective_seconds: float = 0.0
	if nearby_water:
		effective_seconds = elapsed_seconds * policy.wet_growth_multiplier
	else:
		var wet_seconds: float = minf(elapsed_seconds, manual_remaining)
		var dry_seconds: float = maxf(0.0, elapsed_seconds - wet_seconds)
		effective_seconds = (
			wet_seconds * policy.wet_growth_multiplier
			+ dry_seconds * policy.dry_growth_multiplier
		)
		manual_remaining = maxf(0.0, manual_remaining - elapsed_seconds)
		state["manual_remaining_seconds"] = manual_remaining
	var hydrated: bool = nearby_water or manual_remaining > 0.0
	var previous_hydrated: bool = bool(state.get("hydrated", false))
	state["hydrated"] = hydrated
	_soils[key] = state
	if hydrated != previous_hydrated:
		_sync_visual(position, hydrated)
		soil_hydration_changed.emit(
			position,
			hydrated,
			"nearby_water" if nearby_water else "manual_timer"
		)
	return effective_seconds


func advance_unoccupied_soils(elapsed_seconds: float, occupied_soil_keys: Dictionary) -> void:
	if elapsed_seconds <= 0.0:
		return
	for raw_key in _soils.keys().duplicate():
		var key: String = str(raw_key)
		if occupied_soil_keys.has(key):
			continue
		var state: Dictionary = _soils.get(key, {})
		if state.is_empty() or bool(state.get("nearby_water", false)):
			continue
		var remaining: float = maxf(
			0.0,
			float(state.get("manual_remaining_seconds", 0.0)) - elapsed_seconds
		)
		var previous_hydrated: bool = bool(state.get("hydrated", false))
		state["manual_remaining_seconds"] = remaining
		state["hydrated"] = remaining > 0.0
		_soils[key] = state
		if previous_hydrated and remaining <= 0.0:
			var position: Vector3i = _position_from_value(state.get("position", []))
			if position != INVALID_POSITION:
				_sync_visual(position, false)
				soil_hydration_changed.emit(position, false, "manual_timer")


func tick(delta: float) -> void:
	if world == null or delta <= 0.0 or _refresh_keys.is_empty():
		return
	_refresh_accumulator += delta
	if _refresh_accumulator < policy.refresh_interval_seconds:
		return
	_refresh_accumulator = fmod(_refresh_accumulator, policy.refresh_interval_seconds)
	refresh_budgeted(policy.max_refresh_per_tick)


func refresh_all() -> void:
	if world == null:
		return
	var keys: Array = _soils.keys().duplicate()
	for raw_key in keys:
		_refresh_soil(str(raw_key), "environment")


func refresh_budgeted(max_records: int) -> void:
	if world == null or _refresh_keys.is_empty():
		return
	var budget: int = mini(maxi(1, max_records), _refresh_keys.size())
	for _index in budget:
		if _refresh_keys.is_empty():
			return
		_refresh_cursor = posmod(_refresh_cursor, _refresh_keys.size())
		var key: String = _refresh_keys[_refresh_cursor]
		_refresh_cursor += 1
		_refresh_soil(key, "environment")


func on_block_removed(block_position: Vector3i, block_id: String) -> void:
	if policy.is_farmland_block(block_id):
		remove_soil(block_position)


func position_key(position: Vector3i) -> String:
	return _position_key(position)


func _water_soil(
	p_world: Node,
	p_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if p_inventory == null or not p_inventory.has_method("replace_slot_item"):
		return _reject("inventory_contract_missing", block_position, block_id, "背包暂不支持水桶转换")
	var selected_slot: int = int(p_inventory.get("selected_slot"))
	if not bool(
		p_inventory.call(
			"replace_slot_item",
			selected_slot,
			WATER_BUCKET_ITEM,
			EMPTY_BUCKET_ITEM,
			{}
		)
	):
		return _reject("bucket_replace_failed", block_position, block_id, "水桶使用失败，物品未消耗")
	var key: String = _position_key(block_position)
	register_soil(block_position, false)
	var state: Dictionary = _soils[key]
	state["manual_remaining_seconds"] = policy.manual_hydration_seconds
	state["hydrated"] = true
	_soils[key] = state
	var current_block: String = str(p_world.call("get_block", block_position))
	if current_block != policy.wet_block and not bool(
		p_world.call("set_block", block_position, policy.wet_block)
	):
		p_inventory.call(
			"replace_slot_item",
			selected_slot,
			EMPTY_BUCKET_ITEM,
			WATER_BUCKET_ITEM,
			{}
		)
		state["manual_remaining_seconds"] = 0.0
		state["hydrated"] = false
		_soils[key] = state
		return _reject("world_update_failed", block_position, block_id, "浇灌失败，水桶已退回")
	soil_watered.emit(block_position, policy.manual_hydration_seconds)
	soil_hydration_changed.emit(block_position, true, "water_bucket")
	return {
		"handled": true,
		"success": true,
		"action": &"water_soil",
		"position": block_position,
		"duration_seconds": policy.manual_hydration_seconds,
		"message": "已浇灌耕地，可保持湿润 %.0f 秒" % policy.manual_hydration_seconds,
		"severity": "success",
	}


func _refresh_soil(key: String, source: String) -> void:
	if world == null or not _soils.has(key):
		return
	var state: Dictionary = _soils[key]
	var position: Vector3i = _position_from_value(state.get("position", []))
	if position == INVALID_POSITION:
		_soils.erase(key)
		_rebuild_refresh_keys()
		return
	var block_id: String = str(world.call("get_block", position))
	if not policy.is_farmland_block(block_id):
		_soils.erase(key)
		_rebuild_refresh_keys()
		return
	var nearby_water: bool = _has_nearby_water(position)
	var manual_remaining: float = maxf(
		0.0, float(state.get("manual_remaining_seconds", 0.0))
	)
	var hydrated: bool = nearby_water or manual_remaining > 0.0
	var previous_hydrated: bool = bool(state.get("hydrated", false))
	state["nearby_water"] = nearby_water
	state["hydrated"] = hydrated
	_soils[key] = state
	_sync_visual(position, hydrated)
	if hydrated != previous_hydrated:
		soil_hydration_changed.emit(position, hydrated, source)


func _has_nearby_water(position: Vector3i) -> bool:
	if world == null:
		return false
	for y_offset in range(-policy.vertical_radius, policy.vertical_radius + 1):
		for x_offset in range(-policy.horizontal_radius, policy.horizontal_radius + 1):
			for z_offset in range(-policy.horizontal_radius, policy.horizontal_radius + 1):
				if x_offset == 0 and y_offset == 0 and z_offset == 0:
					continue
				var candidate := position + Vector3i(x_offset, y_offset, z_offset)
				if policy.is_water_block(str(world.call("get_block", candidate))):
					return true
	return false


func _sync_visual(position: Vector3i, hydrated: bool) -> void:
	if world == null:
		return
	var current_block: String = str(world.call("get_block", position))
	if not policy.is_farmland_block(current_block):
		return
	var desired_block: String = policy.block_for_hydration(hydrated)
	if current_block != desired_block:
		world.call("set_block", position, desired_block)


func _selected_item_id(p_inventory: Node) -> String:
	if p_inventory == null or not p_inventory.has_method("get_selected_item"):
		return ""
	var selected: Dictionary = p_inventory.call("get_selected_item")
	return str(selected.get("item_id", ""))


func _reject(
	reason: String,
	position: Vector3i,
	block_id: String,
	message: String
) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"action": &"irrigation",
		"reason": reason,
		"position": position,
		"block_id": block_id,
		"message": message,
		"severity": "warning",
	}


func _rebuild_refresh_keys() -> void:
	_refresh_keys.clear()
	for raw_key in _soils:
		_refresh_keys.append(str(raw_key))
	_refresh_keys.sort()
	_refresh_cursor = 0 if _refresh_keys.is_empty() else mini(_refresh_cursor, _refresh_keys.size() - 1)


func _position_key(position: Vector3i) -> String:
	return "soil@%d,%d,%d" % [position.x, position.y, position.z]


func _position_from_value(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return INVALID_POSITION
