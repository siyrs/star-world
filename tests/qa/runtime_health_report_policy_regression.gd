extends SceneTree

const PolicyScript = preload("res://src/diagnostics/runtime_health_report_policy.gd")
const FormatterScript = preload("res://src/diagnostics/runtime_health_report_formatter.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_critical_projection_and_primary_bottleneck()
	_test_healthy_projection_and_formatting()
	if failures.is_empty():
		print("QA RUNTIME HEALTH POLICY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RUNTIME HEALTH POLICY FAILURE: %s" % failure)
		print(
			"QA RUNTIME HEALTH POLICY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_critical_projection_and_primary_bottleneck() -> void:
	var report: Dictionary = PolicyScript.build({
		"streaming": {
			"pending": 120,
			"loaded": 90,
			"domains": {"must_not_escape": {"payload": "large"}},
		},
		"machines": {
			"machine_count": 3500,
			"domain_count": 12,
			"domains": {"furnace": {"machines": {"huge": true}}},
		},
		"agriculture": {
			"crop_count": 2048,
			"mature_crop_count": 512,
			"soil_count": 2048,
			"crop_counts": {"wheat": 2048},
			"world_mutation_batch": {"rejection_count": 1},
		},
		"husbandry": {"managed_animals": 61, "maximum": 64},
		"animal_attraction": {"following": 5},
		"animal_products": {"tracked_animals": 40, "pending_products": 12},
		"ecology": {
			"passive_count": 11,
			"passive_cap": 12,
			"hostile_count": 2,
			"hostile_cap": 2,
			"species_counts": {"chicken": 11, "zombie": 2},
		},
		"pickups": {
			"pickup_node_count": 120,
			"max_pickup_nodes": 128,
			"visible_item_total": 4000,
			"pending_item_total": 300,
			"pending_type_rejection_count": 2,
		},
		"structural_integrity": {
			"pending_candidates": 60000,
			"candidate_queue_budget": 65536,
			"candidate_overflow_count": 1,
			"removed_structure_count": 384,
			"pickup_drop_count": 16,
		},
		"catalog": {
			"last_world_count": 12,
			"last_hit_count": 10,
			"last_fallback_count": 2,
			"last_repair_count": 2,
			"write_failure_count": 0,
			"internal_entries": {"must_not_escape": true},
		},
		"save": {
			"attempt_count": 3,
			"success_count": 2,
			"failure_count": 1,
			"last_success": false,
			"last_world_id": "qa-health",
			"last_bytes": 1048576,
			"last_elapsed_milliseconds": 45.5,
			"full_state": {"inventory": {"huge": true}},
		},
	})
	_check(str(report.get("status", "")) == "critical", "critical domain pressure reaches the report status")
	_check(
		int(report.get("row_count", 0)) == PolicyScript.MAX_ROWS,
		"report retains exactly the bounded twelve health rows",
	)
	_check(
		report.get("rows", []).size() <= PolicyScript.MAX_ROWS
		and report.get("issues", []).size() <= PolicyScript.MAX_ISSUES,
		"rows and issues remain inside fixed projection limits",
	)
	var primary: Dictionary = report.get("primary_bottleneck", {})
	_check(
		int(primary.get("severity", 0)) == 2
		and not str(primary.get("id", "")).is_empty(),
		"report identifies one deterministic critical bottleneck",
	)
	var serialized := JSON.stringify(report)
	for forbidden: String in [
		"must_not_escape",
		"crop_counts",
		"species_counts",
		"full_state",
		"internal_entries",
	]:
		_check(not serialized.contains(forbidden), "bounded projection excludes %s" % forbidden)
	_check(
		int(report.get("save", {}).get("last_bytes", 0)) == 1048576
		and int(report.get("catalog", {}).get("last_repair_count", 0)) == 2,
		"save and catalog evidence survive the whitelist projection",
	)


func _test_healthy_projection_and_formatting() -> void:
	var report: Dictionary = PolicyScript.build({
		"streaming": {"pending": 2, "loaded": 12},
		"machines": {"machine_count": 8, "domain_count": 3},
		"agriculture": {"crop_count": 24, "mature_crop_count": 2, "soil_count": 24},
		"husbandry": {"managed_animals": 4, "maximum": 64},
		"animal_attraction": {"following": 1},
		"animal_products": {"tracked_animals": 4, "pending_products": 0},
		"ecology": {
			"passive_count": 3,
			"passive_cap": 12,
			"hostile_count": 0,
			"hostile_cap": 2,
		},
		"pickups": {
			"pickup_node_count": 2,
			"max_pickup_nodes": 128,
			"visible_item_total": 6,
			"pending_item_total": 0,
		},
		"structural_integrity": {
			"pending_candidates": 0,
			"candidate_queue_budget": 65536,
		},
		"catalog": {
			"hit_count": 12,
			"last_world_count": 12,
			"last_hit_count": 12,
			"last_hit_ratio": 1.0,
		},
		"save": {
			"attempt_count": 1,
			"success_count": 1,
			"last_success": true,
			"last_world_id": "healthy-world",
			"last_bytes": 14590,
			"last_elapsed_milliseconds": 8.9,
		},
	})
	_check(str(report.get("status", "")) == "healthy", "low bounded usage remains healthy")
	_check(report.get("issues", []).is_empty(), "healthy report contains no synthetic issue")
	var text := FormatterScript.format(report)
	for phrase: String in [
		"F3 运行与保存健康",
		"主要压力",
		"Chunk 排队",
		"结构完整性",
		"保存会话",
		"目录累计",
	]:
		_check(text.contains(phrase), "formatter renders %s" % phrase)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
