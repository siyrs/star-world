extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://hostile-encounter-active.png"
const WORLD_READY_TIMEOUT_MS := 120000
const ACTION_TIMEOUT_MS := 25000
const CLEANUP_FRAMES := 56

var checks := 0
var failures: Array[String] = []
var _active_path := ""
var _complete_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_active_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_complete_path = _active_path.get_base_dir().path_join("hostile-encounter-complete.png")
	_report_path = _active_path.get_base_dir().path_join("hostile-encounter-report.json")
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Encounter-Desktop-%d" % Time.get_ticks_msec(),
		"abyss_world",
		55195519
	)
	_check(not state.is_empty(), "desktop encounter journey creates a real abyss world")
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
	_check(ready, "abyss world and player become ready inside the bounded deadline")
	if not ready:
		await _finish(game, hub)
		return
	var director: Node = hub.get_node_or_null("HostileEncounterDirector")
	var overlay: Node = hub.game_ui.get_node_or_null("HostileEncounterOverlay")
	_check(director != null, "production service composition mounts one hostile encounter director")
	_check(overlay != null, "production UI mounts the encounter status overlay")
	if director == null or overlay == null:
		await _finish(game, hub)
		return
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
			var snapshot: Dictionary = director.call("get_snapshot")
			return bool(snapshot.get("active", false)) and str(snapshot.get("map_id", "")) == "abyss_world",
		ACTION_TIMEOUT_MS
	)
	_check(bound, "production director auto-binds to the active abyss world")
	director.call("clear", "desktop_setup")

	hub.inventory.clear()
	hub.equipment_service.clear()
	hub.inventory.add_item("star_pistol", 1, {
		"durability": 420,
		"magazine_rounds": 8,
		"custom_name": "遭遇验收星火手枪",
	})
	var pistol_index := _find_item_slot(hub.inventory, "star_pistol")
	_check(pistol_index >= 0 and hub.equipment_service.equip_from_inventory(hub.inventory, pistol_index), "real inventory equips the encounter pistol")

	var started: Dictionary = director.call("force_decision_for_test", "abyss_assault", 0.0)
	_check(bool(started.get("success", false)), "production director starts the abyss assault through the real spawner")
	var active_snapshot: Dictionary = director.call("get_snapshot")
	_check(int(active_snapshot.get("active_encounter_count", 0)) == 1, "production director tracks one active squad")
	_check(int(active_snapshot.get("tracked_member_count", 0)) == 4, "production director tracks four mixed-role members")
	var members: Array[Node3D] = []
	var role_counts: Dictionary = {}
	var species_counts: Dictionary = {}
	for child: Node in hub.creature_spawner.get_children():
		if child is not Node3D or not child.is_in_group("encounter_hostile"):
			continue
		var member := child as Node3D
		member.set_physics_process(false)
		member.call("clear_combat_motion")
		member.global_position = Vector3(
			player_block.x + 6.0 + float(members.size()) * 1.8,
			floor_y + 1.05,
			player_block.z - 8.0
		)
		members.append(member)
		var role := str(member.get_meta("encounter_role", ""))
		var species_id := str(member.get("species_id"))
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		species_counts[species_id] = int(species_counts.get(species_id, 0)) + 1
		_check(member.get("target") == player, "encounter member receives the shared local player target")
	_check(members.size() == 4, "real spawner creates the complete four-member encounter")
	_check(int(role_counts.get("vanguard", 0)) == 2 and int(role_counts.get("support", 0)) == 1 and int(role_counts.get("finisher", 0)) == 1, "desktop squad preserves vanguard support and finisher roles")
	_check(int(species_counts.get("zombie", 0)) == 2 and int(species_counts.get("abyss_marksman", 0)) == 1 and int(species_counts.get("abyss_brute", 0)) == 1, "desktop squad preserves the mixed-species composition")
	var hud_ready := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = overlay.call("get_snapshot")
			return bool(snapshot.get("visible", false)) and str(snapshot.get("title", "")).contains("深渊突袭队"),
		ACTION_TIMEOUT_MS
	)
	_check(hud_ready, "encounter HUD renders the active mixed-role squad")
	var hud_snapshot: Dictionary = overlay.call("get_snapshot")
	_check(str(hud_snapshot.get("detail", "")).contains("前卫2") and str(hud_snapshot.get("detail", "")).contains("远程1") and str(hud_snapshot.get("detail", "")).contains("重装1"), "encounter HUD exposes the exact role composition")
	await RenderingServer.frame_post_draw
	_save_viewport(_active_path, "active hostile encounter screenshot")

	var defeated_members := 0
	var defeated_ids: Array[int] = []
	for member: Node3D in members:
		if member == null or not is_instance_valid(member):
			continue
		var target_id := int(member.get_instance_id())
		var target_ref: WeakRef = weakref(member)
		member.set("health", 6.0)
		member.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 4.5)
		await _aim_at(player, member.global_position + Vector3(0.0, 0.8, 0.0))
		_push_mouse_button(true)
		await process_frame
		_push_mouse_button(false)
		var defeated := await _wait_until(
			func() -> bool:
				var result: Dictionary = hub.game_ui.call("get_combat_feedback_overlay").call("get_snapshot").get("last_result", {})
				var target_result := _find_target_result(result, target_id)
				return bool(target_result.get("defeated", false)) and target_ref.get_ref() == null,
			ACTION_TIMEOUT_MS
		)
		_check(defeated, "real mouse firearm defeats one encounter member")
		if defeated:
			defeated_members += 1
			defeated_ids.append(target_id)
		var cooled := await _wait_until(
			func() -> bool: return bool(hub.ranged_combat_service.call("get_snapshot").get("cooldown_ready", false)),
			ACTION_TIMEOUT_MS
		)
		_check(cooled, "pistol cooldown settles before the next encounter target")
	var completed := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = director.call("get_snapshot")
			return int(snapshot.get("active_encounter_count", -1)) == 0 and int(snapshot.get("tracked_member_count", -1)) == 0,
		ACTION_TIMEOUT_MS
	)
	_check(defeated_members == 4, "real firearm input defeats the complete four-member squad")
	_check(completed, "completed encounter leaves no tracked runtime members")
	var completed_snapshot: Dictionary = director.call("get_snapshot")
	_check(int(completed_snapshot.get("completion_count", 0)) >= 1, "director records the completed production encounter")

	director.call("clear", "desktop_low_health")
	var survival: Node = player.get("survival") as Node
	var maximum_health := float(survival.get("max_health")) if survival != null else 20.0
	if survival != null:
		survival.set("health", maximum_health * 0.25)
	var suppressed: Dictionary = director.call("force_decision_for_test", "", 0.0)
	_check(str(suppressed.get("reason", "")) == "low_health", "low-health production player suppresses the next squad")
	var suppression_visible := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = overlay.call("get_snapshot")
			return bool(snapshot.get("visible", false)) and str(snapshot.get("title", "")).contains("暂缓"),
		ACTION_TIMEOUT_MS
	)
	_check(suppression_visible, "encounter HUD explains low-health scheduling relief")
	await RenderingServer.frame_post_draw
	_save_viewport(_complete_path, "completed hostile encounter screenshot")
	if survival != null:
		survival.set("health", maximum_health)

	_check(bool(hub.save_current()), "encounter gameplay coexists with the authoritative save")
	hub.return_to_menu()
	var returned := await _wait_until(
		func() -> bool: return str(hub.get("current_world_id")).is_empty(),
		ACTION_TIMEOUT_MS
	)
	_check(returned, "return to menu clears the encounter session")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(not loaded.is_empty(), "saved encounter world remains loadable")
	_check(not loaded.has("hostile_encounters") and not loaded.has("encounter_director"), "hostile encounter state does not enter world.json")
	game.begin_world_state(loaded)
	var reloaded := await _wait_until(
		func() -> bool:
			return str(hub.get("current_world_id")) == _created_world_id and bool(game.player.get("input_enabled")),
		WORLD_READY_TIMEOUT_MS
	)
	_check(reloaded, "encounter world reloads through production composition")
	var reload_snapshot: Dictionary = director.call("get_snapshot")
	_check(int(reload_snapshot.get("active_encounter_count", -1)) == 0 and int(reload_snapshot.get("tracked_member_count", -1)) == 0, "reloaded world begins with no transient encounter squad")

	_report = {
		"checks": checks,
		"failures": failures.duplicate(),
		"viewport": [root.size.x, root.size.y],
		"world_id": _created_world_id,
		"defeated_members": defeated_members,
		"defeated_ids": defeated_ids,
		"role_counts": role_counts,
		"species_counts": species_counts,
		"active_snapshot": active_snapshot,
		"completed_snapshot": completed_snapshot,
		"reload_snapshot": reload_snapshot,
		"active_screenshot": _active_path,
		"complete_screenshot": _complete_path,
	}
	_write_report()
	await _finish(game, hub)


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
	_check(file != null, "hostile encounter JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "hostile encounter JSON report is saved")


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
		print("QA HOSTILE ENCOUNTER DESKTOP PASS | checks=%d | active=%s | complete=%s | report=%s" % [checks, _active_path, _complete_path, _report_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE ENCOUNTER DESKTOP FAILURE: %s" % failure)
	print("QA HOSTILE ENCOUNTER DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
