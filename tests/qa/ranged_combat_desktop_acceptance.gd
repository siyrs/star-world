extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ranged-combat-charge.png"
const WORLD_READY_TIMEOUT_MS := 120000
const ACTION_TIMEOUT_MS := 15000
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _charge_path := ""
var _hit_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_charge_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_hit_path = _charge_path.get_base_dir().path_join("ranged-combat-hit.png")
	_report_path = _charge_path.get_base_dir().path_join("ranged-combat-report.json")
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 3:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Ranged-Combat-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		82726354
	)
	_check(not state.is_empty(), "desktop ranged journey creates a real world")
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
	_check(ready, "world and player become ready inside the bounded deadline")
	if not ready:
		await _finish(game, hub)
		return
	var ranged: Node = hub.get("ranged_combat_service") as Node
	var overlay: Node = hub.game_ui.call("get_combat_feedback_overlay")
	_check(ranged != null, "production character domain mounts RangedCombatService")
	_check(overlay != null, "production UI mounts shared combat feedback")
	if ranged == null or overlay == null:
		await _finish(game, hub)
		return

	var player: Node3D = game.player
	var world: Node = game.world
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("bow", 1, {"durability": 384, "custom_name": "桌面验收猎弓"})
	hub.inventory.add_item("arrow", 3)
	var bow_index := _find_item_slot(hub.inventory, "bow")
	_check(bow_index >= 0 and hub.equipment_service.equip_from_inventory(hub.inventory, bow_index), "real inventory equips the bow")
	_check(str(hub.equipment_service.get_slot("main_hand").get("item_id", "")) == "bow", "main hand owns the ranged weapon")
	var arrows_before: int = int(hub.inventory.count_item("arrow"))
	var durability_before := _main_hand_durability(hub)

	var target_position := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 5.0)
	var target_variant: Variant = hub.creature_spawner.call("spawn_creature", "cow", target_position)
	_check(target_variant is Node3D, "real creature spawner creates a projectile target")
	if target_variant is not Node3D:
		await _finish(game, hub)
		return
	var target: Node3D = target_variant
	target.set("move_speed", 0.0)
	target.set("_decision_timer", 999.0)
	target.set("_wander_direction", Vector3.ZERO)
	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	var health_before := float(target.get("health"))

	_push_mouse_button(true)
	var mouse_charging := await _wait_until(
		func() -> bool: return bool(ranged.call("get_snapshot").get("charging", false)),
		ACTION_TIMEOUT_MS
	)
	_check(mouse_charging, "real left-mouse press starts bow charging")
	var charge_visible := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = overlay.call("get_snapshot")
			return bool(snapshot.get("ranged_visible", false)) and float(snapshot.get("ranged", {}).get("charge_ratio", 0.0)) >= 0.6,
		ACTION_TIMEOUT_MS
	)
	_check(charge_visible, "charge HUD exposes progress and ammunition")
	await RenderingServer.frame_post_draw
	_save_viewport(_charge_path, "ranged charge screenshot")
	_push_mouse_button(false)
	var mouse_hit := await _wait_until(
		func() -> bool:
			var result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
			return str(result.get("attack_kind", "")) == "ranged" and str(result.get("status", "")) == "hit",
		ACTION_TIMEOUT_MS
	)
	_check(mouse_hit, "mouse release fires a real projectile and reaches CombatService")
	var first_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	var first_projectile_id := int(first_result.get("projectile_id", 0))
	var health_after_mouse := float(target.get("health"))
	_check(health_after_mouse < health_before, "mouse projectile changes target health exactly once")
	_check(hub.inventory.count_item("arrow") == arrows_before - 1, "mouse shot consumes exactly one arrow")
	_check(_main_hand_durability(hub) == durability_before - 1, "mouse shot consumes exactly one durability")
	_check(int(ranged.call("get_snapshot").get("projectiles", {}).get("active_count", -1)) == 0, "hit projectile is removed from the bounded runtime")
	await RenderingServer.frame_post_draw
	_save_viewport(_hit_path, "ranged hit screenshot")

	var cooldown_ready := await _wait_until(
		func() -> bool: return bool(ranged.call("get_snapshot").get("cooldown_ready", false)),
		ACTION_TIMEOUT_MS
	)
	_check(cooldown_ready, "ranged cooldown returns to ready")
	if target != null and is_instance_valid(target):
		if target.has_method("clear_combat_motion"):
			target.call("clear_combat_motion")
		target.global_position = target_position
		target.set("move_speed", 0.0)
	await _aim_at(player, target_position + Vector3(0.0, 0.65, 0.0))
	var controller_before: Dictionary = player.call("get_controller_gameplay_snapshot")
	_push_trigger_axis(1.0)
	var controller_charging := await _wait_until(
		func() -> bool: return bool(ranged.call("get_snapshot").get("charging", false)),
		ACTION_TIMEOUT_MS
	)
	_check(controller_charging, "real controller trigger starts the same charge path")
	var controller_full := await _wait_until(
		func() -> bool: return float(ranged.call("get_snapshot").get("charge_ratio", 0.0)) >= 0.95,
		ACTION_TIMEOUT_MS
	)
	_check(controller_full, "controller trigger can reach a full draw")
	_push_trigger_axis(0.0)
	var controller_hit := await _wait_until(
		func() -> bool:
			var result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
			return (
				str(result.get("attack_kind", "")) == "ranged"
				and str(result.get("status", "")) == "hit"
				and int(result.get("projectile_id", 0)) != first_projectile_id
			),
		ACTION_TIMEOUT_MS
	)
	_check(controller_hit, "controller release fires a real projectile and reaches CombatService")
	var controller_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	var controller_after: Dictionary = player.call("get_controller_gameplay_snapshot")
	_check(int(controller_after.get("primary_press_count", 0)) == int(controller_before.get("primary_press_count", 0)) + 1, "controller press counter records the physical trigger")
	_check(int(controller_after.get("primary_release_count", 0)) == int(controller_before.get("primary_release_count", 0)) + 1, "controller release counter records the physical trigger")
	_check(hub.inventory.count_item("arrow") == arrows_before - 2, "mouse and controller consume two arrows total")
	_check(_main_hand_durability(hub) == durability_before - 2, "mouse and controller consume two durability total")
	_check(bool(controller_result.get("accepted", false)), "controller projectile is accepted by the authoritative combat path")

	var arrows_after: int = int(hub.inventory.count_item("arrow"))
	var durability_after := _main_hand_durability(hub)
	_check(bool(hub.save_current()), "ranged inventory and equipment coexist with the authoritative save")
	hub.return_to_menu()
	var returned := await _wait_until(
		func() -> bool: return str(hub.get("current_world_id")).is_empty(),
		ACTION_TIMEOUT_MS
	)
	_check(returned, "final save releases the first ranged session")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(not loaded.is_empty(), "saved ranged world remains loadable")
	game.begin_world_state(loaded)
	var reloaded := await _wait_until(
		func() -> bool:
			return str(hub.get("current_world_id")) == _created_world_id and bool(game.player.get("input_enabled")),
		WORLD_READY_TIMEOUT_MS
	)
	_check(reloaded, "ranged world reloads through the production composition")
	_check(hub.inventory.count_item("arrow") == arrows_after, "arrow count survives save and reload")
	_check(_main_hand_durability(hub) == durability_after, "bow durability survives save and reload")
	_check(int(ranged.call("get_snapshot").get("projectiles", {}).get("active_count", -1)) == 0, "transient projectiles do not enter world.json")

	_report = {
		"checks": checks,
		"failures": failures.duplicate(),
		"viewport": [root.size.x, root.size.y],
		"world_id": _created_world_id,
		"first_result": first_result.duplicate(true),
		"controller_result": controller_result.duplicate(true),
		"ranged_snapshot": ranged.call("get_snapshot"),
		"controller_before": controller_before,
		"controller_after": controller_after,
		"arrows_before": arrows_before,
		"arrows_after": arrows_after,
		"durability_before": durability_before,
		"durability_after": durability_after,
		"charge_screenshot": _charge_path,
		"hit_screenshot": _hit_path,
	}
	_write_report()
	await _finish(game, hub)


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-3, 4):
		for z_offset in range(-9, 3):
			world.call("set_block", Vector3i(center_x + x_offset, floor_y, center_z + z_offset), "stone")
			for y in range(floor_y + 1, floor_y + 6):
				world.call("set_block", Vector3i(center_x + x_offset, y, center_z + z_offset), "air")


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 10):
		var candidate_y := player_block.y - offset - 1
		if str(world.call("get_block", Vector3i(player_block.x, candidate_y, player_block.z))) != "air":
			return candidate_y
	return maxi(1, player_block.y - 1)


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


func _push_trigger_axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	# Continuous controller gameplay is owned by Input's parsed state and polled by
	# GameplayInputService/ControllerExplorationPlayer. Viewport push_input only
	# dispatches an event and does not update that authoritative axis state.
	Input.parse_input_event(event)


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(1, timeout_ms)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) == item_id:
			return index
	return -1


func _main_hand_durability(hub: Node) -> int:
	var slot: Dictionary = hub.equipment_service.call("get_slot", "main_hand")
	return int(slot.get("metadata", {}).get("durability", 384))


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
	_check(file != null, "ranged combat JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "ranged combat JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	_push_trigger_axis(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in 20:
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
		print(
			"QA RANGED COMBAT DESKTOP PASS | checks=%d | charge=%s | hit=%s | report=%s"
			% [checks, _charge_path, _hit_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANGED COMBAT DESKTOP FAILURE: %s" % failure)
		print(
			"QA RANGED COMBAT DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
