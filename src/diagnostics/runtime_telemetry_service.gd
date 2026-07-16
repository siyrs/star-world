class_name RuntimeTelemetryService
extends Node

signal snapshot_updated(snapshot: Dictionary)
signal health_changed(status: String, issues: Array[String])

const HealthPolicyScript = preload("res://src/diagnostics/runtime_health_policy.gd")
const HISTORY_LIMIT := 120
const DEFAULT_STUTTER_THRESHOLD_MS := 50.0

@export_range(0.1, 5.0, 0.1) var sample_interval_seconds := 0.5
@export_range(16.0, 250.0, 1.0) var stutter_threshold_ms := DEFAULT_STUTTER_THRESHOLD_MS

var _world: Node
var _player: Node3D
var _input_context: Node
var _creature_spawner: Node
var _streaming_controller: Node
var _health_policy = HealthPolicyScript.new()
var _sample_accumulator := 0.0
var _frame_sample_count := 0
var _frame_total_ms := 0.0
var _frame_peak_ms := 0.0
var _stutter_count := 0
var _latest_snapshot: Dictionary = {}
var _history: Array[Dictionary] = []
var _last_health_status := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func setup(
	p_input_context: Node = null,
	p_creature_spawner: Node = null,
	p_streaming_controller: Node = null
) -> void:
	_input_context = p_input_context
	_creature_spawner = p_creature_spawner
	_streaming_controller = p_streaming_controller


func attach_runtime(world: Node, player: Node3D) -> void:
	_world = world
	_player = player
	sample_now()


func detach_runtime() -> void:
	_world = null
	_player = null
	_reset_frame_window()
	sample_now()


func _process(delta: float) -> void:
	record_frame(delta)


func record_frame(delta: float) -> void:
	var frame_ms := maxf(0.0, delta) * 1000.0
	_frame_sample_count += 1
	_frame_total_ms += frame_ms
	_frame_peak_ms = maxf(_frame_peak_ms, frame_ms)
	if frame_ms >= stutter_threshold_ms:
		_stutter_count += 1
	_sample_accumulator += maxf(0.0, delta)
	if _sample_accumulator >= maxf(0.1, sample_interval_seconds):
		sample_now()


func sample_now() -> Dictionary:
	var frame_average := (
		_frame_total_ms / float(_frame_sample_count) if _frame_sample_count > 0 else 0.0
	)
	var streaming := _get_streaming_stats()
	var player_position: Array = []
	if is_instance_valid(_player):
		player_position = [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
		]
	var snapshot := {
		"timestamp_msec": Time.get_ticks_msec(),
		"fps": float(Engine.get_frames_per_second()),
		"frame_sample_count": _frame_sample_count,
		"frame_ms_avg": frame_average,
		"frame_ms_peak": _frame_peak_ms,
		"stutter_count": _stutter_count,
		"memory_mib": float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"draw_calls": int(
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		),
		"streaming": streaming,
		"adaptive_streaming": _get_adaptive_streaming_status(),
		"creature_count": _count_creatures(),
		"pickup_count": get_tree().get_nodes_in_group(&"pickups").size() if get_tree() != null else 0,
		"input_context": _get_input_context(),
		"mouse_mode": int(Input.mouse_mode),
		"paused": get_tree().paused if get_tree() != null else false,
		"player_position": player_position,
		"world_attached": is_instance_valid(_world),
		"player_attached": is_instance_valid(_player),
	}
	snapshot["health"] = _health_policy.evaluate(snapshot)
	_latest_snapshot = snapshot.duplicate(true)
	_history.append(_latest_snapshot.duplicate(true))
	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()
	_emit_health_if_changed(snapshot["health"])
	snapshot_updated.emit(_latest_snapshot.duplicate(true))
	_reset_frame_window()
	return _latest_snapshot.duplicate(true)


func get_latest_snapshot() -> Dictionary:
	if _latest_snapshot.is_empty():
		return sample_now()
	return _latest_snapshot.duplicate(true)


func get_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for snapshot in _history:
		result.append(snapshot.duplicate(true))
	return result


func clear_history() -> void:
	_history.clear()


func write_report(path: String) -> bool:
	if path.is_empty():
		return false
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if path.is_absolute_path():
		absolute_directory = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var payload := {
		"version": 2,
		"generated_at": Time.get_datetime_string_from_system(),
		"latest": get_latest_snapshot(),
		"history": get_history(),
	}
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	file.close()
	return true


func _get_streaming_stats() -> Dictionary:
	if not is_instance_valid(_world) or not _world.has_method("get_streaming_stats"):
		return {"loaded": 0, "building": 0, "pending": 0, "last_work_usec": 0}
	var stats = _world.call("get_streaming_stats")
	return stats.duplicate(true) if stats is Dictionary else {}


func _get_adaptive_streaming_status() -> Dictionary:
	if (
		not is_instance_valid(_streaming_controller)
		or not _streaming_controller.has_method("get_status")
	):
		return {"enabled": false, "attached": false, "level_name": "unavailable"}
	var status = _streaming_controller.call("get_status")
	return status.duplicate(true) if status is Dictionary else {}


func _count_creatures() -> int:
	if not is_instance_valid(_creature_spawner):
		return 0
	var count := 0
	for child in _creature_spawner.get_children():
		if child is Node and child.is_in_group("creatures"):
			count += 1
	return count


func _get_input_context() -> String:
	if not is_instance_valid(_input_context) or not _input_context.has_method("get_context"):
		return "unknown"
	return str(_input_context.call("get_context"))


func _emit_health_if_changed(health: Dictionary) -> void:
	var status := str(health.get("status", HealthPolicyScript.STATUS_HEALTHY))
	if status == _last_health_status:
		return
	_last_health_status = status
	var issues: Array[String] = []
	for raw_issue in health.get("issues", []):
		issues.append(str(raw_issue))
	health_changed.emit(status, issues)


func _reset_frame_window() -> void:
	_sample_accumulator = 0.0
	_frame_sample_count = 0
	_frame_total_ms = 0.0
	_frame_peak_ms = 0.0
	_stutter_count = 0
