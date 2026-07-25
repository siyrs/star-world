extends SceneTree

const SaveBrowserScript = preload("res://src/ui/save_browser_panel.gd")
const WORLD_COUNT := 72
const ROW_POOL_LIMIT := 24
const AUTO_SETTLE_LIMIT := 6

var checks := 0
var failures: Array[String] = []


class FakeSaveService:
	extends Node

	var worlds: Array = []
	var list_count := 0
	var permanent_backlog := false
	var current_diagnostics: Dictionary = {}

	func _init(p_world_count: int, p_permanent_backlog: bool = false) -> void:
		permanent_backlog = p_permanent_backlog
		for index in p_world_count:
			worlds.append({
				"id": "virtual-world-%03d" % index,
				"name": "Virtual World %03d" % index,
				"map_id": "star_continent",
				"seed": 700000 + index,
				"updated_at": "2026-07-25T00:%02d:00" % (index % 60),
				"save_bytes": 2048 + index,
				"authoritative_read_deferred": index >= 32,
				"catalog_staged": index >= 16 and index < 32,
			})

	func list_worlds() -> Array:
		list_count += 1
		if permanent_backlog:
			current_diagnostics = _diagnostics(48, 56, 16)
		else:
			match list_count:
				1:
					current_diagnostics = _diagnostics(40, 56, 16)
				2:
					current_diagnostics = _diagnostics(16, 40, 32)
				3:
					current_diagnostics = _diagnostics(0, 24, 24)
				4:
					current_diagnostics = _diagnostics(0, 8, 8)
				_:
					current_diagnostics = _diagnostics(0, 0, 0)
		return worlds.duplicate(true)

	func get_catalog_diagnostics() -> Dictionary:
		return current_diagnostics.duplicate(true)

	func get_recovery_diagnostics() -> Dictionary:
		return {}

	func delete_world(world_id: String) -> bool:
		for index in range(worlds.size() - 1, -1, -1):
			if str(worlds[index].get("id", "")) == world_id:
				worlds.remove_at(index)
				return true
		return false

	func _diagnostics(
		deferred_reads: int,
		deferred_catalogs: int,
		staged_catalogs: int
	) -> Dictionary:
		return {
			"last_world_count": worlds.size(),
			"last_elapsed_milliseconds": 1.0,
			"last_deferred_recovery_count": 0,
			"primary_repair_budget": 8,
			"last_deferred_authoritative_read_count": deferred_reads,
			"authoritative_read_budget": 32,
			"last_deferred_catalog_rebuild_count": deferred_catalogs,
			"catalog_rebuild_budget": 16,
			"staged_catalog_entry_count": staged_catalogs,
			"catalog_stage_capacity": 64,
			"last_stage_hit_count": staged_catalogs,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _exercise_progressive_virtualization()
	await _exercise_hard_settle_cap()
	if failures.is_empty():
		print(
			"QA SAVE BROWSER VIRTUALIZATION PASS | checks=%d | rows=%d | settle=%d"
			% [checks, ROW_POOL_LIMIT, AUTO_SETTLE_LIMIT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE BROWSER VIRTUALIZATION FAILURE: %s" % failure)
		print(
			"QA SAVE BROWSER VIRTUALIZATION FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _exercise_progressive_virtualization() -> void:
	var service := FakeSaveService.new(WORLD_COUNT)
	root.add_child(service)
	var panel := SaveBrowserScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(service)
	for _frame in 8:
		await process_frame
	var snapshot: Dictionary = panel.get_virtualization_snapshot()
	_check(
		int(snapshot.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(snapshot.get("row_create_count", -1)) == ROW_POOL_LIMIT,
		"browser creates exactly twenty-four reusable rows"
	)
	_check(
		int(snapshot.get("total_world_count", -1)) == WORLD_COUNT
		and int(snapshot.get("page_count", -1)) == 3,
		"seventy-two worlds are exposed through three bounded pages"
	)
	_check(
		int(snapshot.get("visible_row_count", -1)) == ROW_POOL_LIMIT,
		"only twenty-four world rows are visible at once"
	)
	_check(
		service.list_count == 5
		and int(snapshot.get("auto_settle_pass_count", -1)) == 4,
		"automatic settling converges after four cross-frame passes"
	)
	_check(
		not bool(snapshot.get("auto_settle_active", true))
		and int(snapshot.get("remaining_auto_settle_passes", -1)) == 0,
		"automatic settling disables processing immediately after convergence"
	)
	var first_page := panel.get_visible_world_ids()
	_check(
		first_page.size() == ROW_POOL_LIMIT
		and first_page[0] == "virtual-world-059"
		and first_page[23] == "virtual-world-036",
		"first page binds the newest twenty-four stable world ids"
	)
	var list_count_before_page_change := service.list_count
	panel.show_page(2)
	var final_page := panel.get_visible_world_ids()
	_check(
		final_page.size() == ROW_POOL_LIMIT
		and final_page[0] == "virtual-world-011"
		and final_page[23] == "virtual-world-060",
		"last page reuses the row pool with deterministic update and id ordering"
	)
	_check(
		service.list_count == list_count_before_page_change,
		"page navigation performs no additional disk or catalog scan"
	)
	var rows_before_refresh := int(
		panel.get_virtualization_snapshot().get("row_create_count", -1)
	)
	panel.refresh()
	await process_frame
	_check(
		int(panel.get_virtualization_snapshot().get("row_create_count", -1))
		== rows_before_refresh,
		"repeated refreshes never allocate another world row"
	)
	panel.queue_free()
	service.queue_free()
	await process_frame
	await process_frame


func _exercise_hard_settle_cap() -> void:
	var service := FakeSaveService.new(WORLD_COUNT, true)
	root.add_child(service)
	var panel := SaveBrowserScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(service)
	for _frame in 10:
		await process_frame
	var snapshot: Dictionary = panel.get_virtualization_snapshot()
	_check(
		service.list_count == AUTO_SETTLE_LIMIT + 1,
		"permanent backlog receives one initial scan and at most six automatic passes"
	)
	_check(
		int(snapshot.get("auto_settle_pass_count", -1)) == AUTO_SETTLE_LIMIT
		and int(snapshot.get("remaining_auto_settle_passes", -1)) == 0,
		"automatic settling obeys the fixed six-pass hard cap"
	)
	_check(
		not bool(snapshot.get("auto_settle_active", true)),
		"hard-capped backlog leaves no idle process loop running"
	)
	_check(
		int(snapshot.get("row_pool_size", -1)) == ROW_POOL_LIMIT,
		"hard-capped backlog still owns only the fixed row pool"
	)
	panel.queue_free()
	service.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
