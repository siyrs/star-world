extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")

const QA_WORLD_PREFIX := "qa-v130-journey-"
const JOURNEY_SEED := 112358
const READY_FRAMES := 720
const CLEANUP_FRAMES := 60

var checks := 0
var failures: Array[String] = []
var _created_world_ids: Array[String] = []
var _journey_records: Array[Dictionary] = []
var _capture_path := ""
var _capture_directory := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile_ids := MapProfileCatalogScript.get_ids()
	var requested_profile := _user_argument("profile")
	if not requested_profile.is_empty():
		if requested_profile not in profile_ids:
			push_error("Unknown journey profile filter: %s" % requested_profile)
			quit(2)
			return
		profile_ids = [requested_profile]
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), "")
	_capture_directory = _capture_path.get_base_dir() if not _capture_path.is_empty() else ""
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	print("JOURNEY_FILTER profiles=%s seed=%d capture=%s" % [JSON.stringify(profile_ids), JOURNEY_SEED, _capture_path])

	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	var menu := hub.get("main_menu") as Control if hub != null else null
	var save := hub.get("save_service") as Node if hub != null else null
	_check(
		hub != null and menu != null and save != null,
		"production game mounts the menu and save services for the journey"
	)
	if hub == null or menu == null or save == null:
		await _finish(game, hub, save)
		return

	var pre_manifest := _directory_manifest("user://worlds")
	for profile_id: String in profile_ids:
		await _exercise_profile(game, hub, menu, save, profile_id)
	var post_manifest := _directory_manifest("user://worlds")
	_check(
		pre_manifest == post_manifest,
		"journey restores the pre-run world-data manifest after QA cleanup"
	)
	_write_report(pre_manifest, post_manifest)
	await _finish(game, hub, save)


func _exercise_profile(game: Node, hub: Node, menu: Control, save: Node, profile_id: String) -> void:
	var display_name := _unique_qa_display_name(profile_id)
	var record: Dictionary = {
		"profile_id": profile_id,
		"seed": JOURNEY_SEED,
		"display_name": display_name,
		"world_id": "",
		"entered": false,
		"returned_to_menu": false,
		"capture": "",
	}
	print("JOURNEY_START profile=%s display_name=%s" % [profile_id, display_name])

	_check(await _click_text(menu, "创建新世界"), "%s real mouse opens world creation" % profile_id)
	var map_panel := menu.get("_map_panel") as Control
	_check(map_panel != null and map_panel.visible, "%s map selection becomes visible" % profile_id)
	var profile_button := _find_profile_button(map_panel, profile_id)
	_check(
		profile_button != null and await _click_button(profile_button),
		"%s real mouse selects its production profile" % profile_id
	)
	var name_edit := map_panel.get("_world_name") as LineEdit if map_panel != null else null
	var seed_edit := map_panel.get("_seed") as LineEdit if map_panel != null else null
	if name_edit != null:
		name_edit.text = display_name
	if seed_edit != null:
		seed_edit.text = str(JOURNEY_SEED)
	_check(
		name_edit != null and name_edit.text == display_name and seed_edit != null and seed_edit.text == str(JOURNEY_SEED),
		"%s journey records its deterministic QA name and seed before creation" % profile_id
	)
	_check(
		await _click_text(map_panel, "创建并进入世界"),
		"%s real mouse submits the normal create-and-enter action" % profile_id
	)
	var entered := await _wait_for_world_ready(game, hub)
	record["entered"] = entered
	_check(entered, "%s normal menu flow reaches a playable production world" % profile_id)

	var world_id := str(hub.get("current_world_id"))
	record["world_id"] = world_id
	if not world_id.is_empty() and world_id not in _created_world_ids:
		_created_world_ids.append(world_id)
	var saved_state: Dictionary = save.call("load_world", world_id) if not world_id.is_empty() else {}
	var metadata: Dictionary = saved_state.get("metadata", {})
	_check(
		str(metadata.get("map_id", "")) == profile_id
		and int(metadata.get("seed", 0)) == JOURNEY_SEED
		and str(metadata.get("name", "")) == display_name,
		"%s persists the selected profile, seed and QA world name" % profile_id
	)
	_check(
		str(game.get("current_profile_id")) == profile_id and int(game.get("current_seed")) == JOURNEY_SEED,
		"%s runtime world identity matches the normal-menu selection" % profile_id
	)
	if entered:
		record["capture"] = await _capture_profile(profile_id)
		_check(
			_capture_path.is_empty() or not str(record["capture"]).is_empty(),
			"%s desktop journey capture is written when requested" % profile_id
		)

	if not world_id.is_empty():
		hub.call("return_to_menu")
		var returned := await _wait_for_menu(hub, menu)
		record["returned_to_menu"] = returned
		_check(returned, "%s returns cleanly to the normal menu" % profile_id)
		_check(bool(save.call("delete_world", world_id)), "%s deletes its isolated QA world" % profile_id)
	_journey_records.append(record)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world := game.get("world") as Node
		if world != null and bool(world.get("is_started")) and not str(hub.get("current_world_id")).is_empty():
			return true
	return false


func _wait_for_menu(hub: Node, menu: Control) -> bool:
	for _frame in CLEANUP_FRAMES:
		await process_frame
		if hub != null and menu != null and str(hub.get("current_world_id")).is_empty() and menu.visible:
			return true
	return false


func _click_text(root_node: Node, text: String) -> bool:
	return await _click_button(_find_button(root_node, text))


func _click_button(button: Button) -> bool:
	if button == null or not button.visible or button.disabled:
		return false
	for _frame in 2:
		await process_frame
	var center := button.get_global_rect().get_center()
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
	release.pressed = false
	root.push_input(release)
	for _frame in 3:
		await process_frame
	return true


func _find_profile_button(node: Node, profile_id: String) -> Button:
	if node == null:
		return null
	if node is Button and str((node as Button).get_meta("map_id", "")) == profile_id:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_profile_button(child, profile_id)
		if found != null:
			return found
	return null


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


func _capture_profile(profile_id: String) -> String:
	if _capture_path.is_empty():
		return ""
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(_capture_directory)
	var capture_path := _capture_directory.path_join("profile-journey-%s.png" % profile_id)
	if image.save_png(capture_path) != OK or not FileAccess.file_exists(capture_path):
		return ""
	if _journey_records.is_empty() and capture_path != _capture_path:
		if image.save_png(_capture_path) != OK or not FileAccess.file_exists(_capture_path):
			return ""
	return capture_path


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


func _write_report(pre_manifest: Dictionary, post_manifest: Dictionary) -> void:
	if _capture_path.is_empty():
		return
	var report_path := _capture_directory.path_join("profile-release-journey-report.json")
	var report := {
		"schema_version": 2,
		"seed": JOURNEY_SEED,
		"records": _journey_records,
		"pre_world_manifest": pre_manifest,
		"post_world_manifest": post_manifest,
		"manifest_restored": pre_manifest == post_manifest,
	}
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_check(false, "profile journey report opens for writing")
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	_check(FileAccess.file_exists(report_path), "profile journey JSON report is saved")


func _finish(game: Node, hub: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub) and not str(hub.get("current_world_id")).is_empty():
		hub.call("return_to_menu")
		for _frame in CLEANUP_FRAMES:
			await process_frame
	if save != null and is_instance_valid(save):
		for world_id: String in _created_world_ids:
			if not world_id.is_empty() and bool(save.call("world_exists", world_id)):
				save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA PROFILE JOURNEY PASS | checks=%d | profiles=%d" % [checks, _journey_records.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PROFILE JOURNEY FAILURE: %s" % failure)
		print("QA PROFILE JOURNEY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _unique_qa_display_name(profile_id: String) -> String:
	return "%s%s-%d-%d" % [QA_WORLD_PREFIX, profile_id, JOURNEY_SEED, Time.get_ticks_msec()]


func _user_argument(name: String) -> String:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).strip_edges()
	return ""


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
