class_name ReleaseSmokeRunner
extends Node

const VisualPolicy = preload("res://src/diagnostics/visual_acceptance_policy.gd")
const DEFAULT_REPORT_PATH := "user://release-smoke.json"
const SMOKE_WORLD_ID := "release-smoke-runtime"

var game: Node
var report_path := DEFAULT_REPORT_PATH
var screenshot_path := "user://release-smoke.png"
var checks := 0
var failures: Array[String] = []
var _world_started := false
var _world_start_failure := ""


static func configuration_from_arguments(arguments: PackedStringArray) -> Dictionary:
	var enabled := false
	var output := DEFAULT_REPORT_PATH
	for argument in arguments:
		if argument == "--release-smoke":
			enabled = true
		elif argument.begins_with("--smoke-output="):
			output = argument.trim_prefix("--smoke-output=").strip_edges()
	if not enabled:
		return {}
	if output.is_empty():
		output = DEFAULT_REPORT_PATH
	return {"report_path": output}


func configure(p_game: Node, configuration: Dictionary) -> void:
	game = p_game
	report_path = str(configuration.get("report_path", DEFAULT_REPORT_PATH))
	screenshot_path = "%s.png" % report_path.get_basename()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_check(game != null, "game_root_available")
	if game == null:
		_finish()
		return
	_world_started = false
	_world_start_failure = ""
	game.connect("world_started", Callable(self, "_on_world_started"), CONNECT_ONE_SHOT)
	game.connect("world_start_failed", Callable(self, "_on_world_start_failed"), CONNECT_ONE_SHOT)
	game.call("begin_world_state", _smoke_world_state())
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(_world_started, "world_started:%s" % _world_start_failure)
	var hub: Node = game.get("service_hub")
	var world: Node = game.get("world")
	var player: Node3D = game.get("player")
	var world_root := game.get("world_root") as Node3D
	var diagnostics: Node = game.get("runtime_diagnostics")
	_check(world != null and bool(world.get("is_started")), "world_is_started")
	_check(world_root != null and world_root.visible, "world_root_visible")
	_check(player != null and player.visible, "player_visible")
	_check(_spawn_chunk_is_renderable(world), "spawn_chunk_renderable")
	_check(
		player != null and get_viewport().get_camera_3d() == player.call("get_view_camera"),
		"player_camera_current"
	)
	if hub != null:
		var input_context = hub.get("input_context")
		_check(
			input_context != null and str(input_context.call("get_context")) == "gameplay",
			"gameplay_input_context"
		)
	_check(diagnostics != null, "runtime_diagnostics_mounted")
	if diagnostics != null:
		_check(diagnostics.get("telemetry") != null, "runtime_telemetry_mounted")
		_check(diagnostics.get("overlay") != null, "diagnostics_overlay_mounted")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var visual_result := VisualPolicy.evaluate(image)
	_check(bool(visual_result.get("ok", false)), "rendered_frame_has_visual_detail")
	if image != null and not image.is_empty():
		_ensure_output_directory(screenshot_path)
		_check(image.save_png(screenshot_path) == OK, "screenshot_saved")
	_finish(visual_result, diagnostics)


func _on_world_started(_profile_id: String, _seed: int, _world_id: String) -> void:
	_world_started = true


func _on_world_start_failed(reason: String) -> void:
	_world_start_failure = reason


func _finish(visual_result: Dictionary = {}, diagnostics: Node = null) -> void:
	var telemetry_snapshot: Dictionary = {}
	if diagnostics != null and diagnostics.has_method("get_latest_snapshot"):
		telemetry_snapshot = diagnostics.call("get_latest_snapshot")
	var payload := {
		"version": 1,
		"ok": failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"generated_at": Time.get_datetime_string_from_system(),
		"report_path": report_path,
		"screenshot_path": screenshot_path,
		"visual": visual_result,
		"telemetry": telemetry_snapshot,
		"engine_version": Engine.get_version_info(),
	}
	_ensure_output_directory(report_path)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		failures.append("report_write_failed")
	else:
		payload["ok"] = failures.is_empty()
		payload["failures"] = failures
		file.store_string(JSON.stringify(payload, "\t", false))
		file.flush()
		file.close()
	if failures.is_empty():
		print("RELEASE SMOKE PASS | checks=%d | report=%s" % [checks, report_path])
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("RELEASE SMOKE FAILURE: %s" % failure)
		print("RELEASE SMOKE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		get_tree().quit(1)


func _smoke_world_state() -> Dictionary:
	return {
		"save_version": 2,
		"metadata": {
			"id": SMOKE_WORLD_ID,
			"name": "Release Smoke",
			"map_id": "star_continent",
			"seed": 24681357,
		},
		"player": {"position": [], "rotation": [0.0, 0.0, 0.0], "look_pitch": 0.0},
		"inventory": {},
		"containers": {"version": 1, "containers": {}},
		"world": {"block_overrides": {}, "loaded_chunks": []},
		"survival": {"health": 20.0, "hunger": 20.0},
		"day_night": {"time_of_day": 9.0, "day": 1},
	}


func _spawn_chunk_is_renderable(world: Node) -> bool:
	if world == null:
		return false
	var chunks = world.get("chunks")
	if chunks is not Dictionary or chunks.is_empty():
		return false
	var chunk = chunks.values()[0]
	if not is_instance_valid(chunk) or int(chunk.get("surface_face_count")) <= 0:
		return false
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	return (
		mesh_instance != null
		and mesh_instance.mesh != null
		and collision != null
		and collision.shape != null
	)


func _ensure_output_directory(path: String) -> void:
	var directory := path.get_base_dir()
	if not path.is_absolute_path():
		directory = ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(directory)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
