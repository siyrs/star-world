extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://bounded-authoritative-read-desktop.png"
const WORLD_COUNT := 40
const AUTHORITATIVE_READ_BUDGET := 32
const CATALOG_REBUILD_BUDGET := 16
const ROW_POOL_LIMIT := 24
const OVERRIDES_PER_WORLD := 32
const CLEANUP_FRAMES := 24

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var primary_text_by_world: Dictionary = {}
var capture_path := ""
var health_capture_path := ""
var report_path := ""
var report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	health_capture_path = capture_path.get_basename() + "-health.png"
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
	var diagnostics: Node = game.get("runtime_diagnostics")
	_check(
		save != null and main_menu != null and diagnostics != null,
		"production game exposes save browser and runtime diagnostics"
	)
	if save == null or main_menu == null or diagnostics == null:
		await _finish(game, save)
		return
	await _create_fixture(save)
	var save_panel: Control = main_menu.get("_save_panel")
	var status_label: Label = save_panel.get("_status") if save_panel != null else null
	var list_node: VBoxContainer = save_panel.get("_list") if save_panel != null else null
	_check(
		save_panel != null and status_label != null and list_node != null,
		"production save browser exposes status and virtual world rows"
	)
	if save_panel == null or status_label == null or list_node == null:
		await _finish(game, save)
		return

	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	save_panel.call("refresh")
	var first: Dictionary = save.get_catalog_diagnostics()
	var first_virtual: Dictionary = save_panel.call("get_virtualization_snapshot")
	var first_panel_worlds: Array = save_panel.get("_worlds")
	_check(
		int(first_virtual.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and list_node.get_child_count() == ROW_POOL_LIMIT,
		"first desktop refresh uses the fixed twenty-four-row pool"
	)
	_check(
		int(first_virtual.get("total_world_count", -1)) == WORLD_COUNT
		and int(first_virtual.get("page_count", -1)) == 2,
		"first desktop refresh renders every world before full metadata resolution"
	)
	_check(
		_pending_metadata_count(first_panel_worlds) == 8,
		"first desktop refresh retains eight explicit metadata placeholders"
	)
	_check(
		int(first.get("last_authoritative_read_budget_used", -1))
		== AUTHORITATIVE_READ_BUDGET,
		"first desktop refresh uses exactly thirty-two authoritative reads"
	)
	_check(
		int(first.get("last_deferred_authoritative_read_count", -1)) == 8,
		"first desktop refresh defers the remaining eight metadata reads"
	)
	_check(
		int(first.get("last_catalog_rebuild_budget_used", -1))
		== CATALOG_REBUILD_BUDGET,
		"first desktop refresh independently writes sixteen sidecars"
	)
	_check(
		int(first.get("staged_catalog_entry_count", -1)) == 16
		and int(first.get("staged_catalog_peak_count", -1)) == 16,
		"first desktop refresh stages sixteen exact catalog entries"
	)
	_check(
		int(first.get("last_repair_budget_used", -1)) == 0,
		"catalog-only metadata loading does not consume primary repair slots"
	)
	_check(
		status_label.text.contains("待读世界 8")
		and status_label.text.contains("每次最多 32"),
		"save browser visibly explains deferred authoritative metadata reads"
	)
	_check(
		status_label.text.contains("暂存目录 16/64"),
		"save browser visibly reports the transient catalog stage"
	)

	var warning_snapshot: Dictionary = diagnostics.call("sample_now")
	var operations: Dictionary = warning_snapshot.get("operations", {})
	var projected_catalog: Dictionary = operations.get("catalog", {})
	_check(
		int(projected_catalog.get("last_deferred_authoritative_read_count", -1)) == 8
		and int(projected_catalog.get("authoritative_read_budget", -1))
		== AUTHORITATIVE_READ_BUDGET,
		"runtime health keeps the bounded authoritative-read backlog"
	)
	_check(
		int(projected_catalog.get("staged_catalog_entry_count", -1)) == 16
		and int(projected_catalog.get("catalog_stage_capacity", -1)) == 64,
		"runtime health keeps the bounded transient staging backlog"
	)
	_check(
		str(operations.get("primary_bottleneck", {}).get("id", "")) == "catalog",
		"deferred authoritative reads become the deterministic health bottleneck"
	)
	var overlay := diagnostics.get("overlay") as CanvasLayer
	_check(overlay != null, "production diagnostics exposes the F3 overlay")
	await _press_f3()
	_check(
		overlay != null and bool(overlay.call("is_overlay_visible")),
		"real F3 input opens the bounded authoritative-read view"
	)
	var display := str(overlay.call("get_display_text")) if overlay != null else ""
	_check(
		display.contains("待读世界 8") and display.contains("权威读取预算 32"),
		"F3 visibly reports deferred worlds and the full-read budget"
	)
	_check(
		display.contains("暂存目录 16/64") and display.contains("暂存命中 0"),
		"F3 visibly reports staged entries and stage hits"
	)
	await _capture(health_capture_path, "F3 authoritative-read health screenshot is saved")
	await _press_f3()

	main_menu.call("_show_panel", save_panel)
	for _frame in 10:
		await process_frame
		var current: Dictionary = save_panel.call("get_virtualization_snapshot")
		if not bool(current.get("auto_settle_active", false)):
			break
	var settled: Dictionary = save.get_catalog_diagnostics()
	var settled_virtual: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		int(settled_virtual.get("auto_settle_pass_count", -1)) == 2,
		"visible save browser settles forty worlds in two automatic passes"
	)
	_check(
		int(settled.get("authoritative_read_count", -1)) == WORLD_COUNT
		and int(settled.get("stage_hit_count", -1)) == 24,
		"desktop convergence parses every authoritative world exactly once"
	)
	_check(
		int(settled.get("last_deferred_authoritative_read_count", -1)) == 0
		and int(settled.get("last_deferred_catalog_rebuild_count", -1)) == 0
		and int(settled.get("staged_catalog_entry_count", -1)) == 0,
		"automatic desktop convergence clears metadata, staging and sidecar backlogs"
	)
	_check(
		int(settled_virtual.get("row_create_count", -1)) == ROW_POOL_LIMIT
		and list_node.get_child_count() == ROW_POOL_LIMIT,
		"automatic desktop convergence allocates no additional world rows"
	)

	var paged_ids: Dictionary = {}
	var list_count_before_pages := int(settled.get("list_count", -1))
	for page_index in 2:
		save_panel.call("show_page", page_index)
		await process_frame
		for raw_world_id: Variant in save_panel.call("get_visible_world_ids"):
			paged_ids[str(raw_world_id)] = true
	_check(
		paged_ids.size() == WORLD_COUNT,
		"two virtual pages expose every forty-world fixture entry"
	)
	_check(
		int(save.get_catalog_diagnostics().get("list_count", -1))
		== list_count_before_pages,
		"virtual page navigation performs no additional authoritative scan"
	)
	await _capture(capture_path, "save browser virtual-page screenshot is saved")

	var rows_before_steady := int(settled_virtual.get("row_create_count", -1))
	save_panel.call("refresh")
	await process_frame
	var steady: Dictionary = save.get_catalog_diagnostics()
	var steady_virtual: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		int(steady.get("last_hit_count", -1)) == WORLD_COUNT
		and int(steady.get("last_fallback_count", -1)) == 0,
		"steady desktop refresh is a pure sidecar hit"
	)
	_check(
		int(steady.get("last_authoritative_read_budget_used", -1)) == 0
		and int(steady.get("last_catalog_rebuild_budget_used", -1)) == 0
		and int(steady.get("staged_catalog_entry_count", -1)) == 0,
		"steady desktop refresh performs zero full reads and zero sidecar writes"
	)
	_check(
		int(steady_virtual.get("row_create_count", -1)) == rows_before_steady,
		"steady desktop refresh reuses the original row pool"
	)
	var recovery: Dictionary = save.get_recovery_diagnostics()
	_check(
		int(recovery.get("recovery_count", 0)) == 0,
		"desktop authoritative-read convergence never enters backup recovery"
	)
	for world_id: String in world_ids:
		_check(
			_read_text(_world_path(world_id))
			== str(primary_text_by_world.get(world_id, "")),
			"desktop metadata convergence preserves primary %s" % world_id
		)

	report = {
		"schema_version": 3,
		"world_count": WORLD_COUNT,
		"authoritative_read_budget": AUTHORITATIVE_READ_BUDGET,
		"catalog_rebuild_budget": CATALOG_REBUILD_BUDGET,
		"catalog_stage_capacity": 64,
		"row_pool_limit": ROW_POOL_LIMIT,
		"first_scan": first,
		"first_virtualization": first_virtual,
		"settled_scan": settled,
		"settled_virtualization": settled_virtual,
		"steady_scan": steady,
		"steady_virtualization": steady_virtual,
		"warning_operations": operations,
		"recovery": recovery,
	}
	_write_report()
	await _finish(game, save)


func _create_fixture(save: Node) -> void:
	var prefix := "Desktop-Authoritative-Read-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.call(
			"create_world",
			"%s-%02d" % [prefix, index],
			"star_continent",
			950000 + index
		)
		_check(not state.is_empty(), "desktop fixture creates world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		var overrides: Dictionary = {}
		for offset in OVERRIDES_PER_WORLD:
			overrides["%d,18,%d" % [index * 64 + offset, index]] = "stone_bricks"
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


func _pending_metadata_count(worlds: Array) -> int:
	var count := 0
	for raw_metadata: Variant in worlds:
		if (
			raw_metadata is Dictionary
			and bool(raw_metadata.get("authoritative_read_deferred", false))
		):
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


func _press_f3() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_F3
	press.physical_keycode = KEY_F3
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = KEY_F3
	release.physical_keycode = KEY_F3
	release.pressed = false
	root.push_input(release)
	await process_frame


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "desktop authoritative-read JSON report opens")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check(FileAccess.file_exists(report_path), "desktop authoritative-read JSON report is saved")


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
			"QA BOUNDED AUTHORITATIVE READ DESKTOP PASS | checks=%d | worlds=%d"
			% [checks, WORLD_COUNT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED AUTHORITATIVE READ DESKTOP FAILURE: %s" % failure)
		print(
			"QA BOUNDED AUTHORITATIVE READ DESKTOP FAIL | checks=%d | failures=%d"
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
