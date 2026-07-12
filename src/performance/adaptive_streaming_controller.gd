class_name AdaptiveStreamingController
extends Node

signal profile_changed(status: Dictionary)
signal controller_enabled_changed(enabled: bool)

const PolicyScript = preload("res://src/performance/adaptive_streaming_policy.gd")
const BudgetAdapterScript = preload("res://src/performance/streaming_budget_adapter.gd")

@export var enabled := true
@export_range(0, 10, 1) var warmup_snapshots := 2
@export_range(0, 10, 1) var cooldown_snapshots := 2
@export_range(1, 10, 1) var pressure_confirmation_snapshots := 2
@export_range(1, 12, 1) var headroom_confirmation_snapshots := 4
@export_range(1, 60, 1) var max_changes_per_minute := 12

var telemetry: Node
var world: Node
var _policy = PolicyScript.new()
var _budget_adapter = BudgetAdapterScript.new()
var _baseline_profile: Dictionary = {}
var _current_profile: Dictionary = {}
var _current_level := PolicyScript.LEVEL_BALANCED
var _warmup_remaining := 0
var _cooldown_remaining := 0
var _pressure_streak := 0
var _headroom_streak := 0
var _change_count := 0
var _last_reason := "未连接"
var _last_decision_code := "detached"
var _last_snapshot_msec := 0
var _recent_change_timestamps: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	_disconnect_telemetry()
	_restore_baseline()


func setup(p_telemetry: Node) -> void:
	_disconnect_telemetry()
	telemetry = p_telemetry
	if telemetry != null and telemetry.has_signal("snapshot_updated"):
		var callback := Callable(self, "_on_snapshot_updated")
		if not telemetry.is_connected("snapshot_updated", callback):
			telemetry.connect("snapshot_updated", callback)


func attach_world(p_world: Node) -> bool:
	if p_world == null or not _budget_adapter.supports(p_world):
		detach_world()
		_last_reason = "世界缺少流式预算合同"
		_last_decision_code = "contract_missing"
		profile_changed.emit(get_status())
		return false
	if world != p_world:
		_restore_baseline()
	world = p_world
	var raw_baseline: Dictionary = _budget_adapter.read_profile(world)
	if raw_baseline.is_empty():
		detach_world()
		_last_reason = "无法读取世界流式预算"
		_last_decision_code = "baseline_missing"
		profile_changed.emit(get_status())
		return false
	_baseline_profile = _policy.profile_for_level(raw_baseline, PolicyScript.LEVEL_BALANCED)
	_current_level = PolicyScript.LEVEL_BALANCED
	_current_profile = _baseline_profile.duplicate(true)
	_warmup_remaining = maxi(0, warmup_snapshots)
	_cooldown_remaining = 0
	_pressure_streak = 0
	_headroom_streak = 0
	_recent_change_timestamps.clear()
	_change_count = 0
	_last_reason = "已连接，等待稳定帧样本"
	_last_decision_code = "attached"
	_apply_profile(_current_profile, false)
	profile_changed.emit(get_status())
	return true


func detach_world() -> void:
	_restore_baseline()
	world = null
	_baseline_profile.clear()
	_current_profile.clear()
	_current_level = PolicyScript.LEVEL_BALANCED
	_warmup_remaining = 0
	_cooldown_remaining = 0
	_pressure_streak = 0
	_headroom_streak = 0
	_recent_change_timestamps.clear()
	_last_reason = "未连接"
	_last_decision_code = "detached"
	profile_changed.emit(get_status())


func set_controller_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		_restore_baseline()
		_current_level = PolicyScript.LEVEL_BALANCED
		_current_profile = _baseline_profile.duplicate(true)
		_pressure_streak = 0
		_headroom_streak = 0
		_last_reason = "自适应流式已关闭，恢复基础预算"
		_last_decision_code = "disabled"
	else:
		_warmup_remaining = maxi(0, warmup_snapshots)
		_last_reason = "自适应流式已启用，等待稳定帧样本"
		_last_decision_code = "enabled"
	controller_enabled_changed.emit(enabled)
	profile_changed.emit(get_status())


func process_snapshot(snapshot: Dictionary) -> bool:
	_last_snapshot_msec = int(snapshot.get("timestamp_msec", Time.get_ticks_msec()))
	if not enabled or not is_instance_valid(world):
		return false
	if _warmup_remaining > 0:
		if int(snapshot.get("frame_sample_count", 0)) >= _policy.minimum_frame_samples:
			_warmup_remaining -= 1
		_last_reason = "等待稳定帧样本"
		_last_decision_code = "warmup"
		return false
	if _cooldown_remaining > 0:
		_cooldown_remaining -= 1
		_last_reason = "预算调整冷却中"
		_last_decision_code = "cooldown"
		return false
	var recommendation: Dictionary = _policy.recommend(snapshot, _current_level)
	var target_level := clampi(
		int(recommendation.get("target_level", _current_level)),
		PolicyScript.MIN_LEVEL,
		PolicyScript.MAX_LEVEL
	)
	var decision_code := str(recommendation.get("code", "balanced"))
	var decision_reason := str(recommendation.get("reason", "维持当前预算"))
	if target_level == _current_level:
		_pressure_streak = 0
		_headroom_streak = 0
		_last_reason = decision_reason
		_last_decision_code = decision_code
		return false
	var required_confirmations := 1
	if target_level < _current_level:
		_pressure_streak += 1
		_headroom_streak = 0
		required_confirmations = (
			1
			if bool(recommendation.get("critical", false))
			else maxi(1, pressure_confirmation_snapshots)
		)
		if _pressure_streak < required_confirmations:
			_last_reason = "%s（确认 %d/%d）" % [
				decision_reason, _pressure_streak, required_confirmations
			]
			_last_decision_code = "pressure_confirmation"
			return false
	else:
		_headroom_streak += 1
		_pressure_streak = 0
		required_confirmations = maxi(1, headroom_confirmation_snapshots)
		if _headroom_streak < required_confirmations:
			_last_reason = "%s（确认 %d/%d）" % [
				decision_reason, _headroom_streak, required_confirmations
			]
			_last_decision_code = "headroom_confirmation"
			return false
	_prune_recent_changes(_last_snapshot_msec)
	if (
		_recent_change_timestamps.size() >= maxi(1, max_changes_per_minute)
		and not bool(recommendation.get("critical", false))
	):
		_last_reason = "一分钟内调整次数达到上限，保持当前预算"
		_last_decision_code = "anti_thrash_hold"
		_pressure_streak = 0
		_headroom_streak = 0
		return false
	var next_profile: Dictionary = _policy.profile_for_level(_baseline_profile, target_level)
	if not _apply_profile(next_profile, true):
		_last_reason = "世界拒绝新的流式预算"
		_last_decision_code = "apply_failed"
		return false
	_current_level = target_level
	_current_profile = next_profile.duplicate(true)
	_cooldown_remaining = maxi(0, cooldown_snapshots)
	_pressure_streak = 0
	_headroom_streak = 0
	_change_count += 1
	_recent_change_timestamps.append(_last_snapshot_msec)
	_last_reason = decision_reason
	_last_decision_code = decision_code
	profile_changed.emit(get_status())
	return true


func get_status() -> Dictionary:
	return {
		"enabled": enabled,
		"attached": is_instance_valid(world),
		"level": _current_level,
		"level_name": _policy.level_name(_current_level),
		"profile": _current_profile.duplicate(true),
		"baseline": _baseline_profile.duplicate(true),
		"warmup_remaining": _warmup_remaining,
		"cooldown_remaining": _cooldown_remaining,
		"pressure_streak": _pressure_streak,
		"headroom_streak": _headroom_streak,
		"change_count": _change_count,
		"recent_change_count": _recent_change_timestamps.size(),
		"last_reason": _last_reason,
		"last_decision_code": _last_decision_code,
		"last_snapshot_msec": _last_snapshot_msec,
	}


func _on_snapshot_updated(snapshot: Dictionary) -> void:
	process_snapshot(snapshot)


func _apply_profile(profile: Dictionary, require_change: bool) -> bool:
	if not is_instance_valid(world):
		return false
	var before: Dictionary = _budget_adapter.read_profile(world)
	if not _budget_adapter.apply_profile(world, profile):
		return false
	var after: Dictionary = _budget_adapter.read_profile(world)
	return before != after or not require_change


func _restore_baseline() -> void:
	if (
		is_instance_valid(world)
		and not _baseline_profile.is_empty()
		and _budget_adapter.supports(world)
	):
		_budget_adapter.apply_profile(world, _baseline_profile)


func _disconnect_telemetry() -> void:
	if telemetry == null or not telemetry.has_signal("snapshot_updated"):
		telemetry = null
		return
	var callback := Callable(self, "_on_snapshot_updated")
	if telemetry.is_connected("snapshot_updated", callback):
		telemetry.disconnect("snapshot_updated", callback)
	telemetry = null


func _prune_recent_changes(now_msec: int) -> void:
	var cutoff := now_msec - 60000
	while not _recent_change_timestamps.is_empty() and _recent_change_timestamps[0] < cutoff:
		_recent_change_timestamps.pop_front()
