class_name HarvestEnabledPlayer
extends "res://src/player/first_person_player.gd"

const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var tool_service: Node
var harvest_service: Node
var _primary_action_held := false


func setup_gameplay_services(services: Dictionary) -> void:
	super.setup_gameplay_services(services)
	if services.get("tools") is Node:
		bind_tool_service(services["tools"])
	if services.get("harvest") is Node:
		bind_harvest_service(services["harvest"])


func bind_tool_service(p_tool_service: Node) -> void:
	tool_service = p_tool_service


func bind_harvest_service(p_harvest_service: Node) -> void:
	harvest_service = p_harvest_service


func set_input_enabled(enabled: bool) -> void:
	if not enabled:
		_primary_action_held = false
		_cancel_harvest("input_disabled")
	super.set_input_enabled(enabled)


func _process(delta: float) -> void:
	super._process(delta)
	if input_enabled and _primary_action_held:
		_advance_harvest(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		_primary_action_held = mouse_event.pressed
		if mouse_event.pressed:
			_start_primary_action()
		else:
			_cancel_harvest("released")
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func break_target_block() -> bool:
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return false
	var collider = interaction_ray.get_collider()
	if collider != null and collider.has_method("take_damage"):
		var attacked := super.break_target_block()
		if attacked:
			_consume_selected_durability("attack")
		return attacked
	if harvest_service == null:
		return super.break_target_block()
	var target := _resolve_harvest_target()
	if target.is_empty():
		return false
	var result: Dictionary = harvest_service.call(
		"harvest_immediately",
		world,
		inventory,
		target["position"],
		str(target["block_id"])
	)
	return _handle_harvest_result(result)


func _start_primary_action() -> void:
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		_primary_action_held = false
		_cancel_harvest("no_target")
		return
	var collider = interaction_ray.get_collider()
	if collider != null and collider.has_method("take_damage"):
		_primary_action_held = false
		if super.break_target_block():
			_consume_selected_durability("attack")
		return
	_advance_harvest(0.0)


func _advance_harvest(delta: float) -> void:
	if harvest_service == null:
		_primary_action_held = false
		super.break_target_block()
		return
	var target := _resolve_harvest_target()
	if target.is_empty():
		_primary_action_held = false
		_cancel_harvest("target_lost")
		return
	var result: Dictionary = harvest_service.call(
		"advance",
		world,
		inventory,
		target["position"],
		str(target["block_id"]),
		delta
	)
	var status := str(result.get("status", ""))
	if status == "completed":
		_handle_harvest_result(result)
	elif status == "rejected":
		_primary_action_held = false


func _resolve_harvest_target() -> Dictionary:
	if world == null:
		return {}
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return {}
	var collider = interaction_ray.get_collider()
	if collider != null and collider.has_method("take_damage"):
		return {}
	var point := interaction_ray.get_collision_point()
	var normal := interaction_ray.get_collision_normal()
	var block_position: Vector3i = world.call("world_to_block", point - normal * 0.01)
	var block_id := str(world.call("get_block", block_position))
	if block_id == BlockRegistryScript.AIR:
		return {}
	return {"position": block_position, "block_id": block_id}


func _handle_harvest_result(result: Dictionary) -> bool:
	if str(result.get("status", "")) != "completed":
		return false
	var block_id := str(result.get("block_id", ""))
	var saved_position = result.get("position", [])
	var block_position := Vector3i.ZERO
	if saved_position is Array and saved_position.size() >= 3:
		block_position = Vector3i(
			int(saved_position[0]), int(saved_position[1]), int(saved_position[2])
		)
	var display_name := str(
		BlockRegistryScript.get_definition(block_id).get("name", block_id)
	)
	var payload := {
		"block_id": block_id,
		"display_name": display_name,
		"position": [block_position.x, block_position.y, block_position.z],
		"drop_granted": bool(result.get("drop_granted", false)),
		"drop_item": str(result.get("drop_item", "")),
		"drop_count": int(result.get("drop_count", 0)),
	}
	if bool(payload["drop_granted"]):
		_report_player_action(&"mine", payload)
	else:
		_report_player_action(&"harvest_no_drop", payload)
	block_broken.emit(block_position, block_id)
	_update_interaction_focus(true)
	return true


func _consume_selected_durability(reason: String) -> void:
	if tool_service != null and tool_service.has_method("consume_selected_durability"):
		tool_service.call("consume_selected_durability", inventory, 1, reason)


func _cancel_harvest(reason: String) -> void:
	if harvest_service != null and harvest_service.has_method("cancel"):
		harvest_service.call("cancel", reason)
