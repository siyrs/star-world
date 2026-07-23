extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const CatalogPolicyScript = preload("res://src/save/world_catalog_policy.gd")
const ProductionWorldScript = preload("res://src/world/cached_batched_voxel_world.gd")

const WORLD_COUNT := 3
const OVERRIDES_PER_WORLD := 96

var checks := 0
var failures: Array[String] = []
var _world_ids: Array[String] = []
var _prefix := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_policy()
	_test_production_world_persistence_surface()
	await _test_catalog_round_trip_and_self_healing()
	if failures.is_empty():
		print("QA WORLD CATALOG PASS | checks=%d | worlds=%d" % [checks, WORLD_COUNT])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD CATALOG FAILURE: %s" % failure)
		print("QA WORLD CATALOG FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_catalog_policy() -> void:
	var state := {
		"save_version": 2,
		"metadata": {
			"id": "wrong-id",
			"name": "  Catalog World  ",
			"map_id": "star_continent",
			"seed": 42,
			"created_at": "2026-07-23T00:00:00",
			"updated_at": "2026-07-23T01:00:00",
			"play_seconds": -7,
			"custom_scalar": "preserved",
		},
	}
	var entry: Dictionary = CatalogPolicyScript.build_entry("catalog-world", state, 4096)
	_check(
		int(entry.get("catalog_version", 0)) == CatalogPolicyScript.CATALOG_VERSION,
		"catalog policy emits the current schema version",
	)
	var metadata: Dictionary = entry.get("metadata", {})
	_check(
		str(metadata.get("id", "")) == "catalog-world"
		and str(metadata.get("name", "")) == "Catalog World",
		"catalog policy owns the authoritative world id and bounded display name",
	)
	_check(
		int(metadata.get("play_seconds", -1)) == 0
		and str(metadata.get("custom_scalar", "")) == "preserved",
		"catalog policy normalizes required fields without discarding compatible metadata",
	)
	var normalized := CatalogPolicyScript.normalize_entry(entry, "catalog-world", 4096)
	_check(not normalized.is_empty(), "matching catalog id and byte length normalize successfully")
	_check(
		CatalogPolicyScript.normalize_entry(entry, "other-world", 4096).is_empty(),
		"catalog entry with the wrong world id is rejected",
	)
	_check(
		CatalogPolicyScript.normalize_entry(entry, "catalog-world", 4097).is_empty(),
		"catalog entry with stale world byte length is rejected",
	)
	var listed := CatalogPolicyScript.metadata_for_list(normalized, "catalog")
	_check(
		int(listed.get("save_bytes", 0)) == 4096
		and str(listed.get("catalog_source", "")) == "catalog",
		"catalog list metadata exposes lightweight size and source diagnostics",
	)


func _test_production_world_persistence_surface() -> void:
	var world = ProductionWorldScript.new()
	world.profile_id = "star_continent"
	world.seed_value = 9911
	world.world_id = "catalog-production-world"
	world.block_overrides = {"0,20,0":"stone_bricks"}
	var serialized: Dictionary = world.serialize_state()
	_check(
		serialized.get("block_overrides", {}).get("0,20,0", "") == "stone_bricks",
		"production world serialization keeps authoritative sparse overrides",
	)
	_check(
		not serialized.has("loaded_chunks")
		and not serialized.has("recent_chunk_cache")
		and not serialized.has("rebuild"),
		"production world serialization excludes transient streaming and cache state",
	)


func _test_catalog_round_trip_and_self_healing() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	_prefix = "qa-catalog-%d" % Time.get_ticks_msec()
	var expected_world_bytes := 0
	for index in WORLD_COUNT:
		var state: Dictionary = save.create_world(
			"%s-%d" % [_prefix, index],
			"star_continent",
			700100 + index,
		)
		_check(not state.is_empty(), "catalog fixture world %d is created" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		_world_ids.append(world_id)
		var overrides: Dictionary = {}
		for offset in OVERRIDES_PER_WORLD:
			var x := index * 200 + offset % 16
			var y := 20 + int(offset / 32)
			var z := int(offset / 16)
			overrides["%d,%d,%d" % [x, y, z]] = "stone_bricks"
		state["world"] = {
			"block_overrides": overrides,
			"loaded_chunks": [[index, 0], [index + 1, 0]],
		}
		state["metadata"]["play_seconds"] = index * 120
		_check(save.save_world(world_id, state), "catalog fixture world %d saves" % index)
		var world_path := _world_path(world_id)
		var catalog_path := _catalog_path(world_id)
		_check(FileAccess.file_exists(catalog_path), "world %d writes a lightweight catalog sidecar" % index)
		var bytes := _file_length(world_path)
		expected_world_bytes += bytes
		_check(bytes > 0, "world %d authoritative payload has a measurable byte length" % index)
		var raw_payload := _read_dictionary(world_path)
		_check(
			not (raw_payload.get("world", {}) as Dictionary).has("loaded_chunks"),
			"world %d strips transient loaded Chunk coordinates before disk persistence" % index,
		)

	_check(_world_ids.size() == WORLD_COUNT, "all catalog fixture worlds are available")
	if _world_ids.size() != WORLD_COUNT:
		_cleanup(save)
		save.queue_free()
		await process_frame
		return

	save.reset_catalog_diagnostics()
	var first_list: Array = save.list_worlds()
	var first_matches := _matching_worlds(first_list)
	var first_diagnostics: Dictionary = save.get_catalog_diagnostics()
	_check(first_matches.size() == WORLD_COUNT, "catalog listing returns every fixture world")
	_check(
		int(first_diagnostics.get("last_hit_count", 0)) >= WORLD_COUNT
		and int(first_diagnostics.get("last_fallback_count", -1)) == 0,
		"fresh world listing reads sidecars without parsing authoritative payloads",
	)
	_check(
		int(first_diagnostics.get("last_avoided_world_bytes", 0)) >= expected_world_bytes,
		"catalog diagnostics prove that full world bytes were avoided",
	)
	for metadata: Dictionary in first_matches:
		_check(
			int(metadata.get("save_bytes", 0)) > 0
			and str(metadata.get("catalog_source", "")) == "catalog",
			"world list exposes size through the catalog path",
		)

	_remove_file(_catalog_path(_world_ids[0]))
	save.reset_catalog_diagnostics()
	var repaired_missing: Array = save.list_worlds()
	var missing_diagnostics: Dictionary = save.get_catalog_diagnostics()
	_check(
		_matching_worlds(repaired_missing).size() == WORLD_COUNT,
		"missing catalog never hides an authoritative world",
	)
	_check(
		int(missing_diagnostics.get("last_fallback_count", 0)) >= 1
		and int(missing_diagnostics.get("last_repair_count", 0)) >= 1
		and FileAccess.file_exists(_catalog_path(_world_ids[0])),
		"missing catalog falls back once and self-heals",
	)

	_write_text(_catalog_path(_world_ids[1]), "{broken catalog")
	save.reset_catalog_diagnostics()
	var repaired_corrupt: Array = save.list_worlds()
	var corrupt_diagnostics: Dictionary = save.get_catalog_diagnostics()
	_check(
		_matching_worlds(repaired_corrupt).size() == WORLD_COUNT,
		"corrupt catalog never hides an authoritative world",
	)
	_check(
		int(corrupt_diagnostics.get("last_fallback_count", 0)) >= 1
		and int(corrupt_diagnostics.get("last_repair_count", 0)) >= 1,
		"corrupt catalog uses authoritative fallback and repairs itself",
	)
	var repaired_entry := _read_dictionary(_catalog_path(_world_ids[1]))
	_check(
		int(repaired_entry.get("catalog_version", 0)) == CatalogPolicyScript.CATALOG_VERSION,
		"self-healed catalog is valid JSON with the current schema",
	)

	var loaded: Dictionary = save.load_world(_world_ids[2])
	_check(
		(loaded.get("world", {}) as Dictionary).get("block_overrides", {}).size()
		== OVERRIDES_PER_WORLD,
		"catalog optimization leaves full world loading unchanged",
	)
	_check(
		not (loaded.get("world", {}) as Dictionary).has("loaded_chunks"),
		"legacy transient Chunk coordinates are removed during load migration",
	)

	_cleanup(save)
	save.queue_free()
	await process_frame


func _matching_worlds(worlds: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_metadata: Variant in worlds:
		if raw_metadata is not Dictionary:
			continue
		var metadata: Dictionary = raw_metadata
		if str(metadata.get("name", "")).begins_with(_prefix):
			result.append(metadata)
	return result


func _cleanup(save: Node) -> void:
	for world_id: String in _world_ids:
		if save != null and is_instance_valid(save):
			save.call("delete_world", world_id)
	_world_ids.clear()


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _file_length(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := int(file.get_length())
	file.close()
	return length


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(value)
	file.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
