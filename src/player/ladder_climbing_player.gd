class_name LadderClimbingPlayer
extends "res://src/player/precision_interaction_player.gd"

signal ladder_state_changed(active: bool, snapshot: Dictionary)

const LadderPolicyScript = preload("res://src/block/block_ladder_policy.gd")
const LADDER_REATTACH_COOLDOWN_SECONDS := 0.22

@export var ladder_climb_speed := 3.2
@export var ladder_acceleration := 16.0
@export var ladder_horizontal_factor := 0.35
@export var ladder_detach_speed := 2.4
@export var ladder_jump_velocity := 4.2

var _ladder_active := false
var _ladder_climbing := false
var _ladder_reattach_remaining := 0.0
var _ladder_enter_count := 0
var _ladder_exit_count := 0
var _ladder_climb_frame_count := 0
var _ladder_contact_scan_count := 0
var _ladder_contact_candidate_count := 0
var _ladder_last_exit_reason := ""
var _ladder_contact: Dictionary = {}


func bind_world(p_world: Node) -> void:
	# bind_world is the lifecycle boundary, even when a scene reuses the same
	# VoxelWorld node instance. Never carry contact, counters or cooldown into
	# the next world session.
	_reset_ladder_runtime()
	super.bind_world(p_world)


func set_input_enabled(enabled: bool) -> void:
	super.set_input_enabled(enabled)
	if not enabled:
		velocity.y = 0.0
		_clear_ladder_state("input_disabled")


func reset_motion() -> void:
	super.reset_motion()
	_ladder_reattach_remaining = 0.0
	_clear_ladder_state("motion_reset")


func get_ladder_movement_snapshot() -> Dictionary:
	return {
		"active":_ladder_active,
		"climbing":_ladder_climbing,
		"reattach_cooldown_seconds":_ladder_reattach_remaining,
		"enter_count":_ladder_enter_count,
		"exit_count":_ladder_exit_count,
		"climb_frame_count":_ladder_climb_frame_count,
		"contact_scan_count":_ladder_contact_scan_count,
		"contact_candidate_count":_ladder_contact_candidate_count,
		"last_exit_reason":_ladder_last_exit_reason,
		"ladder_position":_position_array_from_variant(
			_ladder_contact.get("block_position", null)
		),
		"ladder_block_id":str(_ladder_contact.get("block_id", "")),
		"support_direction":str(_ladder_contact.get("support_direction", "")),
		"budget_exhausted":bool(_ladder_contact.get("budget_exhausted", false)),
	}


func get_resolved_placement_block_id() -> String:
	return _resolve_selected_block_id(get_selected_block_id(), _interaction_focus)


func _configure_movement_controller() -> void:
	super._configure_movement_controller()
	_movement_controller.configure({
		"ladder_climb_speed":ladder_climb_speed,
		"ladder_acceleration":ladder_acceleration,
		"ladder_horizontal_factor":ladder_horizontal_factor,
		"ladder_detach_speed":ladder_detach_speed,
		"ladder_jump_velocity":ladder_jump_velocity,
	})


func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	_ladder_reattach_remaining = maxf(
		0.0,
		_ladder_reattach_remaining - maxf(0.0, delta)
	)
	var in_fluid := _is_in_fluid()
	var ladder_contact := {
		"active":false,
		"scan_count":0,
		"candidate_count":0,
		"budget_exhausted":false,
	}
	if not in_fluid and _ladder_reattach_remaining <= 0.0:
		ladder_contact = LadderPolicyScript.resolve_contact(
			world,
			_player_body_bounds()
		)
	var contact_active := bool(ladder_contact.get("active", false))
	var voxel_ground: Variant = (
		null
		if in_fluid or contact_active
		else _get_nearby_voxel_ground()
	)
	var voxel_grounded := (
		not in_fluid
		and not contact_active
		and voxel_ground is Vector3
		and velocity.y <= 0.0
	)
	if voxel_grounded:
		global_position.y = voxel_ground.y + VOXEL_GROUND_CLEARANCE
		velocity.y = 0.0
	var movement_vector := _get_movement_vector()
	if movement_vector.length_squared() > 0.04:
		_report_action_once(&"move")
	var jump_just_pressed := _is_jump_just_pressed()
	var jump_requested := _is_jump_pressed() if in_fluid else jump_just_pressed
	var movement_result: Dictionary = _movement_controller.step(
		self,
		delta,
		movement_vector,
		jump_requested,
		_is_sprint_pressed(),
		in_fluid,
		voxel_grounded,
		ladder_contact
	)
	if bool(movement_result.get("detached_ladder", false)):
		_ladder_reattach_remaining = LADDER_REATTACH_COOLDOWN_SECONDS
	_update_ladder_state(ladder_contact, movement_result)
	if bool(movement_result.get("climbing", false)):
		_report_action_once(&"climb")
	if bool(movement_result.get("jumped", false)) and (not in_fluid or jump_just_pressed):
		_report_player_action(&"jump")
	elif not in_fluid and not contact_active:
		_apply_voxel_ground_recovery()
	if global_position.y < -12.0:
		respawn()


func _update_interaction_focus(force: bool = false) -> void:
	var next_focus: Dictionary = _focus_resolver.resolve(interaction_ray, world)
	if str(next_focus.get("type", "")) == "block":
		_append_connection_context(next_focus)
		var selected_block_id := _resolve_selected_block_id(
			get_selected_block_id(),
			next_focus
		)
		_append_door_context(next_focus, selected_block_id)
		_append_ladder_context(next_focus, selected_block_id)
		next_focus["placement_preview"] = _placement_preview_policy.evaluate(
			next_focus,
			selected_block_id,
			_player_bounds()
		)
	if not force and next_focus == _interaction_focus:
		return
	_interaction_focus = next_focus.duplicate(true)
	interaction_focus_changed.emit(_interaction_focus.duplicate(true))


func _place_block(block_id: String) -> bool:
	if world == null:
		_report_placement_failure("placement_unavailable", block_id)
		return false
	if inventory != null and _get_selected_item_id().is_empty():
		_report_placement_failure("no_block_selected", block_id)
		return false
	var target := _resolve_placement_target()
	if target.is_empty():
		_report_placement_failure(
			str(_last_placement_evaluation.get("reason", "no_focus")),
			block_id
		)
		return false
	var resolved_block_id := str(target.get("resolved_block_id", block_id))
	var placed := _commit_block_placement(resolved_block_id, target)
	if not placed:
		_report_placement_failure(
			str(_last_placement_evaluation.get("reason", "placement_unavailable")),
			resolved_block_id
		)
	return placed


func _resolve_placement_target() -> Dictionary:
	if world == null:
		_last_placement_evaluation = {
			"valid":false,
			"reason":"placement_unavailable",
		}
		return {}
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		_last_placement_evaluation = _placement_preview_policy.evaluate(
			{},
			get_selected_block_id(),
			_player_bounds()
		)
		return {}
	var selected_block_id := _resolve_selected_block_id(
		get_selected_block_id(),
		target
	)
	var hit_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var placement_position: Vector3i = target.get("placement_position", Vector3i.ZERO)
	var previous_block := str(target.get("placement_block_id", PrecisionBlockRegistry.AIR))
	var hit_block_id := str(target.get("hit_block_id", PrecisionBlockRegistry.AIR))
	var preview_focus := {
		"type":"block",
		"hit_position":[hit_position.x, hit_position.y, hit_position.z],
		"hit_block_id":hit_block_id,
		"face_normal":_vector3_array(
			Vector3(target.get("collision_normal", Vector3.ZERO))
		),
		"target_neighbor_ids":_connection_neighbors_for(hit_position),
		"placement_position":[placement_position.x, placement_position.y, placement_position.z],
		"placement_target_block_id":previous_block,
		"placement_neighbor_ids":_connection_neighbors_for(placement_position),
	}
	_append_door_context(preview_focus, selected_block_id)
	_append_ladder_context(preview_focus, selected_block_id)
	var evaluation: Dictionary = _placement_preview_policy.evaluate(
		preview_focus,
		selected_block_id,
		_player_bounds()
	)
	_last_placement_evaluation = evaluation.duplicate(true)
	if not bool(evaluation.get("valid", false)):
		return {}
	return {
		"position":placement_position,
		"previous_block":previous_block,
		"hit_position":hit_position,
		"face_normal":Vector3(target.get("collision_normal", Vector3.ZERO)),
		"connection_mask":int(evaluation.get("placement_connection_mask", 0)),
		"resolved_block_id":selected_block_id,
	}


func _resolve_selected_block_id(block_id: String, focus: Dictionary) -> String:
	if not LadderPolicyScript.supports(block_id):
		return _resolve_directional_block_id(block_id)
	var face_normal := _vector3_from_variant(focus.get("face_normal", Vector3.ZERO))
	if face_normal == Vector3.ZERO:
		face_normal = _vector3_from_variant(focus.get("collision_normal", Vector3.ZERO))
	var resolved := LadderPolicyScript.resolve_for_face_normal(block_id, face_normal)
	return resolved if not resolved.is_empty() else block_id


func _append_ladder_context(focus: Dictionary, selected_block_id: String) -> void:
	if world == null or not LadderPolicyScript.supports(selected_block_id):
		return
	var placement_position := _focus_position(focus.get("placement_position", []))
	var hit_position := _focus_position(focus.get("hit_position", []))
	if placement_position == INVALID_CONNECTION_POSITION:
		return
	var face_normal := _vector3_from_variant(focus.get("face_normal", Vector3.ZERO))
	if face_normal == Vector3.ZERO:
		face_normal = _vector3_from_variant(focus.get("collision_normal", Vector3.ZERO))
	var resolved := LadderPolicyScript.resolve_for_face_normal(selected_block_id, face_normal)
	var face_valid := not resolved.is_empty()
	focus["placement_ladder_face_valid"] = face_valid
	if not face_valid:
		return
	var support_position := placement_position + LadderPolicyScript.support_offset(resolved)
	focus["placement_ladder_support_position"] = [
		support_position.x,
		support_position.y,
		support_position.z,
	]
	focus["placement_ladder_support_block_id"] = str(
		world.call("get_block", support_position)
	)
	focus["placement_ladder_support_matches_target"] = support_position == hit_position


func _report_placement_failure(reason: String, block_id: String) -> void:
	if reason not in ["ladder_face_invalid", "ladder_support_missing", "ladder_support_mismatch"]:
		super._report_placement_failure(reason, block_id)
		return
	_report_player_action(
		&"place_failed",
		{
			"block_id":block_id,
			"reason":reason,
			"message":"%s；请对准实体墙面的侧面" % PlacementPreviewPolicyScript.reason_text(reason),
		}
	)


func _update_ladder_state(contact: Dictionary, movement_result: Dictionary) -> void:
	_ladder_contact_scan_count = int(contact.get("scan_count", 0))
	_ladder_contact_candidate_count = int(contact.get("candidate_count", 0))
	var was_active := _ladder_active
	var next_active := bool(movement_result.get("on_ladder", false))
	var detached := bool(movement_result.get("detached_ladder", false))
	_ladder_climbing = next_active and bool(movement_result.get("climbing", false))
	if next_active:
		_ladder_contact = contact.duplicate(true)
		if not was_active:
			_ladder_enter_count += 1
		if _ladder_climbing:
			_ladder_climb_frame_count += 1
	else:
		if was_active:
			_ladder_exit_count += 1
			_ladder_last_exit_reason = "jump_detach" if detached else "contact_lost"
		_ladder_contact = contact.duplicate(true)
	_ladder_active = next_active
	if was_active != _ladder_active:
		ladder_state_changed.emit(
			_ladder_active,
			get_ladder_movement_snapshot()
		)


func _clear_ladder_state(reason: String) -> void:
	var was_active := _ladder_active
	if was_active:
		_ladder_exit_count += 1
	_ladder_active = false
	_ladder_climbing = false
	_ladder_contact.clear()
	if not reason.is_empty():
		_ladder_last_exit_reason = reason
	if was_active:
		ladder_state_changed.emit(false, get_ladder_movement_snapshot())


func _reset_ladder_runtime() -> void:
	_ladder_active = false
	_ladder_climbing = false
	_ladder_reattach_remaining = 0.0
	_ladder_enter_count = 0
	_ladder_exit_count = 0
	_ladder_climb_frame_count = 0
	_ladder_contact_scan_count = 0
	_ladder_contact_candidate_count = 0
	_ladder_last_exit_reason = ""
	_ladder_contact.clear()


func _player_body_bounds() -> AABB:
	return AABB(
		global_position + Vector3(-0.32, 0.0, -0.32),
		Vector3(0.64, 1.82, 0.64)
	)


func _player_bounds() -> AABB:
	return _player_body_bounds()


func _vector3_from_variant(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Vector3i:
		return Vector3(value)
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _position_array_from_variant(value: Variant) -> Array[int]:
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Array and value.size() >= 3:
		return [int(value[0]), int(value[1]), int(value[2])]
	return []
