extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://bounded-authoritative-read-desktop.png"
const WORLD_COUNT := 40
const AUTHORITATIVE_READ_BUDGET := 32
const CATALOG_REBUILD_BUDGET := 16
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
		"production save browser exposes status and world rows"
	)
	if save_panel == null or status_label == null or list_node == null:
		await _finish(game, save)
		return

	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	save_panel.call("refresh")
	main_menu.call("_show_panel", save_panel)
	for _frame in 5:
		await process_frame
	var first: Dictionary = save.get_catalog_diagnostics()
	_check(
		_visible_fixture_rows(list_node) == WORLD_COUNT,
		"first desktop refresh renders every world before full metadata resolution"
	)
	_check(
		_pending_fixture_rows(list_node) == 8,
		"first desktop refresh renders eight explicit metadata placeholders"
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
	await _capture(capture_path, "save browser placeholder screenshot is saved")

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

	save_panel.call("refresh")
	for _frame in 4:
		await process_frame
	var second: Dictionary = save.get_catalog_diagnostics()
	_check(
		int(second.get("last_hit_count", -1)) == 16
		and int(second.get("last_deferred_authoritative_read_count", -1)) == 0,
		"second refresh resolves every remaining world metadata payload"
	)
	_check(
		_pending_fixture_rows(list_node) == 0,
		"second desktop refresh replaces all placeholders with exact metadata"
	)
	_check(
		int(second.get("last_authoritative_read_budget_used", -1)) == 8
		and int(second.get("last_stage_hit_count", -1)) == 16,
		"second refresh reuses sixteen staged entries and reads only eight new worlds"
	)
	_check(
		int(second.get("last_catalog_rebuild_budget_used", -1)) == 16
		and int(second.get("last_deferred_catalog_rebuild_count", -1)) == 8,
		"second refresh preserves the independent sidecar budget"
	)
	_check(
		int(second.get("staged_catalog_entry_count", -1)) == 8,
		"second refresh stages only the eight newly read entries waiting for writes"
	)

	save_panel.call("refresh")
	for _frame in 4:
		await process_frame
	var third: Dictionary = save.get_catalog_diagnostics()
	_check(
		int(third.get("last_hit_count", -1)) == 32
		and int(third.get("last_authoritative_read_budget_used", -1)) == 0
		and int(third.get("last_stage_hit_count", -1)) == 8
		and int(third.get("last_catalog_rebuild_budget_used", -1)) == 8
		and int(third.get("last_deferred_catalog_rebuild_count", -1)) == 0,
		"third refresh flushes eight staged entries without another full read"
	)
	_check(
		int(third.get("staged_catalog_entry_count", -1)) == 0,
		"third refresh empties the transient catalog stage"
	)

	save_panel.call("refresh")
	for _frame in 4:
		await process_frame
	var steady: Dictionary = save.get_catalog_diagnostics()
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
		int(steady.get("authoritative_read_count", -1)) == WORLD_COUNT
		and int(steady.get("stage_hit_count", -1)) == 24,
		"desktop convergence parses every authoritative world exactly once"
	)
	_check(
		_visible_fixture_rows(list_node) == WORLD_COUNT,
		"all world rows remain visible after complete convergence"
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
		"schema_version": 2,
		"world_count": WORLD_COUNT,
		"authoritative_read_budget": AUTHORITATIVE_READ_BUDGET,
		"catalog_rebuild_budget": CATALOG_REBUILD_BUDGET,
		"catalog_stage_capacity": 64,
		"first_scan": first,
		"second_scan": second,
		"third_scan": third,
		"steady_scan": steady,
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


func _visible_fixture_rows(list_node: VBoxContainer) -> int:
	var count := 0
	for row: Node in list_node.get_children():
		if row.get_child_count() > 0:
			var button := row.get_child(0) as Button
			if button != null and button.text.to_lower().contains("authoritative-read"):
				count += 1
	return count


func _pending_fixture_rows(list_node: VBoxContainer) -> int:
	var count := 0
	for row: Node in list_node.get_children():
		if row.get_child_count() > 0:
			var button := row.get_child(0) as Button
			if (
				button != null
				and button.text.to_lower().contains("authoritative-read")
				and button.text.contains("世界信息待读取")
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
