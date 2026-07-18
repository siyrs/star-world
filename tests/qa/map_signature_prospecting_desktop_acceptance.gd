extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://map-signature-prospecting-desktop.png"
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
		"Map-Signature-%d" % Time.get_ticks_msec(), "abyss_world", 91426357
	)
	_check(not state.is_empty(), "desktop signature journey creates a temporary abyss world")
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
	var crafting: Node = hub.crafting
	var prospecting: Node = hub.get("prospecting_service")
	var journal: Node = hub.get("exploration_journal_service")
	var rewards: Node = hub.get("exploration_reward_service")
	var danger: Node = hub.get("exploration_danger_service")
	var spawner: Node = hub.creature_spawner
	var game_ui: Node = hub.game_ui
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production abyss world starts")
	_check(prospecting != null and journal != null and rewards != null and danger != null, "production signature services are mounted")
	if player == null or world == null or prospecting == null or journal == null or rewards == null or danger == null:
		await _finish(game, hub)
		return

	# Build a real abyss-danger context before the first pointer-driven scan.
	hub.day_night.set_time(22.0)
	spawner.clear_creatures()
	var hostile_a = spawner.spawn_creature("zombie", player.global_position + Vector3(5.0, 0.0, 1.0))
	var hostile_b = spawner.spawn_creature("zombie", player.global_position + Vector3(-5.0, 0.0, 1.0))
	_check(hostile_a != null and hostile_b != null, "production spawner creates nearby abyss hostiles")
	for _frame in 4:
		await process_frame
		await physics_frame
	var danger_snapshot: Dictionary = danger.call("refresh_now")
	_check(str(danger_snapshot.get("tier_id", "")) in ["dangerous", "severe"], "live abyss ecology reaches the signature danger tier")

	inventory.clear()
	inventory.add_item("prospecting_kit", 1)
	inventory.select_slot(0)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3(deg_to_rad(-42.0), 0.0, 0.0)
	await process_frame
	await _right_click_center()
	var first_snapshot: Dictionary = prospecting.call("get_snapshot")
	var first_result: Dictionary = first_snapshot.get("last_result", {})
	_check(int(first_snapshot.get("record_count", 0)) == 1, "real right click saves the first abyss discovery")
	_check(str(first_result.get("calibration_id", "")) == "basic", "first real scan uses the compatible base instrument")
	_check(not first_result.has("positions") and not first_result.has("coordinates"), "real scan exposes no exact resource coordinates")
	var signature_reward: Dictionary = rewards.call("get_reward", "signature_finding")
	_check(str(signature_reward.get("status", "")) == "claimable", "dangerous abyss scan completes the map signature milestone")

	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	_check(int(game_ui.call("get_active_overlay")) == ExtensionOverlayIds.EXPLORATION_JOURNAL, "real J input opens the signature-enabled journal")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "journal isolates gameplay input before signature claim")
	var panel: Control = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and panel.visible, "production signature journal is visible")
	var signature_button: Button = panel.call("get_claim_button", "signature_finding") as Button if panel != null else null
	_check(signature_button != null and not signature_button.disabled, "map signature exposes a real enabled claim button")
	if signature_button != null:
		await _click_control(signature_button)
	_check(inventory.count_item("abyss_cinder") == 1, "real claim grants exactly one abyss signature material")
	_check(rewards.call("is_claimed", "signature_finding"), "successful signature claim becomes durable claimed state")
	_check(panel != null and str(panel.call("get_reward_status", "signature_finding")) == "claimed", "journal refreshes the claimed signature card")
	await _tap_key(KEY_J)
	_check(int(game_ui.call("get_active_overlay")) == 0, "second J closes the signature journal")

	# Turn the claimed material into a durable map-specific progression tool.
	spawner.clear_creatures()
	inventory.add_item("gold_ingot", 1)
	inventory.add_item("coal", 4)
	crafting.set_station("workbench")
	_check(crafting.can_craft("abyss_prospecting_kit"), "production crafting recognizes the abyss calibration recipe")
	_check(crafting.craft("abyss_prospecting_kit"), "production crafting atomically creates the abyss calibrated instrument")
	_check(inventory.count_item("abyss_prospecting_kit") == 1, "calibrated prospecting tool enters the real inventory")
	_check(inventory.count_item("prospecting_kit") == 0 and inventory.count_item("abyss_cinder") == 0, "calibration consumes the base instrument and signature material once")
	var calibrated_slot := _find_item_slot(inventory, "abyss_prospecting_kit")
	_check(calibrated_slot >= 0, "desktop journey locates the crafted calibrated instrument")
	if calibrated_slot >= 0:
		inventory.equip_slot(calibrated_slot, 0)
		inventory.select_slot(0)
	player.global_position += Vector3(18.0, 0.0, 0.0)
	await create_timer(1.05).timeout
	await _right_click_center()
	var calibrated_snapshot: Dictionary = prospecting.call("get_snapshot")
	var calibrated_result: Dictionary = calibrated_snapshot.get("last_result", {})
	_check(str(calibrated_result.get("tool_item_id", "")) == "abyss_prospecting_kit", "real pointer input uses the crafted calibrated instrument")
	_check(str(calibrated_result.get("calibration_id", "")) == "abyss", "real calibrated scan reports the abyss profile")
	_check(int(calibrated_result.get("scan_profile", {}).get("vertical_radius", 0)) == 18, "real calibrated scan applies the deeper vertical range")
	_check(int(calibrated_result.get("sample_count", 0)) <= 684, "real calibrated scan respects its hard sample budget")
	_check(not calibrated_result.has("positions") and not calibrated_result.has("ore_positions") and not calibrated_result.has("coordinates"), "calibrated desktop scan preserves coarse-only output")
	_check(int(calibrated_snapshot.get("record_count", 0)) == 2, "calibrated scan participates in the same persistent journal")

	_check(bool(hub.save_current()), "signature claim, crafted tool and calibrated record join the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var claimed_ids: Array = loaded.get("exploration_rewards", {}).get("claimed", [])
	_check("signature_finding" in claimed_ids, "saved world retains the claimed map signature")
	_check(int(loaded.get("exploration", {}).get("records", []).size()) == 2, "saved world retains both base and calibrated discoveries")
	var calibrated_before_reload := inventory.count_item("abyss_prospecting_kit")
	var cinder_before_reload := inventory.count_item("abyss_cinder")
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
	prospecting = hub.get("prospecting_service")
	_check(rewards.call("is_claimed", "signature_finding"), "full world reload restores the claimed signature state")
	_check(inventory.count_item("abyss_prospecting_kit") == calibrated_before_reload, "world reload preserves the crafted calibrated tool exactly once")
	_check(inventory.count_item("abyss_cinder") == cinder_before_reload, "world reload does not recreate the consumed signature material")
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == 2, "full world reload restores calibrated exploration history")
	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and str(panel.call("get_reward_status", "signature_finding")) == "claimed", "reloaded journal renders the map signature as claimed")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the map signature progression journal")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "signature evidence is captured at the 1024x576 product resolution")
		_save_image(image)
	await _finish(game, hub)


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in inventory.slot_count:
		if str(inventory.get_slot(index).get("item_id", "")) == item_id:
			return index
	return -1


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


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "map signature desktop screenshot is saved")


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
		print("QA MAP SIGNATURE PROSPECTING DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MAP SIGNATURE PROSPECTING DESKTOP FAILURE: %s" % failure)
		print("QA MAP SIGNATURE PROSPECTING DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
