extends SceneTree

const ProtectedSaveServiceScript = preload(
	"res://src/save/protected_save_service.gd"
)

var checks := 0
var failures: Array[String] = []
var service: Node
var world_ids: Array[String] = []
var trash_ids: Array[String] = []
var prefix := "qa-trash-integrity-%d-%d" % [
	int(Time.get_unix_time_from_system()), Time.get_ticks_msec()
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = ProtectedSaveServiceScript.new()
	root.add_child(service)
	await process_frame
	await _test_backup_recovery_across_restart()
	await _test_temporary_recovery_across_restart()
	await _test_wrong_identity_rejection()
	await _test_all_candidates_corrupt_rejection()
	_cleanup_fixture()
	service.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("QA TRASH RESTORE INTEGRITY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA TRASH RESTORE INTEGRITY FAILURE: %s" % failure)
	print(
		"QA TRASH RESTORE INTEGRITY FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_backup_recovery_across_restart() -> void:
	var fixture := _create_trashed_fixture("backup")
	var world_id := str(fixture.get("world_id", ""))
	var trash_id := str(fixture.get("trash_id", ""))
	if world_id.is_empty() or trash_id.is_empty():
		return
	_write_text(_trash_world_path(trash_id), "{broken-primary")
	await _restart_service()
	var slot := _find_slot(trash_id)
	_check(
		bool(slot.get("valid", false))
		and bool(slot.get("restorable", false))
		and str(slot.get("integrity_source", "")) == "backup"
		and bool(slot.get("requires_primary_repair", false)),
		"restart detects a valid backup without trusting the corrupted primary"
	)
	var restored: Dictionary = service.call("restore_trashed_world", trash_id)
	_check(
		bool(restored.get("ok", false))
		and str(restored.get("recovery_source", "")) == "backup"
		and bool(restored.get("repaired_primary", false)),
		"backup recovery repairs the isolated primary before directory promotion"
	)
	var loaded: Dictionary = service.call("load_world", world_id)
	_check(
		str(loaded.get("metadata", {}).get("qa_marker", "")) == "backup-valid",
		"backup recovery restores the last validated backup generation"
	)
	_check(
		not FileAccess.file_exists(_catalog_path(world_id)),
		"repaired restore invalidates the derived catalog before activation"
	)
	service.call("list_worlds")
	_check(
		FileAccess.file_exists(_catalog_path(world_id)),
		"first authoritative listing rebuilds the invalidated catalog"
	)
	var diagnostics: Dictionary = service.call("get_trash_diagnostics")
	_check(
		int(diagnostics.get("restore_repair_attempt_count", 0)) >= 1
		and int(diagnostics.get("restore_repair_success_count", 0)) >= 1
		and int(diagnostics.get("restore_repair_failure_count", -1)) == 0,
		"backup repair is counted once without a false failure"
	)


func _test_temporary_recovery_across_restart() -> void:
	var fixture := _create_trashed_fixture("temporary")
	var world_id := str(fixture.get("world_id", ""))
	var trash_id := str(fixture.get("trash_id", ""))
	if world_id.is_empty() or trash_id.is_empty():
		return
	var payload := _read_dictionary(_trash_world_path(trash_id))
	payload["metadata"]["qa_marker"] = "temporary-valid"
	_write_text("%s.tmp" % _trash_world_path(trash_id), JSON.stringify(payload, "\t"))
	_write_text(_trash_world_path(trash_id), "{broken-primary")
	_write_text("%s.bak" % _trash_world_path(trash_id), "{broken-backup")
	await _restart_service()
	var slot := _find_slot(trash_id)
	_check(
		bool(slot.get("valid", false))
		and str(slot.get("integrity_source", "")) == "temporary",
		"restart selects the valid temporary candidate ahead of a broken backup"
	)
	var restored: Dictionary = service.call("restore_trashed_world", trash_id)
	var loaded: Dictionary = service.call("load_world", world_id)
	_check(
		bool(restored.get("ok", false))
		and str(restored.get("recovery_source", "")) == "temporary"
		and str(loaded.get("metadata", {}).get("qa_marker", "")) == "temporary-valid",
		"temporary recovery promotes and reloads the exact validated payload"
	)


func _test_wrong_identity_rejection() -> void:
	var fixture := _create_trashed_fixture("wrong-id")
	var world_id := str(fixture.get("world_id", ""))
	var trash_id := str(fixture.get("trash_id", ""))
	if world_id.is_empty() or trash_id.is_empty():
		return
	var payload := _read_dictionary(_trash_world_path(trash_id))
	payload["metadata"]["id"] = "%s-other" % world_id
	var encoded := JSON.stringify(payload, "\t")
	for suffix: String in ["", ".tmp", ".bak"]:
		_write_text("%s%s" % [_trash_world_path(trash_id), suffix], encoded)
	await _restart_service()
	var slot := _find_slot(trash_id)
	_check(
		not bool(slot.get("valid", true))
		and not bool(slot.get("restorable", true))
		and bool(slot.get("purgeable", false))
		and str(slot.get("reason", "")) == "world_payload_unrecoverable",
		"wrong-world candidates are purgeable but never restorable"
	)
	var restored: Dictionary = service.call("restore_trashed_world", trash_id)
	_check(
		not bool(restored.get("ok", true))
		and str(restored.get("reason", "")) == "world_payload_unrecoverable",
		"metadata identity mismatch is rejected by the authoritative restore endpoint"
	)
	_check(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("user://worlds/%s" % world_id)
		),
		"identity mismatch never enters the active world directory"
	)
	_check(
		bool(service.call("purge_trash_slot", trash_id)),
		"identity-mismatched physical slot remains safely purgeable"
	)


func _test_all_candidates_corrupt_rejection() -> void:
	var fixture := _create_trashed_fixture("all-corrupt")
	var world_id := str(fixture.get("world_id", ""))
	var trash_id := str(fixture.get("trash_id", ""))
	if world_id.is_empty() or trash_id.is_empty():
		return
	for suffix: String in ["", ".tmp", ".bak"]:
		_write_text(
			"%s%s" % [_trash_world_path(trash_id), suffix],
			"{broken-%s" % suffix
		)
	await _restart_service()
	var restored: Dictionary = service.call("restore_trashed_world", trash_id)
	var diagnostics: Dictionary = service.call("get_trash_diagnostics")
	_check(
		not bool(restored.get("ok", true))
		and str(restored.get("reason", "")) == "world_payload_unrecoverable"
		and int(diagnostics.get("restore_integrity_failure_count", 0)) >= 1,
		"all-corrupt candidates fail closed and enter bounded diagnostics"
	)
	_check(
		not bool(service.call("world_exists", world_id))
		and bool(service.call("purge_trash_slot", trash_id)),
		"all-corrupt slot is never activated and can be explicitly cleaned"
	)


func _create_trashed_fixture(label: String) -> Dictionary:
	var state: Dictionary = service.call(
		"create_world",
		"%s-%s" % [prefix, label],
		"star_continent",
		610000 + world_ids.size()
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "%s fixture creates an authoritative world" % label)
	if world_id.is_empty():
		return {}
	world_ids.append(world_id)
	state["metadata"]["qa_marker"] = "backup-valid"
	_check(
		bool(service.call("save_world", world_id, state)),
		"%s fixture writes a validated backup generation" % label
	)
	state["metadata"]["qa_marker"] = "primary-latest"
	_check(
		bool(service.call("save_world", world_id, state)),
		"%s fixture writes a newer primary generation" % label
	)
	var trashed: Dictionary = service.call("trash_world", world_id)
	var trash_id := str(trashed.get("trash_id", ""))
	_check(
		bool(trashed.get("ok", false)) and not trash_id.is_empty(),
		"%s fixture enters the bounded trash manager" % label
	)
	if not trash_id.is_empty():
		trash_ids.append(trash_id)
	return {"world_id": world_id, "trash_id": trash_id}


func _restart_service() -> void:
	service.queue_free()
	await process_frame
	await process_frame
	service = ProtectedSaveServiceScript.new()
	root.add_child(service)
	await process_frame


func _find_slot(trash_id: String) -> Dictionary:
	var slots: Array = service.call("list_trash_slots", 32)
	for raw_entry: Variant in slots:
		if raw_entry is Dictionary and str(raw_entry.get("trash_id", "")) == trash_id:
			return raw_entry
	return {}


func _cleanup_fixture() -> void:
	if service == null:
		return
	for raw_entry: Variant in service.call("list_trash_slots", 32):
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var trash_id := str(entry.get("trash_id", ""))
		var world_id := str(entry.get("world_id", ""))
		if world_id.begins_with(prefix) or trash_ids.has(trash_id):
			service.call("purge_trash_slot", trash_id)
	for world_id: String in world_ids:
		if bool(service.call("world_exists", world_id)):
			service.call("delete_world", world_id)


func _read_dictionary(path: String) -> Dictionary:
	var text := _read_text(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture opens %s" % path.get_file())
	if file != null:
		file.store_string(text)
		file.close()


func _trash_world_path(trash_id: String) -> String:
	return "user://world_trash/%s/world.json" % trash_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
