class_name ReleaseSmokeRunner
extends Node

const VisualPolicy = preload("res://src/diagnostics/visual_acceptance_policy.gd")
const DEFAULT_REPORT_PATH := "user://release-smoke.json"
const SMOKE_WORLD_ID := "release-smoke-runtime"
const TELEMETRY_STABILIZATION_FRAMES := 12
const DEFAULT_SOAK_FRAMES := 180
const SOAK_SAMPLE_INTERVAL_FRAMES := 30
const SOAK_MOVE_INTERVAL_FRAMES := 60
const EVIDENCE_SETTLE_FRAMES := 18
const AUDIO_SHUTDOWN_SETTLE_FRAMES := 4
const FINAL_CLEANUP_FRAMES := 6

var game: Node
var report_path := DEFAULT_REPORT_PATH
var screenshot_path := "user://release-smoke.png"
var soak_frames := DEFAULT_SOAK_FRAMES
var checks := 0
var failures: Array[String] = []
var _world_started := false
var _world_start_failure := ""


static func configuration_from_arguments(arguments: PackedStringArray) -> Dictionary:
	var enabled := false
	var output := DEFAULT_REPORT_PATH
	var configured_soak_frames := DEFAULT_SOAK_FRAMES
	for argument in arguments:
		if argument == "--release-smoke":
			enabled = true
		elif argument.begins_with("--smoke-output="):
			output = argument.trim_prefix("--smoke-output=").strip_edges()
		elif argument.begins_with("--smoke-soak-frames="):
			var raw_frames := argument.trim_prefix("--smoke-soak-frames=").strip_edges()
			if raw_frames.is_valid_int():
				configured_soak_frames = clampi(int(raw_frames), 60, 600)
	if not enabled:
		return {}
	if output.is_empty():
		output = DEFAULT_REPORT_PATH
	return {"report_path": output, "soak_frames": configured_soak_frames}


func configure(p_game: Node, configuration: Dictionary) -> void:
	game = p_game
	report_path = str(configuration.get("report_path", DEFAULT_REPORT_PATH))
	screenshot_path = "%s.png" % report_path.get_basename()
	soak_frames = clampi(
		int(configuration.get("soak_frames", DEFAULT_SOAK_FRAMES)), 60, 600
	)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_check(game != null, "game_root_available")
	if game == null:
		await _finish()
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
		_check(
			diagnostics.get("streaming_controller") != null,
			"adaptive_streaming_controller_mounted"
		)
	for _frame in TELEMETRY_STABILIZATION_FRAMES:
		await get_tree().process_frame
	var soak_result: Dictionary = await _run_runtime_soak(world, player, diagnostics)
	_check(bool(soak_result.get("ok", false)), "runtime_soak_stays_bounded")
	var evidence_result: Dictionary = await _prepare_visual_evidence(world, player)
	_check(bool(evidence_result.get("ok", false)), "final_focus_chunk_and_camera_ready")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var visual_result := VisualPolicy.evaluate(image)
	_check(bool(visual_result.get("ok", false)), "rendered_world_region_has_visual_detail")
	if image != null and not image.is_empty():
		_ensure_output_directory(screenshot_path)
		_check(image.save_png(screenshot_path) == OK, "screenshot_saved")
	await _finish(visual_result, diagnostics, soak_result, evidence_result)


func _on_world_started(_profile_id: String, _seed: int, _world_id: String) -> void:
	_world_started = true


func _on_world_start_failed(reason: String) -> void:
	_world_start_failure = reason


func _run_runtime_soak(world: Node, player: Node3D, diagnostics: Node) -> Dictionary:
	if world == null or player == null or diagnostics == null:
		return {"ok": false, "reason": "runtime_missing"}
	var max_pending := 0
	var max_loaded := 0
	var critical_samples := 0
	var samples := 0
	var start_position: Vector3 = world.call("get_spawn_position")
	for frame_index in soak_frames:
		if frame_index > 0 and frame_index % SOAK_MOVE_INTERVAL_FRAMES == 0:
			var leg := floori(float(frame_index) / float(SOAK_MOVE_INTERVAL_FRAMES))
			var candidate := start_position + Vector3(
				float(leg * 20), 4.0, float((leg % 2) * 18)
			)
			var resolved = world.call("resolve_ground_position", candidate)
			if resolved is Vector3:
				player.global_position = resolved
				if player.has_method("reset_motion"):
					player.call("reset_motion")
		await get_tree().process_frame
		if frame_index % SOAK_SAMPLE_INTERVAL_FRAMES != 0:
			continue
		var snapshot: Dictionary = diagnostics.call("sample_now")
		var streaming: Dictionary = snapshot.get("streaming", {})
		max_pending = maxi(max_pending, int(streaming.get("pending", 0)))
		max_loaded = maxi(max_loaded, int(streaming.get("loaded", 0)))
		if frame_index >= SOAK_MOVE_INTERVAL_FRAMES:
			var health: Dictionary = snapshot.get("health", {})
			if str(health.get("status", "healthy")) == "critical":
				critical_samples += 1
		samples += 1
	var final_snapshot: Dictionary = diagnostics.call("sample_now")
	var adaptive: Dictionary = final_snapshot.get("adaptive_streaming", {})
	var profile: Dictionary = adaptive.get("profile", {})
	var budget_ms := float(profile.get("budget_ms", 0.0))
	var change_count := int(adaptive.get("change_count", 0))
	var bounded := (
		max_pending <= 128
		and max_loaded <= 96
		and critical_samples <= 1
		and change_count <= 12
		and budget_ms >= 0.5
		and budget_ms <= 12.0
		and bool(adaptive.get("attached", false))
		and bool(world.get("is_started"))
		and player.visible
	)
	return {
		"ok": bounded,
		"frames": soak_frames,
		"samples": samples,
		"max_pending_chunks": max_pending,
		"max_loaded_chunks": max_loaded,
		"critical_samples": critical_samples,
		"adaptive_change_count": change_count,
		"adaptive_level": str(adaptive.get("level_name", "unknown")),
		"adaptive_budget_ms": budget_ms,
		"final_snapshot": final_snapshot,
	}


func _prepare_visual_evidence(world: Node, player: Node3D) -> Dictionary:
	if world == null or player == null:
		return {"ok": false, "reason": "runtime_missing"}
	var evidence_position: Vector3 = world.call("get_spawn_position")
	if world.has_method("resolve_ground_position"):
		var grounded = world.call("resolve_ground_position", evidence_position)
		if grounded is Vector3:
			evidence_position = grounded
	player.global_position = evidence_position
	if player.has_method("reset_motion"):
		player.call("reset_motion")
	if player.has_method("restore_orientation"):
		player.call(
			"restore_orientation",
			{
				"rotation": [0.0, deg_to_rad(35.0), 0.0],
				"look_pitch": deg_to_rad(-24.0),
			}
		)
	if world.has_method("set_focus"):
		world.call("set_focus", player)
	var focus_coord = null
	if world.has_method("world_to_block") and world.has_method("block_to_chunk"):
		var block_position = world.call("world_to_block", player.global_position)
		var raw_coord = world.call("block_to_chunk", block_position)
		if raw_coord is Vector2i:
			focus_coord = raw_coord
	var focus_chunk = null
	if focus_coord is Vector2i and world.has_method("force_load_chunk"):
		focus_chunk = world.call("force_load_chunk", focus_coord)
	await _wait_process_frames(EVIDENCE_SETTLE_FRAMES)
	var camera := player.call("get_view_camera") as Camera3D if player.has_method("get_view_camera") else null
	var camera_ready := camera != null and get_viewport().get_camera_3d() == camera
	var chunk_ready := _chunk_is_renderable(focus_chunk)
	var focus_value: Array = []
	if focus_coord is Vector2i:
		focus_value = [focus_coord.x, focus_coord.y]
	return {
		"ok": chunk_ready and camera_ready and player.visible,
		"focus_chunk": focus_value,
		"focus_chunk_renderable": chunk_ready,
		"camera_current": camera_ready,
		"look_pitch_degrees": -24.0,
		"player_position": [
			player.global_position.x,
			player.global_position.y,
			player.global_position.z,
		],
	}


func _finish(
	visual_result: Dictionary = {},
	diagnostics: Node = null,
	soak_result: Dictionary = {},
	evidence_result: Dictionary = {}
) -> void:
	var telemetry_snapshot: Dictionary = {}
	if diagnostics != null and diagnostics.has_method("sample_now"):
		telemetry_snapshot = diagnostics.call("sample_now")
	elif diagnostics != null and diagnostics.has_method("get_latest_snapshot"):
		telemetry_snapshot = diagnostics.call("get_latest_snapshot")
	var payload := {
		"version": 3,
		"ok": failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"generated_at": Time.get_datetime_string_from_system(),
		"report_path": report_path,
		"screenshot_path": screenshot_path,
		"visual": visual_result,
		"visual_evidence": evidence_result,
		"soak": soak_result,
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
	var exit_code := 0 if failures.is_empty() else 1
	if failures.is_empty():
		print("RELEASE SMOKE PASS | checks=%d | report=%s" % [checks, report_path])
	else:
		for failure in failures:
			push_error("RELEASE SMOKE FAILURE: %s" % failure)
		print("RELEASE SMOKE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	await _cleanup_runtime()
	get_tree().quit(exit_code)


func _cleanup_runtime() -> void:
	if game == null or not is_instance_valid(game):
		return
	var tree_root := get_tree().root
	if get_parent() == game:
		game.remove_child(self)
		tree_root.add_child(self)
	var diagnostics: Node = game.get("runtime_diagnostics")
	if diagnostics != null and diagnostics.has_method("detach_runtime"):
		diagnostics.call("detach_runtime")
	var hub: Node = game.get("service_hub")
	var audio: Node
	if hub != null:
		var spawner = hub.get("creature_spawner")
		if spawner != null:
			spawner.call("set_active", false)
			spawner.call("clear_creatures")
		audio = hub.get("audio_service")
		if audio != null:
			if audio.has_method("shutdown"):
				audio.call("shutdown")
			else:
				audio.call("stop_ambient")
	await _wait_process_frames(AUDIO_SHUTDOWN_SETTLE_FRAMES)
	if audio != null and is_instance_valid(audio) and audio.has_method("dispose"):
		audio.call("dispose")
	await _wait_process_frames(AUDIO_SHUTDOWN_SETTLE_FRAMES)
	var world: Node = game.get("world")
	if world != null and world.has_method("clear_world"):
		world.call("clear_world")
	game.queue_free()
	game = null
	await _wait_process_frames(FINAL_CLEANUP_FRAMES)


func _wait_process_frames(frame_count: int) -> void:
	for _frame in maxi(0, frame_count):
		await get_tree().process_frame


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
	return _chunk_is_renderable(chunks.values()[0])


func _chunk_is_renderable(chunk: Variant) -> bool:
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
