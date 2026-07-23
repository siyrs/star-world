extends SceneTree

const Actions = preload("res://src/input/gameplay_input_actions.gd")
const ReportServiceScript = preload(
	"res://src/diagnostics/runtime_health_report_service.gd"
)
const TelemetryScript = preload("res://src/diagnostics/runtime_telemetry_service.gd")
const OverlayScript = preload("res://src/ui/diagnostics_overlay.gd")

var checks := 0
var failures: Array[String] = []


class FakeSnapshotNode extends Node:
	var snapshot: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_runtime_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_ecology_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_streaming_stats() -> Dictionary:
		return snapshot.duplicate(true)


class FakeSaveService extends Node:
	signal save_recovered(world_id: String, source: String)
	var catalog: Dictionary = {}

	func get_catalog_diagnostics() -> Dictionary:
		return catalog.duplicate(true)


class FakeInputContext extends Node:
	func get_context() -> StringName:
		return &"gameplay"


class FakeHub extends Node:
	var save_service: Node
	var machine_runtime: Node
	var agriculture_service: Node
	var husbandry_service: Node
	var animal_attraction_service: Node
	var animal_product_service: Node
	var creature_spawner: Node
	var pickup_stack_coordinator: Node
	var structural_integrity_service: Node
	var report_service: Node

	func get_runtime_health_snapshot() -> Dictionary:
		return (
			report_service.call("get_snapshot")
			if report_service != null and report_service.has_method("get_snapshot")
			else {}
		)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_read_only_aggregation_and_f3_surface()
	if failures.is_empty():
		print("QA RUNTIME HEALTH REPORT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RUNTIME HEALTH REPORT FAILURE: %s" % failure)
		print(
			"QA RUNTIME HEALTH REPORT FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_read_only_aggregation_and_f3_surface() -> void:
	Actions.ensure_default_bindings()
	var host := Node.new()
	root.add_child(host)
	var hub := FakeHub.new()
	var save := FakeSaveService.new()
	var world := FakeSnapshotNode.new()
	world.snapshot = {
		"loaded": 90,
		"building": 4,
		"pending": 120,
		"last_work_usec": 2400,
		"internal_chunks": {"must_not_escape": true},
	}
	var machines := FakeSnapshotNode.new()
	machines.snapshot = {
		"machine_count": 3500,
		"domain_count": 12,
		"domains": {"must_not_escape": true},
	}
	var agriculture := FakeSnapshotNode.new()
	agriculture.snapshot = {
		"crop_count": 2048,
		"mature_crop_count": 300,
		"soil_count": 2048,
		"world_mutation_batch": {"rejection_count": 0},
		"crop_counts": {"must_not_escape": true},
	}
	var husbandry := FakeSnapshotNode.new()
	husbandry.snapshot = {"managed_animals": 61, "maximum": 64}
	var attraction := FakeSnapshotNode.new()
	attraction.snapshot = {"following": 4}
	var products := FakeSnapshotNode.new()
	products.snapshot = {"tracked_animals": 40, "pending_products": 6}
	var ecology := FakeSnapshotNode.new()
	ecology.snapshot = {
		"passive_count": 11,
		"passive_cap": 12,
		"hostile_count": 2,
		"hostile_cap": 2,
		"species_counts": {"must_not_escape": true},
	}
	var pickups := FakeSnapshotNode.new()
	pickups.snapshot = {
		"pickup_node_count": 110,
		"max_pickup_nodes": 128,
		"visible_item_total": 800,
		"pending_item_total": 24,
		"budget_deferral_count": 3,
	}
	var structural := FakeSnapshotNode.new()
	structural.snapshot = {
		"pending_candidates": 60000,
		"candidate_queue_budget": 65536,
		"candidate_overflow_count": 1,
		"removed_structure_count": 384,
		"pickup_drop_count": 16,
	}
	var spawner := Node3D.new()
	save.catalog = {
		"hit_count": 10,
		"fallback_count": 2,
		"repair_count": 2,
		"last_world_count": 12,
		"last_hit_count": 10,
		"last_fallback_count": 2,
		"last_repair_count": 2,
		"last_elapsed_milliseconds": 5.9,
	}
	for node: Node in [
		hub,
		save,
		world,
		machines,
		agriculture,
		husbandry,
		attraction,
		products,
		ecology,
		pickups,
		structural,
		spawner,
	]:
		host.add_child(node)
	hub.save_service = save
	hub.machine_runtime = machines
	hub.agriculture_service = agriculture
	hub.husbandry_service = husbandry
	hub.animal_attraction_service = attraction
	hub.animal_product_service = products
	hub.creature_spawner = ecology
	hub.pickup_stack_coordinator = pickups
	hub.structural_integrity_service = structural
	var report_service = ReportServiceScript.new()
	host.add_child(report_service)
	hub.report_service = report_service
	await process_frame
	_check(report_service.setup(hub), "health report service accepts the final service hub")
	report_service.begin_world("qa-runtime-health")
	report_service.attach_runtime(world)
	report_service.record_save_result("qa-runtime-health", true, 8200, 14590)
	save.save_recovered.emit("qa-runtime-health", "backup")
	var report: Dictionary = report_service.get_snapshot()
	_check(bool(report.get("world_attached", false)), "aggregation reports the production world attachment")
	_check(int(report.get("source_count", 0)) == 10, "aggregation reads exactly ten bounded source snapshots")
	_check(str(report.get("status", "")) == "critical", "critical operational pressure reaches the report")
	_check(
		int(report.get("save", {}).get("last_bytes", 0)) == 14590
		and int(report.get("save", {}).get("recovery_count", 0)) == 1,
		"save bytes, duration and recovery remain available without copying world state",
	)
	var serialized := JSON.stringify(report)
	for forbidden: String in ["must_not_escape", "crop_counts", "species_counts", "domains"]:
		_check(not serialized.contains(forbidden), "aggregator excludes full %s dictionaries" % forbidden)

	var telemetry = TelemetryScript.new()
	var overlay = OverlayScript.new()
	var context := FakeInputContext.new()
	var player := Node3D.new()
	for node: Node in [telemetry, overlay, context, player]:
		host.add_child(node)
	await process_frame
	telemetry.setup(context, spawner, null, null, hub)
	telemetry.attach_runtime(world, player)
	for _index in 12:
		telemetry.record_frame(0.016)
	var snapshot: Dictionary = telemetry.sample_now()
	_check(snapshot.get("operations", {}) is Dictionary, "telemetry carries the unified operations projection")
	_check(
		str(snapshot.get("health", {}).get("status", "")) == "critical",
		"top-level runtime health includes operations severity",
	)
	overlay.setup(telemetry)
	await process_frame
	var f3_event := InputEventKey.new()
	f3_event.keycode = KEY_F3
	f3_event.physical_keycode = KEY_F3
	f3_event.pressed = true
	root.push_input(f3_event)
	await process_frame
	_check(overlay.is_overlay_visible(), "a real F3 event opens the combined health surface")
	var display := overlay.get_display_text()
	for phrase: String in ["运行诊断", "运行与保存健康", "主要压力", "保存会话", "目录累计"]:
		_check(display.contains(phrase), "combined F3 surface renders %s" % phrase)
	_check(_all_controls_are_passthrough(overlay), "combined health UI remains mouse passthrough")
	var panel_rect: Rect2 = overlay.get_panel_rect()
	_check(panel_rect.size.x > 0.0 and panel_rect.size.y > 0.0, "combined diagnostics panel owns a real layout rectangle")

	report_service.record_save_result("qa-runtime-health", false, 19000, 14590)
	var failed_report: Dictionary = report_service.get_snapshot()
	_check(
		int(failed_report.get("save", {}).get("failure_count", 0)) == 1
		and str(failed_report.get("status", "")) == "critical",
		"failed save is retained as critical operational evidence",
	)
	report_service.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _all_controls_are_passthrough(node: Node) -> bool:
	if node == null:
		return false
	if node is Control:
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE:
			return false
	for child: Node in node.get_children():
		if not _all_controls_are_passthrough(child):
			return false
	return true


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
