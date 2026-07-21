extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const AppVersion = preload("res://src/update/app_version.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://auto-update-desktop.png"
const CLEANUP_FRAMES := 8

var checks := 0
var failures: Array[String] = []
var _capture_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var update_service := get_node_or_null("/root/StarWorldUpdateService")
	_check(update_service != null, "production update autoload is mounted")
	if update_service == null:
		_finish(null)
		return
	update_service.set("automatic_check_enabled", false)
	update_service.set("automatic_install_enabled", false)
	var game := GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	var menu: Node = hub.get("main_menu") as Node if hub != null else null
	_check(menu != null and bool(menu.get("visible")), "production main menu is visible on first startup")
	_check(menu != null and menu.get("update_service") == update_service, "autoload bridge binds the production update service")
	if menu == null:
		_finish(game)
		return
	var before: Dictionary = update_service.call("get_snapshot")
	_check(int(before.get("check_count", -1)) == 0, "editor and desktop acceptance do not perform an uncontrolled public network check")
	var selection: Dictionary = update_service.call("ingest_release_payload", _release_payload("v1.1.0"))
	for _frame in 3:
		await process_frame
	_check(bool(selection.get("update_available", false)), "production service detects the newer GitHub release payload")
	var panel: Node = menu.call("get_update_panel") as Node
	_check(panel != null and bool(panel.get("visible")), "first-start update prompt opens automatically when an update exists")
	_check(str(panel.call("get_release_version")) == "1.1.0", "prompt displays the latest release version")
	var primary: Button = panel.call("get_primary_button") as Button
	var later: Button = panel.call("get_later_button") as Button
	_check(primary != null and primary.text.contains("自动更新"), "prompt offers download and automatic update")
	_check(later != null and later.text == "稍后", "prompt allows a non-destructive deferral")
	update_service.emit_signal("update_status_changed", &"downloading", "正在下载测试 Release")
	update_service.emit_signal("update_progress_changed", 3 * 1024 * 1024, 8 * 1024 * 1024)
	await process_frame
	_check(float(panel.call("get_progress_value")) > 37.0 and float(panel.call("get_progress_value")) < 38.0, "real progress bar reflects downloaded bytes")
	_check(str(panel.call("get_status_text")).contains("断网或断电"), "download UI explains cross-restart resume")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the update prompt")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "auto-update evidence uses 1024x576 resolution")
		_save_image(image)
	update_service.emit_signal("update_status_changed", &"failed", "网络中断；已下载部分会保留。")
	await process_frame
	_check(primary.text == "重试更新" and not primary.disabled, "interrupted download exposes a retry without discarding progress")
	if later != null:
		await _click_control(later)
	_check(not bool(panel.get("visible")), "later action returns to the main menu")
	_finish(game)


func _release_payload(tag: String) -> Dictionary:
	var base := "https://github.com/siyrs/star-world/releases/download/%s" % tag
	return {
		"tag_name":tag,
		"name":"Star World %s" % tag,
		"draft":false,
		"prerelease":false,
		"body":"自动更新验收 Release。\n\n- 可续传下载\n- SHA-256 校验\n- 自动重启",
		"published_at":"2026-07-21T00:00:00Z",
		"html_url":"https://github.com/siyrs/star-world/releases/tag/%s" % tag,
		"assets":[
			{"id":1, "name":AppVersion.PACKAGE_ASSET_NAME, "size":8 * 1024 * 1024, "browser_download_url":"%s/%s" % [base, AppVersion.PACKAGE_ASSET_NAME]},
			{"id":2, "name":AppVersion.CHECKSUM_ASSET_NAME, "size":96, "browser_download_url":"%s/%s" % [base, AppVersion.CHECKSUM_ASSET_NAME]},
		],
	}


func _click_control(control: Control) -> void:
	await process_frame
	var pointer := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	motion.global_position = pointer
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = pointer
	press.global_position = pointer
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = pointer
	release.global_position = pointer
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "auto-update screenshot is saved")


func _finish(game: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA AUTO UPDATE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AUTO UPDATE DESKTOP FAILURE: %s" % failure)
		print("QA AUTO UPDATE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
