class_name RestService
extends Node

signal spawn_point_changed(position: Vector3, bed_position: Vector3i)
signal spawn_point_cleared(reason: String)
signal slept(previous_time: float, previous_day: int, wake_time: float, wake_day: int)
signal rest_rejected(reason: String, context: Dictionary)

const RestPolicyScript = preload("res://src/rest/rest_policy.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const SERIAL_VERSION := 1
const INVALID_BLOCK_POSITION := Vector3i(2147483647, 2147483647, 2147483647)

var policy = RestPolicyScript.new()
var day_night: Node
var world: Node
var player: Node

var _has_custom_spawn: bool = false
var _bed_position: Vector3i = INVALID_BLOCK_POSITION
var _respawn_position: Vector3 = Vector3.ZERO


func setup(p_day_night: Node) -> void:
	day_night = p_day_night


func attach_world(p_world: Node, p_player: Node) -> void:
	world = p_world
	player = p_player
	if not _has_custom_spawn:
		return
	if not _saved_bed_exists():
		_clear_custom_spawn("bed_missing", true)
		return
	var resolved: Dictionary = _resolve_spawn(world, _bed_position)
	if not bool(resolved.get("ok", false)):
		_clear_custom_spawn("spawn_obstructed", true)
		return
	_respawn_position = resolved.get("position", Vector3.ZERO)
	if not _apply_spawn_to_player(_respawn_position):
		_clear_custom_spawn("player_contract_missing", true)


func detach_world() -> void:
	world = null
	player = null


func clear() -> void:
	detach_world()
	_has_custom_spawn = false
	_bed_position = INVALID_BLOCK_POSITION
	_respawn_position = Vector3.ZERO


func deserialize(data: Dictionary) -> bool:
	_has_custom_spawn = bool(data.get("has_custom_spawn", false))
	_bed_position = _position_from_value(data.get("bed_position", []))
	_respawn_position = _vector3_from_value(data.get("respawn_position", []))
	if (
		not _has_custom_spawn
		or _bed_position == INVALID_BLOCK_POSITION
		or not _vector3_is_finite(_respawn_position)
	):
		_has_custom_spawn = false
		_bed_position = INVALID_BLOCK_POSITION
		_respawn_position = Vector3.ZERO
	return true


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"has_custom_spawn": _has_custom_spawn,
		"bed_position": (
			[_bed_position.x, _bed_position.y, _bed_position.z]
			if _has_custom_spawn
			else []
		),
		"respawn_position": (
			[_respawn_position.x, _respawn_position.y, _respawn_position.z]
			if _has_custom_spawn
			else []
		),
	}


func get_snapshot() -> Dictionary:
	return serialize()


func has_custom_spawn() -> bool:
	return _has_custom_spawn


func get_respawn_position() -> Vector3:
	return _respawn_position


func get_bed_position() -> Vector3i:
	return _bed_position


func try_interact(
	p_world: Node,
	_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if not policy.is_bed_block(block_id):
		return {"handled": false}
	if p_world == null or player == null:
		return _reject("runtime_missing", block_position, block_id, "睡眠服务尚未连接到当前世界")
	world = p_world
	var resolved: Dictionary = _resolve_spawn(world, block_position)
	if not bool(resolved.get("ok", false)):
		return _reject(
			"spawn_obstructed",
			block_position,
			block_id,
			"床边没有足够的安全空间，无法设置重生点"
		)
	var next_spawn: Vector3 = resolved.get("position", Vector3.ZERO)
	if not _apply_spawn_to_player(next_spawn):
		return _reject(
			"player_contract_missing",
			block_position,
			block_id,
			"玩家重生点接口不可用"
		)
	_has_custom_spawn = true
	_bed_position = block_position
	_respawn_position = next_spawn
	spawn_point_changed.emit(_respawn_position, _bed_position)
	if _can_sleep_now():
		var previous_time := float(day_night.get("time_of_day"))
		var previous_day := int(day_night.get("day_count"))
		var skip_result: Dictionary = {}
		if day_night.has_method("skip_to_time"):
			skip_result = day_night.call("skip_to_time", policy.wake_hour)
		elif day_night.has_method("set_time"):
			day_night.call("set_time", policy.wake_hour)
			skip_result = {
				"time_of_day": policy.wake_hour,
				"day": int(day_night.get("day_count")),
			}
		var wake_time := float(skip_result.get("time_of_day", policy.wake_hour))
		var wake_day := int(skip_result.get("day", day_night.get("day_count")))
		slept.emit(previous_time, previous_day, wake_time, wake_day)
		return {
			"handled": true,
			"success": true,
			"action": &"sleep",
			"position": block_position,
			"spawn_position": _respawn_position,
			"previous_time": previous_time,
			"previous_day": previous_day,
			"wake_time": wake_time,
			"wake_day": wake_day,
			"message": "已睡到清晨，并设置重生点",
			"severity": "success",
		}
	return {
		"handled": true,
		"success": true,
		"action": &"set_spawn",
		"position": block_position,
		"spawn_position": _respawn_position,
		"message": "重生点已设置，夜晚可在这里睡到清晨",
		"severity": "success",
	}


func get_interaction_hint(block_id: String, _selected_item_id: String = "") -> String:
	if not policy.is_bed_block(block_id):
		return ""
	if _can_sleep_now():
		return "右键睡到清晨并设置重生点"
	return "右键设置重生点（夜晚可睡）"


func can_break_block(_world: Node, _block_position: Vector3i, _block_id: String) -> bool:
	return true


func on_block_removed(_world: Node, block_position: Vector3i, block_id: String) -> void:
	if (
		_has_custom_spawn
		and policy.is_bed_block(block_id)
		and block_position == _bed_position
	):
		_clear_custom_spawn("bed_removed", true)


func _can_sleep_now() -> bool:
	return (
		day_night != null
		and is_instance_valid(day_night)
		and policy.is_sleep_time(float(day_night.get("time_of_day")))
	)


func _saved_bed_exists() -> bool:
	return (
		world != null
		and world.has_method("get_block")
		and policy.is_bed_block(str(world.call("get_block", _bed_position)))
	)


func _resolve_spawn(p_world: Node, bed_position: Vector3i) -> Dictionary:
	if p_world == null or not p_world.has_method("get_block"):
		return {"ok": false}
	for offset: Vector3i in policy.get_spawn_offsets():
		var feet_block := bed_position + offset
		if not _spawn_cells_are_clear(p_world, feet_block):
			continue
		var support_block := str(p_world.call("get_block", feet_block + Vector3i.DOWN))
		if not BlockRegistryScript.is_solid(support_block):
			continue
		var position := Vector3(
			float(feet_block.x) + 0.5,
			float(feet_block.y) + 0.02,
			float(feet_block.z) + 0.5
		)
		return {
			"ok": true,
			"position": position,
			"feet_block": feet_block,
		}
	return {"ok": false}


func _spawn_cells_are_clear(p_world: Node, feet_block: Vector3i) -> bool:
	for vertical_offset in policy.required_clearance_blocks:
		var block_id := str(
			p_world.call("get_block", feet_block + Vector3i.UP * vertical_offset)
		)
		if block_id != BlockRegistryScript.AIR:
			return false
	return true


func _apply_spawn_to_player(position: Vector3) -> bool:
	if player == null or not is_instance_valid(player) or not _vector3_is_finite(position):
		return false
	if player.has_method("set_respawn_position"):
		return bool(player.call("set_respawn_position", position))
	for property: Dictionary in player.get_property_list():
		if str(property.get("name", "")) == "spawn_position":
			player.set("spawn_position", position)
			return true
	return false


func _reset_player_spawn() -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("reset_respawn_position"):
		player.call("reset_respawn_position")


func _clear_custom_spawn(reason: String, notify: bool) -> void:
	var had_custom_spawn := _has_custom_spawn
	_has_custom_spawn = false
	_bed_position = INVALID_BLOCK_POSITION
	_respawn_position = Vector3.ZERO
	_reset_player_spawn()
	if notify and had_custom_spawn:
		spawn_point_cleared.emit(reason)


func _reject(
	reason: String,
	block_position: Vector3i,
	block_id: String,
	message: String
) -> Dictionary:
	var context := {
		"position": [block_position.x, block_position.y, block_position.z],
		"block_id": block_id,
		"message": message,
	}
	rest_rejected.emit(reason, context.duplicate(true))
	return {
		"handled": true,
		"success": false,
		"action": &"rest",
		"reason": reason,
		"position": block_position,
		"block_id": block_id,
		"message": message,
		"severity": "warning",
	}


func _position_from_value(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return INVALID_BLOCK_POSITION


func _vector3_from_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector3_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
