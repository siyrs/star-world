extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://exploration-journal-desktop.png"
const CLEANUP_FRAMES := 8

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production game exposes the exploration service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Exploration-Journal-%d" % Time.get_ticks_msec(),
		"abyss_world",
		78241639
	)
	_check(not state.is_empty(), "desktop journal journey creates a temporary abyss world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	for _frame in 10:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var prospecting: Node = hub.get("prospecting_service")
	var journal: Node = hub.get("exploration_journal_service")
	var game_ui: Node = hub.game_ui
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts")
	_check(prospecting != null and journal != null, "production prospecting and journal services are mounted")
	if player == null or world == null or prospecting == null or journal == null:
		await _finish(game, hub)
		return

	hub.inventory.clear()
	hub.inventory.add_item("prospecting_kit", 1)
	hub.inventory.select_slot(0)
	hub.day_night.set_time(8.5)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3(deg_to_rad(-40.0), 0.0, 0.0)
	await process_frame
	await _right_click_center()
	var first_snapshot: Dictionary = prospecting.call("get_snapshot")
	_check(int(first_snapshot.get("record_count", 0)) == 1, "real right click creates the first journal discovery")
	_check(int(first_snapshot.get("last_result", {}).get("world_day", 0)) >= 1, "real discovery stores the in-world day")

	# Continue from the real scan's monotonic clock. Mixing a smaller artificial
	# timestamp with Time.get_ticks_msec() would correctly trigger the cooldown.
	var scan_clock := Time.get_ticks_msec() + 2000
	var origin := player.global_position
	hub.day_night.day_count = 3
	hub.day_night.set_time(15.25)
	player.global_position = origin + Vector3(18.0, 0.0, 0.0)
	var second: Dictionary = prospecting.call("use_item", "prospecting_kit", scan_clock)
	_check(
		bool(second.get("success", false)),
		"production service records a second real-world chunk: %s" % second
	)
	scan_clock += 2000
	hub.day_night.day_count = 4
	hub.day_night.set_time(21.5)
	player.global_position = origin + Vector3(36.0, 0.0, 0.0)
	var third: Dictionary = prospecting.call("use_item", "prospecting_kit", scan_clock)
	_check(
		bool(third.get("success", false)),
		"production service records a third real-world chunk: %s" % third
	)
	scan_clock += 2000
	player.global_position = origin
	var refreshed: Dictionary = prospecting.call("use_item", "prospecting_kit", scan_clock)
	_check(
		bool(refreshed.get("success", false)),
		"production service refreshes an existing chunk: %s" % refreshed
	)
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == 3, "refreshing an existing discovery keeps journal rows unique")
	_check(int(refreshed.get("sequence", 0)) > int(third.get("sequence", 0)), "refreshed discovery becomes the newest journal entry")

	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	_check(int(game_ui.call("get_active_overlay")) == ExtensionOverlayIds.EXPLORATION_JOURNAL, "real J input opens the exploration journal")
	_check(str(hub.input_context.call("get_context")) == str(InputContextScript.CONTEXT_JOURNAL), "journal switches the production input context")
	_check(not bool(player.get("input_enabled")), "journal blocks player movement and interaction input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "journal releases the mouse for UI interaction")
	var panel: Control = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and panel.visible, "production journal panel is visible")
	if panel != null:
		var summary := str(panel.call("get_summary_text"))
		var records: Array = panel.call("get_record_texts")
		var milestones: Array = panel.call("get_milestone_texts")
		_check(summary.contains("已记录 3 条发现"), "journal summary reflects deduplicated production records")
		_check(records.size() == 3, "journal panel renders three production discoveries")
		_check(str(records[0]).begins_with("#4"), "refreshed record keeps its stable discovery id and renders first")
		_check(str(records[0]).contains("第 4 天 21:30"), "journal renders stable in-world date and time")
		_check(milestones.size() >= 1 and str(milestones[0]).begins_with("✓"), "first-discovery milestone is visibly completed")
		var rects: Dictionary = panel.call("get_layout_rects")
		var panel_rect: Rect2 = rects.get("panel", Rect2())
		var visible_rect := panel.get_viewport().get_visible_rect()
		print("QA EXPLORATION JOURNAL LAYOUT | visible=%s panel=%s" % [visible_rect, panel_rect])
		_check(_rect_inside(visible_rect, panel_rect), "journal panel remains inside the actual desktop viewport")
	var before_blocked_click := int(prospecting.call("get_snapshot").get("record_count", 0))
	await _right_click_center()
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == before_blocked_click, "journal overlay blocks real prospecting input")
	await _tap_key(KEY_J)
	_check(int(game_ui.call("get_active_overlay")) == 0, "second real J input closes the journal")
	_check(str(hub.input_context.call("get_context")) == str(InputContextScript.CONTEXT_GAMEPLAY), "closing journal restores gameplay context")
	_check(bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing journal restores player and mouse input")

	_check(bool(hub.save_current()), "journal discoveries participate in the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(int(loaded.get("exploration", {}).get("version", 0)) == 3, "saved world uses exploration persistence version 3")
	var saved_records: Array = loaded.get("exploration", {}).get("records", [])
	_check(saved_records.size() == 3, "saved journal keeps deduplicated discoveries")
	if saved_records.size() == 3:
		_check(int(saved_records[0].get("sequence", 0)) == 2 and int(saved_records[2].get("sequence", 0)) == 4, "save preserves stable sequence gaps without changing order")
		_check(not str(saved_records).contains("ore_positions") and not str(saved_records).contains("coordinates"), "saved journal contains no forbidden coordinate payloads")

	hub.return_to_menu()
	for _frame in 6:
		await process_frame
	game.begin_world_state(loaded)
	for _frame in 10:
		await process_frame
	await physics_frame
	player = game.player
	prospecting = hub.get("prospecting_service")
	journal = hub.get("exploration_journal_service")
	_check(int(journal.call("get_snapshot").get("record_count", 0)) == 3, "full production world reload restores the journal")
	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(int(game_ui.call("get_active_overlay")) == ExtensionOverlayIds.EXPLORATION_JOURNAL, "journal reopens after full world reload")
	if panel != null:
		var reloaded_records: Array = panel.call("get_record_texts")
		_check(reloaded_records.size() == 3, "reloaded journal renders all persisted records")
		_check(str(reloaded_records[0]).begins_with("#4"), "reloaded journal keeps the stable newest-first discovery id")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the exploration journal")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "desktop evidence is captured at the 1024x576 product resolution")
		_save_image(image)
	await _finish(game, hub)


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (1 << (int(button) - 1)) if pressed else 0
	event.pressed = pressed
	root.push_input(event)


func _tap_key(keycode: Key) -> void:
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
	await process_frame
	await process_frame


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x
		and candidate.position.y >= container_rect.position.y
		and candidate.end.x <= container_rect.end.x
		and candidate.end.y <= container_rect.end.y
	)


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "exploration journal desktop screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA EXPLORATION JOURNAL DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION JOURNAL DESKTOP FAILURE: %s" % failure)
		print("QA EXPLORATION JOURNAL DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
