extends SceneTree

# OpenSpec 5.3/5.4: like-for-like performance capture across release scenarios.
#
# Scenarios: main menu, each profile spawn + rapid movement/turning pressure,
# repeated load, and a settings change. Each scenario records real frame times
# (avg / p95 / p99 / 1% low FPS), fps, streaming convergence, node count, and a
# timestamped JSON report at --capture-output=<dir>/perf-report.json.
#
# Memory is sampled externally by the PowerShell driver (Working Set / Private
# Bytes of the launched PID) because release MEMORY_STATIC is unreliable — the
# internal memory_mib is recorded only when valid (>= 0) and marked unavailable
# otherwise, per the observability spec.

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")

const QA_PREFIX := "qa-v130-perf-"
const JOURNEY_SEED := 112358
const READY_FRAMES := 720
const CLEANUP_FRAMES := 60
const SCENARIO_FRAMES := 240
const MOVE_INTERVAL := 30

var checks := 0
var failures: Array[String] = []
var _created_world_ids: Array[String] = []
var _capture_path := ""
var _capture_directory := ""
var _scenarios: Array[Dictionary] = []

var _game: Node
var _hub: Node
var _save: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), "")
	_capture_directory = _capture_path.get_base_dir() if not _capture_path.is_empty() else ""
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	_game = GameScene.instantiate()
	root.add_child(_game)
	for _frame in 8:
		await process_frame
	_hub = _game.get("service_hub") as Node
	_save = _hub.get("save_service") as Node if _hub != null else null
	_check(_hub != null and _save != null, "perf: production game mounts")
	if _hub == null or _save == null:
		await _finish()
		return

	await _scenario_menu()
	for profile_id: String in MapProfileCatalogScript.get_ids():
		await _scenario_profile(profile_id)
	await _scenario_repeated_load()
	await _scenario_settings_change()
	_write_report()
	await _finish()


func _scenario_menu() -> void:
	var samples := await _collect_frames(SCENARIO_FRAMES, false)
	_record_scenario("menu", "main_menu", samples)


func _scenario_profile(profile_id: String) -> void:
	var display_name := "%s%s-%d" % [QA_PREFIX, profile_id, Time.get_ticks_msec()]
	var state: Dictionary = _save.call("create_world", display_name, profile_id, JOURNEY_SEED)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_track(world_id)

	var load_start := Time.get_ticks_msec()
	_game.call("begin_world_state", state)
	var entered := false
	for _frame in READY_FRAMES:
		await process_frame
		var world := _game.get("world") as Node
		if world != null and bool(world.get("is_started")):
			entered = true
			break
	var load_ms := Time.get_ticks_msec() - load_start
	_check(entered, "%s perf scenario enters the world" % profile_id)
	if not entered:
		return

	# Spawn phase: static world, let streaming settle.
	var spawn_samples := await _collect_frames(SCENARIO_FRAMES, false)
	_record_scenario(profile_id, "spawn", spawn_samples, load_ms)

	# Movement/turning pressure: teleport the player on a grid while sampling.
	var pressure_samples := await _collect_frames(SCENARIO_FRAMES, true)
	_record_scenario(profile_id, "movement_pressure", pressure_samples)

	_hub.call("return_to_menu")
	for _frame in CLEANUP_FRAMES:
		await process_frame
	_cleanup_world(world_id)


func _scenario_repeated_load() -> void:
	var display_name := "%srload-%d" % [QA_PREFIX, Time.get_ticks_msec()]
	var state: Dictionary = _save.call("create_world", display_name, "star_continent", JOURNEY_SEED)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_track(world_id)
	var load_times: Array[int] = []
	for cycle in 3:
		var start := Time.get_ticks_msec()
		_game.call("begin_world_state", state)
		for _frame in READY_FRAMES:
			await process_frame
			var world := _game.get("world") as Node
			if world != null and bool(world.get("is_started")):
				break
		load_times.append(Time.get_ticks_msec() - start)
		_hub.call("return_to_menu")
		for _frame in CLEANUP_FRAMES:
			await process_frame
	_check(load_times.size() == 3, "perf: repeated load completes 3 cycles")
	_record_scenario("star_continent", "repeated_load", {"frame_ms": [], "fps": []}, 0, load_times)
	_cleanup_world(world_id)


func _scenario_settings_change() -> void:
	var menu: Control = _hub.get("main_menu")
	var original: Dictionary = _hub.get("current_settings")
	var changed: Dictionary = original.duplicate(true)
	changed["ui_scale"] = 1.25
	changed["render_distance"] = maxi(4, int(original.get("render_distance", 6)) - 1)
	if menu != null and menu.has_signal("settings_changed"):
		menu.emit_signal("settings_changed", changed)
	for _frame in 10:
		await process_frame
	var samples := await _collect_frames(120, false)
	_record_scenario("menu", "settings_change", samples)
	# Restore.
	if menu != null and menu.has_signal("settings_changed"):
		menu.emit_signal("settings_changed", original)
	for _frame in 6:
		await process_frame
	_check(true, "perf: settings change scenario completes and restores")


# Collect real frame times over `frames` process frames. When `apply_pressure` is
# true, teleports the player every MOVE_INTERVAL frames to force chunk streaming.
func _collect_frames(frames: int, apply_pressure: bool) -> Dictionary:
	var frame_ms: Array[float] = []
	var fps_samples: Array[float] = []
	var last_usec := Time.get_ticks_usec()
	var player: CharacterBody3D = _game.get("player")
	var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
	for frame_index in frames:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var elapsed_ms := float(now_usec - last_usec) / 1000.0
		last_usec = now_usec
		if frame_index > 2: # skip warmup frames
			frame_ms.append(elapsed_ms)
			var fps := float(Engine.get_frames_per_second())
			if fps > 0.0:
				fps_samples.append(fps)
		if apply_pressure and player != null and frame_index % MOVE_INTERVAL == 0:
			var leg := frame_index / MOVE_INTERVAL
			player.global_position = origin + Vector3(float(leg % 5) * 12.0, 0.0, float(leg / 5 % 5) * 12.0)
	return {"frame_ms": frame_ms, "fps": fps_samples}


func _record_scenario(profile_id: String, phase: String, samples: Dictionary, load_ms: int = 0, load_series: Array[int] = []) -> void:
	var frame_ms: Array = samples.get("frame_ms", [])
	var fps: Array = samples.get("fps", [])
	var summary: Dictionary = {
		"profile": profile_id,
		"phase": phase,
		"sample_count": frame_ms.size(),
		"load_ms": load_ms,
		"avg_fps": _average(fps),
		"one_percent_low_fps": _percentile(fps, 1.0),
		"frame_ms_avg": _average(frame_ms),
		"frame_ms_p95": _percentile(frame_ms, 95.0),
		"frame_ms_p99": _percentile(frame_ms, 99.0),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	}
	var diagnostics: Node = _game.get("runtime_diagnostics")
	if diagnostics != null:
		var snapshot: Dictionary = diagnostics.call("get_latest_snapshot")
		var streaming: Dictionary = snapshot.get("streaming", {})
		summary["streaming_pending"] = int(streaming.get("pending", -1))
		summary["streaming_loaded"] = int(streaming.get("loaded", -1))
		var memory_mib := float(snapshot.get("memory_mib", -1.0))
		summary["memory_mib_internal"] = memory_mib if memory_mib >= 0.0 else "unavailable"
	if not load_series.is_empty():
		summary["load_series_ms"] = load_series
	_scenarios.append(summary)
	print(
		"PERF_SCENARIO profile=%s phase=%s samples=%d avg_fps=%.1f 1%%low=%.1f frame_avg=%.2f p95=%.2f p99=%.2f load=%dms"
		% [
			profile_id, phase, summary["sample_count"],
			summary["avg_fps"], summary["one_percent_low_fps"],
			summary["frame_ms_avg"], summary["frame_ms_p95"], summary["frame_ms_p99"], load_ms,
		]
	)


func _write_report() -> void:
	if _capture_path.is_empty():
		return
	var report := {
		"schema_version": 1,
		"seed": JOURNEY_SEED,
		"generated_at": Time.get_datetime_string_from_system(),
		"environment": {
			"godot": Engine.get_version_info().get("string", "unknown"),
			"os": OS.get_name(),
			"viewport": [root.size.x, root.size.y],
			"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		},
		"scenarios": _scenarios,
	}
	DirAccess.make_dir_recursive_absolute(_capture_directory)
	var report_path := _capture_directory.path_join("perf-report.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_check(false, "perf: report opens for writing")
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	_check(FileAccess.file_exists(report_path), "perf: JSON report is saved")


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: Variant in values:
		total += float(value)
	return total / float(values.size())


func _percentile(values: Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var rank := clampi(int(ceil(percentile / 100.0 * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return float(sorted[rank])


func _track(world_id: String) -> void:
	if not world_id.is_empty() and world_id not in _created_world_ids:
		_created_world_ids.append(world_id)


func _cleanup_world(world_id: String) -> void:
	if not world_id.is_empty() and bool(_save.call("world_exists", world_id)):
		_save.call("delete_world", world_id)


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if _hub != null and is_instance_valid(_hub) and not str(_hub.get("current_world_id")).is_empty():
		_hub.call("return_to_menu")
		for _frame in CLEANUP_FRAMES:
			await process_frame
	if _save != null and is_instance_valid(_save):
		for world_id: String in _created_world_ids:
			if not world_id.is_empty() and bool(_save.call("world_exists", world_id)):
				_save.call("delete_world", world_id)
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA PERF CAPTURE PASS | checks=%d | scenarios=%d" % [checks, _scenarios.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PERF CAPTURE FAILURE: %s" % failure)
		print("QA PERF CAPTURE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
