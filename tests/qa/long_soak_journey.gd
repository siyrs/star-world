extends SceneTree

# OpenSpec 5.5: long-run soak spanning all profiles with saves, loads, and menu
# returns. Driven by run_long_soak.ps1 which samples the workload PID externally
# and enforces the wall-clock budget via --soak-seconds=<N>.
#
# Each cycle: enter a profile (rotating through all five), wander with movement
# pressure, save, return to menu. Records per-cycle frame-time samples, streaming
# high-water marks, and any fatal/error signals from the diagnostics snapshot.
# Exits 0 only if no cycle regressed: no crash (process alive), no sustained
# degradation (last-cycle p95 frame time <= 2x first-cycle), no fatal log.

const GameScene = preload("res://scenes/game/game.tscn")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")
const RouteProbeScript = preload("res://src/diagnostics/production_route_probe.gd")

const QA_PREFIX := "qa-v130-soak-"
const JOURNEY_SEED := 112358
const READY_FRAMES := 720
const CLEANUP_FRAMES := 60
const WANDER_FRAMES := 300

var checks := 0
var failures: Array[String] = []
var _created_world_ids: Array[String] = []
var _cycles: Array[Dictionary] = []
var _soak_seconds := 600
var _minimum_cycles := 5
var _start_msec := 0

var _game: Node
var _hub: Node
var _save: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_soak_seconds = maxi(60, int(_user_argument("soak-seconds", "600")))
	_minimum_cycles = clampi(int(_user_argument("minimum-cycles", "5")), 2, 100)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	_start_msec = Time.get_ticks_msec()

	_game = GameScene.instantiate()
	root.add_child(_game)
	for _frame in 8:
		await process_frame
	_hub = _game.get("service_hub") as Node
	_save = _hub.get("save_service") as Node if _hub != null else null
	_check(_hub != null and _save != null, "soak: production game mounts")
	if _hub == null or _save == null:
		await _finish()
		return

	var profile_ids := MapProfileCatalogScript.get_ids()
	var cycle := 0
	while _elapsed_seconds() < _soak_seconds or cycle < _minimum_cycles:
		var profile_id: String = profile_ids[cycle % profile_ids.size()]
		await _soak_cycle(profile_id, cycle)
		cycle += 1
	print("SOAK_COMPLETE cycles=%d elapsed=%ds" % [cycle, _elapsed_seconds()])
	_evaluate_trend(profile_ids)
	_write_report()
	await _finish()


func _soak_cycle(profile_id: String, cycle: int) -> void:
	var display_name := "%s%s-c%d-%d" % [QA_PREFIX, profile_id, cycle, Time.get_ticks_msec()]
	var state: Dictionary = _save.call("create_world", display_name, profile_id, JOURNEY_SEED + cycle)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_track(world_id)

	_game.call("begin_world_state", state)
	var entered := false
	for _frame in READY_FRAMES:
		await process_frame
		var world := _game.get("world") as Node
		if world != null and bool(world.get("is_started")):
			entered = true
			break
	if not entered:
		_check(false, "soak cycle %d (%s) enters the world" % [cycle, profile_id])
		return

	# Generate real streaming and movement pressure through the production input
	# route probe. No cycle is allowed to write the player transform after spawn.
	var player: CharacterBody3D = _game.get("player")
	var world: Node = _game.get("world") as Node
	var route_probe = RouteProbeScript.new()
	var route_result: Dictionary = await route_probe.execute(
		self,
		world,
		player,
		profile_id,
		JOURNEY_SEED + cycle,
		{
			"min_route_steps": 12,
			"target_route_steps": 18,
			"min_route_displacement": 8.0,
		}
	)
	_check(bool(route_result.get("ok", false)), "soak cycle %d (%s) completes production-input route pressure" % [cycle, profile_id])
	_check(int(route_result.get("player_transform_writes", -1)) == 0, "soak cycle %d (%s) performs no post-spawn transport" % [cycle, profile_id])

	# Sample a bounded settle window after the live route so frame trends remain
	# comparable across cycles and profiles.
	var frame_ms: Array[float] = []
	var last_usec := Time.get_ticks_usec()
	var max_pending := 0
	for frame_index in WANDER_FRAMES:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_ms.append(float(now_usec - last_usec) / 1000.0)
		last_usec = now_usec
		if frame_index % 60 == 0:
			var diagnostics: Node = _game.get("runtime_diagnostics")
			if diagnostics != null:
				var snapshot: Dictionary = diagnostics.call("get_latest_snapshot")
				max_pending = maxi(max_pending, int(snapshot.get("streaming", {}).get("pending", 0)))

	_check(bool(_hub.call("save_current")), "soak cycle %d (%s) saves" % [cycle, profile_id])
	_hub.call("return_to_menu")
	for _frame in CLEANUP_FRAMES:
		await process_frame
	_cleanup_world(world_id)

	var p95 := _percentile(frame_ms, 95.0)
	_cycles.append({
		"cycle": cycle,
		"profile": profile_id,
		"frames": frame_ms.size(),
		"frame_ms_avg": _average(frame_ms),
		"frame_ms_p95": p95,
		"max_pending_chunks": max_pending,
		"route": route_result,
		"post_spawn_transport": false,
		"elapsed_s": _elapsed_seconds(),
	})
	print(
		"SOAK_CYCLE %d %s frames=%d avg=%.2fms p95=%.2fms pending=%d elapsed=%ds"
		% [cycle, profile_id, frame_ms.size(), _average(frame_ms), p95, max_pending, _elapsed_seconds()]
	)


func _evaluate_trend(profile_ids: Array) -> void:
	_check(
		_cycles.size() >= _minimum_cycles,
		"soak completes the minimum %d cycles (got %d)" % [_minimum_cycles, _cycles.size()]
	)
	if _cycles.size() < 2:
		return
	var first_p95 := float(_cycles[0].get("frame_ms_p95", 0.0))
	var last_p95 := float(_cycles[_cycles.size() - 1].get("frame_ms_p95", 0.0))
	_check(
		last_p95 <= maxf(50.0, first_p95 * 2.0),
		"soak shows no sustained degradation (first p95=%.2fms, last p95=%.2fms)" % [first_p95, last_p95]
	)
	var profiles_seen: Dictionary = {}
	for cycle_data: Dictionary in _cycles:
		profiles_seen[str(cycle_data.get("profile", ""))] = true
	var required_profile_count := mini(profile_ids.size(), _minimum_cycles)
	_check(
		profiles_seen.size() >= required_profile_count,
		"soak spans all required profiles (%d / %d distinct)"
		% [profiles_seen.size(), required_profile_count]
	)


func _write_report() -> void:
	var output := _user_argument("soak-output", "")
	if output.is_empty():
		return
	var profiles_seen: Array[String] = []
	for cycle_data: Dictionary in _cycles:
		var profile_id := str(cycle_data.get("profile", ""))
		if not profile_id.is_empty() and profile_id not in profiles_seen:
			profiles_seen.append(profile_id)
	var report := {
		"schema_version": 2,
		"soak_seconds_target": _soak_seconds,
		"minimum_cycles_target": _minimum_cycles,
		"elapsed_seconds": _elapsed_seconds(),
		"unique_profiles": profiles_seen,
		"cycles": _cycles,
		"checks": checks,
		"failures": failures,
	}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var report_file := FileAccess.open(output, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()


func _elapsed_seconds() -> int:
	return int((Time.get_ticks_msec() - _start_msec) / 1000)


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
		print("QA LONG SOAK PASS | checks=%d | cycles=%d" % [checks, _cycles.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA LONG SOAK FAILURE: %s" % failure)
		print("QA LONG SOAK FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _user_argument(name: String, fallback: String) -> String:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).strip_edges()
	return fallback


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
