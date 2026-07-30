extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://encounter-reward-granted.png"
const WORLD_READY_TIMEOUT_MS := 120000
const ACTION_TIMEOUT_MS := 30000
const CLEANUP_FRAMES := 64

var checks := 0
var failures: Array[String] = []
var _granted_path := ""
var _pending_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_granted_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_pending_path = _granted_path.get_base_dir().path_join("encounter-reward-pending.png")
	_report_path = _granted_path.get_base_dir().path_join("encounter-reward-report.json")
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production reward journey exposes the service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Reward-Economy-Desktop-%d" % Time.get_ticks_msec(),
		"abyss_world",
		56195519
	)
	_check(not state.is_empty(), "reward journey creates a real abyss world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	var ready := await _wait_until(
		func() -> bool:
			return (
				game.world != null
				and bool(game.world.get("is_started"))
				and game.player != null
				and bool(game.player.get("input_enabled"))
			),
		WORLD_READY_TIMEOUT_MS
	)
	_check(ready, "reward world and player become ready inside the bounded deadline")
	if not ready:
		await _finish(game, hub)
		return

	var director: Node = hub.get_node_or_null("HostileEncounterDirector")
	var reward_service: Node = hub.get_node_or_null("EncounterRewardService")
	var encounter_overlay: Node = hub.game_ui.get_node_or_null("HostileEncounterOverlay")
	var reward_overlay := await _wait_for_node(hub.game_ui, "EncounterRewardOverlay", ACTION_TIMEOUT_MS)
	_check(director != null, "production composition mounts one encounter director")
	_check(reward_service != null, "production composition mounts one encounter reward service")
	_check(encounter_overlay != null, "production UI retains the encounter squad HUD")
	_check(reward_overlay != null, "production UI mounts the reward economy HUD")
	if director == null or reward_service == null or reward_overlay == null:
		await _finish(game, hub)
		return
	var services_ready := await _wait_until(
		func() -> bool: return bool(reward_service.call("get_snapshot").get("services_ready", false)),
		ACTION_TIMEOUT_MS
	)
	_check(services_ready, "reward service auto-binds director inventory ranged combat and spawner")

	var player: Node3D = game.player
	var world: Node = game.world
	hub.day_night.running = false
	hub.day_night.set_time(22.0)
	hub.creature_spawner.clear_creatures()
	hub.creature_spawner.set_process(false)
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := 10
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	await process_frame
	var bound := await _wait_until(
		func() -> bool:
			return (
				str(reward_service.call("get_snapshot").get("world_id", "")) == _created_world_id
				and bool(director.call("get_snapshot").get("active", false))
			),
		ACTION_TIMEOUT_MS
	)
	_check(bound, "reward economy and encounter director bind to the same production world")
	director.call("clear", "reward_desktop_setup")
	reward_service.call("clear", "reward_desktop_setup")

	hub.inventory.clear()
	hub.equipment_service.clear()
	hub.inventory.add_item("star_pistol", 1, {
		"durability":420,
		"magazine_rounds":8,
		"custom_name":"补给验收星火手枪",
	})
	var pistol_index := _find_item_slot(hub.inventory, "star_pistol")
	_check(
		pistol_index >= 0
		and hub.equipment_service.equip_from_inventory(hub.inventory, pistol_index),
		"real inventory equips the reward-economy pistol"
	)

	var first_started: Dictionary = director.call("force_decision_for_test", "abyss_assault", 0.0)
	_check(bool(first_started.get("success", false)), "production director starts a reward-bearing abyss assault")
	var first_members := _collect_encounter_members(hub.creature_spawner)
	_check(first_members.size() == 4, "first reward encounter owns the complete four-member squad")
	_freeze_members(first_members, player_block, floor_y)
	var ledger_ready := await _wait_until(
		func() -> bool: return int(reward_service.call("get_snapshot").get("active_ledger_count", 0)) == 1,
		ACTION_TIMEOUT_MS
	)
	_check(ledger_ready, "reward service opens one ledger for the production squad")
	var first_defeated := await _defeat_members_with_pistol(hub, player, first_members, player_block, floor_y)
	_check(first_defeated == 4, "four real mouse shots defeat the first complete squad")
	var first_granted := await _wait_until(
		func() -> bool: return int(reward_service.call("get_snapshot").get("reward_grant_count", 0)) == 1,
		ACTION_TIMEOUT_MS
	)
	_check(first_granted, "last production member grants the encounter reward exactly once")
	var first_result: Dictionary = reward_service.call("get_snapshot").get("last_result", {})
	_check(int(first_result.get("shot_count", -1)) == 4, "last-kill reward waits until the fourth shot is recorded")
	_check(int(first_result.get("rewards", {}).get("light_round", 0)) == 6, "efficient assault grants six light rounds")
	_check(int(first_result.get("net_ammo", {}).get("light_round", 99)) == 2, "four spent rounds and six rewarded rounds produce net plus two")
	_check(hub.inventory.count_item("gunpowder") == 2, "first assault atomically grants two gunpowder")
	_check(hub.inventory.count_item("shotgun_shell") == 1, "first assault atomically grants one shotgun shell")
	var reward_hud_ready := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = reward_overlay.call("get_snapshot")
			return (
				bool(snapshot.get("visible", false))
				and str(snapshot.get("title", "")).contains("深渊突袭补给")
				and str(snapshot.get("detail", "")).contains("消耗 4 发")
			),
		ACTION_TIMEOUT_MS
	)
	_check(reward_hud_ready, "reward HUD shows the granted supply exact shot cost and net economy")
	await RenderingServer.frame_post_draw
	_save_viewport(_granted_path, "granted encounter reward screenshot")

	var first_completed := await _wait_until(
		func() -> bool: return int(director.call("get_snapshot").get("active_encounter_count", -1)) == 0,
		ACTION_TIMEOUT_MS
	)
	_check(first_completed, "first rewarded encounter completes and releases all tracked members")

	_fill_reward_inventory_to_capacity(hub.inventory)
	_check(hub.inventory.get_add_capacity("light_round") == 0, "real inventory has no remaining light-round capacity")
	_check(hub.inventory.get_add_capacity("gunpowder") == 0, "real inventory has no remaining gunpowder capacity")
	_check(_occupied_slots(hub.inventory) == int(hub.inventory.get("slot_count")), "all real inventory slots are occupied before the pending test")
	director.call("clear", "pending_reward_setup")
	var second_started: Dictionary = director.call("force_decision_for_test", "abyss_skirmish", 0.0)
	_check(bool(second_started.get("success", false)), "production director starts a second reward-bearing skirmish")
	var second_members := _collect_encounter_members(hub.creature_spawner)
	_check(second_members.size() == 3, "second reward encounter owns three members")
	_freeze_members(second_members, player_block, floor_y)
	var second_defeated := await _defeat_members_with_pistol(hub, player, second_members, player_block, floor_y)
	_check(second_defeated == 3, "three additional real shots defeat the pending-reward squad")
	var pending_ready := await _wait_until(
		func() -> bool: return int(reward_service.call("get_snapshot").get("pending_reward_count", 0)) == 1,
		ACTION_TIMEOUT_MS
	)
	_check(pending_ready, "full production inventory keeps the complete reward in one pending record")
	_check(hub.inventory.count_item("light_round") == 64, "pending transaction does not partially add light rounds")
	_check(hub.inventory.count_item("gunpowder") == 64, "pending transaction does not partially add gunpowder")
	var pending_hud_ready := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = reward_overlay.call("get_snapshot")
			return bool(snapshot.get("visible", false)) and str(snapshot.get("title", "")).contains("等待领取"),
		ACTION_TIMEOUT_MS
	)
	_check(pending_hud_ready, "reward HUD explains the full-inventory pending state")
	await RenderingServer.frame_post_draw
	_save_viewport(_pending_path, "pending encounter reward screenshot")

	var freed_slots := _free_weapon_slots(hub.inventory, 2)
	_check(freed_slots == 2, "desktop journey frees exactly two inventory slots for the atomic retry")
	var retry_granted := await _wait_until(
		func() -> bool: return int(reward_service.call("get_snapshot").get("reward_grant_count", 0)) == 2,
		ACTION_TIMEOUT_MS
	)
	_check(retry_granted, "inventory change automatically retries and grants the pending reward")
	_check(int(reward_service.call("get_snapshot").get("pending_reward_count", -1)) == 0, "successful production retry clears the pending record")
	_check(hub.inventory.count_item("light_round") == 69, "pending skirmish atomically adds five light rounds")
	_check(hub.inventory.count_item("gunpowder") == 65, "pending skirmish atomically adds one gunpowder")

	var grants_before_abandon := int(reward_service.call("get_snapshot").get("reward_grant_count", 0))
	director.call("clear", "abandoned_reward_setup")
	var abandoned_started: Dictionary = director.call("force_decision_for_test", "abyss_skirmish", 0.0)
	_check(bool(abandoned_started.get("success", false)), "production director starts an abandonment control squad")
	hub.creature_spawner.clear_creatures()
	var abandoned_completed := await _wait_until(
		func() -> bool: return int(director.call("get_snapshot").get("active_encounter_count", -1)) == 0,
		ACTION_TIMEOUT_MS
	)
	_check(abandoned_completed, "unloaded control squad is removed inside the bounded deadline")
	_check(int(reward_service.call("get_snapshot").get("reward_grant_count", 0)) == grants_before_abandon, "member unload cannot masquerade as a rewarded squad defeat")
	_check(int(reward_service.call("get_snapshot").get("abandoned_encounter_count", 0)) >= 1, "reward diagnostics record the unrewarded abandoned squad")

	_check(bool(hub.save_current()), "reward economy coexists with the authoritative save")
	hub.return_to_menu()
	var returned := await _wait_until(
		func() -> bool: return str(hub.get("current_world_id")).is_empty(),
		ACTION_TIMEOUT_MS
	)
	_check(returned, "return to menu clears reward ledgers pending records and claim history")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(not loaded.is_empty(), "reward economy world remains loadable")
	_check(
		not loaded.has("encounter_rewards")
		and not loaded.has("encounter_economy")
		and not loaded.has("pending_encounter_rewards"),
		"reward ledgers claims and pending records do not enter world.json"
	)
	game.begin_world_state(loaded)
	var reloaded := await _wait_until(
		func() -> bool:
			return str(hub.get("current_world_id")) == _created_world_id and bool(game.player.get("input_enabled")),
		WORLD_READY_TIMEOUT_MS
	)
	_check(reloaded, "reward economy world reloads through production composition")
	var reload_reward: Dictionary = reward_service.call("get_snapshot")
	_check(int(reload_reward.get("active_ledger_count", -1)) == 0, "reloaded world begins with no transient reward ledger")
	_check(int(reload_reward.get("pending_reward_count", -1)) == 0, "reloaded world begins with no transient pending reward")
	_check(int(reload_reward.get("claim_history_count", -1)) == 0, "reloaded world begins with an empty runtime claim history")

	_report = {
		"checks":checks,
		"failures":failures.duplicate(),
		"viewport":[root.size.x, root.size.y],
		"world_id":_created_world_id,
		"first_defeated":first_defeated,
		"second_defeated":second_defeated,
		"first_result":first_result,
		"reward_snapshot_before_save":reward_service.call("get_snapshot"),
		"reload_reward_snapshot":reload_reward,
		"granted_screenshot":_granted_path,
		"pending_screenshot":_pending_path,
	}
	_write_report()
	await _finish(game, hub)


func _collect_encounter_members(spawner: Node) -> Array[Node3D]:
	var members: Array[Node3D] = []
	for child: Node in spawner.get_children():
		if child is Node3D and child.is_in_group("encounter_hostile"):
			members.append(child as Node3D)
	members.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.get_instance_id() < b.get_instance_id())
	return members


func _freeze_members(
	members: Array[Node3D],
	player_block: Vector3i,
	floor_y: int
) -> void:
	for index in members.size():
		var member := members[index]
		member.set_physics_process(false)
		member.call("clear_combat_motion")
		member.global_position = Vector3(
			player_block.x + 6.0 + float(index) * 1.8,
			floor_y + 1.05,
			player_block.z - 8.0
		)


func _defeat_members_with_pistol(
	hub: Node,
	player: Node3D,
	members: Array[Node3D],
	player_block: Vector3i,
	floor_y: int
) -> int:
	var defeated_count := 0
	for member: Node3D in members:
		if member == null or not is_instance_valid(member):
			continue
		var target_id := int(member.get_instance_id())
		var target_ref: WeakRef = weakref(member)
		member.set("health", 6.0)
		member.global_position = Vector3(
			player_block.x + 0.5,
			floor_y + 1.05,
			player_block.z - 4.5
		)
		await _aim_at(player, member.global_position + Vector3(0.0, 0.8, 0.0))
		_push_mouse_button(true)
		await process_frame
		_push_mouse_button(false)
		var defeated := await _wait_until(
			func() -> bool:
				var feedback: Node = hub.game_ui.call("get_combat_feedback_overlay")
				var result: Dictionary = feedback.call("get_snapshot").get("last_result", {})
				var target_result := _find_target_result(result, target_id)
				return bool(target_result.get("defeated", false)) and target_ref.get_ref() == null,
			ACTION_TIMEOUT_MS
		)
		_check(defeated, "real mouse firearm defeats one reward encounter member")
		if defeated:
			defeated_count += 1
		var cooled := await _wait_until(
			func() -> bool: return bool(hub.ranged_combat_service.call("get_snapshot").get("cooldown_ready", false)),
			ACTION_TIMEOUT_MS
		)
		_check(cooled, "pistol cooldown settles before the next reward target")
	return defeated_count


func _fill_reward_inventory_to_capacity(inventory: Node) -> void:
	inventory.add_item("light_round", maxi(0, 64 - inventory.count_item("light_round")))
	inventory.add_item("gunpowder", maxi(0, 64 - inventory.count_item("gunpowder")))
	inventory.add_item("shotgun_shell", maxi(0, 32 - inventory.count_item("shotgun_shell")))
	while inventory.add_item("star_pistol", 1) == 0:
		pass


func _free_weapon_slots(inventory: Node, count: int) -> int:
	var freed := 0
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) != "star_pistol":
			continue
		inventory.call("remove_from_slot", index, 1)
		freed += 1
		if freed >= count:
			break
	return freed


func _occupied_slots(inventory: Node) -> int:
	var count := 0
	for index in int(inventory.get("slot_count")):
		if not inventory.call("get_slot", index).is_empty():
			count += 1
	return count


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-8, 12):
		for z_offset in range(-12, 6):
			world.call("set_block", Vector3i(center_x + x_offset, floor_y, center_z + z_offset), "stone")
			for y in range(floor_y + 1, floor_y + 7):
				world.call("set_block", Vector3i(center_x + x_offset, y, center_z + z_offset), "air")


func _aim_at(player: Node3D, target_position: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	if camera != null:
		camera.look_at(target_position, Vector3.UP)
	await physics_frame
	await process_frame


func _push_mouse_button(pressed: bool) -> void:
	var center := Vector2(root.size) * 0.5
	var event := InputEventMouseButton.new()
	event.position = center
	event.global_position = center
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)


func _find_target_result(batch: Dictionary, target_id: int) -> Dictionary:
	var raw_results: Variant = batch.get("target_results", [])
	if raw_results is not Array:
		return {}
	for raw_result: Variant in raw_results:
		if raw_result is Dictionary and int(raw_result.get("target_id", 0)) == target_id:
			return raw_result.duplicate(true)
	return {}


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) == item_id:
			return index
	return -1


func _wait_for_node(parent: Node, node_name: String, timeout_ms: int) -> Node:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var node := parent.get_node_or_null(node_name)
		if node != null:
			return node
		await process_frame
	return parent.get_node_or_null(node_name)


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(1, timeout_ms)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _save_viewport(path: String, description: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s renders a non-empty viewport" % description)
	if image != null and not image.is_empty():
		var error := image.save_png(path)
		_check(error == OK and FileAccess.file_exists(path), "%s is saved" % description)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "encounter reward JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "encounter reward JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in 24:
				await process_frame
		if not _created_world_id.is_empty() and hub.get("save_service") != null:
			if bool(hub.save_service.call("world_exists", _created_world_id)):
				hub.save_service.call("delete_world", _created_world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA ENCOUNTER REWARD DESKTOP PASS | checks=%d | granted=%s | pending=%s | report=%s" % [checks, _granted_path, _pending_path, _report_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA ENCOUNTER REWARD DESKTOP FAILURE: %s" % failure)
	print("QA ENCOUNTER REWARD DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
