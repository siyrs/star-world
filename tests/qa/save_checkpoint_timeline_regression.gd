extends SceneTree

const TimelinePolicy = preload("res://src/save/save_checkpoint_timeline_policy.gd")
const TimelineFormatter = preload("res://src/save/save_checkpoint_timeline_formatter.gd")
const ReportServiceScript = preload(
	"res://src/diagnostics/runtime_health_report_service.gd"
)
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeSaveService:
	extends Node
	signal save_recovered(world_id: String, source: String)

	func get_catalog_diagnostics() -> Dictionary:
		return {}


class FakeAutosave:
	extends Node
	var snapshot := {
		"enabled":true,
		"active":true,
		"paused":false,
		"pending":false,
		"saving":false,
		"interval_seconds":300.0,
		"next_in_seconds":125.0,
		"consecutive_failure_count":0,
		"last_retry_delay_seconds":0.0,
	}

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)


class FakeHub:
	extends Node
	var save_service: Node
	var autosave_runtime_participant: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_bounds_and_strict_projection()
	await _test_report_service_exact_counts_and_lifecycle()
	await _test_production_reason_context_and_transience()
	if failures.is_empty():
		print("QA SAVE CHECKPOINT TIMELINE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE CHECKPOINT TIMELINE FAILURE: %s" % failure)
		print(
			"QA SAVE CHECKPOINT TIMELINE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_policy_bounds_and_strict_projection() -> void:
	var history: Array[Dictionary] = []
	var reasons: Array[StringName] = [
		TimelinePolicy.REASON_MANUAL,
		TimelinePolicy.REASON_AUTOSAVE,
		TimelinePolicy.REASON_RETURN_TO_MENU,
		&"unexpected",
	]
	for index in 20:
		var event := TimelinePolicy.create_event(
			index + 1,
			reasons[index % reasons.size()],
			"policy-world",
			index != 7,
			1000 + index,
			4096 + index,
			2000 + index
		)
		event["payload"] = {"must_not_escape":true}
		history = TimelinePolicy.append_bounded(history, event)
	_check(
		history.size() == TimelinePolicy.MAX_EVENTS,
		"checkpoint policy retains exactly twelve recent events"
	)
	_check(
		int(history.front().get("sequence", 0)) == 9
		and int(history.back().get("sequence", 0)) == 20,
		"bounded history drops the oldest eight events deterministically"
	)
	var timeline := TimelinePolicy.project_timeline({
		"history":history,
		"history_dropped_count":8,
		"reason_counts":{"manual":5, "autosave":5, "return_to_menu":5, "system":5},
		"current_world_id":"policy-world",
		"autosave":{"enabled":true, "active":true, "next_in_seconds":125.0},
		"captured_at_msec":5000,
	})
	_check(
		int(timeline.get("current_world_history_count", 0)) == TimelinePolicy.MAX_EVENTS,
		"current-world projection keeps every retained matching checkpoint"
	)
	_check(
		str(timeline.get("last_event", {}).get("reason", "")) == "system",
		"unknown save reasons normalize to the bounded system category"
	)
	var serialized := JSON.stringify(timeline)
	_check(
		not serialized.contains("must_not_escape") and not serialized.contains("payload"),
		"timeline projection strips arbitrary event payloads"
	)
	var display := "\n".join(TimelineFormatter.format_f3(timeline))
	for phrase: String in ["保存来源", "检查点历史", "最近检查点", "自动保存"]:
		_check(display.contains(phrase), "timeline formatter renders %s" % phrase)


func _test_report_service_exact_counts_and_lifecycle() -> void:
	var host := Node.new()
	root.add_child(host)
	var hub := FakeHub.new()
	var save := FakeSaveService.new()
	var autosave := FakeAutosave.new()
	var report = ReportServiceScript.new()
	for node: Node in [hub, save, autosave, report]:
		host.add_child(node)
	hub.save_service = save
	hub.autosave_runtime_participant = autosave
	await process_frame
	_check(report.setup(hub), "timeline report service accepts bounded save and autosave ports")
	report.begin_world("timeline-world")
	var reasons: Array[StringName] = [
		TimelinePolicy.REASON_MANUAL,
		TimelinePolicy.REASON_AUTOSAVE,
		TimelinePolicy.REASON_RETURN_TO_MENU,
		&"invalid-reason",
	]
	for index in 15:
		report.record_save_result(
			"timeline-world",
			index != 7,
			2000 + index,
			8192 + index,
			reasons[index % reasons.size()]
		)
	var timeline: Dictionary = report.get_save_timeline_snapshot()
	var counts: Dictionary = timeline.get("reason_counts", {})
	_check(
		int(counts.get("manual", 0)) == 4
		and int(counts.get("autosave", 0)) == 4
		and int(counts.get("return_to_menu", 0)) == 4
		and int(counts.get("system", 0)) == 3,
		"reason counters remain exact after bounded event eviction"
	)
	_check(
		int(timeline.get("history_count", 0)) == 12
		and int(timeline.get("history_dropped_count", 0)) == 3,
		"fifteen attempts retain twelve events and exact dropped history count"
	)
	_check(
		str(timeline.get("last_event", {}).get("reason", "")) == "return_to_menu"
		and int(timeline.get("last_event", {}).get("sequence", 0)) == 15,
		"latest checkpoint preserves exact sequence and source"
	)
	_check(
		is_equal_approx(
			float(timeline.get("autosave", {}).get("next_in_seconds", 0.0)), 125.0
		),
		"timeline projects the bounded autosave countdown without copying runtime internals"
	)
	var report_snapshot: Dictionary = report.get_snapshot()
	_check(
		report_snapshot.get("save_timeline", {}) is Dictionary
		and int(report_snapshot.get("save", {}).get("failure_count", 0)) == 1,
		"unified health snapshot carries timeline and exact failed-save evidence"
	)
	report.end_world()
	timeline = report.get_save_timeline_snapshot()
	_check(
		str(timeline.get("current_world_id", "")).is_empty()
		and int(timeline.get("history_count", 0)) == 12,
		"ending a world clears active identity without discarding session history"
	)
	report.clear_session_counters()
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", -1)) == 0
		and int(timeline.get("history_dropped_count", -1)) == 0,
		"explicit session reset clears bounded checkpoint evidence"
	)
	report.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_reason_context_and_transience() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var save: Node = hub.get("save_service") as Node
	var report: Node = hub.get("runtime_health_report_service") as Node
	_check(save != null and report != null, "production hub exposes authoritative save and timeline report")
	var state: Dictionary = save.call(
		"create_world",
		"checkpoint-timeline-%d" % Time.get_ticks_msec(),
		"star_continent",
		430726
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "production timeline regression creates a temporary world")
	if world_id.is_empty():
		await _finish_production(hub, save, world_id)
		return
	hub.call("_begin_world", state)
	_check(bool(hub.call("save_current")), "default production save records a manual checkpoint")
	_check(
		bool(hub.call("save_current_with_reason", &"system")),
		"explicit system save reuses the same authoritative transaction"
	)
	var loaded: Dictionary = save.call("load_world", world_id)
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("save_timeline")
		and not serialized.contains("checkpoint_history")
		and not serialized.contains("save_checkpoint"),
		"checkpoint timeline remains transient and never enters world.json"
	)
	hub.call("return_to_menu")
	var timeline: Dictionary = report.call("get_save_timeline_snapshot")
	var counts: Dictionary = timeline.get("reason_counts", {})
	_check(
		int(counts.get("manual", 0)) == 1
		and int(counts.get("system", 0)) == 1
		and int(counts.get("return_to_menu", 0)) == 1,
		"production context distinguishes manual, system and final return saves"
	)
	_check(
		str(timeline.get("current_world_id", "")).is_empty(),
		"successful return clears the runtime health world identity"
	)
	await _finish_production(hub, save, world_id)


func _finish_production(hub: Node, save: Node, world_id: String) -> void:
	if save != null and is_instance_valid(save) and not world_id.is_empty():
		if bool(save.call("world_exists", world_id)):
			save.call("delete_world", world_id)
	if hub != null and is_instance_valid(hub):
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
		hub.queue_free()
	for _frame in 8:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
