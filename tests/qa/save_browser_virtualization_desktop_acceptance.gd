extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://save-browser-virtualization-desktop.png"
const WORLD_COUNT := 72
const ROW_POOL_LIMIT := 24
const AUTO_SETTLE_LIMIT := 6
const OVERRIDES_PER_WORLD := 8
const CLEANUP_FRAMES := 24

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var primary_text_by_world: Dictionary = {}
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
	var list_node: VBoxContainer = save_panel.get("_list") if save_panel != null else null
	var status_label: Label = save_panel.get("_status") if save_panel != null else null
	var page_label: Label = save_panel.get("_page_label") if save_panel != null else null
	_check(
		save_panel != null
		and list_node != null
		and status_label != null
		and page_label != null,
		"production save browser exposes virtual rows, status and pager"
	)
	if save_panel == null or list_node == null or status_label == null or page_label == null:
		await _finish(game, save)
		return

	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	save_panel.call("refresh")
	var initial_snapshot: Dictionary = save_panel.call("get_virtualization_snapshot")
	var first_scan: Dictionary = save.get_catalog_diagnostics()
	_check(
		int(initial_snapshot.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(initial_snapshot.get("row_create_count", -1)) == ROW_POOL_LIMIT
		and list_node.get_child_count() == ROW_POOL_LIMIT,
		"real browser creates exactly twenty-four reusable row nodes"
	)
	_check(
		int(initial_snapshot.get("total_world_count", -1)) == WORLD_COUNT
		and int(initial_snapshot.get("page_count", -1)) == 3
		and int(initial_snapshot.get("visible_row_count", -1)) == ROW_POOL_LIMIT,
		"real seventy-two-world browser exposes three bounded pages"
	)
	_check(
		int(first_scan.get("last_authoritative_read_budget_used", -1)) == 32
		and int(first_scan.get("last_catalog_rebuild_budget_used", -1)) == 16
		and int(first_scan.get("staged_catalog_entry_count", -1)) == 16,
		"initial hidden refresh preserves existing read, write and staging budgets"
	)
	_check(
		int(initial_snapshot.get("remaining_auto_settle_passes", -1))
		== AUTO_SETTLE_LIMIT
		and not bool(initial_snapshot.get("auto_settle_active", true)),
		"hidden browser arms but does not run progressive catalog settling"
	)

	main_menu.call("_show_panel", save_panel)
	for _frame in 14:
		await process_frame
		var current: Dictionary = save_panel.call("get_virtualization_snapshot")
		if not bool(current.get("auto_settle_active", false)):
			break
	var settled_snapshot: Dictionary = save_panel.call("get_virtualization_snapshot")
	var settled_catalog: Dictionary = save.get_catalog_diagnostics()
	_check(
		int(settled_snapshot.get("auto_settle_pass_count", -1)) == 4
		and int(settled_snapshot.get("refresh_count", -1)) == 5,
		"visible browser converges the seventy-two-world catalog in four automatic cross-frame passes"
	)
	_check(
		not bool(settled_snapshot.get("auto_settle_active", true))
		and int(settled_snapshot.get("remaining_auto_settle_passes", -1)) == 0,
		"automatic settling stops immediately after the backlog reaches zero"
	)
	_check(
		int(settled_catalog.get("authoritative_read_count", -1)) == WORLD_COUNT
		and int(settled_catalog.get("stage_hit_count", -1)) == 56,
		"automatic convergence parses every authoritative world once and reuses staged metadata"
	)
	_check(
		_catalog_count() == WORLD_COUNT,
		"automatic convergence creates every derived catalog without manual refresh clicks"
	)
	_check(
		int(settled_snapshot.get("row_create_count", -1)) == ROW_POOL_LIMIT
		and list_node.get_child_count() == ROW_POOL_LIMIT,
		"automatic refreshes never allocate additional world rows"
	)

	var list_count_before_pages := int(settled_catalog.get("list_count", -1))
	var paged_world_ids: Dictionary = {}
	for page_index in 3:
		save_panel.call("show_page", page_index)
		await process_frame
		var visible_ids: Array = save_panel.call("get_visible_world_ids")
		_check(
			visible_ids.size() == ROW_POOL_LIMIT,
			"page %d reuses all twenty-four row slots" % (page_index + 1)
		)
		for raw_world_id: Variant in visible_ids:
			paged_world_ids[str(raw_world_id)] = true
	_check(
		paged_world_ids.size() == WORLD_COUNT,
		"three pages expose every real world exactly once"
	)
	_check(
		int(save.get_catalog_diagnostics().get("list_count", -1))
		== list_count_before_pages,
		"real page navigation performs no catalog or disk scan"
	)
	_check(
		page_label.text.contains("第 3 / 3 页")
		and page_label.text.contains("每页最多 24 个"),
		"real pager visibly explains the bounded row pool"
	)
	await _capture(capture_path, "virtualized save browser screenshot is saved")

	var rows_before_steady := int(
		save_panel.call("get_virtualization_snapshot").get("row_create_count", -1)
	)
	save_panel.call("refresh")
	await process_frame
	var steady: Dictionary = save.get_catalog_diagnostics()
	var steady_snapshot: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		int(steady.get("last_hit_count", -1)) == WORLD_COUNT
		and int(steady.get("last_fallback_count", -1)) == 0,
		"post-settlement refresh is a pure seventy-two-world sidecar hit"
	)
	_check(
		int(steady.get("last_authoritative_read_budget_used", -1)) == 0
		and int(steady.get("last_catalog_rebuild_budget_used", -1)) == 0
		and int(steady.get("staged_catalog_entry_count", -1)) == 0,
		"steady virtualized refresh performs zero full reads, writes or staging"
	)
	_check(
		int(steady_snapshot.get("row_create_count", -1)) == rows_before_steady
		and int(steady_snapshot.get("row_pool_size", -1)) == ROW_POOL_LIMIT,
		"steady refresh retains the original fixed row pool"
	)
	for world_id: String in world_ids:
		_check(
			_read_text(_world_path(world_id))
			== str(primary_text_by_world.get(world_id, "")),
			"virtualized auto-settlement preserves primary %s" % world_id
		)

	report = {
		"schema_version": 1,
		"world_count": WORLD_COUNT,
		"row_pool_limit": ROW_POOL_LIMIT,
		"auto_settle_limit": AUTO_SETTLE_LIMIT,
		"initial_virtualization": initial_snapshot,
		"initial_catalog": first_scan,
		"settled_virtualization": settled_snapshot,
		"settled_catalog": settled_catalog,
		"steady_virtualization": steady_snapshot,
		"steady_catalog": steady,
		"paged_world_count": paged_world_ids.size(),
	}
	_write_report()
	await _finish(game, save)


func _create_fixture(save: Node) -> void:
	var prefix := "Desktop-Virtual-Saves-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.call(
			"create_world",
			"%s-%02d" % [prefix, index],
			"star_continent",
			980000 + index
		)
		_check(not state.is_empty(), "desktop fixture creates world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		var overrides: Dictionary = {}
		for offset in OVERRIDES_PER_WORLD:
			overrides["%d,21,%d" % [index * 32 + offset, index]] = "stone_bricks"
		state["world"] = {"block_overrides": overrides}
		_check(
			bool(save.call("save_world", world_id, state)),
			"desktop fixture writes authoritative world %02d" % index
		)
		primary_text_by_world[world_id] = _read_text(_world_path(world_id))
		_remove_file(_catalog_path(world_id))
		_check(
			not FileAccess.file_exists(_catalog_path(world_id)),
			"desktop fixture removes sidecar %02d" % index
		)
	await process_frame


func _catalog_count() -> int:
	var count := 0
	for world_id: String in world_ids:
		if FileAccess.file_exists(_catalog_path(world_id)):
			count += 1
	return count


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
		_check(false, "save browser virtualization JSON report opens")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check(
		FileAccess.file_exists(report_path),
		"save browser virtualization JSON report is saved"
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
			"QA SAVE BROWSER VIRTUALIZATION DESKTOP PASS | checks=%d | worlds=%d | rows=%d"
			% [checks, WORLD_COUNT, ROW_POOL_LIMIT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE BROWSER VIRTUALIZATION DESKTOP FAILURE: %s" % failure)
		print(
			"QA SAVE BROWSER VIRTUALIZATION DESKTOP FAIL | checks=%d | failures=%d"
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
