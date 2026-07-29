class_name AutosaveRuntimeParticipant
extends Node

signal autosave_completed(success: bool, snapshot: Dictionary)

const SettingsPolicyScript = preload("res://src/settings/game_settings_policy.gd")
const SchedulePolicyScript = preload("res://src/save/autosave_schedule_policy.gd")
const MAX_PROCESS_DELTA_SECONDS := 1.0
const MAX_INTERVAL_MINUTES := 15.0
const RETRY_DELAYS_SECONDS: Array[float] = [15.0, 60.0, 300.0]

var hub: Node
var pause_service: Node
var _installed := false
var _active := false
var _paused := false
var _shutdown := false
var _saving := false
var _current_world_id := ""
var _schedule_state: Dictionary = SchedulePolicyScript.create()
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
	return [
		&"machine_runtime",
		&"agriculture_runtime",
		&"husbandry_runtime",
		&"ranch_runtime",
		&"exploration_runtime",
		&"exploration_journal_rewards",
	]


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
	_saving = false
	_schedule_state = SchedulePolicyScript.reset_for_world(_schedule_state)
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
	_saving = false
	_current_world_id = ""
	_schedule_state = SchedulePolicyScript.reset_for_world(_schedule_state)
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
	var result := SchedulePolicyScript.configure(
		_schedule_state, normalized_minutes * 60.0
	)
	var raw_state: Variant = result.get("state", {})
	if raw_state is Dictionary:
		_schedule_state = raw_state
	if bool(result.get("changed", false)):
		_configuration_count += 1


func advance_active_time(delta_seconds: float) -> bool:
	if not _should_advance() or not is_finite(delta_seconds):
		return false
	var result := SchedulePolicyScript.advance(
		_schedule_state, maxf(0.0, delta_seconds)
	)
	var raw_state: Variant = result.get("state", {})
	if raw_state is Dictionary:
		_schedule_state = raw_state
	if not bool(result.get("due", false)):
		return false
	_due_count += 1
	call_deferred("_flush_autosave")
	return true


func get_snapshot() -> Dictionary:
	var schedule := SchedulePolicyScript.snapshot(_schedule_state)
	var snapshot := schedule.duplicate(true)
	snapshot["installed"] = _installed
	snapshot["active"] = _active
	snapshot["paused"] = _paused
	snapshot["shutdown"] = _shutdown
	snapshot["saving"] = _saving
	snapshot["current_world_id"] = _current_world_id
	snapshot["retry_delays_seconds"] = RETRY_DELAYS_SECONDS.duplicate()
	snapshot["process_delta_cap_seconds"] = MAX_PROCESS_DELTA_SECONDS
	snapshot["configuration_count"] = _configuration_count
	snapshot["due_count"] = _due_count
	snapshot["attempt_count"] = _attempt_count
	snapshot["success_count"] = _success_count
	snapshot["failure_count"] = _failure_count
	snapshot["retry_count"] = _retry_count
	snapshot["manual_reset_count"] = _manual_reset_count
	snapshot["last_success"] = _last_success
	snapshot["last_world_id"] = _last_world_id
	snapshot["last_elapsed_usec"] = _last_elapsed_usec
	snapshot["last_elapsed_milliseconds"] = float(_last_elapsed_usec) / 1000.0
	snapshot["last_completed_timestamp_msec"] = _last_completed_timestamp_msec
	return snapshot


func get_lifecycle_snapshot() -> Dictionary:
	return get_snapshot()


func _process(delta: float) -> void:
	advance_active_time(minf(maxf(0.0, delta), MAX_PROCESS_DELTA_SECONDS))


func _flush_autosave() -> void:
	if not SchedulePolicyScript.is_pending(_schedule_state):
		return
	# Preserve the pending boundary while paused. Consuming before this guard
	# would lose the first resumed frame and silently reintroduce schedule drift.
	if not _should_advance():
		return
	_schedule_state = SchedulePolicyScript.consume_pending(_schedule_state)
	_saving = true
	var world_id := _current_world_id
	var started_at := Time.get_ticks_usec()
	var success := bool(hub.call("save_current"))
	_last_elapsed_usec = maxi(0, Time.get_ticks_usec() - started_at)
	_last_completed_timestamp_msec = Time.get_ticks_msec()
	_last_world_id = world_id
	_last_success = success
	_attempt_count += 1
	if success:
		_success_count += 1
		_schedule_state = SchedulePolicyScript.record_success(_schedule_state)
	else:
		_failure_count += 1
		_retry_count += 1
		var schedule := SchedulePolicyScript.snapshot(_schedule_state)
		var failure_index := (
			maxi(0, int(schedule.get("consecutive_failure_count", 0))) + 1
		)
		var retry_delay := _retry_delay_for_failure(failure_index)
		_schedule_state = SchedulePolicyScript.record_failure(
			_schedule_state, retry_delay
		)
	_saving = false
	autosave_completed.emit(success, get_snapshot())


func _retry_delay_for_failure(failure_index: int) -> float:
	var schedule := SchedulePolicyScript.snapshot(_schedule_state)
	var interval_seconds := maxf(0.0, float(schedule.get("interval_seconds", 0.0)))
	if interval_seconds <= 0.0:
		return 0.0
	var retry_index := clampi(
		maxi(1, failure_index) - 1, 0, RETRY_DELAYS_SECONDS.size() - 1
	)
	return minf(interval_seconds, RETRY_DELAYS_SECONDS[retry_index])


func _should_advance() -> bool:
	return (
		_installed
		and not _shutdown
		and _active
		and not _paused
		and not _saving
		and SchedulePolicyScript.is_enabled(_schedule_state)
		and not _current_world_id.is_empty()
		and hub != null
		and is_instance_valid(hub)
	)


func _on_world_save_completed(world_id: String) -> void:
	if _current_world_id.is_empty() or world_id != _current_world_id:
		return
	if _saving:
		return
	_schedule_state = SchedulePolicyScript.record_manual_save(_schedule_state)
	_manual_reset_count += 1


func _on_settings_applied(settings: Dictionary) -> void:
	configure_from_settings(settings)


func _on_pause_changed(paused: bool) -> void:
	_paused = paused
	if (
		not paused
		and _installed
		and not _shutdown
		and _active
		and SchedulePolicyScript.is_pending(_schedule_state)
	):
		# Multiple deferred calls are safe: the first successful flush consumes
		# pending and every later call becomes a no-op.
		call_deferred("_flush_autosave")


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


func _exit_tree() -> void:
	shutdown()
