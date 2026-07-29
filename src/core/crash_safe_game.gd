class_name CrashSafeStarWorldGame
extends "res://src/core/batched_game.gd"

signal application_quit_prepared(source: StringName)
signal application_quit_blocked(source: StringName)

var application_exit_enabled := true
var _application_quit_in_flight := false
var _quit_request_count := 0
var _quit_success_count := 0
var _quit_failure_count := 0
var _duplicate_quit_request_count := 0
var _last_quit_source: StringName = &""


func _ready() -> void:
	super._ready()
	var tree := get_tree()
	if tree != null:
		tree.auto_accept_quit = false
	if service_hub != null and service_hub.has_signal("application_quit_requested"):
		var callback := Callable(self, "request_application_quit")
		if not service_hub.is_connected("application_quit_requested", callback):
			service_hub.connect("application_quit_requested", callback)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("request_application_quit", &"window_close")


func request_application_quit(source: StringName = &"system") -> bool:
	_quit_request_count += 1
	_last_quit_source = source
	if _application_quit_in_flight:
		_duplicate_quit_request_count += 1
		return false
	if service_hub == null or not service_hub.has_method("prepare_application_quit"):
		_quit_failure_count += 1
		application_quit_blocked.emit(source)
		return false
	_application_quit_in_flight = true
	var prepared := bool(service_hub.call("prepare_application_quit", source))
	if not prepared:
		_quit_failure_count += 1
		_application_quit_in_flight = false
		application_quit_blocked.emit(source)
		return false
	_quit_success_count += 1
	application_quit_prepared.emit(source)
	if service_hub.has_method("show_application_quit_prepared"):
		service_hub.call("show_application_quit_prepared")
	if application_exit_enabled:
		var tree := get_tree()
		if tree != null:
			tree.quit(0)
	else:
		_application_quit_in_flight = false
	return true


func get_application_quit_snapshot() -> Dictionary:
	return {
		"in_flight": _application_quit_in_flight,
		"request_count": _quit_request_count,
		"success_count": _quit_success_count,
		"failure_count": _quit_failure_count,
		"duplicate_request_count": _duplicate_quit_request_count,
		"last_source": str(_last_quit_source),
		"exit_enabled": application_exit_enabled,
	}


func _exit_tree() -> void:
	if service_hub != null and service_hub.has_signal("application_quit_requested"):
		var callback := Callable(self, "request_application_quit")
		if service_hub.is_connected("application_quit_requested", callback):
			service_hub.disconnect("application_quit_requested", callback)
	var tree := get_tree()
	if tree != null:
		tree.auto_accept_quit = true
