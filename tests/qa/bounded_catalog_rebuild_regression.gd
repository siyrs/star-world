extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const HealthPolicyScript = preload("res://src/diagnostics/runtime_health_report_policy.gd")
const WORLD_COUNT := 48
const CATALOG_REBUILD_BUDGET := 16
const OVERRIDES_PER_WORLD := 32

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var primary_text_by_world: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	await _create_worlds_without_catalogs(save)
	if world_ids.size() == WORLD_COUNT:
		_run_progressive_catalog_scans(save)
	for world_id: String in world_ids:
		save.delete_world(world_id)
	save.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA BOUNDED CATALOG REBUILD PASS | checks=%d | worlds=%d | budget=%d"
			% [checks, WORLD_COUNT, CATALOG_REBUILD_BUDGET]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED CATALOG REBUILD FAILURE: %s" % failure)
		print(
			"QA BOUNDED CATALOG REBUILD FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _create_worlds_without_catalogs(save: Node) -> void:
	var prefix := "QA-Catalog-Rebuild-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.create_world(
			"%s-%02d" % [prefix, index],
			"star_continent",
			970000 + index
		)
		_check(not state.is_empty(), "fixture creates healthy world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		state["world"] = {"block_overrides": _overrides(index)}
		_check(
			save.save_world(world_id, state),
			"fixture writes non-trivial authoritative world %02d" % index
		)
		primary_text_by_world[world_id] = _read_text(_world_path(world_id))
		_remove_file(_catalog_path(world_id))
		_check(
			not FileAccess.file_exists(_catalog_path(world_id)),
			"fixture removes derived catalog %02d" % index
		)
	await process_frame


func _run_progressive_catalog_scans(save: Node) -> void:
	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	var expected_hits := [0, 16, 32, 48]
	var expected_fallbacks := [48, 32, 16, 0]
	var expected_rebuilds := [16, 16, 16, 0]
	var expected_deferred := [32, 16, 0, 0]
	var expected_catalogs := [16, 32, 48, 48]
	for scan_index in 4:
		var worlds: Array = save.list_worlds()
		var catalog: Dictionary = save.get_catalog_diagnostics()
		_check(
			_matching_count(worlds) == WORLD_COUNT,
			"scan %d keeps every healthy world visible while sidecars converge"
			% (scan_index + 1)
		)
		_check(
			int(catalog.get("catalog_rebuild_budget", 0)) == CATALOG_REBUILD_BUDGET,
			"scan %d exposes the fixed catalog rebuild budget" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_catalog_rebuild_budget_used", -1))
			== expected_rebuilds[scan_index],
			"scan %d uses the exact expected catalog write slots" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_repair_count", -1)) == expected_rebuilds[scan_index],
			"scan %d records every successful catalog rebuild" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_deferred_catalog_rebuild_count", -1))
			== expected_deferred[scan_index],
			"scan %d reports the exact deferred catalog count" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_hit_count", -1)) == expected_hits[scan_index]
			and int(catalog.get("last_fallback_count", -1))
			== expected_fallbacks[scan_index],
			"scan %d converges through the expected hit and fallback counts"
			% (scan_index + 1)
		)
		_check(
			int(catalog.get("last_catalog_rebuild_budget_used", 0))
			<= CATALOG_REBUILD_BUDGET,
			"scan %d never exceeds the catalog disk-write budget" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_repair_budget_used", -1)) == 0
			and int(catalog.get("last_deferred_recovery_count", -1)) == 0,
			"scan %d does not consume authoritative primary repair capacity"
			% (scan_index + 1)
		)
		_check(
			_catalog_count() == expected_catalogs[scan_index],
			"scan %d creates only the expected number of sidecars" % (scan_index + 1)
		)
		_check(
			_deferred_metadata_count(worlds) == expected_deferred[scan_index],
			"scan %d marks exactly the worlds waiting for a sidecar" % (scan_index + 1)
		)
		if scan_index == 0:
			var report: Dictionary = HealthPolicyScript.build({"catalog": catalog})
			_check(
				str(report.get("status", "")) == "warning"
				and int(report.get("catalog", {}).get(
					"last_deferred_catalog_rebuild_count", -1
				)) == 32,
				"F3 projection preserves bounded catalog backlog evidence"
			)
	var recovery: Dictionary = save.get_recovery_diagnostics()
	_check(
		int(recovery.get("recovery_count", 0)) == 0
		and int(recovery.get("repair_attempt_count", 0)) == 0,
		"healthy primaries never enter backup recovery"
	)
	_check(
		int(save.get_catalog_diagnostics().get("write_failure_count", 0)) == 0,
		"all bounded sidecar writes succeed"
	)
	for world_id: String in world_ids:
		_check(
			_read_text(_world_path(world_id))
			== str(primary_text_by_world.get(world_id, "")),
			"catalog convergence never mutates authoritative primary %s" % world_id
		)
		_check(
			FileAccess.file_exists(_catalog_path(world_id)),
			"final sidecar exists for %s" % world_id
		)


func _overrides(index: int) -> Dictionary:
	var result: Dictionary = {}
	for offset in OVERRIDES_PER_WORLD:
		result["%d,15,%d" % [index * 64 + offset, index]] = "stone_bricks"
	return result


func _matching_count(worlds: Array) -> int:
	var count := 0
	for metadata: Variant in worlds:
		if metadata is Dictionary and world_ids.has(str(metadata.get("id", ""))):
			count += 1
	return count


func _deferred_metadata_count(worlds: Array) -> int:
	var count := 0
	for metadata: Variant in worlds:
		if (
			metadata is Dictionary
			and world_ids.has(str(metadata.get("id", "")))
			and bool(metadata.get("catalog_rebuild_deferred", false))
		):
			count += 1
	return count


func _catalog_count() -> int:
	var count := 0
	for world_id: String in world_ids:
		if FileAccess.file_exists(_catalog_path(world_id)):
			count += 1
	return count


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
