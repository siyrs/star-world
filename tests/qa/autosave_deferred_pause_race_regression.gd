extends SceneTree

const AutosaveRuntimeScript = preload(
	"res://src/save/autosave_runtime_participant.gd"
)

var checks := 0
var failures: Array[String] = []


class FakePauseService:
	extends Node
	signal pause_changed(paused: bool)

	var paused := false

	func set_paused(value: bool) -> void:
		if paused == value:
			return
		paused = value
		pause_changed.emit(paused)

	func is_paused() -> bool:
		return paused


class FakeHub:
	extends Node
	signal world_save_completed(world_id: String)
	signal settings_applied(settings: Dictionary)

	var current_settings := {"autosave_minutes":5}
	var simulation_pause: Node
	var current_world_id := "pause-race-world"
	var save_call_count := 0

	func save_current() -> bool:
		save_call_count += 1
		world_save_completed.emit(current_world_id)
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_pending_survives_pause_and_manual_save_cancels_it()
	if failures.is_empty():
		print("QA AUTOSAVE DEFERRED PAUSE RACE PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA AUTOSAVE DEFERRED PAUSE RACE FAILURE: %s" % failure)
	print(
		"QA AUTOSAVE DEFERRED PAUSE RACE FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_pending_survives_pause_and_manual_save_cancels_it() -> void:
	var host := Node.new()
	root.add_child(host)
	var hub := FakeHub.new()
	var pause := FakePauseService.new()
	var runtime = AutosaveRuntimeScript.new()
	host.add_child(hub)
	hub.add_child(pause)
	hub.add_child(runtime)
	hub.simulation_pause = pause
	await process_frame
	_check(runtime.install(hub), "autosave runtime installs against the pause-race fixture")
	runtime.begin_world({"metadata":{"id":hub.current_world_id}})
	runtime.activate()
	runtime.set_process(false)
	runtime.configure_interval_minutes(1.0 / 60.0)

	_check(
		bool(runtime.advance_active_time(1.0)),
		"one active second schedules the deferred autosave boundary"
	)
	pause.set_paused(true)
	for _frame in 3:
		await process_frame
	var paused_snapshot: Dictionary = runtime.get_snapshot()
	_check(
		hub.save_call_count == 0
		and bool(paused_snapshot.get("pending", false))
		and int(paused_snapshot.get("attempt_count", 0)) == 0,
		"pausing before deferred flush preserves pending without writing"
	)

	pause.set_paused(false)
	for _frame in 4:
		await process_frame
	var resumed_snapshot: Dictionary = runtime.get_snapshot()
	_check(
		hub.save_call_count == 1
		and int(resumed_snapshot.get("attempt_count", 0)) == 1
		and int(resumed_snapshot.get("success_count", 0)) == 1,
		"resume flushes the preserved boundary exactly once"
	)
	_check(
		not bool(resumed_snapshot.get("pending", true))
		and is_equal_approx(
			float(resumed_snapshot.get("next_in_seconds", 0.0)), 1.0
		),
		"resumed save starts a complete next interval without losing a frame"
	)

	_check(
		bool(runtime.advance_active_time(1.0)),
		"a second boundary can be queued before a paused manual save"
	)
	pause.set_paused(true)
	for _frame in 3:
		await process_frame
	_check(
		bool(runtime.get_snapshot().get("pending", false)),
		"second deferred boundary remains pending during pause"
	)
	_check(hub.save_current(), "paused manual save succeeds through the authoritative fixture")
	var manual_snapshot: Dictionary = runtime.get_snapshot()
	_check(
		not bool(manual_snapshot.get("pending", true))
		and int(manual_snapshot.get("manual_reset_count", 0)) == 1,
		"manual save cancels the paused pending boundary and resets the schedule"
	)
	pause.set_paused(false)
	for _frame in 4:
		await process_frame
	var final_snapshot: Dictionary = runtime.get_snapshot()
	_check(
		hub.save_call_count == 2
		and int(final_snapshot.get("attempt_count", 0)) == 1
		and int(final_snapshot.get("success_count", 0)) == 1,
		"resume after manual cancellation does not duplicate the autosave"
	)
	_check(
		is_equal_approx(float(final_snapshot.get("next_in_seconds", 0.0)), 1.0),
		"manual cancellation leaves one complete future interval"
	)

	runtime.shutdown()
	host.queue_free()
	for _frame in 8:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
