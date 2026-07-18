extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://exploration-milestone-reward-desktop.png"
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
		"Exploration-Rewards-%d" % Time.get_ticks_msec(),
		"abyss_world",
		82651347
	)
	_check(not state.is_empty(), "desktop reward journey creates a temporary abyss world")
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
	var inventory: Node = hub.inventory
	var prospecting: Node = hub.get("prospecting_service")
	var rewards: Node = hub.get("exploration_reward_service")
	var game_ui: Node = hub.game_ui
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts")
	_check(prospecting != null and rewards != null, "production prospecting and reward services are mounted")
	if player == null or world == null or prospecting == null or rewards == null:
		await _finish(game, hub)
		return

	inventory.clear()
	inventory.add_item("prospecting_kit", 1)
	inventory.select_slot(0)
	hub.day_night.set_time(8.5)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3(deg_to_rad(-42.0), 0.0, 0.0)
	await process_frame
	await _right_click_center()
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == 1, "real right click completes the first exploration milestone")
	_check(str(rewards.call("get_reward", "first_discovery").get("status", "")) == "claimable", "first discovery reward becomes claimable in production")

	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	_check(int(game_ui.call("get_active_overlay")) == ExtensionOverlayIds.EXPLORATION_JOURNAL, "real J input opens the reward-enabled journal")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "journal isolates gameplay input before claiming")
	var panel: Control = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and panel.visible, "production reward journal is visible")
	var first_button: Button = panel.call("get_claim_button", "first_discovery") as Button if panel != null else null
	_check(first_button != null and not first_button.disabled, "first discovery exposes a real enabled claim button")
	if first_button != null:
		await _click_control(first_button)
	_check(inventory.count_item("torch") == 4, "real claim grants the base torch bundle")
	_check(inventory.count_item("cooked_chicken") == 2, "real abyss claim grants its map-specific food bonus")
	_check(str(rewards.call("get_reward", "first_discovery").get("status", "")) == "claimed", "successful desktop claim becomes durable claimed state")
	_check(panel != null and str(panel.call("get_reward_status", "first_discovery")) == "claimed", "journal refreshes the claimed milestone card")
	await _tap_key(KEY_J)
	_check(int(game_ui.call("get_active_overlay")) == 0, "second J closes the reward journal")

	var origin: Vector3 = player.global_position
	var base_msec: int = Time.get_ticks_msec() + 2000
	player.global_position = origin + Vector3(18.0, 0.0, 0.0)
	var second: Dictionary = prospecting.call("use_item", "prospecting_kit", base_msec)
	player.global_position = origin + Vector3(36.0, 0.0, 0.0)
	var third: Dictionary = prospecting.call("use_item", "prospecting_kit", base_msec + 2000)
	_check(bool(second.get("success", false)) and bool(third.get("success", false)), "production service records two additional real-world chunks")
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == 3, "three unique chunks complete the second reward milestone")
	_check(str(rewards.call("get_reward", "three_regions").get("status", "")) == "claimable", "three-region reward becomes claimable")

	var serial := 0
	while serial < 48:
		var remaining: int = int(inventory.add_item("wooden_pickaxe", 1, {"serial":serial}))
		if remaining > 0:
			break
		serial += 1
	_check(_non_empty_slots(inventory) == inventory.slot_count, "desktop journey fills every real inventory slot")
	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	panel = game_ui.call("get_exploration_journal_panel") as Control
	var three_button: Button = panel.call("get_claim_button", "three_regions") as Button if panel != null else null
	_check(three_button != null and not three_button.disabled, "three-region reward exposes a real claim button")
	if three_button != null:
		await _click_control(three_button)
	_check(inventory.count_item("iron_ingot") == 0, "full inventory receives no partial reward items")
	_check(str(rewards.call("get_reward", "three_regions").get("status", "")) == "claimable", "full-inventory rejection preserves pending reward state")
	_check(panel != null and str(panel.call("get_reward_status", "three_regions")) == "claimable", "journal keeps the failed reward visibly claimable")
	_check(_remove_first_item(inventory, "wooden_pickaxe"), "desktop journey releases one inventory slot")
	if three_button != null and is_instance_valid(three_button):
		await _click_control(three_button)
	_check(inventory.count_item("iron_ingot") == 2, "retry grants the complete iron reward after space is available")
	_check(str(rewards.call("get_reward", "three_regions").get("status", "")) == "claimed", "successful retry marks the reward claimed")

	_check(bool(hub.save_current()), "claimed and pending reward state participates in the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var claimed_ids: Array = loaded.get("exploration_rewards", {}).get("claimed", [])
	_check(int(loaded.get("exploration_rewards", {}).get("version", 0)) == 1, "saved world contains reward state version one")
	_check("first_discovery" in claimed_ids and "three_regions" in claimed_ids, "saved world retains both claimed milestones")
	var torch_before_reload: int = int(inventory.count_item("torch"))
	var iron_before_reload: int = int(inventory.count_item("iron_ingot"))
	await _tap_key(KEY_J)
	hub.return_to_menu()
	for _frame in 6:
		await process_frame
	game.begin_world_state(loaded)
	for _frame in 10:
		await process_frame
	await physics_frame
	player = game.player
	inventory = hub.inventory
	rewards = hub.get("exploration_reward_service")
	_check(rewards.call("is_claimed", "first_discovery") and rewards.call("is_claimed", "three_regions"), "full world reload restores claimed reward state")
	_check(inventory.count_item("torch") == torch_before_reload and inventory.count_item("iron_ingot") == iron_before_reload, "world reload does not duplicate claimed reward items")
	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and str(panel.call("get_reward_status", "first_discovery")) == "claimed", "reloaded journal renders the first reward as claimed")
	_check(panel != null and str(panel.call("get_reward_status", "three_regions")) == "claimed", "reloaded journal renders the retried reward as claimed")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the reward-enabled exploration journal")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "reward evidence is captured at the 1024x576 product resolution")
		_save_image(image)
	await _finish(game, hub)


func _click_control(control: Control) -> void:
	await process_frame
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = target
	press.global_position = target
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = target
	release.global_position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


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


func _non_empty_slots(inventory: Node) -> int:
	var result := 0
	for index in inventory.slot_count:
		if not inventory.get_slot(index).is_empty():
			result += 1
	return result


func _remove_first_item(inventory: Node, item_id: String) -> bool:
	for index in inventory.slot_count:
		if str(inventory.get_slot(index).get("item_id", "")) == item_id:
			inventory.remove_from_slot(index, 1)
			return true
	return false


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "reward desktop screenshot is saved")


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
		print("QA EXPLORATION REWARD DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION REWARD DESKTOP FAILURE: %s" % failure)
		print("QA EXPLORATION REWARD DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
