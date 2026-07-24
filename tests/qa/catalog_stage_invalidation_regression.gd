extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const HealthPolicyScript = preload("res://src/diagnostics/runtime_health_report_policy.gd")

const WORLD_COUNT := 40
const AUTHORITATIVE_READ_BUDGET := 32
const CATALOG_REBUILD_BUDGET := 16
const STAGE_CAPACITY := 64
const OVERRIDES_PER_WORLD := 8

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
		_exercise_staging_and_invalidation(save)
	for world_id: String in world_ids:
		save.delete_world(world_id)
	save.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA CATALOG STAGE INVALIDATION PASS | checks=%d | worlds=%d | capacity=%d"
			% [checks, WORLD_COUNT, STAGE_CAPACITY]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA CATALOG STAGE INVALIDATION FAILURE: %s" % failure)
		print(
			"QA CATALOG STAGE INVALIDATION FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _create_worlds_without_catalogs(save: Node) -> void:
	var prefix := "QA-Catalog-Stage-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.create_world(
			"%s-%02d" % [prefix, index],
			"star_continent",
			990000 + index
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


func _exercise_staging_and_invalidation(save: Node) -> void:
	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	var first_worlds: Array = save.list_worlds()
	var first: Dictionary = save.get_catalog_diagnostics()
	_check(
		_matching_count(first_worlds) == WORLD_COUNT,
		"first scan keeps every world visible"
	)
	_check(
		int(first.get("last_authoritative_read_budget_used", -1))
		== AUTHORITATIVE_READ_BUDGET,
		"first scan uses exactly thirty-two full reads"
	)
	_check(
		int(first.get("last_catalog_rebuild_budget_used", -1))
		== CATALOG_REBUILD_BUDGET,
		"first scan writes exactly sixteen sidecars"
	)
	_check(
		int(first.get("staged_catalog_entry_count", -1)) == 16,
		"first scan stages the sixteen exact entries waiting behind writes"
	)
	_check(
		int(first.get("catalog_stage_capacity", 0)) == STAGE_CAPACITY,
		"catalog staging exposes the fixed sixty-four entry capacity"
	)
	_check(
		int(first.get("last_deferred_authoritative_read_count", -1)) == 8,
		"first scan leaves eight explicit metadata placeholders"
	)

	var ordered_ids := world_ids.duplicate()
	ordered_ids.sort()
	var save_target := ordered_ids[16]
	var invalidation_target := ordered_ids[17]
	var save_state := _read_dictionary(_world_path(save_target))
	var save_metadata: Dictionary = save_state.get("metadata", {})
	save_metadata["name"] = "Stage Save Refresh"
	save_state["metadata"] = save_metadata
	_check(
		save.save_world(save_target, save_state),
		"explicit save replaces one staged entry with a real sidecar"
	)
	primary_text_by_world[save_target] = _read_text(_world_path(save_target))
	_check(
		FileAccess.file_exists(_catalog_path(save_target)),
		"explicit save creates the selected sidecar"
	)
	_check(
		int(save.get_catalog_diagnostics().get("staged_catalog_entry_count", -1)) == 15,
		"explicit save invalidates only its own staged entry"
	)

	var external_state := _read_dictionary(_world_path(invalidation_target))
	var external_metadata: Dictionary = external_state.get("metadata", {})
	external_metadata["name"] = "Externally Updated Catalog Stage"
	external_state["metadata"] = external_metadata
	var external_world: Dictionary = external_state.get("world", {})
	var external_overrides: Dictionary = external_world.get("block_overrides", {})
	external_overrides["999,19,999"] = "diamond_ore"
	external_world["block_overrides"] = external_overrides
	external_state["world"] = external_world
	_check(
		_write_dictionary_direct(_world_path(invalidation_target), external_state),
		"fixture changes one staged authoritative file outside SaveService"
	)
	primary_text_by_world[invalidation_target] = _read_text(
		_world_path(invalidation_target)
	)
	_check(
		not FileAccess.file_exists(_catalog_path(invalidation_target)),
		"externally changed staged world still has no sidecar"
	)

	save.reset_catalog_diagnostics()
	_check(
		int(save.get_catalog_diagnostics().get("staged_catalog_entry_count", -1)) == 15,
		"diagnostic reset does not erase transient staging behavior"
	)
	var second_worlds: Array = save.list_worlds()
	var second: Dictionary = save.get_catalog_diagnostics()
	_check(
		_matching_count(second_worlds) == WORLD_COUNT,
		"second scan keeps every world visible after one staged invalidation"
	)
	_check(
		_find_name(second_worlds, invalidation_target)
		== "Externally Updated Catalog Stage",
		"stale staged metadata is rejected and refreshed from the changed primary"
	)
	_check(
		int(second.get("last_stage_invalidation_count", -1)) == 1
		and int(second.get("stage_invalidation_count", -1)) == 1,
		"byte or timestamp mismatch records exactly one staged invalidation"
	)
	_check(
		int(second.get("last_stage_hit_count", -1)) == 14,
		"second scan reuses every still-valid staged entry without full parsing"
	)
	_check(
		int(second.get("last_authoritative_read_budget_used", -1)) == 9
		and int(second.get("authoritative_read_count", -1)) == 9,
		"second scan performs one invalidation reread plus eight new reads"
	)
	_check(
		int(second.get("last_catalog_rebuild_budget_used", -1)) == 16,
		"stage reuse and refreshed metadata share the existing write budget"
	)
	_check(
		int(second.get("staged_catalog_entry_count", -1)) == 7,
		"seven newly read entries remain staged after the second write budget"
	)
	_check(
		int(second.get("last_deferred_authoritative_read_count", -1)) == 0,
		"all forty worlds have exact metadata after the second scan"
	)
	var report: Dictionary = HealthPolicyScript.build({"catalog": second})
	_check(
		str(report.get("status", "")) == "warning"
		and int(report.get("catalog", {}).get("staged_catalog_entry_count", -1)) == 7
		and int(report.get("catalog", {}).get("last_stage_invalidation_count", -1)) == 1,
		"F3 projection preserves bounded staging and invalidation evidence"
	)
	var serialized := JSON.stringify(report)
	_check(
		not serialized.contains("block_overrides")
		and not serialized.contains("Externally Updated Catalog Stage"),
		"health projection never exposes staged metadata or world payloads"
	)

	for _scan in 4:
		if _catalog_count() == WORLD_COUNT:
			break
		save.list_worlds()
	var steady_worlds: Array = save.list_worlds()
	var steady: Dictionary = save.get_catalog_diagnostics()
	_check(
		_matching_count(steady_worlds) == WORLD_COUNT
		and int(steady.get("last_hit_count", -1)) == WORLD_COUNT,
		"catalog staging converges to a pure forty-world sidecar hit"
	)
	_check(
		int(steady.get("last_authoritative_read_budget_used", -1)) == 0
		and int(steady.get("last_catalog_rebuild_budget_used", -1)) == 0
		and int(steady.get("staged_catalog_entry_count", -1)) == 0,
		"steady scan performs no full reads, writes or staged retention"
	)
	var recovery: Dictionary = save.get_recovery_diagnostics()
	_check(
		int(recovery.get("recovery_count", 0)) == 0
		and int(recovery.get("repair_attempt_count", 0)) == 0,
		"healthy staging and invalidation never enter backup recovery"
	)
	for world_id: String in world_ids:
		_check(
			_read_text(_world_path(world_id))
			== str(primary_text_by_world.get(world_id, "")),
			"staging never mutates authoritative primary %s" % world_id
		)
		_check(
			FileAccess.file_exists(_catalog_path(world_id)),
			"final sidecar exists for %s" % world_id
		)


func _overrides(index: int) -> Dictionary:
	var result: Dictionary = {}
	for offset in OVERRIDES_PER_WORLD:
		result["%d,19,%d" % [index * 32 + offset, index]] = "stone_bricks"
	return result


func _matching_count(worlds: Array) -> int:
	var count := 0
	for metadata: Variant in worlds:
		if metadata is Dictionary and world_ids.has(str(metadata.get("id", ""))):
			count += 1
	return count


func _find_name(worlds: Array, world_id: String) -> String:
	for metadata: Variant in worlds:
		if metadata is Dictionary and str(metadata.get("id", "")) == world_id:
			return str(metadata.get("name", ""))
	return ""


func _catalog_count() -> int:
	var count := 0
	for world_id: String in world_ids:
		if FileAccess.file_exists(_catalog_path(world_id)):
			count += 1
	return count


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_dictionary_direct(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return FileAccess.file_exists(path)


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
