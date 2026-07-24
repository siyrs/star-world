extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const HealthPolicyScript = preload("res://src/diagnostics/runtime_health_report_policy.gd")
const WORLD_COUNT := 96
const AUTHORITATIVE_READ_BUDGET := 32
const CATALOG_REBUILD_BUDGET := 16
const OVERRIDES_PER_WORLD := 16
const STAGE_CAPACITY := 64
const LEGACY_FULL_READ_COUNT := 176

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
		_run_progressive_scans(save)
	for world_id: String in world_ids:
		save.delete_world(world_id)
	save.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA BOUNDED AUTHORITATIVE READ PASS | checks=%d | worlds=%d | read_budget=%d"
			% [checks, WORLD_COUNT, AUTHORITATIVE_READ_BUDGET]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED AUTHORITATIVE READ FAILURE: %s" % failure)
		print(
			"QA BOUNDED AUTHORITATIVE READ FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _create_worlds_without_catalogs(save: Node) -> void:
	var prefix := "QA-Authoritative-Read-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.create_world(
			"%s-%02d" % [prefix, index],
			"star_continent",
			960000 + index
		)
		_check(not state.is_empty(), "fixture creates healthy world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		state["world"] = {"block_overrides": _overrides(index)}
		_check(
			save.save_world(world_id, state),
			"fixture writes authoritative world %02d" % index
		)
		primary_text_by_world[world_id] = _read_text(_world_path(world_id))
		_remove_file(_catalog_path(world_id))
		_check(
			not FileAccess.file_exists(_catalog_path(world_id)),
			"fixture removes sidecar %02d" % index
		)
	await process_frame


func _run_progressive_scans(save: Node) -> void:
	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	var expected_hits := [0, 16, 32, 48, 64, 80, 96]
	var expected_fallbacks := [96, 80, 64, 48, 32, 16, 0]
	var expected_reads := [32, 32, 32, 0, 0, 0, 0]
	var expected_deferred_reads := [64, 32, 0, 0, 0, 0, 0]
	var expected_rebuilds := [16, 16, 16, 16, 16, 16, 0]
	var expected_deferred_catalogs := [80, 64, 48, 32, 16, 0, 0]
	var expected_catalogs := [16, 32, 48, 64, 80, 96, 96]
	var expected_stage_hits := [0, 16, 32, 48, 32, 16, 0]
	var expected_staged_entries := [16, 32, 48, 32, 16, 0, 0]
	for scan_index in 7:
		var worlds: Array = save.list_worlds()
		var catalog: Dictionary = save.get_catalog_diagnostics()
		_check(
			_matching_count(worlds) == WORLD_COUNT,
			"scan %d keeps all worlds visible before metadata is resolved"
			% (scan_index + 1)
		)
		_check(
			int(catalog.get("authoritative_read_budget", 0))
			== AUTHORITATIVE_READ_BUDGET,
			"scan %d exposes the fixed authoritative read budget" % (scan_index + 1)
		)
		_check(
			int(catalog.get("catalog_stage_capacity", 0)) == STAGE_CAPACITY,
			"scan %d exposes the fixed transient stage capacity" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_authoritative_read_budget_used", -1))
			== expected_reads[scan_index],
			"scan %d uses the exact expected full-read slots" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_deferred_authoritative_read_count", -1))
			== expected_deferred_reads[scan_index],
			"scan %d reports the exact deferred metadata count" % (scan_index + 1)
		)
		_check(
			_pending_metadata_count(worlds) == expected_deferred_reads[scan_index],
			"scan %d exposes placeholders for every deferred full read" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_stage_hit_count", -1))
			== expected_stage_hits[scan_index],
			"scan %d reuses the exact expected staged catalog entries" % (scan_index + 1)
		)
		_check(
			int(catalog.get("staged_catalog_entry_count", -1))
			== expected_staged_entries[scan_index],
			"scan %d retains the exact bounded staging backlog" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_catalog_rebuild_budget_used", -1))
			== expected_rebuilds[scan_index],
			"scan %d preserves the independent sidecar write budget" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_deferred_catalog_rebuild_count", -1))
			== expected_deferred_catalogs[scan_index],
			"scan %d reports every sidecar waiting behind reads or writes" % (scan_index + 1)
		)
		_check(
			int(catalog.get("last_hit_count", -1)) == expected_hits[scan_index]
			and int(catalog.get("last_fallback_count", -1))
			== expected_fallbacks[scan_index],
			"scan %d converges through the expected hit and miss counts"
			% (scan_index + 1)
		)
		_check(
			int(catalog.get("last_authoritative_read_budget_used", 0))
			<= AUTHORITATIVE_READ_BUDGET,
			"scan %d never exceeds the authoritative JSON read budget"
			% (scan_index + 1)
		)
		_check(
			int(catalog.get("staged_catalog_entry_count", 0)) <= STAGE_CAPACITY,
			"scan %d never exceeds the transient catalog stage capacity"
			% (scan_index + 1)
		)
		_check(
			int(catalog.get("last_repair_budget_used", -1)) == 0
			and int(catalog.get("last_deferred_recovery_count", -1)) == 0,
			"scan %d never consumes primary repair capacity" % (scan_index + 1)
		)
		_check(
			_catalog_count() == expected_catalogs[scan_index],
			"scan %d creates only the expected number of sidecars" % (scan_index + 1)
		)
		if scan_index == 0:
			var report: Dictionary = HealthPolicyScript.build({"catalog": catalog})
			_check(
				str(report.get("status", "")) == "warning"
				and int(report.get("catalog", {}).get(
					"last_deferred_authoritative_read_count", -1
				)) == 64
				and int(report.get("catalog", {}).get(
					"staged_catalog_entry_count", -1
				)) == 16,
				"F3 projection preserves transient catalog staging evidence"
			)
	var final_catalog: Dictionary = save.get_catalog_diagnostics()
	var actual_reads := int(final_catalog.get("authoritative_read_count", -1))
	_check(
		actual_reads == WORLD_COUNT
		and LEGACY_FULL_READ_COUNT - actual_reads == 80,
		"transient staging eliminates eighty redundant full reads"
	)
	_check(
		int(final_catalog.get("staged_catalog_peak_count", -1)) == 48
		and int(final_catalog.get("staged_catalog_peak_count", 0)) <= STAGE_CAPACITY,
		"stage cache peak remains inside the fixed sixty-four entry capacity"
	)
	_check(
		int(final_catalog.get("stage_hit_count", -1)) == 144
		and int(final_catalog.get("stage_invalidation_count", -1)) == 0,
		"unchanged primaries reuse staged entries without invalidation"
	)
	var recovery: Dictionary = save.get_recovery_diagnostics()
	_check(
		int(recovery.get("recovery_count", 0)) == 0
		and int(recovery.get("repair_attempt_count", 0)) == 0,
		"healthy primaries never enter backup recovery"
	)
	_check(
		int(final_catalog.get("write_failure_count", 0)) == 0,
		"all bounded sidecar writes succeed"
	)
	for world_id: String in world_ids:
		_check(
			_read_text(_world_path(world_id))
			== str(primary_text_by_world.get(world_id, "")),
			"deferred metadata reads never mutate authoritative primary %s" % world_id
		)
		_check(
			FileAccess.file_exists(_catalog_path(world_id)),
			"final sidecar exists for %s" % world_id
		)


func _overrides(index: int) -> Dictionary:
	var result: Dictionary = {}
	for offset in OVERRIDES_PER_WORLD:
		result["%d,17,%d" % [index * 48 + offset, index]] = "stone_bricks"
	return result


func _matching_count(worlds: Array) -> int:
	var count := 0
	for metadata: Variant in worlds:
		if metadata is Dictionary and world_ids.has(str(metadata.get("id", ""))):
			count += 1
	return count


func _pending_metadata_count(worlds: Array) -> int:
	var count := 0
	for metadata: Variant in worlds:
		if (
			metadata is Dictionary
			and world_ids.has(str(metadata.get("id", "")))
			and bool(metadata.get("authoritative_read_deferred", false))
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
