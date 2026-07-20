extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://service-hub-feature-lifecycle-desktop.png"
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
	var coordinator: Node = hub.get("feature_lifecycle") if hub != null else null
	var machine: Node = hub.get("machine_runtime_participant") if hub != null else null
	var husbandry: Node = hub.get("husbandry_runtime_participant") if hub != null else null
	var ranch: Node = hub.get("ranch_runtime_participant") if hub != null else null
	var runtime: Node = hub.get("exploration_runtime_participant") if hub != null else null
	var participant: Node = hub.get("exploration_journal_reward_participant") if hub != null else null
	var machine_runtime: Node = hub.get("machine_runtime") if hub != null else null
	_check(
		hub != null
		and coordinator != null
		and machine != null
		and husbandry != null
		and ranch != null
		and runtime != null
		and participant != null
		and machine_runtime != null,
		"production game mounts all five feature lifecycle participants"
	)
	if (
		hub == null
		or coordinator == null
		or machine == null
		or husbandry == null
		or ranch == null
		or runtime == null
		or participant == null
		or machine_runtime == null
	):
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Lifecycle-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		8529143
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop lifecycle journey creates a temporary world")
	game.begin_world_state(state)
	for _frame in 10:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var inventory: Node = hub.inventory
	var husbandry_service: Node = hub.get("husbandry_service")
	var husbandry_interaction: Node = hub.get("husbandry_interaction")
	var attraction: Node = hub.get("animal_attraction_service")
	var products: Node = hub.get("animal_product_service")
	var prospecting: Node = hub.get("prospecting_service")
	var danger: Node = hub.get("exploration_danger_service")
	var rewards: Node = hub.get("exploration_reward_service")
	var journal: Node = hub.get("exploration_journal_service")
	var game_ui: Node = hub.game_ui
	_check(player != null and bool(player.get("input_enabled")), "production player starts after participant begin and activate phases")
	_check(
		husbandry_service != null
		and husbandry_interaction != null
		and attraction != null
		and products != null
		and prospecting != null
		and danger != null
		and rewards != null
		and journal != null,
		"legacy husbandry, ranch and exploration service ports remain mounted"
	)
	_check(coordinator.call("has_participant", &"machine_runtime"), "Machine Base is registered as the lifecycle root")
	_check(
		coordinator.call("get_participant_dependencies", &"ranch_runtime") == ["husbandry_runtime"],
		"production lifecycle exposes the ranch-to-husbandry dependency"
	)
	_check(
		coordinator.call("get_participant_dependencies", &"exploration_journal_rewards") == ["exploration_runtime"],
		"production lifecycle exposes the journal dependency"
	)
	_check(bool(machine_runtime.call("is_active")), "production world activation starts Machine Base")
	if (
		player == null
		or husbandry_service == null
		or husbandry_interaction == null
		or attraction == null
		or products == null
		or prospecting == null
		or danger == null
		or rewards == null
		or journal == null
	):
		await _finish(game, hub)
		return

	var announcements: Array[Array] = []
	participant.connect(
		"claimable_reward_announced",
		func(ids: Array[String], _snapshot: Dictionary) -> void: announcements.append(ids.duplicate())
	)
	inventory.clear()
	inventory.add_item("prospecting_kit", 1)
	inventory.select_slot(0)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3(deg_to_rad(-42.0), 0.0, 0.0)
	await process_frame
	await _right_click_center()
	var prospecting_snapshot: Dictionary = prospecting.call("get_snapshot")
	_check(int(prospecting_snapshot.get("record_count", 0)) == 1, "real right click records the first discovery through composed services")
	_check(int(runtime.call("get_lifecycle_snapshot").get("scan_success_count", 0)) == 1, "runtime participant observes the real scan exactly once")
	_check(announcements.size() == 1 and "first_discovery" in announcements[0], "real scan publishes exactly one new reward availability notice")
	var feedback: Node = hub.player_experience.call("get_feedback")
	_check(int(feedback.call("get_queue_size")) >= 1, "reward availability notice enters the bounded production feedback queue")
	journal.call("refresh")
	await process_frame
	_check(announcements.size() == 1, "manual journal refresh does not duplicate the reward notice")

	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	_check(int(game_ui.call("get_active_overlay")) == ExtensionOverlayIds.EXPLORATION_JOURNAL, "real J input opens the participant-backed exploration journal")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "journal still isolates gameplay input after composition")
	var panel: Control = game_ui.call("get_exploration_journal_panel") as Control
	var claim_button: Button = panel.call("get_claim_button", "first_discovery") as Button if panel != null else null
	_check(claim_button != null and not claim_button.disabled, "first discovery keeps its real claim button")
	if claim_button != null:
		await _click_control(claim_button)
	_check(rewards.call("is_claimed", "first_discovery"), "real pointer claim reaches the composed reward service")
	_check(inventory.count_item("torch") == 4 and inventory.count_item("apple") == 2, "real claim grants the complete star-continent reward bundle")
	await _tap_key(KEY_J)
	_check(int(game_ui.call("get_active_overlay")) == 0, "second J closes the composed journal")

	_check(bool(hub.save_current()), "all participant states join the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(loaded.has("machines") and loaded.get("machines", {}).has("furnaces"), "saved world contains the Machine Base domain")
	_check(loaded.has("husbandry"), "saved world contains the husbandry participant domain")
	_check(loaded.has("animal_products"), "saved world contains the ranch participant domain")
	_check((loaded.get("exploration", {}).get("records", []) as Array).size() == 1, "saved world contains the runtime exploration record")
	_check("first_discovery" in (loaded.get("exploration_rewards", {}).get("claimed", []) as Array), "saved world contains the claimed dependent state")
	var announcement_count_before_reload := int(participant.call("get_lifecycle_snapshot").get("announcement_count", 0))
	var old_player := player
	hub.return_to_menu()
	for _frame in 6:
		await process_frame
	_check((journal.call("get_snapshot") as Dictionary).is_empty(), "real return-to-menu clears participant journal state")
	_check((rewards.call("get_snapshot") as Dictionary).is_empty(), "real return-to-menu clears participant reward state")
	_check(int(runtime.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "real return-to-menu clears the exploration player binding")
	_check(int(ranch.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "real return-to-menu clears the ranch player binding")
	_check(int(husbandry.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "real return-to-menu clears the husbandry player binding")
	_check(not bool(machine_runtime.call("is_active")), "real return-to-menu stops the Machine Base scheduler")
	if old_player != null and is_instance_valid(old_player):
		_check(old_player.get("prospecting_service") == null, "old player no longer retains the runtime prospecting port")
		_check(old_player.get("entity_interaction_service") == null, "old player no longer retains the husbandry interaction port")
	var lifecycle_after_menu: Dictionary = coordinator.call("get_snapshot")
	_check(_phase_count_with_prefix(lifecycle_after_menu, "clear:return_to_menu") == 1, "return-to-menu invokes the feature clear phase exactly once")
	var history: Array = lifecycle_after_menu.get("phase_history", [])
	_check(
		not history.is_empty()
		and str(history.back()).contains(
			"exploration_journal_rewards,exploration_runtime,ranch_runtime,husbandry_runtime,machine_runtime"
		),
		"desktop cleanup records the complete reverse dependency order"
	)

	game.begin_world_state(loaded)
	for _frame in 10:
		await process_frame
	await physics_frame
	player = game.player
	inventory = hub.inventory
	rewards = hub.get("exploration_reward_service")
	journal = hub.get("exploration_journal_service")
	_check(rewards.call("is_claimed", "first_discovery"), "full world reload restores participant-owned claimed state")
	_check(inventory.count_item("torch") == 4 and inventory.count_item("apple") == 2, "full reload does not duplicate reward items")
	_check(int(participant.call("get_lifecycle_snapshot").get("announcement_count", 0)) == announcement_count_before_reload, "reload baseline prevents duplicate reward availability messages")
	_check(player != null and player.get("prospecting_service") == prospecting, "reload rebinds the runtime prospecting service")
	_check(player != null and player.get("entity_interaction_service") == husbandry_interaction, "reload rebinds the husbandry interaction service")
	_check(int(ranch.call("get_lifecycle_snapshot").get("bound_player_id", 0)) == player.get_instance_id(), "reload rebinds the ranch runtime to the current player")
	_check(int(husbandry.call("get_lifecycle_snapshot").get("bound_player_id", 0)) == player.get_instance_id(), "reload rebinds the husbandry runtime to the current player")
	_check(bool(machine_runtime.call("is_active")), "reload reactivates the shared Machine Base scheduler")
	await _tap_key(KEY_J)
	for _frame in 3:
		await process_frame
	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and str(panel.call("get_reward_status", "first_discovery")) == "claimed", "reloaded production journal renders the participant reward as claimed")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(int(character_snapshot.get("feature_lifecycle", {}).get("participant_count", 0)) == 5, "production diagnostics expose all five composed participants")
	_check(character_snapshot.has("machine_runtime") and character_snapshot.has("machines"), "Machine Base participant preserves its diagnostics fields")
	_check(character_snapshot.has("husbandry"), "husbandry participant preserves its legacy diagnostics field")
	_check(character_snapshot.has("animal_attraction") and character_snapshot.has("animal_products"), "ranch participant preserves legacy diagnostics fields")
	_check(character_snapshot.has("exploration") and character_snapshot.has("danger"), "runtime participant preserves legacy diagnostics fields")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the participant-backed journal")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "lifecycle evidence is captured at the 1024x576 product resolution")
		_save_image(image)

	game.call("_abort_world_start", "qa_feature_lifecycle_failure")
	for _frame in 4:
		await process_frame
	_check(hub.current_world_id.is_empty(), "real world-start failure signal resets the hub identity")
	_check((journal.call("get_snapshot") as Dictionary).is_empty() and (rewards.call("get_snapshot") as Dictionary).is_empty(), "real world-start failure clears dependent services")
	_check(int((prospecting.call("get_snapshot") as Dictionary).get("record_count", 0)) == 0 and (danger.call("get_snapshot") as Dictionary).is_empty(), "real world-start failure clears exploration runtime services")
	_check(int(runtime.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "failed-start cleanup removes the exploration player binding")
	_check(int(ranch.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "failed-start cleanup removes the ranch player binding")
	_check(int(husbandry.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "failed-start cleanup removes the husbandry player binding")
	_check(not bool(machine_runtime.call("is_active")), "failed-start cleanup stops Machine Base")
	await _finish(game, hub)


func _phase_count_with_prefix(snapshot: Dictionary, phase_prefix: String) -> int:
	var result := 0
	var phase_counts: Dictionary = snapshot.get("phase_counts", {})
	for raw_phase: Variant in phase_counts.keys():
		if str(raw_phase).begins_with(phase_prefix):
			result += int(phase_counts[raw_phase])
	return result


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
	_check(error == OK and FileAccess.file_exists(_capture_path), "service hub lifecycle desktop screenshot is saved")


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
		print("QA SERVICE HUB FEATURE LIFECYCLE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SERVICE HUB FEATURE LIFECYCLE DESKTOP FAILURE: %s" % failure)
		print("QA SERVICE HUB FEATURE LIFECYCLE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
