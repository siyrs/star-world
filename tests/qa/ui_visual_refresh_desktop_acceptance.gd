extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ui-visual-refresh-main-menu.png"
const READY_FRAMES := 720
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _output_dir := ""
var _report_path := ""
var _world_ids: Array[String] = []
var _captures: Dictionary = {}
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var primary_path := CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_output_dir = primary_path.get_base_dir()
	_report_path = _output_dir.path_join("ui-visual-refresh-report.json")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	var main_menu := hub.get("main_menu") as Control if hub != null else null
	var game_ui := hub.get("game_ui") as Node if hub != null else null
	var save := hub.get("save_service") as Node if hub != null else null
	var diagnostics := game.get("runtime_diagnostics") as Node
	_check(
		hub != null and main_menu != null and game_ui != null and save != null and diagnostics != null,
		"production game mounts the complete menu, gameplay and diagnostics interface"
	)
	if hub == null or main_menu == null or game_ui == null or save == null or diagnostics == null:
		await _finish(game, hub, save)
		return

	_check(await _capture("main-menu"), "professional main menu screenshot is saved")
	var menu_snapshot: Dictionary = main_menu.call("get_visual_snapshot")
	_check(
		str((menu_snapshot.get("button_variations", []) as Array)[0]) == "MenuPrimaryButton",
		"main menu presents one visually dominant start action"
	)

	_check(await _click_text(main_menu, "地图选择"), "real mouse opens the map briefing workspace")
	var map_panel := main_menu.get("_map_panel") as Control
	_check(map_panel != null and map_panel.visible, "map briefing becomes visible")
	_check(await _capture("map-selection"), "map selection screenshot is saved")
	_check(await _click_text(map_panel, "返回"), "real mouse returns from map briefing")

	_check(await _click_text(main_menu, "设置"), "real mouse opens the settings workspace")
	var settings_panel := main_menu.get("_settings_panel") as Control
	_check(settings_panel != null and settings_panel.visible, "settings workspace becomes visible")
	_check(await _capture("settings"), "settings workspace screenshot is saved")
	_check(await _click_text(settings_panel, "返回"), "real mouse returns from settings")

	for index in 3:
		var archived: Dictionary = save.call(
			"create_world",
			"UI-Archive-%02d" % (index + 1),
			["star_continent", "desert_ruins", "frozen_wastes"][index],
			880100 + index
		)
		var archived_id := str(archived.get("metadata", {}).get("id", ""))
		if not archived_id.is_empty():
			_world_ids.append(archived_id)
	_check(await _click_text(main_menu, "存档 / 继续"), "real mouse opens the protected save archive")
	var save_panel := main_menu.get("_save_panel") as Control
	_check(save_panel != null and save_panel.visible, "save archive becomes visible")
	_check(await _capture("save-browser"), "save archive screenshot is saved")
	_check(await _click_text(save_panel, "返回"), "real mouse returns from the save archive")

	_check(await _click_text(main_menu, "开始游戏"), "real mouse opens world creation from the primary CTA")
	map_panel = main_menu.get("_map_panel") as Control
	_check(await _click_text(map_panel, "创建并进入世界"), "real mouse creates the selected production world")
	_check(
		await _wait_for_world_ready(game, hub),
		"production world reaches a playable state after the redesigned menu journey"
	)
	var active_world_id := str(hub.get("current_world_id"))
	if not active_world_id.is_empty():
		_world_ids.append(active_world_id)
	_check(await _capture("gameplay-hud"), "gameplay HUD screenshot is saved")

	await _press_key(KEY_ESCAPE)
	_check(int(game_ui.call("get_active_overlay")) == 5, "real Escape opens the redesigned pause modal")
	_check(await _capture("pause"), "pause modal screenshot is saved")
	_check(await _click_text(game_ui, "继续游戏"), "real mouse resumes from the pause modal")

	await _press_key(KEY_E)
	_check(int(game_ui.call("get_active_overlay")) == 1, "real E opens the redesigned inventory")
	_check(await _capture("inventory"), "inventory workspace screenshot is saved")
	await _press_key(KEY_E)

	await _press_key(KEY_C)
	_check(int(game_ui.call("get_active_overlay")) == 2, "real C opens the redesigned crafting database")
	_check(await _capture("crafting"), "crafting workspace screenshot is saved")
	await _press_key(KEY_C)

	await _press_key(KEY_J)
	_check(int(game_ui.call("get_active_overlay")) == 8, "real J opens the redesigned exploration archive")
	_check(await _capture("exploration-journal"), "exploration journal screenshot is saved")
	await _press_key(KEY_J)

	await _press_key(KEY_F3)
	var overlay := diagnostics.get("overlay") as Node
	_check(overlay != null and bool(overlay.call("is_overlay_visible")), "real F3 opens the redesigned diagnostics dashboard")
	_check(await _capture("diagnostics"), "diagnostics dashboard screenshot is saved")
	var diagnostics_snapshot: Dictionary = overlay.call("get_visual_snapshot") if overlay != null else {}
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	_check(
		_rect_inside(viewport_rect, diagnostics_snapshot.get("panel", Rect2())),
		"diagnostics dashboard remains inside the 1280x720 viewport"
	)

	_report = {
		"schema_version": 1,
		"viewport": {"width": root.size.x, "height": root.size.y},
		"captures": _captures.duplicate(true),
		"capture_count": _captures.size(),
		"main_menu": menu_snapshot,
		"map_selection": map_panel.call("get_visual_snapshot") if map_panel != null else {},
		"settings": settings_panel.call("get_layout_snapshot") if settings_panel != null else {},
		"save_browser": save_panel.call("get_virtualization_snapshot") if save_panel != null else {},
		"game_ui": game_ui.call("get_visual_snapshot"),
		"hud": game_ui.hud.call("get_layout_rects") if game_ui.get("hud") != null else {},
		"diagnostics": diagnostics_snapshot,
		"world_id": active_world_id,
	}
	_write_report()
	await _finish(game, hub, save)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world := game.get("world") as Node
		if (
			world != null
			and bool(world.get("is_started"))
			and not str(hub.get("current_world_id")).is_empty()
		):
			return true
	return false


func _click_text(root_node: Node, text: String) -> bool:
	var button := _find_button(root_node, text)
	if button == null or not button.visible or button.disabled:
		return false
	for _frame in 2:
		await process_frame
	var rect := button.get_global_rect()
	var center := rect.position + rect.size * 0.5
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	for _frame in 3:
		await process_frame
	return true


func _press_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release)
	for _frame in 3:
		await process_frame


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _capture(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var path := _output_dir.path_join("ui-visual-refresh-%s.png" % name)
	var error := image.save_png(path)
	if error != OK or not FileAccess.file_exists(path):
		return false
	_captures[name] = path
	return true


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "UI visual refresh report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "UI visual refresh JSON report is saved")


func _finish(game: Node, hub: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		var diagnostics := game.get("runtime_diagnostics") as Node if game != null else null
		if diagnostics != null and diagnostics.get("overlay") != null:
			var overlay := diagnostics.get("overlay") as Node
			if overlay.has_method("set_overlay_visible"):
				overlay.call("set_overlay_visible", false)
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in CLEANUP_FRAMES:
				await process_frame
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if save != null and is_instance_valid(save):
		for world_id: String in _world_ids:
			if not world_id.is_empty() and bool(save.call("world_exists", world_id)):
				save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA UI VISUAL REFRESH DESKTOP PASS | checks=%d | captures=%d | report=%s"
			% [checks, _captures.size(), _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA UI VISUAL REFRESH DESKTOP FAILURE: %s" % failure)
		print(
			"QA UI VISUAL REFRESH DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x - 0.5
		and candidate.position.y >= container_rect.position.y - 0.5
		and candidate.end.x <= container_rect.end.x + 0.5
		and candidate.end.y <= container_rect.end.y + 0.5
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
