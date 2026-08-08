extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const OLD_NAME := "ALPHA"
const NEW_NAME := "BRAVO"

var checks := 0
var failures: Array[String] = []
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first = SaveServiceScript.new()
	root.add_child(first)
	await process_frame
	var state: Dictionary = first.create_world(
		"%s-%d" % [OLD_NAME, Time.get_ticks_msec()],
		"star_continent",
		580058
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "fixture creates one authoritative catalog-backed world")
	if _world_id.is_empty():
		await _finish(first)
		return

	# Replace only the fixed-width display-name fragment. The world file therefore
	# keeps the exact same byte length as the old catalog identity, reproducing the
	# crash window that size-only sidecar validation cannot detect.
	var world_path := _world_path(_world_id)
	var catalog_path := _catalog_path(_world_id)
	var original_text := _read_text(world_path)
	var updated_text := original_text.replace(OLD_NAME, NEW_NAME)
	_check(
		updated_text != original_text and updated_text.length() == original_text.length(),
		"same-byte authoritative mutation changes metadata without changing file size"
	)
	_check(_write_text(world_path, updated_text), "fixture writes the newer same-byte authoritative world")
	_check(_write_text(_pending_path(_world_id), "pending\n"), "fixture leaves the cross-file catalog transaction marker")
	var stale_catalog: Dictionary = _read_json(catalog_path)
	_check(
		str(stale_catalog.get("metadata", {}).get("name", "")).contains(OLD_NAME),
		"pre-restart sidecar still contains the older display metadata"
	)

	first.queue_free()
	for _frame in 3:
		await process_frame
	var restarted = SaveServiceScript.new()
	root.add_child(restarted)
	await process_frame
	restarted.reset_catalog_diagnostics()
	var worlds: Array = restarted.list_worlds()
	var listed := _metadata_for_world(worlds, _world_id)
	var first_diagnostics: Dictionary = restarted.get_catalog_diagnostics()
	_check(
		str(listed.get("name", "")).contains(NEW_NAME),
		"restart rejects the stale same-byte sidecar and lists authoritative metadata"
	)
	_check(
		str(listed.get("catalog_source", "")) == "world_fallback",
		"pending transaction marker forces exactly one authoritative fallback"
	)
	_check(
		int(first_diagnostics.get("pending_marker_detected_count", 0)) == 1
		and int(first_diagnostics.get("last_pending_marker_detected_count", 0)) == 1,
		"catalog diagnostics expose the detected interrupted transaction"
	)
	_check(
		int(first_diagnostics.get("last_authoritative_read_budget_used", 0)) == 1
		and int(first_diagnostics.get("last_catalog_rebuild_budget_used", 0)) == 1
		and int(first_diagnostics.get("last_repair_count", 0)) == 1,
		"self-healing consumes one bounded read and one bounded sidecar rebuild"
	)
	_check(
		not FileAccess.file_exists(_pending_path(_world_id)),
		"successful sidecar rebuild clears the interrupted transaction marker"
	)
	var rebuilt_catalog: Dictionary = _read_json(catalog_path)
	_check(
		str(rebuilt_catalog.get("metadata", {}).get("name", "")).contains(NEW_NAME),
		"rebuilt sidecar now matches the authoritative same-byte metadata"
	)

	restarted.reset_catalog_diagnostics()
	var steady_worlds: Array = restarted.list_worlds()
	var steady_diagnostics: Dictionary = restarted.get_catalog_diagnostics()
	_check(
		str(_metadata_for_world(steady_worlds, _world_id).get("name", "")).contains(NEW_NAME),
		"steady restart listing preserves the repaired metadata"
	)
	_check(
		int(steady_diagnostics.get("last_hit_count", 0)) == 1
		and int(steady_diagnostics.get("last_fallback_count", -1)) == 0
		and int(steady_diagnostics.get("last_authoritative_read_budget_used", -1)) == 0,
		"second listing is a pure sidecar hit with zero authoritative reads; diagnostics=%s"
		% JSON.stringify(steady_diagnostics)
	)
	var loaded: Dictionary = restarted.load_world(_world_id)
	_check(
		str(loaded.get("metadata", {}).get("name", "")).contains(NEW_NAME),
		"normal world loading retains the recovered authoritative metadata"
	)
	await _finish(restarted)


func _metadata_for_world(worlds: Array, world_id: String) -> Dictionary:
	for raw_metadata: Variant in worlds:
		if raw_metadata is Dictionary and str(raw_metadata.get("id", "")) == world_id:
			return raw_metadata
	return {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


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


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return parsed if parsed is Dictionary else {}


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _pending_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.pending" % world_id


func _finish(save: Node) -> void:
	if save != null and is_instance_valid(save):
		if not _world_id.is_empty() and bool(save.call("world_exists", _world_id)):
			save.call("delete_world", _world_id)
		save.queue_free()
	for _frame in 4:
		await process_frame
	if failures.is_empty():
		print("QA CATALOG TRANSACTION MARKER RECOVERY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA CATALOG TRANSACTION MARKER RECOVERY FAILURE: %s" % failure)
	print("QA CATALOG TRANSACTION MARKER RECOVERY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
