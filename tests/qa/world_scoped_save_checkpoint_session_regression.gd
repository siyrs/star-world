extends SceneTree

const BaseTimelinePolicy = preload("res://src/save/save_checkpoint_timeline_policy.gd")
const ScopedTimelinePolicy = preload(
	"res://src/save/world_scoped_save_checkpoint_timeline_policy.gd"
)
const TimelineFormatter = preload("res://src/save/save_checkpoint_timeline_formatter.gd")
const ReportServiceScript = preload(
	"res://src/diagnostics/session_scoped_runtime_health_report_service.gd"
)

var checks := 0
var failures: Array[String] = []


class FakeSaveService:
	extends Node
	signal save_recovered(world_id: String, source: String)

	func get_catalog_diagnostics() -> Dictionary:
		return {}


class FakeAutosave:
	extends Node

	func get_snapshot() -> Dictionary:
		return {
			"enabled":true,
			"active":true,
			"paused":false,
			"pending":false,
			"saving":false,
			"interval_seconds":300.0,
			"next_in_seconds":90.0,
			"consecutive_failure_count":0,
			"last_retry_delay_seconds":0.0,
		}


class FakeHub:
	extends Node
	var save_service: Node
	var autosave_runtime_participant: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_scoped_projection_and_legacy_compatibility()
	await _test_service_world_entry_lifecycle()
	if failures.is_empty():
		print("QA WORLD-SCOPED SAVE CHECKPOINT SESSION PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA WORLD-SCOPED SAVE CHECKPOINT SESSION FAILURE: %s" % failure)
	print(
		"QA WORLD-SCOPED SAVE CHECKPOINT SESSION FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_scoped_projection_and_legacy_compatibility() -> void:
	var history: Array[Dictionary] = [
		BaseTimelinePolicy.create_event(1, &"manual", "world-a", true, 1000, 4096, 1000),
		BaseTimelinePolicy.create_event(2, &"autosave", "world-a", true, 1100, 4100, 1100),
		BaseTimelinePolicy.create_event(3, &"return_to_menu", "world-b", true, 1200, 4200, 1200),
		BaseTimelinePolicy.create_event(4, &"manual", "world-a", true, 1300, 4300, 1300),
	]
	var scoped: Dictionary = ScopedTimelinePolicy.project_timeline({
		"history":history,
		"reason_counts":{"manual":2, "autosave":1, "return_to_menu":1, "system":0},
		"current_world_id":"world-a",
		"current_world_session_sequence":3,
		"current_world_session_started_after_sequence":3,
		"captured_at_msec":2000,
	})
	_check(
		bool(scoped.get("world_session_scope_active", false)),
		"world-scoped projection activates only when an explicit entry boundary exists"
	)
	_check(
		int(scoped.get("history_count", 0)) == 4
		and int(scoped.get("current_session_history_count", 0)) == 1,
		"global checkpoint history is retained while the current entry exposes one event"
	)
	_check(
		int(scoped.get("last_current_session_event", {}).get("sequence", 0)) == 4,
		"same-world events from an earlier entry are excluded by the sequence boundary"
	)
	_check(
		int(scoped.get("current_world_history_count", 0)) == 1
		and int(scoped.get("last_current_world_event", {}).get("sequence", 0)) == 4,
		"compatibility aliases now carry current-entry semantics"
	)
	var empty_current: Dictionary = ScopedTimelinePolicy.project_timeline({
		"history":history,
		"reason_counts":{"manual":2, "autosave":1, "return_to_menu":1, "system":0},
		"current_world_id":"world-b",
		"current_world_session_sequence":4,
		"current_world_session_started_after_sequence":4,
		"captured_at_msec":2000,
	})
	var display := "\n".join(TimelineFormatter.format_f3(empty_current))
	_check(
		int(empty_current.get("history_count", 0)) == 4
		and int(empty_current.get("current_session_history_count", -1)) == 0,
		"a newly entered world keeps old global evidence without inheriting a checkpoint"
	)
	_check(
		display.contains("当前世界本次进入尚无保存记录")
		and not display.contains("最近检查点：手动保存成功")
		and not display.contains("最近检查点：返回主菜单保存成功"),
		"F3 never falls back to another world or an earlier entry while a world is active"
	)
	var legacy: Dictionary = ScopedTimelinePolicy.project_timeline({
		"history":history,
		"current_world_id":"world-a",
	})
	_check(
		not bool(legacy.get("world_session_scope_active", true))
		and int(legacy.get("current_session_history_count", 0)) == 3,
		"legacy unscoped snapshots preserve their previous world-id projection"
	)


func _test_service_world_entry_lifecycle() -> void:
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
	_check(report.setup(hub), "session-scoped report accepts the existing save and autosave ports")

	report.begin_world("world-a")
	var scope: Dictionary = report.get_world_session_scope_snapshot()
	_check(
		bool(scope.get("active", false))
		and int(scope.get("session_sequence", 0)) == 1
		and int(scope.get("started_after_save_sequence", -1)) == 0,
		"first world entry establishes session one at the current save sequence"
	)
	report.record_save_result("world-a", true, 1000, 4096, &"manual")
	var timeline: Dictionary = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", 0)) == 1
		and int(timeline.get("current_session_history_count", 0)) == 1,
		"first world checkpoint enters both global and current-entry history"
	)

	report.end_world()
	report.begin_world("world-b")
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", 0)) == 1
		and int(timeline.get("current_session_history_count", -1)) == 0
		and int(timeline.get("current_world_session_sequence", 0)) == 2,
		"switching worlds preserves old evidence but starts with an empty current entry"
	)
	_check(
		"\n".join(TimelineFormatter.format_f3(timeline)).contains(
			"当前世界本次进入尚无保存记录"
		),
		"new-world F3 explicitly reports that this entry has not saved yet"
	)
	report.record_save_result("world-b", true, 1200, 5000, &"autosave")
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("current_session_history_count", 0)) == 1
		and str(timeline.get("last_current_session_event", {}).get("world_id", "")) == "world-b",
		"world B records only its own current-entry checkpoint"
	)

	report.end_world()
	report.begin_world("world-a")
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", 0)) == 2
		and int(timeline.get("current_session_history_count", -1)) == 0
		and int(timeline.get("current_world_session_sequence", 0)) == 3,
		"re-entering the same world excludes checkpoints from its previous entry"
	)
	report.record_save_result("world-a", true, 1400, 6000, &"system")
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", 0)) == 3
		and int(timeline.get("current_session_history_count", 0)) == 1
		and int(timeline.get("last_current_session_event", {}).get("sequence", 0)) == 3,
		"same-world re-entry receives only the newly recorded checkpoint"
	)

	report.clear_session_counters()
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", -1)) == 0
		and int(timeline.get("current_session_history_count", -1)) == 0
		and int(timeline.get("current_world_session_sequence", 0)) == 1,
		"explicit session reset clears global evidence and re-bases the active world entry"
	)
	report.record_save_result("world-a", true, 1600, 7000, &"manual")
	timeline = report.get_save_timeline_snapshot()
	_check(
		int(timeline.get("history_count", 0)) == 1
		and int(timeline.get("current_session_history_count", 0)) == 1
		and int(timeline.get("last_current_session_event", {}).get("sequence", 0)) == 1,
		"saving after explicit reset converges from a clean sequence without losing scope"
	)

	report.shutdown()
	host.queue_free()
	for _frame in 4:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
