extends SceneTree

const SchedulePolicy = preload("res://src/save/autosave_schedule_policy.gd")
const TimelinePolicy = preload("res://src/save/save_checkpoint_timeline_policy.gd")
const ScopedTimelinePolicy = preload(
	"res://src/save/world_scoped_save_checkpoint_timeline_policy.gd"
)

const HOURS := 24
const INTERVAL_SECONDS := 5.0 * 60.0
const WINDOW_COUNT := HOURS * 12
const FAILURE_WINDOWS: Array[int] = [57, 144, 231]
const FAILURE_RETRY_DELAYS: Array[float] = [15.0, 60.0, 300.0]
const WORLD_IDS: Array[String] = [
	"scale-world-a",
	"scale-world-b",
	"scale-world-c",
	"scale-world-d",
	"scale-world-e",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_twenty_four_hour_autosave_checkpoint_convergence()
	_test_cross_world_entry_scope_after_rollover()
	if failures.is_empty():
		print("QA LONG TERM SCALE RECOVERY PASS | checks=%d | hours=%d | windows=%d" % [checks, HOURS, WINDOW_COUNT])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA LONG TERM SCALE RECOVERY FAILURE: %s" % failure)
	print("QA LONG TERM SCALE RECOVERY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_twenty_four_hour_autosave_checkpoint_convergence() -> void:
	var state := SchedulePolicy.create(INTERVAL_SECONDS)
	var history: Array[Dictionary] = []
	var dropped_count := 0
	var reason_counts := TimelinePolicy.empty_reason_counts()
	var sequence := 0
	var autosave_attempts := 0
	var autosave_successes := 0
	var autosave_failures := 0
	var manual_saves := 0
	for window_index in range(1, WINDOW_COUNT + 1):
		var due := SchedulePolicy.advance(state, INTERVAL_SECONDS)
		state = _result_state(due, state)
		_check(bool(due.get("due", false)), "window %03d reaches exactly one pending autosave boundary" % window_index)
		if FAILURE_WINDOWS.has(window_index):
			for retry_delay: float in FAILURE_RETRY_DELAYS:
				autosave_attempts += 1
				autosave_failures += 1
				sequence += 1
				var failed_event := TimelinePolicy.create_event(
					sequence,
					&"autosave",
					WORLD_IDS[(window_index - 1) % WORLD_IDS.size()],
					false,
					2000 + autosave_attempts,
					8192 + autosave_attempts,
					sequence * 1000
				)
				var before_size := history.size()
				history = TimelinePolicy.append_bounded(history, failed_event)
				dropped_count += 1 if before_size == TimelinePolicy.MAX_EVENTS else 0
				reason_counts["autosave"] = int(reason_counts.get("autosave", 0)) + 1
				state = SchedulePolicy.record_failure(state, retry_delay)
				var retry_due := SchedulePolicy.advance(state, retry_delay)
				state = _result_state(retry_due, state)
				_check(
					bool(retry_due.get("due", false)),
					"failure window %03d reaches the bounded %.0f-second retry" % [window_index, retry_delay]
				)
		autosave_attempts += 1
		autosave_successes += 1
		sequence += 1
		var success_event := TimelinePolicy.create_event(
			sequence,
			&"autosave",
			WORLD_IDS[(window_index - 1) % WORLD_IDS.size()],
			true,
			1800 + autosave_attempts,
			9000 + window_index,
			sequence * 1000
		)
		var before_success_size := history.size()
		history = TimelinePolicy.append_bounded(history, success_event)
		dropped_count += 1 if before_success_size == TimelinePolicy.MAX_EVENTS else 0
		reason_counts["autosave"] = int(reason_counts.get("autosave", 0)) + 1
		state = SchedulePolicy.record_success(state)
		if window_index % 48 == 0:
			manual_saves += 1
			sequence += 1
			var manual_event := TimelinePolicy.create_event(
				sequence,
				&"manual",
				WORLD_IDS[(window_index - 1) % WORLD_IDS.size()],
				true,
				1500 + manual_saves,
				10000 + manual_saves,
				sequence * 1000
			)
			var before_manual_size := history.size()
			history = TimelinePolicy.append_bounded(history, manual_event)
			dropped_count += 1 if before_manual_size == TimelinePolicy.MAX_EVENTS else 0
			reason_counts["manual"] = int(reason_counts.get("manual", 0)) + 1
			state = SchedulePolicy.record_manual_save(state)
		var window_snapshot := SchedulePolicy.snapshot(state)
		_check(
			not bool(window_snapshot.get("pending", true))
			and int(history.size()) <= TimelinePolicy.MAX_EVENTS,
			"window %03d converges to one non-pending schedule and a bounded timeline" % window_index
		)

	var snapshot := SchedulePolicy.snapshot(state)
	var expected_attempts := WINDOW_COUNT + FAILURE_WINDOWS.size() * FAILURE_RETRY_DELAYS.size()
	var expected_events := expected_attempts + manual_saves
	_check(autosave_attempts == expected_attempts, "twenty-four-hour campaign records the exact autosave attempt count")
	_check(autosave_successes == WINDOW_COUNT, "every five-minute window eventually commits exactly one successful checkpoint")
	_check(autosave_failures == 9, "three bounded failure bursts produce exactly nine failed attempts")
	_check(manual_saves == 6, "one manual save interleaves every four active hours")
	_check(
		int(snapshot.get("consecutive_failure_count", -1)) == 0
		and is_zero_approx(float(snapshot.get("last_retry_delay_seconds", -1.0))),
		"final recovery clears all transient backoff pressure"
	)
	_check(
		int(snapshot.get("window_sequence", 0)) == WINDOW_COUNT + manual_saves,
		"successful autosaves and manual saves advance one exact persistent-free window sequence"
	)
	_check(
		int(snapshot.get("discarded_overshoot_seconds", -1)) == 0
		and float(snapshot.get("max_carried_overshoot_seconds", 0.0)) <= SchedulePolicy.MAX_CARRY_SECONDS,
		"production-sized long-session steps never create a catch-up storm"
	)
	_check(history.size() == TimelinePolicy.MAX_EVENTS, "checkpoint history remains at the exact twelve-event hard limit")
	_check(dropped_count == expected_events - TimelinePolicy.MAX_EVENTS, "all older checkpoint events are evicted exactly once")
	_check(
		int(reason_counts.get("autosave", 0)) == expected_attempts
		and int(reason_counts.get("manual", 0)) == manual_saves,
		"reason counters retain every attempt even while display history rolls over"
	)
	var projected := TimelinePolicy.project_timeline({
		"history": history,
		"history_dropped_count": dropped_count,
		"reason_counts": reason_counts,
		"current_world_id": WORLD_IDS[(WINDOW_COUNT - 1) % WORLD_IDS.size()],
		"autosave": snapshot,
	})
	_check(
		int(projected.get("history_count", 0)) == TimelinePolicy.MAX_EVENTS
		and int(projected.get("history_dropped_count", 0)) == dropped_count,
		"projected long-session timeline preserves bounded history and cumulative eviction evidence"
	)


func _test_cross_world_entry_scope_after_rollover() -> void:
	var history: Array[Dictionary] = []
	var sequence := 0
	for entry_index in 20:
		sequence += 1
		var world_id := WORLD_IDS[entry_index % WORLD_IDS.size()]
		history = TimelinePolicy.append_bounded(
			history,
			TimelinePolicy.create_event(
				sequence,
				&"autosave" if entry_index % 2 == 0 else &"manual",
				world_id,
				true,
				1000 + entry_index,
				4096 + entry_index,
				sequence * 1000
			)
		)
	var current_world := WORLD_IDS[0]
	var boundary := sequence
	for reason: StringName in [&"manual", &"autosave", &"return_to_menu"]:
		sequence += 1
		history = TimelinePolicy.append_bounded(
			history,
			TimelinePolicy.create_event(
				sequence,
				reason,
				current_world,
				true,
				2000 + sequence,
				8192 + sequence,
				sequence * 1000
			)
		)
	var scoped := ScopedTimelinePolicy.project_timeline({
		"history": history,
		"reason_counts": {"manual": 1, "autosave": 1, "return_to_menu": 1, "system": 0},
		"current_world_id": current_world,
		"current_world_session_sequence": 21,
		"current_world_session_started_after_sequence": boundary,
		"captured_at_msec": 99999,
	})
	_check(bool(scoped.get("world_session_scope_active", false)), "explicit cross-world entry activates current-session filtering")
	_check(
		int(scoped.get("history_count", 0)) == TimelinePolicy.MAX_EVENTS
		and int(scoped.get("current_session_history_count", 0)) == 3,
		"global rolled history is retained while the active entry exposes only three new checkpoints"
	)
	_check(
		int(scoped.get("last_current_session_event", {}).get("sequence", 0)) == sequence
		and str(scoped.get("last_current_session_event", {}).get("reason", "")) == "return_to_menu",
		"current-entry projection ends on its own explicit return-to-menu checkpoint"
	)
	for raw_event: Variant in scoped.get("current_session_history", []):
		_check(
			raw_event is Dictionary
			and str(raw_event.get("world_id", "")) == current_world
			and int(raw_event.get("sequence", 0)) > boundary,
			"current-entry history never leaks another world or an earlier visit"
		)
	var reset := ScopedTimelinePolicy.project_timeline({
		"history": [],
		"history_dropped_count": 0,
		"reason_counts": TimelinePolicy.empty_reason_counts(),
		"current_world_id": current_world,
		"current_world_session_sequence": 1,
		"current_world_session_started_after_sequence": 0,
	})
	_check(
		int(reset.get("history_count", -1)) == 0
		and int(reset.get("current_session_history_count", -1)) == 0,
		"explicit session reset converges without inheriting old global evidence"
	)


func _result_state(result: Dictionary, fallback: Dictionary) -> Dictionary:
	var raw_state: Variant = result.get("state", fallback)
	return raw_state if raw_state is Dictionary else fallback


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
