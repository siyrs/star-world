extends SceneTree

# OpenSpec 7.1: save/load release matrix.
# Fills the four gaps not covered by existing focused suites:
#   1. manual-save round-trip through the production hub save_current() path
#   2. overwrite: a later save_world() replaces data and .bak holds the previous generation
#   3. multi-world: N distinct real worlds with distinct payloads list/load independently
#   4. old-schema migration: a v1 world.json on disk loads as save_version=2 with backfilled domains
# Existing suites already cover: autosave (bounded_autosave), exit/read-back relaunch
# (acceptance_suite), malformed .tmp/.bak recovery (save_recovery, bounded_multi_world),
# user-data isolation (profile journey pre/post manifest). This script still records its own
# pre/post manifest for the worlds it touches and cleans them up.

const SaveServiceScript = preload("res://src/save/save_service.gd")
const GameScene = preload("res://scenes/game/game.tscn")

const QA_PREFIX := "qa-v130-savematrix-"
const MATRIX_SEED := 112358

var checks := 0
var failures: Array[String] = []
var _created_world_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Track only this suite's QA prefix: under headless CI the user://worlds dir is
	# shared with any concurrently-running QA soak, so a global pre/post manifest
	# would be polluted by unrelated QA worlds. The isolation contract that matters
	# is "this suite leaves zero worlds behind".
	var pre_qa_worlds := _qa_world_ids()

	await _test_manual_save_roundtrip()
	await _test_overwrite_generations()
	await _test_multi_world_independence()
	await _test_v1_schema_migration()

	var post_qa_worlds := _qa_world_ids()
	_check(
		post_qa_worlds == pre_qa_worlds,
		"save matrix leaves no QA worlds behind (pre=%d post=%d)" % [pre_qa_worlds.size(), post_qa_worlds.size()]
	)

	if failures.is_empty():
		print("QA SAVE MATRIX PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA SAVE MATRIX FAILURE: %s" % failure)
	print("QA SAVE MATRIX FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _qa_world_ids() -> Array[String]:
	var ids: Array[String] = []
	var directory := DirAccess.open("user://worlds")
	if directory == null:
		return ids
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if not entry_name.begins_with(".") and directory.current_is_dir() and entry_name.begins_with("qa-v130-savematrix-"):
			ids.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	ids.sort()
	return ids


# --- 1. Manual save through the production hub path (UI save button / autosave / return all
# funnel through service_hub.save_current). Drives a real world entry, mutates inventory,
# saves, reloads from disk, and verifies the mutation persisted. ---
func _test_manual_save_roundtrip() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub: Node = game.get("service_hub")
	var save: Node = hub.get("save_service")
	_check(hub != null and save != null, "manual-save: production hub and save service mount")
	if hub == null or save == null:
		game.queue_free()
		await process_frame
		return

	var display_name := "%smanual-%d" % [QA_PREFIX, Time.get_ticks_msec()]
	var state: Dictionary = save.call("create_world", display_name, "star_continent", MATRIX_SEED)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_track(world_id)
	_check(not world_id.is_empty(), "manual-save: QA world is created with a fixed seed")

	game.call("begin_world_state", state)
	for _frame in 30:
		await process_frame
	_check(str(hub.get("current_world_id")) == world_id, "manual-save: hub begins the QA world")

	var inventory: Node = hub.get("inventory")
	if inventory != null and inventory.has_method("add_item"):
		inventory.call("add_item", "stone", 7)
	var saved: bool = bool(hub.call("save_current"))
	_check(saved, "manual-save: hub.save_current() commits the manual save")

	var loaded: Dictionary = save.call("load_world", world_id)
	var loaded_slots: Array = loaded.get("inventory", {}).get("slots", [])
	var found_stone := false
	for slot: Variant in loaded_slots:
		if slot is Dictionary and str((slot as Dictionary).get("item_id", "")) == "stone" and int((slot as Dictionary).get("count", 0)) >= 7:
			found_stone = true
	_check(found_stone, "manual-save: inventory mutation survives the save/load round-trip")
	_check(
		int(loaded.get("save_version", 0)) == 2,
		"manual-save: round-trip payload carries the current save_version"
	)

	if str(hub.get("current_world_id")) == world_id:
		hub.call("return_to_menu")
		for _frame in 30:
			await process_frame
	_cleanup_world(save, world_id)
	game.queue_free()
	for _frame in 10:
		await process_frame


# --- 2. Overwrite: two generations of one world; primary holds the latest, .bak the previous. ---
func _test_overwrite_generations() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame

	var display_name := "%soverwrite-%d" % [QA_PREFIX, Time.get_ticks_msec()]
	var state: Dictionary = save.call("create_world", display_name, "desert_ruins", MATRIX_SEED)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_track(world_id)
	_check(not world_id.is_empty(), "overwrite: QA world is created")

	var gen1: Dictionary = state.duplicate(true)
	gen1["player"] = {"position": [1.0, 20.0, 1.0], "generation_marker": 1}
	_check(bool(save.call("save_world", world_id, gen1)), "overwrite: generation 1 saves")

	var gen2: Dictionary = state.duplicate(true)
	gen2["player"] = {"position": [9.0, 30.0, 9.0], "generation_marker": 2}
	_check(bool(save.call("save_world", world_id, gen2)), "overwrite: generation 2 saves over generation 1")

	var loaded: Dictionary = save.call("load_world", world_id)
	_check(
		int(loaded.get("player", {}).get("generation_marker", 0)) == 2,
		"overwrite: primary world.json serves the latest generation"
	)

	var bak_path := "user://worlds/%s/world.json.bak" % world_id
	_check(FileAccess.file_exists(bak_path), "overwrite: previous generation is preserved as .bak")
	var bak_text := FileAccess.get_file_as_string(bak_path)
	var bak_json: Variant = JSON.parse_string(bak_text)
	_check(
		bak_json is Dictionary and int((bak_json as Dictionary).get("player", {}).get("generation_marker", 0)) == 1,
		"overwrite: .bak holds the previous generation payload"
	)

	_cleanup_world(save, world_id)
	save.queue_free()
	await process_frame
	await process_frame


# --- 3. Multi-world: three real worlds with distinct payloads list and load independently. ---
func _test_multi_world_independence() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame

	var specs: Array[Array] = [
		["star_continent", 111],
		["frozen_wastes", 222],
		["abyss_world", 333],
	]
	var world_ids: Array[String] = []
	for spec: Array in specs:
		var display_name := "%smulti-%s-%d" % [QA_PREFIX, spec[0], Time.get_ticks_msec()]
		var state: Dictionary = save.call("create_world", display_name, spec[0], spec[1])
		var world_id := str(state.get("metadata", {}).get("id", ""))
		_track(world_id)
		world_ids.append(world_id)
		var payload: Dictionary = state.duplicate(true)
		payload["player"] = {"position": [float(spec[1]), 25.0, float(spec[1])], "marker": spec[1]}
		save.call("save_world", world_id, payload)
	_check(world_ids.size() == 3 and not world_ids.has(""), "multi-world: three QA worlds are created")

	var listed: Array = save.call("list_worlds")
	var listed_ids: Array[String] = []
	for entry: Variant in listed:
		if entry is Dictionary:
			listed_ids.append(str((entry as Dictionary).get("id", "")))
	for world_id: String in world_ids:
		_check(world_id in listed_ids, "multi-world: catalog lists %s" % world_id.get_slice("-", 0))

	for index in world_ids.size():
		var loaded: Dictionary = save.call("load_world", world_ids[index])
		var expected_marker: int = specs[index][1]
		_check(
			int(loaded.get("player", {}).get("marker", 0)) == expected_marker
			and str(loaded.get("metadata", {}).get("map_id", "")) == specs[index][0],
			"multi-world: world %d loads its own distinct payload" % index
		)

	for world_id: String in world_ids:
		_cleanup_world(save, world_id)
	save.queue_free()
	await process_frame
	await process_frame


# --- 4. Old-schema migration: write a v1 world.json to disk, load through the service, and
# require save_version=2 plus backfilled day_night/survival/agriculture domains. ---
func _test_v1_schema_migration() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame

	var display_name := "%smigrate-%d" % [QA_PREFIX, Time.get_ticks_msec()]
	var state: Dictionary = save.call("create_world", display_name, "sky_islands", MATRIX_SEED)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_track(world_id)
	_check(not world_id.is_empty(), "migration: QA world shell is created")

	# Rewrite the on-disk payload as a minimal v1 save (the shape produced before
	# day_night/survival/equipment/agriculture existed).
	var v1_payload := {
		"save_version": 1,
		"metadata": state.get("metadata", {}),
		"player": {"position": [0.5, 45.0, 0.5]},
		"inventory": {"items": {}},
		"world": {"block_overrides": {}},
	}
	var world_path := "user://worlds/%s/world.json" % world_id
	var direct := FileAccess.open(world_path, FileAccess.WRITE)
	_check(direct != null, "migration: v1 payload file opens for writing")
	if direct != null:
		direct.store_string(JSON.stringify(v1_payload))
		direct.close()

	var loaded: Dictionary = save.call("load_world", world_id)
	_check(not loaded.is_empty(), "migration: v1 world loads through the service")
	_check(
		int(loaded.get("save_version", 0)) == 2,
		"migration: loaded payload is upgraded to save_version 2"
	)
	_check(
		loaded.get("day_night", {}) is Dictionary and not (loaded.get("day_night", {}) as Dictionary).is_empty(),
		"migration: day_night domain is backfilled"
	)
	_check(
		loaded.get("survival", {}) is Dictionary and not (loaded.get("survival", {}) as Dictionary).is_empty(),
		"migration: survival domain is backfilled"
	)
	_check(
		loaded.get("agriculture", {}) is Dictionary
		and ((loaded.get("agriculture", {}) as Dictionary).get("soil_moisture", {}) is Dictionary),
		"migration: agriculture domain is backfilled with soil_moisture"
	)
	_check(
		str(loaded.get("metadata", {}).get("id", "")) == world_id
		and str(loaded.get("metadata", {}).get("map_id", "")) == "sky_islands",
		"migration: original v1 metadata survives the upgrade"
	)
	_check(
		(loaded.get("player", {}) as Dictionary).get("position", []) == [0.5, 45.0, 0.5],
		"migration: original v1 player payload survives the upgrade"
	)

	_cleanup_world(save, world_id)
	save.queue_free()
	await process_frame
	await process_frame


func _track(world_id: String) -> void:
	if not world_id.is_empty() and world_id not in _created_world_ids:
		_created_world_ids.append(world_id)


func _cleanup_world(save: Node, world_id: String) -> void:
	if world_id.is_empty():
		return
	if bool(save.call("world_exists", world_id)):
		_check(bool(save.call("delete_world", world_id)), "cleanup: QA world %s is deleted" % world_id)


func _directory_manifest(directory_path: String) -> Dictionary:
	var manifest: Dictionary = {}
	_append_directory_manifest(directory_path, "", manifest)
	return manifest


func _append_directory_manifest(directory_path: String, relative_path: String, manifest: Dictionary) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if not entry_name.begins_with("."):
			var child_relative := entry_name if relative_path.is_empty() else relative_path.path_join(entry_name)
			var child_path := directory_path.path_join(entry_name)
			if directory.current_is_dir():
				_append_directory_manifest(child_path, child_relative, manifest)
			else:
				manifest[child_relative] = {
					"bytes": FileAccess.get_file_as_bytes(child_path).size(),
					"sha256": FileAccess.get_sha256(child_path),
				}
		entry_name = directory.get_next()
	directory.list_dir_end()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
