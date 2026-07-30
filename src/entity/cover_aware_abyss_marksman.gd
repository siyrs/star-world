class_name CoverAwareAbyssMarksmanCreature
extends "res://src/entity/abyss_marksman.gd"

const CoverPolicyScript = preload("res://src/entity/hostile_cover_counter_policy.gd")
const LOS_STABLE_RESET_SECONDS := 1.0

var cover_counter_service: Node
var _blocked_lane_seconds := 0.0
var _clear_lane_seconds := 0.0
var _reposition_cooldown_remaining := 0.0
var _reposition_attempt_count := 0
var _reposition_success_count := 0
var _tracked_target_id := 0
var _last_reposition_result: Dictionary = {}


func bind_cover_counter_service(service: Node) -> void:
	cover_counter_service = service


func clear_combat_motion() -> void:
	_reset_reposition_state(true)
	super.clear_combat_motion()


func get_hostile_attack_snapshot() -> Dictionary:
	var snapshot := super.get_hostile_attack_snapshot()
	snapshot.merge({
		"cover_counter_available": (
			cover_counter_service != null and is_instance_valid(cover_counter_service)
		),
		"blocked_lane_seconds": _blocked_lane_seconds,
		"reposition_cooldown_remaining": _reposition_cooldown_remaining,
		"reposition_attempt_count": _reposition_attempt_count,
		"reposition_attempt_budget": CoverPolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET,
		"reposition_success_count": _reposition_success_count,
		"last_reposition_result": _last_reposition_result.duplicate(true),
	}, true)
	return snapshot


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	_reposition_cooldown_remaining = maxf(
		0.0, _reposition_cooldown_remaining - safe_delta
	)
	_acquire_target()
	var next_target_id := (
		int(target.get_instance_id())
		if target != null and is_instance_valid(target)
		else 0
	)
	if next_target_id != _tracked_target_id:
		_tracked_target_id = next_target_id
		_reset_reposition_state(false)
	if _is_attack_target_valid():
		_refresh_line_of_sight(false)
		if _line_of_sight:
			_blocked_lane_seconds = 0.0
			_clear_lane_seconds += safe_delta
			if _clear_lane_seconds >= LOS_STABLE_RESET_SECONDS:
				_reposition_attempt_count = 0
		else:
			_clear_lane_seconds = 0.0
			_blocked_lane_seconds = minf(
				CoverPolicyScript.REPOSITION_DELAY_SECONDS * 4.0,
				_blocked_lane_seconds + safe_delta
			)
	else:
		_blocked_lane_seconds = 0.0
		_clear_lane_seconds = 0.0
	super._physics_process(safe_delta)


func _choose_direction() -> Vector3:
	_acquire_target()
	if _is_attack_target_valid():
		_refresh_line_of_sight(false)
		if (
			not _line_of_sight
			and CoverPolicyScript.can_attempt_reposition(
				_blocked_lane_seconds,
				_reposition_cooldown_remaining,
				_reposition_attempt_count
			)
			and cover_counter_service != null
			and is_instance_valid(cover_counter_service)
			and cover_counter_service.has_method("find_marksman_reposition_destination")
		):
			_reposition_attempt_count += 1
			_reposition_cooldown_remaining = CoverPolicyScript.REPOSITION_COOLDOWN_SECONDS
			var result: Dictionary = cover_counter_service.call(
				"find_marksman_reposition_destination",
				self,
				target,
				minimum_attack_range,
				attack_range
			)
			_last_reposition_result = result.duplicate(true)
			if bool(result.get("success", false)):
				var destination: Vector3 = result.get("destination", global_position)
				_cover_destination = destination
				_cover_destination_active = true
				_blocked_lane_seconds = 0.0
				_reposition_success_count += 1
				if cover_counter_service.has_method("report_marksman_reposition"):
					cover_counter_service.call(
						"report_marksman_reposition",
						self,
						destination,
						int(result.get("probes", 0)),
						_reposition_attempt_count
					)
	return super._choose_direction()


func _compute_line_of_sight() -> bool:
	if (
		cover_counter_service != null
		and is_instance_valid(cover_counter_service)
		and cover_counter_service.has_method("has_projectile_lane")
		and _is_attack_target_valid()
	):
		return bool(cover_counter_service.call("has_projectile_lane", self, target))
	return super._compute_line_of_sight()


func _reset_reposition_state(reset_target: bool) -> void:
	_blocked_lane_seconds = 0.0
	_clear_lane_seconds = 0.0
	_reposition_cooldown_remaining = 0.0
	_reposition_attempt_count = 0
	_reposition_success_count = 0
	_last_reposition_result.clear()
	if reset_target:
		_tracked_target_id = 0
