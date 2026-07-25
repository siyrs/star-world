extends SceneTree

const SaveBrowserScript = preload("res://src/ui/save_browser_panel.gd")
const QueryPolicy = preload("res://src/ui/save_browser_query_policy.gd")
const WORLD_COUNT := 256
const ROW_POOL_LIMIT := 24

var checks := 0
var failures: Array[String] = []


class FakeSaveService:
	extends Node

	var worlds: Array = []
	var list_count := 0

	func _init() -> void:
		var groups := ["Alpha", "Beta", "Gamma", "Delta"]
		var maps := [
			"star_continent",
			"snowfield",
			"desert",
			"floating_islands",
			"abyss",
		]
		for index in WORLD_COUNT:
			worlds.append({
				"id": "indexed-world-%03d" % index,
				"name": "Indexed %s %03d" % [groups[index % groups.size()], index],
				"map_id": maps[index % maps.size()],
				"seed": 1300000 + index,
				"updated_at": "2026-07-25T00:%02d:%02d" % [
					index / 60,
					index % 60,
				],
				"save_bytes": 8192 + index * 23,
			})
		worlds.append(worlds[0])

	func list_worlds() -> Array:
		list_count += 1
		return worlds

	func get_catalog_diagnostics() -> Dictionary:
		return {
			"last_world_count": WORLD_COUNT,
			"last_elapsed_milliseconds": 2.5,
			"last_deferred_recovery_count": 0,
			"primary_repair_budget": 8,
			"last_deferred_authoritative_read_count": 0,
			"authoritative_read_budget": 32,
			"last_deferred_catalog_rebuild_count": 0,
			"catalog_rebuild_budget": 16,
			"staged_catalog_entry_count": 0,
			"catalog_stage_capacity": 64,
			"last_stage_hit_count": 0,
		}

	func get_recovery_diagnostics() -> Dictionary:
		return {}

	func delete_world(world_id: String) -> bool:
		for index in range(worlds.size() - 1, -1, -1):
			if (
				worlds[index] is Dictionary
				and str(worlds[index].get("id", "")) == world_id
			):
				worlds.remove_at(index)
			return true
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := FakeSaveService.new()
	root.add_child(service)
	var panel := SaveBrowserScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(service)
	await process_frame

	var initial: Dictionary = panel.get_virtualization_snapshot()
	_check(
		service.list_count == 1
		and int(initial.get("total_world_count", -1)) == WORLD_COUNT
		and int(initial.get("indexed_world_count", -1)) == WORLD_COUNT,
		"one authoritative refresh deduplicates and indexes all two hundred fifty-six worlds"
	)
	_check(
		int(initial.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(initial.get("row_create_count", -1)) == ROW_POOL_LIMIT
		and int(initial.get("page_count", -1)) == 11,
		"indexed browser retains the fixed row pool across eleven pages"
	)
	var newest_page := panel.get_visible_world_ids()
	_check(
		newest_page.size() == ROW_POOL_LIMIT
		and newest_page[0] == "indexed-world-255"
		and newest_page[23] == "indexed-world-232",
		"default indexed page remains deterministic newest-first"
	)

	var calls_before_page := service.list_count
	panel.show_page(10)
	var last_page := panel.get_visible_world_ids()
	_check(
		last_page.size() == 16
		and last_page[0] == "indexed-world-015"
		and last_page[15] == "indexed-world-000",
		"last indexed page reuses sixteen visible slots"
	)
	_check(
		service.list_count == calls_before_page,
		"indexed page navigation performs zero service or disk scans"
	)

	var calls_before_query := service.list_count
	panel.apply_query("gamma", QueryPolicy.SORT_NAME_ASC)
	var gamma: Dictionary = panel.get_virtualization_snapshot()
	var gamma_page := panel.get_visible_world_ids()
	_check(
		int(gamma.get("matched_world_count", -1)) == 64
		and int(gamma.get("page_count", -1)) == 3
		and gamma_page[0] == "indexed-world-002"
		and gamma_page[1] == "indexed-world-006",
		"name search and natural sorting expose sixty-four deterministic matches"
	)
	_check(
		service.list_count == calls_before_query,
		"search and sort operate only on the in-memory index"
	)
	panel.show_page(2)
	_check(
		panel.get_visible_world_ids().size() == 16,
		"filtered final page keeps the same fixed row pool"
	)

	panel.show_page(0)
	panel.call("_select_slot", 0)
	_check(
		str(panel.get("_selected_world_id")) == "indexed-world-002",
		"visible result selection stores a stable world id"
	)
	panel.apply_query("indexed-world-123", QueryPolicy.SORT_UPDATED_DESC)
	_check(
		str(panel.get("_selected_world_id")).is_empty()
		and int(panel.get_virtualization_snapshot().get("matched_world_count", -1)) == 1,
		"filtering a selected world out clears hidden deletion state"
	)

	panel.apply_query("", QueryPolicy.SORT_SIZE_DESC)
	var largest_page := panel.get_visible_world_ids()
	_check(
		largest_page[0] == "indexed-world-255"
		and largest_page[23] == "indexed-world-232",
		"largest-first sorting reuses the in-memory index"
	)
	var search_input := panel.get("_search_input") as LineEdit
	var applies_before_typing := int(
		panel.get_virtualization_snapshot().get("query_apply_count", -1)
	)
	search_input.text = "alpha"
	await process_frame
	_check(
		int(panel.get_virtualization_snapshot().get("query_apply_count", -1))
		== applies_before_typing,
		"typing does not run an unbounded full-directory query per keystroke"
	)
	search_input.text_submitted.emit("alpha")
	await process_frame
	_check(
		int(panel.get_virtualization_snapshot().get("matched_world_count", -1)) == 64
		and service.list_count == calls_before_query,
		"Enter applies the staged search without a service scan"
	)

	var rows_before_refresh := int(
		panel.get_virtualization_snapshot().get("row_create_count", -1)
	)
	panel.refresh()
	await process_frame
	var refreshed: Dictionary = panel.get_virtualization_snapshot()
	_check(
		service.list_count == calls_before_query + 1
		and int(refreshed.get("index_rebuild_count", -1)) == 2,
		"explicit refresh rebuilds the index exactly once"
	)
	_check(
		int(refreshed.get("row_create_count", -1)) == rows_before_refresh
		and int(refreshed.get("row_pool_size", -1)) == ROW_POOL_LIMIT,
		"index rebuilds never allocate additional UI rows"
	)

	panel.queue_free()
	service.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA INDEXED SAVE BROWSER PASS | checks=%d | worlds=%d | rows=%d"
			% [checks, WORLD_COUNT, ROW_POOL_LIMIT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA INDEXED SAVE BROWSER FAILURE: %s" % failure)
		print(
			"QA INDEXED SAVE BROWSER FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
