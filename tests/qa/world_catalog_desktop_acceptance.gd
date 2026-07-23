extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://world-catalog-desktop.png"
const WORLD_COUNT := 12
const OVERRIDES_PER_WORLD := 2048
const MAX_CATALOG_BYTES := 4096
const MAX_CATALOG_LIST_MILLISECONDS := 2500.0
const MIN_AVOIDED_WORLD_BYTES := 750000
const READY_FRAMES := 600
const CLEANUP_FRAMES := 10

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _prefix := ""
var _world_ids: Array[String] = []
var _world_id_by_name: Dictionary = {}
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 6:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	var main_menu: Control = hub.get("main_menu") as Control if hub != null else null
	var save: Node = hub.get("save_service") as Node if hub != null else null
	_check(
		hub != null and main_menu != null and save != null,
		"production game mounts the main menu and authoritative save service",
	)
	if hub == null or main_menu == null or save == null:
		await _finish(game, hub, save)
		return

	_prefix = "Catalog-Bench-%d" % Time.get_ticks_msec()
	var total_world_bytes := 0
	var total_override_count := 0
	var max_catalog_bytes := 0
	for index in WORLD_COUNT:
		var state: Dictionary = save.call(
			"create_world",
			"%s-%02d" % [_prefix, index + 1],
			"star_continent",
			810000 + index,
		)
		_check(not state.is_empty(), "desktop catalog creates world %d" % (index + 1))
		if state.is_empty():
			continue
		var raw_metadata: Variant = state.get("metadata", {})
		var metadata: Dictionary = raw_metadata if raw_metadata is Dictionary else {}
		var world_id := str(metadata.get("id", ""))
		var world_name := str(metadata.get("name", world_id))
		_world_ids.append(world_id)
		_world_id_by_name[world_name] = world_id
		var overrides: Dictionary = {}
		for offset in OVERRIDES_PER_WORLD:
			var x := index * 512 + offset % 32
			var y := 10 + int(offset / 1024)
			var z := int(offset / 32)
			overrides["%d,%d,%d" % [x, y, z]] = (
				"stone_bricks" if offset % 3 != 0 else "glass_pane"
			)
		state["world"] = {
			"block_overrides": overrides,
			"loaded_chunks": _legacy_loaded_chunks(),
		}
		metadata["play_seconds"] = index * 300
		metadata["map_profile"] = _large_metadata_extension(index)
		state["metadata"] = metadata
		_check(
			bool(save.call("save_world", world_id, state)),
			"desktop catalog persists world %d through the production atomic store" % (index + 1),
		)
		var world_bytes := _file_length(_world_path(world_id))
		var catalog_bytes := _file_length(_catalog_path(world_id))
		max_catalog_bytes = maxi(max_catalog_bytes, catalog_bytes)
		total_world_bytes += world_bytes
		total_override_count += overrides.size()
		_check(world_bytes > 0, "desktop world %d produces a measurable payload" % (index + 1))
		_check(
			catalog_bytes > 0 and catalog_bytes <= MAX_CATALOG_BYTES,
			"desktop world %d keeps its catalog below four kilobytes" % (index + 1),
		)
		var catalog_payload := _read_dictionary(_catalog_path(world_id))
		var raw_catalog_metadata: Variant = catalog_payload.get("metadata", {})
		var catalog_metadata: Dictionary = (
			raw_catalog_metadata if raw_catalog_metadata is Dictionary else {}
		)
		_check(
			not catalog_metadata.has("map_profile"),
			"desktop world %d excludes unbounded metadata extensions from the catalog" % (index + 1),
		)

	_check(_world_ids.size() == WORLD_COUNT, "desktop catalog creates all benchmark worlds")
	_check(
		total_override_count == WORLD_COUNT * OVERRIDES_PER_WORLD,
		"desktop fixture contains the exact large-world override count",
	)
	_check(
		total_world_bytes >= MIN_AVOIDED_WORLD_BYTES,
		"desktop fixture is large enough to prove avoided authoritative reads",
	)
	if _world_ids.size() != WORLD_COUNT:
		await _finish(game, hub, save)
		return

	_remove_file(_catalog_path(_world_ids[0]))
	_write_text(_catalog_path(_world_ids[1]), "{broken catalog")
	save.call("reset_catalog_diagnostics")
	var repaired_worlds: Array = save.call("list_worlds")
	var repair_diagnostics: Dictionary = save.call("get_catalog_diagnostics")
	_check(
		_matching_worlds(repaired_worlds).size() == WORLD_COUNT,
		"missing and corrupt sidecars never hide real worlds",
	)
	_check(
		int(repair_diagnostics.get("last_fallback_count", 0)) >= 2
		and int(repair_diagnostics.get("last_repair_count", 0)) >= 2,
		"production catalog performs bounded authoritative fallback and repairs both sidecars",
	)
	_check(
		FileAccess.file_exists(_catalog_path(_world_ids[0]))
		and _read_dictionary(_catalog_path(_world_ids[1])).has("catalog_version"),
		"desktop fallback leaves both catalog sidecars healthy",
	)

	var save_panel: Control = main_menu.get("_save_panel") as Control
	_check(save_panel != null, "production main menu exposes the save browser panel")
	if save_panel == null:
		await _finish(game, hub, save)
		return
	save.call("reset_catalog_diagnostics")
	var list_started := Time.get_ticks_usec()
	save_panel.call("refresh")
	var catalog_list_ms := float(Time.get_ticks_usec() - list_started) / 1000.0
	main_menu.call("_show_panel", save_panel)
	for _frame in 4:
		await process_frame
	var steady_diagnostics: Dictionary = save.call("get_catalog_diagnostics")
	_check(
		int(steady_diagnostics.get("last_hit_count", 0)) >= WORLD_COUNT,
		"steady-state save browser resolves every benchmark world from a sidecar",
	)
	_check(
		int(steady_diagnostics.get("last_avoided_world_bytes", 0)) >= total_world_bytes,
		"steady-state diagnostics account for every avoided benchmark payload byte",
	)
	_check(
		catalog_list_ms <= MAX_CATALOG_LIST_MILLISECONDS
		and float(steady_diagnostics.get("last_elapsed_milliseconds", 0.0))
		<= MAX_CATALOG_LIST_MILLISECONDS,
		"real save browser refresh completes inside the 2.5-second catalog budget",
	)

	var list_node: VBoxContainer = save_panel.get("_list") as VBoxContainer
	var status_label: Label = save_panel.get("_status") as Label
	_check(
		list_node != null and list_node.get_child_count() >= WORLD_COUNT,
		"save browser renders every benchmark world as a real selectable row",
	)
	_check(
		status_label != null and status_label.text.contains("目录") and status_label.text.contains("ms"),
		"save browser communicates lightweight catalog latency",
	)
	var target_load_button: Button = null
	var target_world_id := ""
	var size_label_found := false
	if list_node != null:
		for row: Node in list_node.get_children():
			if row.get_child_count() < 2:
				continue
			var select_button := row.get_child(0) as Button
			var load_button := row.get_child(1) as Button
			if select_button == null or load_button == null:
				continue
			if select_button.text.contains(_prefix):
				size_label_found = (
					select_button.text.contains("存档")
					and (
						select_button.text.contains("KB")
						or select_button.text.contains("MB")
					)
				)
				var world_name := _world_name_from_row(select_button.text)
				target_load_button = load_button
				target_world_id = str(_world_id_by_name.get(world_name, ""))
				break
	_check(size_label_found, "real save row shows a human-readable authoritative file size")
	_check(target_load_button != null, "desktop acceptance locates a real continue button")
	_check(not target_world_id.is_empty(), "desktop acceptance resolves the selected row without full world reads")

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the large-world save browser")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "world catalog evidence uses the 1024x576 product resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var image_error := image.save_png(_capture_path)
		_check(
			image_error == OK and FileAccess.file_exists(_capture_path),
			"world catalog screenshot is saved",
		)

	if target_load_button != null and not target_world_id.is_empty():
		target_load_button.pressed.emit()
		_check(
			await _wait_for_world_ready(game, hub, target_world_id),
			"save browser continue button starts the selected full world",
		)
		var loaded_world_node: Node = game.get("world") as Node
		_check(
			loaded_world_node != null and bool(loaded_world_node.get("is_started")),
			"catalog-backed selection reaches a playable production world",
		)
		var loaded_payload: Dictionary = save.call("load_world", target_world_id)
		var raw_loaded_world: Variant = loaded_payload.get("world", {})
		var loaded_world: Dictionary = raw_loaded_world if raw_loaded_world is Dictionary else {}
		var raw_loaded_overrides: Variant = loaded_world.get("block_overrides", {})
		var loaded_overrides: Dictionary = (
			raw_loaded_overrides if raw_loaded_overrides is Dictionary else {}
		)
		_check(
			loaded_overrides.size() == OVERRIDES_PER_WORLD,
			"full load restores every large-world override after catalog selection",
		)
		_check(
			not loaded_world.has("loaded_chunks"),
			"catalog selection never restores transient loaded Chunk coordinates",
		)

	_report = {
		"schema_version": 1,
		"world_count": WORLD_COUNT,
		"overrides_per_world": OVERRIDES_PER_WORLD,
		"total_override_count": total_override_count,
		"total_world_bytes": total_world_bytes,
		"max_catalog_bytes": max_catalog_bytes,
		"catalog_list_milliseconds": catalog_list_ms,
		"repair_diagnostics": repair_diagnostics,
		"steady_diagnostics": steady_diagnostics,
		"selected_world_id": target_world_id,
	}
	_write_report()
	await _finish(game, hub, save)


func _legacy_loaded_chunks() -> Array:
	var result: Array = []
	for x in range(-4, 5):
		for z in range(-4, 5):
			result.append([x, z])
	return result


func _large_metadata_extension(index: int) -> Dictionary:
	var markers: Array[String] = []
	for marker in 128:
		markers.append("map-profile-%d-%03d" % [index, marker])
	return {
		"id": "star_continent",
		"display_name": "Benchmark profile %d" % index,
		"markers": markers,
	}


func _matching_worlds(worlds: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_metadata: Variant in worlds:
		if raw_metadata is not Dictionary:
			continue
		var metadata: Dictionary = raw_metadata
		if str(metadata.get("name", "")).begins_with(_prefix):
			result.append(metadata)
	return result


func _world_name_from_row(text: String) -> String:
	return text.get_slice("\n", 0).strip_edges()


func _wait_for_world_ready(game: Node, hub: Node, world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		if (
			world != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == world_id
		):
			return true
	return false


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "world catalog JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "world catalog JSON report is saved")


func _finish(game: Node, hub: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub) and not str(hub.get("current_world_id")).is_empty():
		hub.call("return_to_menu")
		for _frame in CLEANUP_FRAMES:
			await process_frame
	if save != null and is_instance_valid(save):
		for world_id: String in _world_ids:
			save.call("delete_world", world_id)
	_world_ids.clear()
	_world_id_by_name.clear()
	if hub != null and is_instance_valid(hub):
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA WORLD CATALOG DESKTOP PASS | checks=%d | worlds=%d | bytes=%d | catalog_ms=%.3f | capture=%s"
			% [
				checks,
				WORLD_COUNT,
				int(_report.get("total_world_bytes", 0)),
				float(_report.get("catalog_list_milliseconds", 0.0)),
				_capture_path,
			]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD CATALOG DESKTOP FAILURE: %s" % failure)
		print("QA WORLD CATALOG DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


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
