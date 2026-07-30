extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://firearm-combat-reload.png"
const WORLD_READY_TIMEOUT_MS := 120000
const ACTION_TIMEOUT_MS := 20000
const CLEANUP_FRAMES := 48

var checks := 0
var failures: Array[String] = []
var _reload_path := ""
var _hit_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_reload_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_hit_path = _reload_path.get_base_dir().path_join("firearm-combat-hit.png")
	_report_path = _reload_path.get_base_dir().path_join("firearm-combat-report.json")
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
		"Firearm-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		5318008
	)
	_check(not state.is_empty(), "desktop firearm journey creates a real world")
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
	_check(ranged != null, "production character domain mounts the shared ranged service")
	_check(overlay != null, "production UI mounts shared firearm feedback")
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
	hub.inventory.add_item("star_pistol", 1, {
		"durability": 420,
		"magazine_rounds": 2,
		"custom_name": "桌面验收星火手枪",
	})
	hub.inventory.add_item("light_round", 12)
	var pistol_index := _find_item_slot(hub.inventory, "star_pistol")
	_check(pistol_index >= 0 and hub.equipment_service.equip_from_inventory(hub.inventory, pistol_index), "real inventory equips the loaded pistol")
	var view: Node = player.get_node_or_null("CameraPivot/Camera3D/HeldItemView")
	if view != null:
		view.call("refresh_for_test")
		var view_snapshot: Dictionary = view.call("get_snapshot")
		_check(str(view_snapshot.get("item_source", "")) == "equipment", "production viewmodel reads the equipped main hand")
		_check(str(view_snapshot.get("model_kind", "")) == "firearm", "production viewmodel renders a firearm model")
	var reserve_before: int = int(hub.inventory.count_item("light_round"))
	var durability_before := _main_hand_durability(hub)
	var target_position := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 5.0)
	var target_variant: Variant = hub.creature_spawner.call("spawn_creature", "cow", target_position)
	_check(target_variant is Node3D, "real creature spawner creates a firearm target")
	if target_variant is not Node3D:
		await _finish(game, hub)
		return
	var target: Node3D = target_variant
	var target_id := int(target.get_instance_id())
	var target_ref: WeakRef = weakref(target)
	target.set("max_health", 40.0)
	target.set("health", 40.0)
	_freeze_target(target)
	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	var health_before := float(target.get("health"))

	_push_mouse_button(true)
	await process_frame
	_push_mouse_button(false)
	var mouse_hit := await _wait_until(
		func() -> bool:
			var result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
			return (
				str(result.get("attack_kind", "")) == "firearm"
				and str(result.get("status", "")) == "hit"
				and int(result.get("target_id", 0)) == target_id
			),
		ACTION_TIMEOUT_MS
	)
	_check(mouse_hit, "real left-mouse click fires a hitscan pistol shot through CombatService")
	var mouse_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	var live_target: Variant = target_ref.get_ref()
	var target_changed := bool(mouse_result.get("accepted", false))
	if live_target is Node and is_instance_valid(live_target):
		target_changed = float(live_target.get("health")) < health_before
	else:
		target_changed = bool(mouse_result.get("defeated", false))
	_check(target_changed, "mouse firearm shot changes or defeats the target exactly once")
	var after_mouse: Dictionary = ranged.call("get_snapshot")
	_check(int(after_mouse.get("magazine_rounds", -1)) == 1, "mouse shot consumes one magazine round")
	_check(hub.inventory.count_item("light_round") == reserve_before, "mouse shot does not consume reserve ammunition")
	_check(_main_hand_durability(hub) == durability_before - 1, "mouse shot consumes one firearm durability")

	_parse_key(KEY_R, true)
	await process_frame
	_parse_key(KEY_R, false)
	var keyboard_reload := await _wait_until(
		func() -> bool: return bool(ranged.call("get_snapshot").get("reloading", false)),
		ACTION_TIMEOUT_MS
	)
	_check(keyboard_reload, "real keyboard R starts the shared reload transaction")
	_check(hub.inventory.count_item("light_round") == reserve_before, "reserve ammunition remains unchanged while reload is in progress")
	var reload_visible := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = overlay.call("get_snapshot")
			return bool(snapshot.get("ranged_visible", false)) and str(snapshot.get("ranged_text", "")).contains("换弹"),
		ACTION_TIMEOUT_MS
	)
	_check(reload_visible, "firearm HUD exposes reload progress magazine and reserve")
	await RenderingServer.frame_post_draw
	_save_viewport(_reload_path, "firearm reload screenshot")
	var keyboard_reload_complete := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = ranged.call("get_snapshot")
			return not bool(snapshot.get("reloading", true)) and int(snapshot.get("magazine_rounds", 0)) == 8,
		ACTION_TIMEOUT_MS
	)
	_check(keyboard_reload_complete, "keyboard reload atomically fills the pistol magazine")
	_check(hub.inventory.count_item("light_round") == reserve_before - 7, "keyboard reload consumes exactly seven reserve rounds")

	live_target = target_ref.get_ref()
	if live_target is Node3D and is_instance_valid(live_target):
		if live_target.has_method("clear_combat_motion"):
			live_target.call("clear_combat_motion")
		live_target.global_position = target_position
		_freeze_target(live_target)
	await _aim_at(player, target_position + Vector3(0.0, 0.65, 0.0))
	var controller_before: Dictionary = player.call("get_controller_gameplay_snapshot")
	_parse_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var controller_hit := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = ranged.call("get_snapshot")
			return int(snapshot.get("shot_count", 0)) >= 2 and int(snapshot.get("magazine_rounds", 0)) == 7,
		ACTION_TIMEOUT_MS
	)
	_parse_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(controller_hit, "real controller right trigger fires the same pistol path")
	var controller_after: Dictionary = player.call("get_controller_gameplay_snapshot")
	_check(int(controller_after.get("primary_press_count", 0)) == int(controller_before.get("primary_press_count", 0)) + 1, "controller trigger records one physical press")
	_check(int(controller_after.get("primary_release_count", 0)) == int(controller_before.get("primary_release_count", 0)) + 1, "controller trigger records one physical release")
	_parse_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await process_frame
	_parse_button(JOY_BUTTON_LEFT_SHOULDER, false)
	var controller_reload := await _wait_until(
		func() -> bool: return bool(ranged.call("get_snapshot").get("reloading", false)),
		ACTION_TIMEOUT_MS
	)
	_check(controller_reload, "real controller left shoulder starts the shared reload transaction")
	controller_after = player.call("get_controller_gameplay_snapshot")
	_check(int(controller_after.get("reload_count", 0)) == int(controller_before.get("reload_count", 0)) + 1, "controller reload counter records the physical command")
	var controller_reload_complete := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = ranged.call("get_snapshot")
			return not bool(snapshot.get("reloading", true)) and int(snapshot.get("magazine_rounds", 0)) == 8,
		ACTION_TIMEOUT_MS
	)
	_check(controller_reload_complete, "controller reload fills the final magazine round")
	await RenderingServer.frame_post_draw
	_save_viewport(_hit_path, "firearm hit and ready screenshot")

	var reserve_after: int = int(hub.inventory.count_item("light_round"))
	var durability_after := _main_hand_durability(hub)
	var magazine_after := _magazine_rounds(hub)
	_check(bool(hub.save_current()), "firearm inventory and equipment coexist with the authoritative save")
	hub.return_to_menu()
	var returned := await _wait_until(
		func() -> bool: return str(hub.get("current_world_id")).is_empty(),
		ACTION_TIMEOUT_MS
	)
	_check(returned, "final save releases the first firearm session")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(not loaded.is_empty(), "saved firearm world remains loadable")
	game.begin_world_state(loaded)
	var reloaded := await _wait_until(
		func() -> bool:
			return str(hub.get("current_world_id")) == _created_world_id and bool(game.player.get("input_enabled")),
		WORLD_READY_TIMEOUT_MS
	)
	_check(reloaded, "firearm world reloads through production composition")
	_check(hub.inventory.count_item("light_round") == reserve_after, "reserve ammunition survives save and reload")
	_check(_main_hand_durability(hub) == durability_after, "firearm durability survives save and reload")
	_check(_magazine_rounds(hub) == magazine_after, "magazine rounds survive save and reload")
	_check(not bool(ranged.call("get_snapshot").get("reloading", true)), "transient reload state does not enter world.json")
	_check(int(ranged.call("get_snapshot").get("hitscan", {}).get("shot_count", 0)) >= 2, "desktop journey records two real hitscan shots")

	_report = {
		"checks": checks,
		"failures": failures.duplicate(),
		"viewport": [root.size.x, root.size.y],
		"world_id": _created_world_id,
		"target_id": target_id,
		"target_alive_after_mouse": target_ref.get_ref() != null,
		"mouse_result": mouse_result.duplicate(true),
		"reserve_before": reserve_before,
		"reserve_after": reserve_after,
		"durability_before": durability_before,
		"durability_after": durability_after,
		"magazine_after": magazine_after,
		"controller_before": controller_before,
		"controller_after": controller_after,
		"ranged_snapshot": ranged.call("get_snapshot"),
		"reload_screenshot": _reload_path,
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


func _freeze_target(target: Node3D) -> void:
	target.set("move_speed", 0.0)
	target.set("_decision_timer", 999.0)
	target.set("_wander_direction", Vector3.ZERO)


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


func _parse_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _parse_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _parse_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
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
	return int(hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("durability", 0))


func _magazine_rounds(hub: Node) -> int:
	return int(hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("magazine_rounds", -1))


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
	_check(file != null, "firearm combat JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "firearm combat JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	_parse_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_parse_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_parse_key(KEY_R, false)
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
		print("QA FIREARM DESKTOP PASS | checks=%d | reload=%s | hit=%s | report=%s" % [checks, _reload_path, _hit_path, _report_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA FIREARM DESKTOP FAILURE: %s" % failure)
	print("QA FIREARM DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)