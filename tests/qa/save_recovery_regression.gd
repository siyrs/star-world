extends SceneTree

const AtomicStoreScript = preload("res://src/save/atomic_json_store.gd")
const SaveServiceScript = preload("res://src/save/save_service.gd")
const HealthPolicyScript = preload("res://src/diagnostics/runtime_health_report_policy.gd")

const TEST_ROOT := "user://qa-save-recovery"
const EXPECTED_OVERRIDE_COUNT := 64

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_validated_backup_repair()
	await _test_temporary_candidate_precedence()
	await _test_save_service_repair_and_catalog_rebuild()
	_test_health_projection()
	_remove_empty_directory(TEST_ROOT)
	if failures.is_empty():
		print("QA SAVE RECOVERY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE RECOVERY FAILURE: %s" % failure)
		print("QA SAVE RECOVERY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_validated_backup_repair() -> void:
	var store = AtomicStoreScript.new()
	var path := _atomic_path("backup")
	var backup_payload := _atomic_payload("backup-good")
	var newer_payload := _atomic_payload("newer-primary")
	_check(store.write_dictionary(path, backup_payload), "atomic fixture writes the initial primary")
	_check(store.write_dictionary(path, newer_payload), "atomic fixture creates a valid backup generation")
	_check(
		_write_dictionary_direct(path, {
			"metadata": {"id": "qa-atomic"},
			"player": "syntactically-valid-but-invalid",
			"world": {"block_overrides": {}},
		}),
		"atomic fixture replaces the primary with parseable structural corruption",
	)
	var result: Dictionary = store.read_dictionary_validated(
		path,
		Callable(self, "_valid_atomic_payload"),
		true,
	)
	_check(bool(result.get("ok", false)), "validated read finds a usable recovery generation")
	_check(str(result.get("source", "")) == "backup", "structurally invalid primary falls back to backup")
	_check(
		str(result.get("data", {}).get("marker", "")) == "backup-good",
		"backup recovery returns the expected authoritative generation",
	)
	_check(
		bool(result.get("repair_attempted", false))
		and bool(result.get("repair_success", false)),
		"backup recovery atomically promotes a repaired primary",
	)
	_check(
		(result.get("rejected_sources", []) as Array).has("primary"),
		"semantic validator records the rejected primary source",
	)
	var steady: Dictionary = store.read_dictionary_validated(
		path,
		Callable(self, "_valid_atomic_payload"),
		false,
	)
	_check(
		str(steady.get("source", "")) == "primary"
		and str(steady.get("data", {}).get("marker", "")) == "backup-good",
		"the next read uses the repaired primary without another fallback",
	)
	_check(
		str(_read_dictionary_direct("%s%s" % [path, AtomicStoreScript.BACKUP_SUFFIX]).get("marker", ""))
		== "backup-good",
		"recovery promotion preserves the valid backup instead of overwriting it with corruption",
	)
	_check(_recovery_artifacts_absent(path), "successful promotion removes temporary recovery artifacts")
	_cleanup_file_family(path)
	await process_frame


func _test_temporary_candidate_precedence() -> void:
	var store = AtomicStoreScript.new()
	var path := _atomic_path("temporary")
	_check(
		_write_dictionary_direct(path, {
			"metadata": {"id": "qa-atomic"},
			"player": "invalid",
			"world": {"block_overrides": {}},
		}),
		"temporary fixture writes a structurally invalid primary",
	)
	_check(
		_write_dictionary_direct(
			"%s%s" % [path, AtomicStoreScript.TEMP_SUFFIX],
			_atomic_payload("temporary-newest"),
		),
		"temporary fixture writes a valid interrupted-save candidate",
	)
	_check(
		_write_dictionary_direct(
			"%s%s" % [path, AtomicStoreScript.BACKUP_SUFFIX],
			_atomic_payload("backup-older"),
		),
		"temporary fixture keeps an older valid backup",
	)
	var result: Dictionary = store.read_dictionary_validated(
		path,
		Callable(self, "_valid_atomic_payload"),
		true,
	)
	_check(str(result.get("source", "")) == "temporary", "valid temporary generation wins before the older backup")
	_check(
		str(result.get("data", {}).get("marker", "")) == "temporary-newest"
		and bool(result.get("repair_success", false)),
		"temporary generation becomes the repaired primary",
	)
	_check(
		str(_read_dictionary_direct(path).get("marker", "")) == "temporary-newest",
		"promoted primary retains the newest valid generation",
	)
	_check(
		str(_read_dictionary_direct("%s%s" % [path, AtomicStoreScript.BACKUP_SUFFIX]).get("marker", ""))
		== "backup-older",
		"temporary recovery leaves the older backup available",
	)
	_check(_recovery_artifacts_absent(path), "temporary promotion removes stale tmp and repair staging files")
	_cleanup_file_family(path)
	await process_frame


func _test_save_service_repair_and_catalog_rebuild() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	var state: Dictionary = save.create_world(
		"QA-Recovery-%d" % Time.get_ticks_msec(),
		"star_continent",
		730033,
	)
	_check(not state.is_empty(), "production save service creates a recovery fixture world")
	if state.is_empty():
		save.queue_free()
		await process_frame
		return
	var metadata: Dictionary = state.get("metadata", {})
	var world_id := str(metadata.get("id", ""))
	var backup_overrides := _block_overrides(EXPECTED_OVERRIDE_COUNT)
	metadata["recovery_marker"] = "backup-ready"
	state["metadata"] = metadata
	state["world"] = {"block_overrides": backup_overrides.duplicate(true)}
	_check(save.save_world(world_id, state), "production save writes the backup-ready generation")
	metadata["recovery_marker"] = "newer-primary"
	state["metadata"] = metadata
	var newer_overrides := backup_overrides.duplicate(true)
	newer_overrides["999,12,999"] = "glass_pane"
	state["world"] = {"block_overrides": newer_overrides}
	_check(save.save_world(world_id, state), "production save rotates the backup-ready generation into .bak")

	var world_path := _world_path(world_id)
	var catalog_path := _catalog_path(world_id)
	_remove_file(catalog_path)
	_check(
		_write_dictionary_direct(world_path, {
			"save_version": 2,
			"metadata": {"id": world_id, "name": "Parseable corruption"},
			"player": "invalid-player-domain",
			"world": {"block_overrides": "invalid-world-domain"},
		}),
		"production fixture corrupts the primary with valid JSON and invalid core domains",
	)
	save.reset_recovery_diagnostics()
	save.reset_catalog_diagnostics()
	var listed: Array = save.list_worlds()
	var recovery: Dictionary = save.get_recovery_diagnostics()
	var catalog: Dictionary = save.get_catalog_diagnostics()
	_check(_contains_world(listed, world_id), "catalog fallback keeps the recovered world visible")
	_check(
		int(recovery.get("recovery_count", 0)) == 1
		and int(recovery.get("repair_attempt_count", 0)) == 1
		and int(recovery.get("repair_success_count", 0)) == 1
		and int(recovery.get("repair_failure_count", 0)) == 0,
		"save diagnostics record one successful authoritative repair",
	)
	_check(
		str(recovery.get("last_source", "")) == "backup"
		and bool(recovery.get("last_repaired", false))
		and int(recovery.get("primary_rejection_count", 0)) == 1,
		"save diagnostics identify the rejected primary and backup source",
	)
	_check(
		int(recovery.get("last_candidate_bytes", 0)) > 0
		and int(recovery.get("last_primary_bytes", 0)) > 0
		and float(recovery.get("last_elapsed_milliseconds", 0.0)) >= 0.0,
		"save diagnostics retain bounded bytes and repair duration",
	)
	_check(
		int(catalog.get("last_fallback_count", 0)) == 1
		and int(catalog.get("last_repair_count", 0)) == 1,
		"catalog rebuild occurs only after the authoritative primary is healthy",
	)

	var repaired_primary := _read_dictionary_direct(world_path)
	var repaired_metadata: Dictionary = repaired_primary.get("metadata", {})
	var repaired_world: Dictionary = repaired_primary.get("world", {})
	_check(
		str(repaired_metadata.get("recovery_marker", "")) == "backup-ready",
		"repaired world.json contains the expected backup generation",
	)
	_check(
		(repaired_world.get("block_overrides", {}) as Dictionary).size()
		== EXPECTED_OVERRIDE_COUNT,
		"repaired world.json restores the exact sparse world state",
	)
	_check(
		str(_read_dictionary_direct("%s%s" % [world_path, AtomicStoreScript.BACKUP_SUFFIX]).get("metadata", {}).get("recovery_marker", ""))
		== "backup-ready",
		"production repair preserves the valid world backup",
	)
	var catalog_payload := _read_dictionary_direct(catalog_path)
	_check(
		int(catalog_payload.get("save_bytes", 0)) == _file_length(world_path),
		"rebuilt catalog is bound to the repaired primary byte length",
	)
	_check(_recovery_artifacts_absent(world_path), "production repair leaves no stale recovery files")

	var recovery_count_before_load := int(recovery.get("recovery_count", 0))
	var loaded: Dictionary = save.load_world(world_id)
	_check(
		str(loaded.get("metadata", {}).get("recovery_marker", "")) == "backup-ready",
		"normal full load now reads the repaired primary generation",
	)
	_check(
		int(save.get_recovery_diagnostics().get("recovery_count", 0))
		== recovery_count_before_load,
		"full load does not repeat recovery after primary repair",
	)
	save.reset_catalog_diagnostics()
	var steady_worlds: Array = save.list_worlds()
	var steady_catalog: Dictionary = save.get_catalog_diagnostics()
	_check(_contains_world(steady_worlds, world_id), "steady catalog still lists the repaired world")
	_check(
		int(steady_catalog.get("last_hit_count", 0)) == 1
		and int(steady_catalog.get("last_fallback_count", 0)) == 0,
		"next catalog scan is a pure sidecar hit without another authoritative read",
	)
	_check(
		(save.get_recovery_diagnostics().get("last_rejected_sources", []) as Array).size() <= 3,
		"recovery source diagnostics remain fixed-size",
	)
	_check(save.delete_world(world_id), "recovery fixture world is deleted")
	save.queue_free()
	await process_frame
	await process_frame


func _test_health_projection() -> void:
	var healed: Dictionary = HealthPolicyScript.build({
		"save": {
			"recovery_count": 1,
			"repair_attempt_count": 1,
			"repair_success_count": 1,
			"repair_failure_count": 0,
			"primary_rejection_count": 1,
			"last_recovery_source": "backup",
			"last_recovery_repaired": true,
			"last_recovery_bytes": 4096,
			"last_recovery_elapsed_milliseconds": 2.5,
		}
	})
	var healed_row := _row_by_id(healed, "save")
	_check(
		str(healed_row.get("status", "")) == "warning"
		and str(healed_row.get("issue", "")).contains("重建主存档"),
		"F3 health reports a successful self-heal as visible warning evidence",
	)
	var failed: Dictionary = HealthPolicyScript.build({
		"save": {
			"recovery_count": 1,
			"repair_attempt_count": 1,
			"repair_failure_count": 1,
			"last_recovery_source": "backup",
		}
	})
	var failed_row := _row_by_id(failed, "save")
	_check(
		str(failed.get("status", "")) == "critical"
		and str(failed_row.get("status", "")) == "critical",
		"F3 health treats an unrepaired authoritative primary as critical",
	)


func _atomic_payload(marker: String) -> Dictionary:
	return {
		"marker": marker,
		"metadata": {"id": "qa-atomic", "name": marker},
		"player": {"position": []},
		"world": {"block_overrides": {"0,1,0": "stone_bricks"}},
	}


func _valid_atomic_payload(payload: Dictionary) -> bool:
	return (
		payload.get("metadata", null) is Dictionary
		and payload.get("player", null) is Dictionary
		and payload.get("world", null) is Dictionary
		and (payload.get("world", {}) as Dictionary).get("block_overrides", null)
		is Dictionary
	)


func _block_overrides(count: int) -> Dictionary:
	var result: Dictionary = {}
	for index in count:
		result["%d,%d,%d" % [index % 16, 12 + int(index / 32), int(index / 16)]] = (
			"stone_bricks" if index % 3 != 0 else "glass_pane"
		)
	return result


func _row_by_id(report: Dictionary, row_id: String) -> Dictionary:
	for raw_row: Variant in report.get("rows", []):
		if raw_row is Dictionary and str(raw_row.get("id", "")) == row_id:
			return raw_row
	return {}


func _contains_world(worlds: Array, world_id: String) -> bool:
	for raw_metadata: Variant in worlds:
		if raw_metadata is Dictionary and str(raw_metadata.get("id", "")) == world_id:
			return true
	return false


func _atomic_path(label: String) -> String:
	return "%s/%s-%d/world.json" % [TEST_ROOT, label, Time.get_ticks_usec()]


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _write_dictionary_direct(path: String, payload: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(payload, "\t", false))


func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _read_dictionary_direct(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or parser.data is not Dictionary:
		return {}
	return parser.data


func _file_length(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := int(file.get_length())
	file.close()
	return length


func _recovery_artifacts_absent(path: String) -> bool:
	return (
		not FileAccess.file_exists("%s%s" % [path, AtomicStoreScript.TEMP_SUFFIX])
		and not FileAccess.file_exists("%s%s" % [path, AtomicStoreScript.RECOVERY_SUFFIX])
		and not FileAccess.file_exists("%s%s" % [path, AtomicStoreScript.DISPLACED_SUFFIX])
	)


func _cleanup_file_family(path: String) -> void:
	for suffix: String in [
		"",
		AtomicStoreScript.TEMP_SUFFIX,
		AtomicStoreScript.BACKUP_SUFFIX,
		AtomicStoreScript.RECOVERY_SUFFIX,
		AtomicStoreScript.DISPLACED_SUFFIX,
	]:
		_remove_file("%s%s" % [path, suffix])
	_remove_empty_directory(path.get_base_dir())


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_empty_directory(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := DirAccess.open(absolute)
	if directory != null and directory.get_files().is_empty() and directory.get_directories().is_empty():
		DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
