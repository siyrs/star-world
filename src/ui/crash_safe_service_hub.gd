class_name CrashSafeServiceHub
extends "res://src/ui/exploration_progression_service_hub.gd"

signal application_quit_requested(source: StringName)

const SessionRecoveryServiceScript = preload(
	"res://src/save/world_session_recovery_service.gd"
)

var world_session_recovery_service: Node
var _application_quit_request_count := 0
var _application_quit_success_count := 0
var _application_quit_failure_count := 0
var _last_application_quit_source: StringName = &""


func _ready() -> void:
	super._ready()
	world_session_recovery_service = _add_service(
		SessionRecoveryServiceScript.new(), "WorldSessionRecovery"
	)
	if world_session_recovery_service != null:
		world_session_recovery_service.call("setup", save_service)
	if main_menu != null:
		if main_menu.has_method("setup_session_recovery"):
			main_menu.call(
				"setup_session_recovery", world_session_recovery_service
			)
		var menu_quit_callback := Callable(self, "_on_main_menu_quit_requested")
		if main_menu.has_signal("quit_requested") and not main_menu.is_connected(
			"quit_requested", menu_quit_callback
		):
			main_menu.connect("quit_requested", menu_quit_callback)
	if game_ui != null:
		var gameplay_quit_callback := Callable(self, "_on_gameplay_quit_requested")
		if game_ui.has_signal("quit_to_desktop_requested") and not game_ui.is_connected(
			"quit_to_desktop_requested", gameplay_quit_callback
		):
			game_ui.connect("quit_to_desktop_requested", gameplay_quit_callback)


func _begin_world(state: Dictionary) -> void:
	if world_session_recovery_service != null:
		world_session_recovery_service.call("begin_world", state)
	super._begin_world(state)


func activate_gameplay() -> void:
	super.activate_gameplay()
	if world_session_recovery_service != null:
		world_session_recovery_service.call("mark_active", current_world_id)


func handle_world_start_failed(reason: String) -> void:
	var failed_world_id := current_world_id
	super.handle_world_start_failed(reason)
	if world_session_recovery_service != null and not failed_world_id.is_empty():
		world_session_recovery_service.call("abort_world", failed_world_id)


func return_to_menu() -> void:
	var released_world_id := current_world_id
	super.return_to_menu()
	if (
		world_session_recovery_service != null
		and not released_world_id.is_empty()
		and current_world_id.is_empty()
	):
		world_session_recovery_service.call("end_world", released_world_id)


func prepare_application_quit(source: StringName = &"system") -> bool:
	_application_quit_request_count += 1
	_last_application_quit_source = source
	if game_ui != null and game_ui.has_method("show_quit_progress"):
		game_ui.call("show_quit_progress")
	if current_world_id.is_empty():
		_application_quit_success_count += 1
		return true
	return_to_menu()
	var prepared := current_world_id.is_empty()
	if prepared:
		_application_quit_success_count += 1
		if game_ui != null and game_ui.has_method("show_quit_result"):
			game_ui.call("show_quit_result", true)
	else:
		_application_quit_failure_count += 1
		if game_ui != null and game_ui.has_method("show_quit_result"):
			game_ui.call("show_quit_result", false)
	return prepared


func show_application_quit_prepared() -> void:
	if main_menu != null and main_menu.has_method("show_shutdown_ready"):
		main_menu.call("show_shutdown_ready")


func get_session_recovery_snapshot() -> Dictionary:
	if (
		world_session_recovery_service == null
		or not world_session_recovery_service.has_method("get_snapshot")
	):
		return {}
	return world_session_recovery_service.call("get_snapshot")


func get_application_quit_snapshot() -> Dictionary:
	return {
		"request_count": _application_quit_request_count,
		"success_count": _application_quit_success_count,
		"failure_count": _application_quit_failure_count,
		"last_source": str(_last_application_quit_source),
		"world_active": not current_world_id.is_empty(),
	}


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["session_recovery"] = get_session_recovery_snapshot()
	snapshot["application_quit"] = get_application_quit_snapshot()
	return snapshot


func _on_main_menu_quit_requested() -> void:
	application_quit_requested.emit(&"main_menu")


func _on_gameplay_quit_requested() -> void:
	application_quit_requested.emit(&"pause_menu")


func _exit_tree() -> void:
	if main_menu != null:
		var menu_callback := Callable(self, "_on_main_menu_quit_requested")
		if main_menu.has_signal("quit_requested") and main_menu.is_connected(
			"quit_requested", menu_callback
		):
			main_menu.disconnect("quit_requested", menu_callback)
	if game_ui != null:
		var gameplay_callback := Callable(self, "_on_gameplay_quit_requested")
		if game_ui.has_signal("quit_to_desktop_requested") and game_ui.is_connected(
			"quit_to_desktop_requested", gameplay_callback
		):
			game_ui.disconnect("quit_to_desktop_requested", gameplay_callback)
	if (
		world_session_recovery_service != null
		and world_session_recovery_service.has_method("shutdown")
	):
		world_session_recovery_service.call("shutdown")
	super._exit_tree()
