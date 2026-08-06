class_name BatchedStarWorldGame
extends "res://src/core/game.gd"

signal application_quit_prepared(source: StringName)
signal application_quit_blocked(source: StringName)

const BATCHED_WORLD_SCRIPT_PATH := "res://src/world/persistent_cached_batched_voxel_world.gd"
const BATCHED_PLAYER_SCENE_PATH := "res://scenes/game/player.tscn"
const ReleaseLifecycleReportServiceScript = preload(
	"res://src/diagnostics/release_lifecycle_report_service.gd"
)

var application_exit_enabled := true
var force_release_lifecycle_reporting := false
var release_lifecycle_report_path_override := ""
var release_lifecycle_report: Node
var _application_quit_in_flight := false
var _quit_request_count := 0
var _quit_success_count := 0
var _quit_failure_count := 0
var _duplicate_quit_request_count := 0
var _last_quit_source: StringName = &""


func _ready() -> void:
	_setup_release_lifecycle_report()
	super._ready()
	var tree := get_tree()
	if tree != null:
		tree.auto_accept_quit = false
	if service_hub != null and service_hub.has_signal("application_quit_requested"):
		var callback := Callable(self, "request_application_quit")
		if not service_hub.is_connected("application_quit_requested", callback):
			service_hub.connect("application_quit_requested", callback)
	_bind_release_lifecycle_report()
	if release_lifecycle_report != null:
		release_lifecycle_report.call("mark_scene_ready")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("request_application_quit", &"window_close")


func request_application_quit(source: StringName = &"system") -> bool:
	_quit_request_count += 1
	_last_quit_source = source
	if _application_quit_in_flight:
		_duplicate_quit_request_count += 1
		return false
	_begin_release_quit(source)
	if service_hub == null or not service_hub.has_method("prepare_application_quit"):
		_quit_failure_count += 1
		_complete_release_quit(false)
		application_quit_blocked.emit(source)
		return false
	_application_quit_in_flight = true
	var prepared := bool(service_hub.call("prepare_application_quit", source))
	if not prepared:
		_quit_failure_count += 1
		_application_quit_in_flight = false
		_complete_release_quit(false)
		application_quit_blocked.emit(source)
		return false
	_quit_success_count += 1
	application_quit_prepared.emit(source)
	if service_hub.has_method("show_application_quit_prepared"):
		service_hub.call("show_application_quit_prepared")
	_complete_release_quit(true)
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


func get_release_lifecycle_snapshot() -> Dictionary:
	if release_lifecycle_report == null:
		return {}
	return release_lifecycle_report.call("get_snapshot")


func _setup_release_lifecycle_report() -> void:
	if release_lifecycle_report != null:
		return
	release_lifecycle_report = ReleaseLifecycleReportServiceScript.new()
	release_lifecycle_report.name = "ReleaseLifecycleReport"
	release_lifecycle_report.call(
		"configure",
		force_release_lifecycle_reporting,
		release_lifecycle_report_path_override
	)
	add_child(release_lifecycle_report)


func _bind_release_lifecycle_report() -> void:
	if release_lifecycle_report == null:
		return
	var world_callback := Callable(self, "_on_release_world_started")
	if not world_started.is_connected(world_callback):
		world_started.connect(world_callback)
	if service_hub == null:
		return
	var health_report := service_hub.get("runtime_health_report_service") as Node
	if health_report == null or not health_report.has_signal("save_checkpoint_recorded"):
		return
	var save_callback := Callable(self, "_on_release_save_checkpoint_recorded")
	if not health_report.is_connected("save_checkpoint_recorded", save_callback):
		health_report.connect("save_checkpoint_recorded", save_callback)


func _unbind_release_lifecycle_report() -> void:
	var world_callback := Callable(self, "_on_release_world_started")
	if world_started.is_connected(world_callback):
		world_started.disconnect(world_callback)
	if service_hub == null:
		return
	var health_report := service_hub.get("runtime_health_report_service") as Node
	if health_report == null or not health_report.has_signal("save_checkpoint_recorded"):
		return
	var save_callback := Callable(self, "_on_release_save_checkpoint_recorded")
	if health_report.is_connected("save_checkpoint_recorded", save_callback):
		health_report.disconnect("save_checkpoint_recorded", save_callback)


func _on_release_world_started(profile_id: String, seed: int, world_id: String) -> void:
	if release_lifecycle_report != null:
		release_lifecycle_report.call(
			"mark_first_world_playable", profile_id, seed, world_id
		)


func _on_release_save_checkpoint_recorded(
	event: Dictionary, timeline: Dictionary
) -> void:
	if release_lifecycle_report != null:
		release_lifecycle_report.call("mark_first_save", event, timeline)


func _begin_release_quit(source: StringName) -> void:
	if release_lifecycle_report != null:
		release_lifecycle_report.call("begin_quit", source)


func _complete_release_quit(prepared: bool) -> void:
	if release_lifecycle_report == null:
		return
	var runtime_health: Dictionary = {}
	var service_hub_quit: Dictionary = {}
	if service_hub != null:
		if service_hub.has_method("get_runtime_health_snapshot"):
			var raw_health: Variant = service_hub.call("get_runtime_health_snapshot")
			if raw_health is Dictionary:
				runtime_health = raw_health
		if service_hub.has_method("get_application_quit_snapshot"):
			var raw_hub_quit: Variant = service_hub.call(
				"get_application_quit_snapshot"
			)
			if raw_hub_quit is Dictionary:
				service_hub_quit = raw_hub_quit
	release_lifecycle_report.call(
		"complete_quit",
		prepared,
		runtime_health,
		service_hub_quit,
		get_application_quit_snapshot()
	)


func _ensure_core_nodes() -> void:
	if world == null and ResourceLoader.exists(BATCHED_WORLD_SCRIPT_PATH):
		var world_script: Script = load(BATCHED_WORLD_SCRIPT_PATH)
		world = world_script.new()
		world.name = "VoxelWorld"
		world_root.add_child(world)
	if player == null and ResourceLoader.exists(BATCHED_PLAYER_SCENE_PATH):
		var player_scene: PackedScene = load(BATCHED_PLAYER_SCENE_PATH)
		player = player_scene.instantiate()
		player.name = "Player"
		add_child(player)


func _exit_tree() -> void:
	_unbind_release_lifecycle_report()
	if (
		release_lifecycle_report != null
		and release_lifecycle_report.has_method("finalize_scene_exit")
	):
		release_lifecycle_report.call("finalize_scene_exit")
	if service_hub != null and service_hub.has_signal("application_quit_requested"):
		var callback := Callable(self, "request_application_quit")
		if service_hub.is_connected("application_quit_requested", callback):
			service_hub.disconnect("application_quit_requested", callback)
	var tree := get_tree()
	if tree != null:
		tree.auto_accept_quit = true
