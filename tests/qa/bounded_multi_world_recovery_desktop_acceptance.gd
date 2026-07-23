extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://bounded-multi-world-recovery-desktop.png"
const WORLD_COUNT := 20
const REPAIR_BUDGET := 8

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var capture_path := ""
var report_path := ""
var report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	report_path = capture_path.get_basename() + ".json"
	root.size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub: Node = game.get("service_hub")
	var save: Node = hub.get("save_service") if hub != null else null
	var main_menu: Control = hub.get("main_menu") if hub != null else null
	_check(save != null and main_menu != null, "production game exposes save service and main menu")
	if save == null or main_menu == null:
		await _finish(game, save)
		return
	await _create_fixture(save)
	var save_panel: Control = main_menu.get("_save_panel")
	var status_label: Label = save_panel.get("_status") if save_panel != null else null
	var list_node: VBoxContainer = save_panel.get("_list") if save_panel != null else null
	_check(save_panel != null and status_label != null and list_node != null, "production save browser exposes status and rows")
	if save_panel == null:
		await _finish(game, save)
		return

	save.reset_catalog_diagnostics()
	save.reset_recovery_diagnostics()
	save_panel.call("refresh")
	main_menu.call("_show_panel", save_panel)
	for _frame in 5:
		await process_frame
	var first: Dictionary = save.get_catalog_diagnostics()
	_check(_visible_fixture_rows(list_node) == WORLD_COUNT, "first desktop refresh renders every damaged world")
	_check(int(first.get("last_repair_budget_used", -1)) == REPAIR_BUDGET, "first desktop refresh uses exactly eight repair slots")
	_check(int(first.get("last_deferred_recovery_count", -1)) == 12, "first desktop refresh defers the remaining twelve worlds")
	_check(status_label.text.contains("待渐进修复 12") and status_label.text.contains("每次最多 8"), "save browser visibly explains progressive recovery")
	await _capture(capture_path)

	save_panel.call("refresh")
	for _frame in 3:
		await process_frame
	var second: Dictionary = save.get_catalog_diagnostics()
	_check(int(second.get("last_repair_budget_used", -1)) == 8 and int(second.get("last_deferred_recovery_count", -1)) == 4, "second refresh repairs eight more and leaves four")
	save_panel.call("refresh")
	for _frame in 3:
		await process_frame
	var third: Dictionary = save.get_catalog_diagnostics()
	_check(int(third.get("last_repair_budget_used", -1)) == 4 and int(third.get("last_deferred_recovery_count", -1)) == 0, "third refresh completes the remaining four repairs")
	save_panel.call("refresh")
	for _frame in 3:
		await process_frame
	var steady: Dictionary = save.get_catalog_diagnostics()
	_check(int(steady.get("last_hit_count", 0)) >= WORLD_COUNT and int(steady.get("last_fallback_count", -1)) == 0, "steady desktop refresh is a pure sidecar hit")
	_check(_visible_fixture_rows(list_node) == WORLD_COUNT, "all rows remain visible after convergence")

	var recovery: Dictionary = save.get_recovery_diagnostics()
	report = {
		"schema_version": 1,
		"world_count": WORLD_COUNT,
		"repair_budget": REPAIR_BUDGET,
		"first_scan": first,
		"second_scan": second,
		"third_scan": third,
		"steady_scan": steady,
		"recovery": recovery,
	}
	_write_report()
	await _finish(game, save)


func _create_fixture(save: Node) -> void:
	var prefix := "Desktop-Bounded-Recovery-%d" % Time.get_ticks_msec()
	for index in WORLD_COUNT:
		var state: Dictionary = save.call("create_world", "%s-%02d" % [prefix, index], "star_continent", 990000 + index)
		_check(not state.is_empty(), "desktop fixture creates world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		var overrides: Dictionary = {}
		for offset in 32:
			overrides["%d,14,%d" % [index * 64 + offset, index]] = "stone_bricks"
		state["world"] = {"block_overrides": overrides}
		_check(bool(save.call("save_world", world_id, state)), "desktop fixture writes backup-ready world %02d" % index)
		state["metadata"]["generation"] = "newer"
		_check(bool(save.call("save_world", world_id, state)), "desktop fixture rotates backup %02d" % index)
		_remove_file(_catalog_path(world_id))
		_check(_write_corrupt_primary(world_id), "desktop fixture corrupts primary %02d" % index)
	await process_frame


func _visible_fixture_rows(list_node: VBoxContainer) -> int:
	var count := 0
	for row: Node in list_node.get_children():
		if row.get_child_count() > 0:
			var button := row.get_child(0) as Button
			if button != null and button.text.contains("Desktop-Bounded-Recovery"):
				count += 1
	return count


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop recovery viewport produces an image")
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image.save_png(path) == OK and FileAccess.file_exists(path), "desktop recovery screenshot is saved")


func _write_corrupt_primary(world_id: String) -> bool:
	var file := FileAccess.open(_world_path(world_id), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"save_version": 2, "metadata": {"id": world_id, "name": "Recovering world"}, "player": "broken", "world": {"block_overrides": "broken"}}))
	file.close()
	return true


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "desktop recovery JSON report opens")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check(FileAccess.file_exists(report_path), "desktop recovery JSON report is saved")


func _finish(game: Node, save: Node) -> void:
	for world_id: String in world_ids:
		if save != null and is_instance_valid(save):
			save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in 5:
		await process_frame
	if failures.is_empty():
		print("QA BOUNDED MULTI WORLD RECOVERY DESKTOP PASS | checks=%d | worlds=%d" % [checks, WORLD_COUNT])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED MULTI WORLD RECOVERY DESKTOP FAILURE: %s" % failure)
		print("QA BOUNDED MULTI WORLD RECOVERY DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


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
