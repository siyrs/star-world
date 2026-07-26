class_name AutosaveRuntimeParticipant
extends Node

signal autosave_completed(success: bool, snapshot: Dictionary)

const SettingsPolicyScript = preload("res://src/settings/game_settings_policy.gd")
const DEFAULT_RETRY_DELAY_SECONDS := 30.0
const MAX_PROCESS_DELTA_SECONDS := 1.0
const MAX_INTERVAL_MINUTES := 60.0

var hub: Node
var pause_service: Node
var _installed := false
var _active := false
var _paused := false
var _shutdown := false
var _pending_flush := false
var _saving := false
var _current_world_id := ""
var _interval_seconds := 0.0
var _elapsed_active_seconds := 0.0
var _retry_delay_seconds := DEFAULT_RETRY_DELAY_SECONDS
var _configuration_count := 0
var _due_count := 0
var _attempt_count := 0
var _success_count := 0
var _failure_count := 0
var _retry_count := 0
var _manual_reset_count := 0
var _last_success := false
var _last_world_id := ""
var _last_elapsed_usec := 0
var _last_completed_timestamp_msec := 0


func get_dependencies() -> Array[StringName]:
	return []


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	if not p_hub.has_method("save_current"):
		return false
	hub = p_hub
	pause_service = hub.get("simulation_pause") as Node
	_connect_hub_signals()
	_connect_pause_signal()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	var raw_settings: Variant = hub.get("current_settings")
	configure_from_settings(raw_settings if raw_settings is Dictionary else {})
	_paused = _read_paused()
	_installed = true
	_shutdown = false
	return true


func normalize_world_state(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func begin_world(state: Dictionary) -> void:
	_active = false
	_pending_flush = false
	_saving = false
	_elapsed_active_seconds = 0.0
	_paused = _read_paused()
	var metadata: Dictionary = state.get("metadata", {})
	_current_world_id = str(metadata.get("id", "")).strip_edges().left(128)


func attach_game(
	_world,
	_player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	pass


func activate() -> void:
	if _shutdown or _current_world_id.is_empty():
		return
	_active = true
	_paused = _read_paused()


func save_into(_payload: Dictionary) -> void:
	# Autosave owns only transient scheduling evidence. It must never create a
	# second persistence domain inside world.json.
	pass


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["autosave"] = get_snapshot()


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_pending_flush = false
	_saving = false
	_current_world_id = ""
	_elapsed_active_seconds = 0.0
	_paused = false


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	_disconnect_hub_signals()
	_disconnect_pause_signal()
	hub = null
	pause_service = null
	set_process(false)


func configure_from_settings(settings: Dictionary) -> void:
	var normalized := SettingsPolicyScript.normalize(settings)
	configure_interval_minutes(float(normalized.get("autosave_minutes", 5)))


func configure_interval_minutes(minutes: float) -> void:
	var safe_minutes := minutes if is_finite(minutes) else 0.0
	var normalized_minutes := clampf(safe_minutes, 0.0, MAX_INTERVAL_MINUTES)
	_interval_seconds = normalized_minutes * 60.0
	_elapsed_active_seconds = 0.0
	_pending_flush = false
	_configuration_count += 1


func advance_active_time(delta_seconds: float) -> bool:
	if not _should_advance() or not is_finite(delta_seconds):
		return false
	_elapsed_active_seconds += maxf(0.0, delta_seconds)
	if (
		_elapsed_active_seconds < _interval_seconds
		or _pending_flush
		or _saving
	):
		return false
	_pending_flush = true
	_due_count += 1
	call_deferred("_flush_autosave")
	return true


func get_snapshot() -> Dictionary:
	var enabled := _interval_seconds > 0.0
	return {
		"enabled": enabled,
		"installed": _installed,
		"active": _active,
		"paused": _paused,
		"shutdown": _shutdown,
		"pending": _pending_flush,
		"saving": _saving,
		"current_world_id": _current_world_id,
		"interval_minutes": _interval_seconds / 60.0,
		"interval_seconds": _interval_seconds,
		"elapsed_active_seconds": _elapsed_active_seconds,
		"next_in_seconds": (
			maxf(0.0, _interval_seconds - _elapsed_active_seconds) if enabled else 0.0
		),
		"retry_delay_seconds": _retry_delay_seconds,
		"process_delta_cap_seconds": MAX_PROCESS_DELTA_SECONDS,
		"configuration_count": _configuration_count,
		"due_count": _due_count,
		"attempt_count": _attempt_count,
		"success_count": _success_count,
		"failure_count": _failure_count,
		"retry_count": _retry_count,
		"manual_reset_count": _manual_reset_count,
		"last_success": _last_success,
		"last_world_id": _last_world_id,
		"last_elapsed_usec": _last_elapsed_usec,
		"last_elapsed_milliseconds": float(_last_elapsed_usec) / 1000.0,
		"last_completed_timestamp_msec": _last_completed_timestamp_msec,
	}


func get_lifecycle_snapshot() -> Dictionary:
	return get_snapshot()


func _process(delta: float) -> void:
	advance_active_time(minf(maxf(0.0, delta), MAX_PROCESS_DELTA_SECONDS))


func _flush_autosave() -> void:
	if not _pending_flush:
		return
	_pending_flush = false
	if not _should_advance():
		return
	_saving = true
	var world_id := _current_world_id
	var started_at := Time.get_ticks_usec()
	var success := bool(hub.call("save_current"))
	_last_elapsed_usec = maxi(0, Time.get_ticks_usec() - started_at)
	_last_completed_timestamp_msec = Time.get_ticks_msec()
	_last_world_id = world_id
	_last_success = success
	_attempt_count += 1
	_saving = false
	if success:
		_success_count += 1
		_elapsed_active_seconds = 0.0
	else:
		_failure_count += 1
		_retry_count += 1
		var retry_window := minf(_retry_delay_seconds, _interval_seconds)
		_elapsed_active_seconds = maxf(0.0, _interval_seconds - retry_window)
		_publish_failure_message()
	autosave_completed.emit(success, get_snapshot())


func _should_advance() -> bool:
	return (
		_installed
		and not _shutdown
		and _active
		and not _paused
		and not _saving
		and _interval_seconds > 0.0
		and not _current_world_id.is_empty()
		and hub != null
		and is_instance_valid(hub)
	)


func _on_world_save_completed(world_id: String) -> void:
	if _current_world_id.is_empty() or world_id != _current_world_id:
		return
	_elapsed_active_seconds = 0.0
	_pending_flush = false
	if not _saving:
		_manual_reset_count += 1


func _on_settings_applied(settings: Dictionary) -> void:
	configure_from_settings(settings)


func _on_pause_changed(paused: bool) -> void:
	_paused = paused


func _read_paused() -> bool:
	if (
		pause_service != null
		and is_instance_valid(pause_service)
		and pause_service.has_method("is_paused")
	):
		return bool(pause_service.call("is_paused"))
	return false


func _connect_hub_signals() -> void:
	if hub == null or not is_instance_valid(hub):
		return
	var save_callback := Callable(self, "_on_world_save_completed")
	if hub.has_signal("world_save_completed") and not hub.is_connected(
		"world_save_completed", save_callback
	):
		hub.connect("world_save_completed", save_callback)
	var settings_callback := Callable(self, "_on_settings_applied")
	if hub.has_signal("settings_applied") and not hub.is_connected(
		"settings_applied", settings_callback
	):
		hub.connect("settings_applied", settings_callback)


func _disconnect_hub_signals() -> void:
	if hub == null or not is_instance_valid(hub):
		return
	var save_callback := Callable(self, "_on_world_save_completed")
	if hub.has_signal("world_save_completed") and hub.is_connected(
		"world_save_completed", save_callback
	):
		hub.disconnect("world_save_completed", save_callback)
	var settings_callback := Callable(self, "_on_settings_applied")
	if hub.has_signal("settings_applied") and hub.is_connected(
		"settings_applied", settings_callback
	):
		hub.disconnect("settings_applied", settings_callback)


func _connect_pause_signal() -> void:
	if pause_service == null or not is_instance_valid(pause_service):
		return
	var callback := Callable(self, "_on_pause_changed")
	if pause_service.has_signal("pause_changed") and not pause_service.is_connected(
		"pause_changed", callback
	):
		pause_service.connect("pause_changed", callback)


func _disconnect_pause_signal() -> void:
	if pause_service == null or not is_instance_valid(pause_service):
		return
	var callback := Callable(self, "_on_pause_changed")
	if pause_service.has_signal("pause_changed") and pause_service.is_connected(
		"pause_changed", callback
	):
		pause_service.disconnect("pause_changed", callback)


func _publish_failure_message() -> void:
	if hub != null and is_instance_valid(hub) and hub.has_method("_publish_character_message"):
		hub.call(
			"_publish_character_message",
			"自动存档失败，将在活动时间 30 秒后重试",
			"warning",
			"autosave_failed",
			4.0
		)


func _exit_tree() -> void:
	shutdown()
