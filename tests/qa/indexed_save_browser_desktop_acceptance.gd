extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const QueryPolicy = preload("res://src/ui/save_browser_query_policy.gd")
const OUTPUT_PATH := "user://indexed-save-browser-desktop.png"
const WORLD_COUNT := 256
const ROW_POOL_LIMIT := 24
const CLEANUP_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var primary_text_by_world: Dictionary = {}
var expected_gamma_ids: Dictionary = {}
var expected_seed_world_id := ""
var capture_path := ""
var report_path := ""
var report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	report_path = capture_path.get_basename() + ".json"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub: Node = game.get("service_hub")
	var save: Node = hub.get("save_service") if hub != null else null
	var main_menu: Control = hub.get("main_menu") if hub != null else null
	_check(
		save != null and main_menu != null,
		"production game exposes save service and main menu"
	)
	if save == null or main_menu == null:
		await _finish(game, save)
		return

	await _create_fixture(save)
	var save_panel: Control = main_menu.get("_save_panel")
	var list_node := save_panel.get("_list") as VBoxContainer if save_panel != null else null
	var search_input := save_panel.get("_search_input") as LineEdit if save_panel != null else null
	var sort_option := save_panel.get("_sort_option") as OptionButton if save_panel != null else null
	var page_label := save_panel.get("_page_label") as Label if save_panel != null else null
	_check(
		save_panel != null
		and list_node != null
		and search_input != null
		and sort_option != null
		and page_label != null,
		"production save browser exposes indexed rows, search, sorting and pager"
	)
	if save_panel == null or list_node == null or search_input == null or sort_option == null:
		await _finish(game, save)
		return

	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	save_panel.call("refresh")
	var initial: Dictionary = save_panel.call("get_virtualization_snapshot")
	var initial_catalog: Dictionary = save.get_catalog_diagnostics()
	_check(
		int(initial.get("total_world_count", -1)) == WORLD_COUNT
		and int(initial.get("indexed_world_count", -1)) == WORLD_COUNT
		and int(initial.get("matched_world_count", -1)) == WORLD_COUNT,
		"real browser indexes all two hundred fifty-six worlds"
	)
	_check(
		int(initial.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(initial.get("row_create_count", -1)) == ROW_POOL_LIMIT
		and int(initial.get("page_count", -1)) == 11,
		"real indexed directory stays bounded to twenty-four rows across eleven pages"
	)
	_check(
		int(initial_catalog.get("list_count", -1)) == 1
		and int(initial_catalog.get("last_hit_count", -1)) == WORLD_COUNT
		and int(initial_catalog.get("last_fallback_count", -1)) == 0,
		"initial indexed refresh is one pure two-hundred-fifty-six-sidecar scan"
	)

	main_menu.call("_show_panel", save_panel)
	for _frame in 3:
		await process_frame
	var list_count_before_queries := int(
		save.get_catalog_diagnostics().get("list_count", -1)
	)
	search_input.text = "Gamma"
	sort_option.select(1)
	sort_option.item_selected.emit(1)
	await process_frame
	var gamma: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		str(gamma.get("applied_query", "")) == "gamma"
		and str(gamma.get("sort_mode", "")) == QueryPolicy.SORT_NAME_ASC
		and int(gamma.get("matched_world_count", -1)) == 64
		and int(gamma.get("page_count", -1)) == 3,
		"real search control finds sixty-four Gamma worlds and sorts by name"
	)
	_check(
		int(save.get_catalog_diagnostics().get("list_count", -1))
		== list_count_before_queries,
		"real search and sorting perform zero additional catalog scans"
	)
	var gamma_ids: Dictionary = {}
	for page_index in 3:
		save_panel.call("show_page", page_index)
		await process_frame
		for raw_world_id: Variant in save_panel.call("get_visible_world_ids"):
			gamma_ids[str(raw_world_id)] = true
	_check(
		gamma_ids.size() == expected_gamma_ids.size()
		and _same_keys(gamma_ids, expected_gamma_ids),
		"three filtered pages expose every real Gamma world exactly once"
	)
	_check(
		int(save.get_catalog_diagnostics().get("list_count", -1))
		== list_count_before_queries,
		"filtered page navigation performs zero service or disk scans"
	)

	save_panel.call("show_page", 0)
	await process_frame
	await _capture(capture_path, "indexed save browser search screenshot is saved")
	_check(
		page_label.text.contains("匹配 64 / 共 256")
		and page_label.text.contains("每页最多 24 个"),
		"real pager visibly reports matched, total and row-pool limits"
	)

	save_panel.call("_select_slot", 0)
	var selected_before_filter := str(save_panel.get("_selected_world_id"))
	_check(
		not selected_before_filter.is_empty(),
		"real search result can be selected by stable world id"
	)
	search_input.text = "1300123"
	search_input.text_submitted.emit(search_input.text)
	await process_frame
	var seed_match: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		int(seed_match.get("matched_world_count", -1)) == 1
		and save_panel.call("get_visible_world_ids") == [expected_seed_world_id],
		"real Enter search resolves one exact seed without loading a world"
	)
	_check(
		str(save_panel.get("_selected_world_id")).is_empty(),
		"real filtering clears selection when the selected row becomes hidden"
	)

	save_panel.call("apply_query", "snowfield", QueryPolicy.SORT_UPDATED_DESC)
	var map_match: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		int(map_match.get("matched_world_count", -1)) == 51,
		"real map-id search returns all fifty-one snowfield worlds"
	)
	save_panel.call("apply_query", "", QueryPolicy.SORT_SIZE_DESC)
	var largest_ids: Array = save_panel.call("get_visible_world_ids")
	var world_by_id: Dictionary = save_panel.get("_world_by_id")
	_check(
		_non_increasing_sizes(largest_ids, world_by_id),
		"real largest-first sorting is monotonic on the visible page"
	)
	_check(
		int(save.get_catalog_diagnostics().get("list_count", -1))
		== list_count_before_queries,
		"all real query and sort variants stay inside the in-memory index"
	)

	var rows_before_refresh := int(
		save_panel.call("get_virtualization_snapshot").get("row_create_count", -1)
	)
	save_panel.call("refresh")
	await process_frame
	var steady: Dictionary = save_panel.call("get_virtualization_snapshot")
	var steady_catalog: Dictionary = save.get_catalog_diagnostics()
	_check(
		int(steady.get("row_create_count", -1)) == rows_before_refresh
		and int(steady.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(steady.get("indexed_world_count", -1)) == WORLD_COUNT,
		"real index rebuild preserves the original fixed row pool"
	)
	_check(
		int(steady_catalog.get("last_hit_count", -1)) == WORLD_COUNT
		and int(steady_catalog.get("last_fallback_count", -1)) == 0
		and int(steady_catalog.get("last_authoritative_read_budget_used", -1)) == 0
		and int(steady_catalog.get("last_catalog_rebuild_budget_used", -1)) == 0,
		"steady indexed refresh remains a pure sidecar hit with zero reads and writes"
	)
	for world_id: String in world_ids:
		_check(
			_read_text(_world_path(world_id))
			== str(primary_text_by_world.get(world_id, "")),
			"indexed search preserves primary %s" % world_id
		)

	report = {
		"schema_version": 1,
		"world_count": WORLD_COUNT,
		"row_pool_limit": ROW_POOL_LIMIT,
		"initial": initial,
		"initial_catalog": initial_catalog,
		"gamma_query": gamma,
		"seed_query": seed_match,
		"map_query": map_match,
		"steady": steady,
		"steady_catalog": steady_catalog,
		"gamma_world_count": gamma_ids.size(),
		"query_catalog_list_count": list_count_before_queries,
	}
	_write_report()
	await _finish(game, save)


func _create_fixture(save: Node) -> void:
	var groups := ["Alpha", "Beta", "Gamma", "Delta"]
	var maps := [
		"star_continent",
		"snowfield",
		"desert",
		"floating_islands",
		"abyss",
	]
	var prefix := "Indexed-Desktop-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var group: String = groups[index % groups.size()]
		var state: Dictionary = save.call(
			"create_world",
			"%s-%s-%03d" % [prefix, group, index],
			maps[index % maps.size()],
			1300000 + index
		)
		_check(not state.is_empty(), "desktop fixture creates world %03d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		if group == "Gamma":
			expected_gamma_ids[world_id] = true
		if index == 123:
			expected_seed_world_id = world_id
		primary_text_by_world[world_id] = _read_text(_world_path(world_id))
	await process_frame


func _same_keys(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left:
		if not right.has(key):
			return false
	return true


func _non_increasing_sizes(ids: Array, world_by_id: Dictionary) -> bool:
	var previous := 9223372036854775807
	for raw_world_id: Variant in ids:
		var metadata: Dictionary = world_by_id.get(str(raw_world_id), {})
		var current := maxi(0, int(metadata.get("save_bytes", 0)))
		if current > previous:
			return false
		previous = current
	return true


func _capture(path: String, description: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s produces an image" % description)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(
		image.save_png(path) == OK and FileAccess.file_exists(path),
		description
	)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "indexed save browser JSON report opens")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check(
		FileAccess.file_exists(report_path),
		"indexed save browser JSON report is saved"
	)


func _finish(game: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for world_id: String in world_ids:
		if save != null and is_instance_valid(save):
			save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA INDEXED SAVE BROWSER DESKTOP PASS | checks=%d | worlds=%d | rows=%d"
			% [checks, WORLD_COUNT, ROW_POOL_LIMIT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA INDEXED SAVE BROWSER DESKTOP FAILURE: %s" % failure)
		print(
			"QA INDEXED SAVE BROWSER DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
