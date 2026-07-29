extends SceneTree

const SchedulePolicy = preload("res://src/save/autosave_schedule_policy.gd")
const TimelineFormatter = preload("res://src/save/save_checkpoint_timeline_formatter.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

const EIGHT_HOURS_SECONDS := 8.0 * 60.0 * 60.0
const FIVE_MINUTES_SECONDS := 5.0 * 60.0
const TEN_MINUTES_SECONDS := 10.0 * 60.0
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []


class FailingSaveService:
	extends Node

	func save_world(_world_id: String, _state: Dictionary) -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bounded_projection_and_overshoot_carry()
	_test_eight_hour_mixed_frame_schedule()
	await _test_production_rollover_failure_and_recovery()
	if failures.is_empty():
		print("QA AUTOSAVE LONG SESSION PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA AUTOSAVE LONG SESSION FAILURE: %s" % failure)
	print(
		"QA AUTOSAVE LONG SESSION FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_bounded_projection_and_overshoot_carry() -> void:
	var projected := SchedulePolicy.project({
		"interval_microseconds":999999999999,
		"remaining_microseconds":-50,
		"fractional_microseconds":5.0,
		"pending":true,
		"current_carry_microseconds":999999999,
		"consecutive_failure_count":-4,
	})
	_check(
		int(projected.get("interval_microseconds", 0))
		== SchedulePolicy.MAX_INTERVAL_MICROSECONDS,
		"schedule projection clamps the interval to the fifteen-minute hard limit"
	)
	_check(
		int(projected.get("remaining_microseconds", -1)) == 0
		and absf(float(projected.get("fractional_microseconds", 1.0))) <= 0.5
		and int(projected.get("consecutive_failure_count", -1)) == 0,
		"schedule projection repairs pending, fractional and failure state deterministically"
	)

	var state := SchedulePolicy.create(FIVE_MINUTES_SECONDS)
	var due := SchedulePolicy.advance(state, FIVE_MINUTES_SECONDS + 0.75)
	state = _result_state(due, state)
	_check(
		bool(due.get("due", false)),
		"crossing a checkpoint boundary produces one due transition"
	)
	var boundary_snapshot := SchedulePolicy.snapshot(state)
	_check(
		is_equal_approx(
			float(boundary_snapshot.get("current_carried_overshoot_seconds", 0.0)),
			0.75
		),
		"sub-frame active time beyond the boundary is retained instead of discarded"
	)
	state = SchedulePolicy.record_success(state)
	var carried_snapshot := SchedulePolicy.snapshot(state)
	_check(
		is_equal_approx(
			float(carried_snapshot.get("next_in_seconds", 0.0)),
			FIVE_MINUTES_SECONDS - 0.75
		),
		"a successful checkpoint applies the carried overshoot to the next window"
	)

	due = SchedulePolicy.advance(state, FIVE_MINUTES_SECONDS - 0.75)
	state = _result_state(due, state)
	_check(
		bool(due.get("due", false)),
		"the carry-adjusted second window reaches its exact active-time boundary"
	)
	state = SchedulePolicy.record_success(state)
	_check(
		is_equal_approx(
			float(SchedulePolicy.snapshot(state).get("next_in_seconds", 0.0)),
			FIVE_MINUTES_SECONDS
		),
		"an exact boundary restores a complete next interval"
	)

	due = SchedulePolicy.advance(state, 3600.0)
	state = _result_state(due, state)
	var huge_delta_snapshot := SchedulePolicy.snapshot(state)
	_check(
		bool(due.get("due", false))
		and float(huge_delta_snapshot.get("current_carried_overshoot_seconds", 0.0))
		<= SchedulePolicy.MAX_CARRY_SECONDS,
		"unexpected giant deltas retain at most one production-frame carry"
	)
	_check(
		float(huge_delta_snapshot.get("discarded_overshoot_seconds", 0.0)) > 0.0,
		"excess catch-up time is explicitly counted instead of scheduling a save storm"
	)
	state = SchedulePolicy.record_success(state)
	_check(
		float(SchedulePolicy.snapshot(state).get("next_in_seconds", 0.0))
		>= FIVE_MINUTES_SECONDS - SchedulePolicy.MAX_CARRY_SECONDS,
		"bounded catch-up never creates multiple immediate checkpoints"
	)


func _test_eight_hour_mixed_frame_schedule() -> void:
	var state := SchedulePolicy.create(FIVE_MINUTES_SECONDS)
	var pattern: Array[float] = [
		0.0166666667,
		0.0333333333,
		0.125,
		0.25,
		0.5,
		0.9,
		1.0,
	]
	var remaining_total := EIGHT_HOURS_SECONDS
	var iteration := 0
	var due_count := 0
	while remaining_total > 0.0000001 and iteration < 200000:
		var step := minf(pattern[iteration % pattern.size()], remaining_total)
		var result := SchedulePolicy.advance(state, step)
		state = _result_state(result, state)
		remaining_total = maxf(0.0, remaining_total - step)
		if bool(result.get("due", false)):
			due_count += 1
			state = SchedulePolicy.record_success(state)
		iteration += 1
	var snapshot := SchedulePolicy.snapshot(state)
	_check(
		iteration < 200000 and remaining_total <= 0.0000001,
		"eight-hour mixed-frame simulation converges within a bounded iteration budget"
	)
	_check(
		due_count == 96,
		"eight active hours at five-minute intervals produce exactly ninety-six checkpoints"
	)
	_check(
		absf(float(snapshot.get("next_in_seconds", 0.0)) - FIVE_MINUTES_SECONDS)
		<= 0.002,
		"mixed frame deltas finish with no cumulative checkpoint drift"
	)
	_check(
		int(snapshot.get("carried_overshoot_count", 0)) > 0
		and float(snapshot.get("max_carried_overshoot_seconds", 0.0))
		<= SchedulePolicy.MAX_CARRY_SECONDS,
		"long-session precision uses bounded carry on real frame-boundary crossings"
	)
	_check(
		is_zero_approx(float(snapshot.get("discarded_overshoot_seconds", -1.0))),
		"production-sized frame deltas never discard active time"
	)
	_check(
		int(snapshot.get("window_sequence", 0)) == 96,
		"schedule window sequence remains exact across the full eight-hour run"
	)


func _test_production_rollover_failure_and_recovery() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var save: Node = hub.get("save_service") as Node
	var runtime: Node = hub.get("autosave_runtime_participant") as Node
	var report: Node = hub.get("runtime_health_report_service") as Node
	_check(
		save != null and runtime != null and report != null,
		"production hub exposes save, autosave and session-scoped health services"
	)
	if save == null or runtime == null or report == null:
		await _finish_production(hub, save, "", null)
		return
	var state: Dictionary = save.call(
		"create_world",
		"qa-autosave-long-session-%d" % Time.get_ticks_msec(),
		"star_continent",
		500729
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "production long-session regression creates a temporary world")
	if world_id.is_empty():
		await _finish_production(hub, save, world_id, null)
		return
	hub.call("_begin_world", state)
	runtime.call("activate")
	runtime.set_process(false)
	runtime.call("configure_interval_minutes", TEN_MINUTES_SECONDS / 60.0)
	var apples_before := int(hub.inventory.call("count_item", "apple"))

	for checkpoint_index in 8:
		hub.inventory.call("add_item", "apple", 1)
		_check(
			bool(runtime.call("advance_active_time", TEN_MINUTES_SECONDS)),
			"accelerated production interval %d schedules one authoritative autosave"
			% (checkpoint_index + 1)
		)
		await _settle_deferred()
	var pre_manual_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		int(pre_manual_snapshot.get("success_count", 0)) == 8
		and int(pre_manual_snapshot.get("attempt_count", 0)) == 8,
		"eight accelerated intervals produce eight real successful save transactions"
	)

	hub.inventory.call("add_item", "apple", 1)
	_check(
		bool(hub.call("save_current")),
		"one real manual save interleaves with the same authoritative transaction"
	)
	var post_manual_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		int(post_manual_snapshot.get("manual_reset_count", 0)) >= 1
		and is_equal_approx(
			float(post_manual_snapshot.get("next_in_seconds", 0.0)),
			TEN_MINUTES_SECONDS
		),
		"manual save resets the pure schedule without creating a duplicate checkpoint"
	)

	var failing_save := FailingSaveService.new()
	failing_save.name = "LongSessionFailingSave"
	hub.add_child(failing_save)
	hub.set("save_service", failing_save)
	hub.inventory.call("add_item", "apple", 3)
	_check(
		bool(runtime.call("advance_active_time", TEN_MINUTES_SECONDS)),
		"the first post-manual interval reaches the failure fixture"
	)
	await _settle_deferred()
	for retry_delay: float in [15.0, 60.0]:
		_check(
			bool(runtime.call("advance_active_time", retry_delay)),
			"failed production autosave retries after %.0f active seconds" % retry_delay
		)
		await _settle_deferred()
	var failed_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		int(failed_snapshot.get("consecutive_failure_count", 0)) == 3
		and is_equal_approx(
			float(failed_snapshot.get("last_retry_delay_seconds", 0.0)),
			300.0
		),
		"three real failures reach the bounded 300-second retry tier"
	)
	var failed_timeline: Dictionary = report.call("get_save_timeline_snapshot")
	var failed_f3 := "\n".join(TimelineFormatter.format_f3(failed_timeline))
	_check(
		failed_f3.contains("连续失败 3 次")
		and failed_f3.contains("5分00秒后重试"),
		"F3 exposes the active failure streak and exact retry window"
	)

	hub.set("save_service", save)
	failing_save.queue_free()
	await process_frame
	_check(
		bool(runtime.call("advance_active_time", 300.0)),
		"restoring the authoritative save service schedules one bounded recovery attempt"
	)
	await _settle_deferred()
	var recovered_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		int(recovered_snapshot.get("attempt_count", 0)) == 12
		and int(recovered_snapshot.get("success_count", 0)) == 9
		and int(recovered_snapshot.get("failure_count", 0)) == 3,
		"eight successes, three failures and one recovery produce exact runtime counters"
	)
	_check(
		int(recovered_snapshot.get("consecutive_failure_count", -1)) == 0
		and is_zero_approx(
			float(recovered_snapshot.get("last_retry_delay_seconds", -1.0))
		),
		"successful recovery clears transient failure pressure"
	)
	var loaded: Dictionary = save.call("load_world", world_id)
	_check(
		_count_inventory_item(loaded.get("inventory", {}), "apple")
		== apples_before + 12,
		"recovery persists every mutation accumulated before and during failed attempts"
	)
	var timeline: Dictionary = report.call("get_save_timeline_snapshot")
	var counts: Dictionary = timeline.get("reason_counts", {})
	_check(
		int(counts.get("manual", 0)) == 1
		and int(counts.get("autosave", 0)) == 12,
		"save timeline distinguishes one manual checkpoint and twelve autosave attempts"
	)
	_check(
		int(timeline.get("history_count", 0)) == 12
		and int(timeline.get("history_dropped_count", 0)) == 1
		and int(timeline.get("current_session_history_count", 0)) == 12,
		"thirteen production checkpoints roll over to the exact twelve-event session budget"
	)
	_check(
		str(timeline.get("last_current_session_event", {}).get("reason", ""))
		== "autosave"
		and bool(timeline.get("last_current_session_event", {}).get("success", false)),
		"the current world entry ends on the successful recovered autosave"
	)
	var recovered_f3 := "\n".join(TimelineFormatter.format_f3(timeline))
	_check(
		recovered_f3.contains("最近检查点：自动保存成功")
		and not recovered_f3.contains("连续失败"),
		"F3 switches from active backoff to the recovered checkpoint fact"
	)
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("autosave_schedule")
		and not serialized.contains("carried_overshoot")
		and not serialized.contains("consecutive_failure_count"),
		"fixed-point scheduling and long-session diagnostics remain outside world.json"
	)
	await _finish_production(hub, save, world_id, runtime)


func _result_state(result: Dictionary, fallback: Dictionary) -> Dictionary:
	var raw_state: Variant = result.get("state", fallback)
	return raw_state if raw_state is Dictionary else fallback


func _count_inventory_item(serialized: Dictionary, item_id: String) -> int:
	var total := 0
	var raw_slots: Variant = serialized.get("slots", [])
	if raw_slots is not Array:
		return 0
	for raw_slot: Variant in raw_slots:
		if raw_slot is Dictionary and str(raw_slot.get("item_id", "")) == item_id:
			total += maxi(0, int(raw_slot.get("count", 0)))
	return total


func _settle_deferred() -> void:
	for _frame in 4:
		await process_frame


func _finish_production(
	hub: Node,
	save: Node,
	world_id: String,
	runtime: Node
) -> void:
	if hub != null and is_instance_valid(hub):
		if save != null and is_instance_valid(save):
			hub.set("save_service", save)
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in 8:
				await process_frame
	if save != null and is_instance_valid(save) and not world_id.is_empty():
		if bool(save.call("world_exists", world_id)):
			save.call("delete_world", world_id)
	if runtime != null and is_instance_valid(runtime):
		runtime.call("shutdown")
	if hub != null and is_instance_valid(hub):
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
		var accessibility: Node = hub.get("ui_accessibility") as Node
		if accessibility != null and accessibility.has_method("dispose"):
			accessibility.call("dispose")
		hub.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
