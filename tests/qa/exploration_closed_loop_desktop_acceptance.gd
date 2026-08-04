extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const OverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://exploration-closed-loop-desktop.png"
const CLEANUP_FRAMES := 10
const TOOL_ITEM_ID := "abyss_prospecting_kit"
const MILESTONE_IDS: Array[String] = [
	"first_discovery",
	"three_regions",
	"deep_delver",
	"rich_signal",
	"danger_scout",
	"four_depths",
	"seasoned_explorer",
	"signature_finding",
]

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the exploration service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Exploration-Closed-Loop-%d" % Time.get_ticks_msec(),
		"abyss_world",
		78241639,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "exploration journey creates a temporary abyss world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production exploration world reaches a bounded ready state")

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var inventory: Node = hub.get("inventory") as Node
	var prospecting: Node = hub.get("prospecting_service") as Node
	var journal: Node = hub.get("exploration_journal_service") as Node
	var rewards: Node = hub.get("exploration_reward_service") as Node
	var danger: Node = hub.get("exploration_danger_service") as Node
	var day_night: Node = hub.get("day_night") as Node
	var game_ui: Node = hub.get("game_ui") as Node
	_check(
		player != null and world != null and inventory != null
		and prospecting != null and journal != null and rewards != null
		and danger != null and day_night != null and game_ui != null,
		"production player, world, prospecting, journal, rewards and danger services are mounted",
	)
	if player == null or world == null or inventory == null or prospecting == null or journal == null or rewards == null or danger == null or day_night == null or game_ui == null:
		await _finish(game, hub)
		return

	var completed_scans: Array[Dictionary] = []
	var rejected_scans: Array[Dictionary] = []
	var claimed_rewards: Array[Dictionary] = []
	var rejected_rewards: Array[Dictionary] = []
	prospecting.scan_completed.connect(
		func(result: Dictionary) -> void:
			completed_scans.append(result.duplicate(true))
	)
	prospecting.scan_rejected.connect(
		func(reason: String, context: Dictionary) -> void:
			rejected_scans.append({"reason":reason, "context":context.duplicate(true)})
	)
	rewards.reward_claimed.connect(
		func(milestone_id: String, result: Dictionary) -> void:
			claimed_rewards.append({"milestone_id":milestone_id, "result":result.duplicate(true)})
	)
	rewards.reward_rejected.connect(
		func(milestone_id: String, reason: String, context: Dictionary) -> void:
			rejected_rewards.append({
				"milestone_id":milestone_id,
				"reason":reason,
				"context":context.duplicate(true),
			})
	)

	inventory.clear()
	inventory.call("add_item", TOOL_ITEM_ID, 1)
	inventory.select_slot(0)
	_check(inventory.count_item(TOOL_ITEM_ID) == 1, "fixture grants the production abyss calibration tool")
	var stations := _station_centers(world, player)
	_check(stations.size() == 12, "fixture defines twelve unique chunk and depth scan stations")

	for index in stations.size():
		var center: Vector3i = stations[index]
		await _prepare_scan_station(world, player, center)
		day_night.set("day_count", index + 1)
		day_night.call("set_time", 23.0 if center.y <= 10 else 12.0)
		if danger.has_method("refresh_now"):
			danger.call("refresh_now")
		if index > 0:
			await create_timer(1.0).timeout
		var before_count := int(prospecting.call("get_snapshot").get("record_count", 0))
		await _right_click_center()
		var after_snapshot: Dictionary = prospecting.call("get_snapshot")
		_check(
			int(after_snapshot.get("record_count", 0)) == before_count + 1,
			"real right click stores unique exploration record %d" % (index + 1),
		)
		var last_result: Dictionary = after_snapshot.get("last_result", {})
		_check(bool(last_result.get("success", false)), "scan %d completes through the production service" % (index + 1))
		_check(str(last_result.get("tool_item_id", "")) == TOOL_ITEM_ID, "scan %d retains the selected calibration identity" % (index + 1))
		_check(str(last_result.get("density_id", "")) == "rich", "scan %d records the deterministic rich geology station" % (index + 1))
		if center.y <= 10:
			_check(str(last_result.get("depth_band_id", "")) == "deep", "deep station records the deep depth band")
			_check(str(last_result.get("danger_tier_id", "")) in ["dangerous", "severe"], "deep night scan records dangerous or severe risk")
		if index == 0:
			var records_before_cooldown: Array = prospecting.call("get_records")
			await _right_click_center()
			_check(not rejected_scans.is_empty(), "immediate repeated right click emits a production cooldown rejection")
			if not rejected_scans.is_empty():
				_check(str(rejected_scans[-1].get("reason", "")) == "cooldown", "repeated scan retains the exact cooldown reason")
			_check(prospecting.call("get_records") == records_before_cooldown, "cooldown failure cannot mutate exploration records")

	var journal_snapshot: Dictionary = journal.call("get_snapshot")
	_check(int(journal_snapshot.get("record_count", 0)) == 12, "twelve real right clicks create twelve stable records")
	_check(int(journal_snapshot.get("unique_chunk_count", 0)) == 12, "all exploration records belong to unique chunks")
	_check(int(journal_snapshot.get("depth_band_count", 0)) == 4, "real scans cover upper, middle, lower and deep geology")
	_check(int(journal_snapshot.get("rich_count", 0)) == 12, "all deterministic stations retain rich density evidence")
	_check(int(journal_snapshot.get("completed_milestone_count", 0)) == 8, "all eight production exploration milestones are completed")
	_check(completed_scans.size() == 12, "exactly twelve scan-completed events are emitted")
	_check(_all_milestones_complete(journal_snapshot), "every configured milestone is visibly complete in the journal snapshot")

	_fill_inventory(inventory)
	_check(_occupied_slot_count(inventory) == 36, "fixture fills all real player inventory slots before reward collection")
	var full_inventory: Dictionary = inventory.call("serialize")
	await _tap_key(KEY_J)
	for _frame in 4:
		await process_frame
	_check(int(game_ui.call("get_active_overlay")) == OverlayIds.EXPLORATION_JOURNAL, "real J input opens the production exploration journal")
	_check(str(hub.get("input_context").call("get_context")) == str(InputContextScript.CONTEXT_JOURNAL), "journal uses the production input context")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "journal isolates gameplay input and releases the mouse")
	var panel: Control = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and panel.visible, "production exploration journal panel is visible")
	if panel == null:
		await _finish(game, hub)
		return
	_check(str(panel.call("get_summary_text")).contains("里程碑 8 / 8"), "journal summary displays all eight completed milestones")
	for milestone_id: String in MILESTONE_IDS:
		_check(str(panel.call("get_reward_status", milestone_id)) == "claimable", "%s reward is visibly claimable" % milestone_id)

	var failed_milestone := MILESTONE_IDS[0]
	var failed_button: Button = panel.call("get_claim_button", failed_milestone) as Button
	_check(failed_button != null and not failed_button.disabled, "first completed milestone exposes a real claim button")
	if failed_button != null:
		await _ensure_visible(failed_button)
		await _click_control(failed_button)
	_check(not rejected_rewards.is_empty(), "full-inventory claim emits a production reward rejection")
	if not rejected_rewards.is_empty():
		_check(str(rejected_rewards[-1].get("reason", "")) == "inventory_full", "reward failure retains the exact inventory_full reason")
		_check(str(rejected_rewards[-1].get("milestone_id", "")) == failed_milestone, "reward failure retains the exact clicked milestone identity")
	_check(inventory.call("serialize") == full_inventory, "full-inventory reward failure cannot partially mutate any player slot")
	_check(not bool(rewards.call("is_claimed", failed_milestone)), "failed reward remains unclaimed")
	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(str(panel.call("get_reward_status", failed_milestone)) == "claimable", "failed reward remains visibly claimable")

	inventory.clear()
	for milestone_id: String in MILESTONE_IDS:
		panel = game_ui.call("get_exploration_journal_panel") as Control
		var button: Button = panel.call("get_claim_button", milestone_id) as Button
		_check(button != null and not button.disabled, "%s exposes a live claim button before collection" % milestone_id)
		if button == null:
			continue
		await _ensure_visible(button)
		await _click_control(button)
		_check(bool(rewards.call("is_claimed", milestone_id)), "%s reward is committed by the real UI button" % milestone_id)
	var reward_snapshot: Dictionary = rewards.call("get_snapshot")
	_check(int(reward_snapshot.get("claimed_count", 0)) == 8, "all eight milestone rewards are claimed exactly once")
	_check(int(reward_snapshot.get("claimable_count", 0)) == 0, "no completed reward remains pending after collection")
	_check(claimed_rewards.size() == 8, "eight successful reward claims emit exactly eight production events")
	_check(_reward_inventory_is_exact(inventory), "collected inventory matches the authoritative abyss reward table")
	var claimed_inventory: Dictionary = inventory.call("serialize")
	var claimed_state: Dictionary = rewards.call("serialize")
	var scan_event_count := completed_scans.size()
	var reward_event_count := claimed_rewards.size()

	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(str(panel.call("get_summary_text")).contains("奖励已领 8 / 待领 0"), "journal summary displays all rewards as claimed")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "exploration closed-loop viewport renders the completed journal")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "exploration evidence uses 1024x576 resolution")
		_save_image(image)
	await _tap_key(KEY_J)
	_check(int(game_ui.call("get_active_overlay")) == 0, "real J input closes the completed journal")
	_check(bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing journal restores production gameplay input")

	_check(bool(hub.call("save_current")), "exploration records and claimed rewards join the authoritative save")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check((loaded.get("exploration", {}).get("records", []) as Array).size() == 12, "world.json stores all twelve exploration records")
	_check((loaded.get("exploration_rewards", {}).get("claimed", []) as Array).size() == 8, "world.json stores all eight claimed reward identities")
	_check(loaded.get("inventory", {}) == claimed_inventory, "world.json stores the exact reward inventory")

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "completed exploration world performs a full production reload")
	player = game.get("player") as CharacterBody3D
	inventory = hub.get("inventory") as Node
	journal = hub.get("exploration_journal_service") as Node
	rewards = hub.get("exploration_reward_service") as Node
	game_ui = hub.get("game_ui") as Node
	_check(inventory.call("serialize") == claimed_inventory, "reload restores the exact claimed reward inventory")
	_check(journal.call("get_snapshot").get("record_count", 0) == 12, "reload restores all twelve exploration records")
	_check(rewards.call("serialize") == claimed_state, "reload restores the exact claimed reward state")
	_check(int(rewards.call("get_snapshot").get("claimed_count", 0)) == 8, "reload retains all eight claims without duplication")
	_check(completed_scans.size() == scan_event_count and claimed_rewards.size() == reward_event_count, "reload does not replay scan or reward events")
	await _tap_key(KEY_J)
	for _frame in 4:
		await process_frame
	panel = game_ui.call("get_exploration_journal_panel") as Control
	_check(panel != null and panel.visible, "completed journal reopens after full world reload")
	if panel != null:
		for milestone_id: String in MILESTONE_IDS:
			var claimed_button: Button = panel.call("get_claim_button", milestone_id) as Button
			_check(str(panel.call("get_reward_status", milestone_id)) == "claimed", "%s remains visibly claimed after reload" % milestone_id)
			_check(claimed_button != null and claimed_button.disabled, "%s claim button remains disabled after reload" % milestone_id)
	_check(bool(player.get("input_enabled")) == false and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "reloaded journal still owns the UI input context")
	await _tap_key(KEY_J)
	_check(bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "final journal close restores normal gameplay")
	await _finish(game, hub)


func _station_centers(world: Node, player: Node3D) -> Array[Vector3i]:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var result: Array[Vector3i] = []
	var depths: Array[int] = [50, 28, 15, 8]
	for index in 12:
		result.append(Vector3i(origin.x + 48 + index * 32, depths[index % depths.size()], origin.z))
	return result


func _prepare_scan_station(world: Node, player: CharacterBody3D, center: Vector3i) -> void:
	var chunk: Vector2i = world.call("block_to_chunk", center)
	world.call("force_load_chunk", chunk)
	for x_offset in range(-2, 3):
		for z_offset in range(-2, 3):
			world.call("set_block", center + Vector3i(x_offset, -1, z_offset), "stone")
			for y_offset in range(0, 4):
				world.call("set_block", center + Vector3i(x_offset, y_offset, z_offset), "air")
	_seed_rich_samples(world, center)
	player.global_position = Vector3(center) + Vector3(0.5, 0.05, 0.5)
	player.call("reset_motion")
	player.velocity = Vector3.ZERO
	world.call("set_focus", player)
	for _frame in 5:
		await physics_frame
		await process_frame


func _seed_rich_samples(world: Node, center: Vector3i) -> void:
	var written := 0
	var minimum_y := maxi(1, center.y - 18)
	var maximum_y := mini(63, center.y + 18)
	for x in range(center.x - 5, center.x + 6, 2):
		for z in range(center.z - 5, center.z + 6, 2):
			for y in range(minimum_y, maximum_y + 1, 2):
				if written >= 144:
					return
				world.call("set_block", Vector3i(x, y, z), "diamond_ore")
				written += 1


func _all_milestones_complete(snapshot: Dictionary) -> bool:
	var milestones: Array = snapshot.get("milestones", [])
	if milestones.size() != MILESTONE_IDS.size():
		return false
	for raw_milestone: Variant in milestones:
		if raw_milestone is not Dictionary or not bool(raw_milestone.get("completed", false)):
			return false
	return true


func _fill_inventory(inventory: Node) -> void:
	inventory.clear()
	for index in 36:
		inventory.call(
			"add_item",
			"wooden_pickaxe",
			1,
			{"fixture_slot":"exploration_%02d" % index},
		)


func _occupied_slot_count(inventory: Node) -> int:
	var count := 0
	for index in int(inventory.get("slot_count")):
		if not (inventory.call("get_slot", index) as Dictionary).is_empty():
			count += 1
	return count


func _reward_inventory_is_exact(inventory: Node) -> bool:
	var expected := {
		"torch":28,
		"cooked_chicken":6,
		"iron_ingot":4,
		"coal":8,
		"bread":6,
		"diamond":1,
		"gold_ingot":3,
		"iron_pickaxe":1,
		"abyss_cinder":1,
	}
	for item_id: String in expected.keys():
		if inventory.count_item(item_id) != int(expected[item_id]):
			return false
	var total := 0
	for value: Variant in expected.values():
		total += int(value)
	return _total_item_count(inventory) == total


func _total_item_count(inventory: Node) -> int:
	var total := 0
	for index in int(inventory.get("slot_count")):
		total += int((inventory.call("get_slot", index) as Dictionary).get("count", 0))
	return total


func _ensure_visible(control: Control) -> void:
	var current: Node = control.get_parent()
	while current != null and current is not ScrollContainer:
		current = current.get_parent()
	if current is ScrollContainer:
		(current as ScrollContainer).ensure_control_visible(control)
	for _frame in 3:
		await process_frame


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 300:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if (
			world != null and player != null and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(player.get("input_enabled"))
		):
			return true
	return false


func _right_click_center() -> void:
	var center := Vector2(root.size) * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.global_position = center
		event.button_index = MOUSE_BUTTON_RIGHT
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _tap_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _click_control(control: Control) -> void:
	if control == null:
		return
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = target
		event.global_position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "exploration closed-loop screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.get("save_service").delete_world(_world_id)
		if hub.get("audio_service") != null and hub.get("audio_service").has_method("shutdown"):
			hub.get("audio_service").shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA EXPLORATION CLOSED LOOP DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION CLOSED LOOP DESKTOP FAILURE: %s" % failure)
		print("QA EXPLORATION CLOSED LOOP DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
