extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const WORLD_COUNT := 20
const REPAIR_BUDGET := 8

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	await _create_corrupt_worlds(save)
	if world_ids.size() == WORLD_COUNT:
		_run_progressive_scans(save)
	for world_id: String in world_ids:
		save.delete_world(world_id)
	save.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("QA BOUNDED MULTI WORLD RECOVERY PASS | checks=%d | worlds=%d | budget=%d" % [checks, WORLD_COUNT, REPAIR_BUDGET])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED MULTI WORLD RECOVERY FAILURE: %s" % failure)
		print("QA BOUNDED MULTI WORLD RECOVERY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _create_corrupt_worlds(save: Node) -> void:
	var prefix := "QA-Bounded-Recovery-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.create_world("%s-%02d" % [prefix, index], "star_continent", 880000 + index)
		_check(not state.is_empty(), "fixture creates world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		state["world"] = {"block_overrides": _overrides(index)}
		_check(save.save_world(world_id, state), "fixture writes backup-ready world %02d" % index)
		state["metadata"]["generation"] = "newer-%02d" % index
		_check(save.save_world(world_id, state), "fixture rotates valid backup %02d" % index)
		_remove_file(_catalog_path(world_id))
		_check(_write_corrupt_primary(world_id), "fixture corrupts primary %02d" % index)
	await process_frame


func _run_progressive_scans(save: Node) -> void:
	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	var expected_deferred := [12, 4, 0, 0]
	var expected_repairs := [8, 8, 4, 0]
	var expected_hits := [0, 8, 16, 20]
	for scan_index in 4:
		var worlds: Array = save.list_worlds()
		var catalog: Dictionary = save.get_catalog_diagnostics()
		_check(_matching_count(worlds) == WORLD_COUNT, "scan %d keeps all valid fallback worlds visible" % (scan_index + 1))
		_check(int(catalog.get("primary_repair_budget", 0)) == REPAIR_BUDGET, "scan %d exposes the fixed repair budget" % (scan_index + 1))
		_check(int(catalog.get("last_repair_budget_used", -1)) == expected_repairs[scan_index], "scan %d uses only the expected repair slots" % (scan_index + 1))
		_check(int(catalog.get("last_deferred_recovery_count", -1)) == expected_deferred[scan_index], "scan %d reports the exact deferred recovery count" % (scan_index + 1))
		_check(int(catalog.get("last_hit_count", -1)) == expected_hits[scan_index], "scan %d converges to the expected sidecar hit count" % (scan_index + 1))
		_check(int(catalog.get("last_repair_budget_used", 0)) <= REPAIR_BUDGET, "scan %d never exceeds the disk repair budget" % (scan_index + 1))
	var recovery: Dictionary = save.get_recovery_diagnostics()
	_check(int(recovery.get("repair_attempt_count", 0)) == WORLD_COUNT, "all corrupt primaries are eventually repaired exactly once")
	_check(int(recovery.get("repair_success_count", 0)) == WORLD_COUNT, "all bounded repair attempts succeed")
	_check(int(recovery.get("repair_failure_count", 0)) == 0, "progressive repair has no failed primary promotions")
	for world_id: String in world_ids:
		_check(_valid_primary(world_id), "final primary is structurally valid for %s" % world_id)


func _overrides(index: int) -> Dictionary:
	var result: Dictionary = {}
	for offset in 16:
		result["%d,12,%d" % [index * 32 + offset, index]] = "stone_bricks"
	return result


func _write_corrupt_primary(world_id: String) -> bool:
	var file := FileAccess.open(_world_path(world_id), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"save_version": 2, "metadata": {"id": world_id}, "player": "broken", "world": {"block_overrides": "broken"}}))
	file.close()
	return true


func _valid_primary(world_id: String) -> bool:
	var file := FileAccess.open(_world_path(world_id), FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed is Dictionary and parsed.get("player", null) is Dictionary and parsed.get("world", {}).get("block_overrides", null) is Dictionary


func _matching_count(worlds: Array) -> int:
	var count := 0
	for metadata: Variant in worlds:
		if metadata is Dictionary and world_ids.has(str(metadata.get("id", ""))):
			count += 1
	return count


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
