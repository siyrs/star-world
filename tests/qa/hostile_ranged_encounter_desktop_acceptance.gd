extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://hostile-ranged-aim.png"
const WORLD_READY_TIMEOUT_MS := 120000
const ACTION_TIMEOUT_MS := 25000
const CLEANUP_FRAMES := 56
const OPEN_LANE_DISTANCE := 7.5
const IMMEDIATE_COVER_FRAMES := 45

var checks := 0
var failures: Array[String] = []
var _aim_path := ""
var _cover_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_aim_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_cover_path = _aim_path.get_base_dir().path_join("hostile-ranged-cover.png")
	_report_path = _aim_path.get_base_dir().path_join("hostile-ranged-report.json")
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
		"Hostile-Ranged-Desktop-%d" % Time.get_ticks_msec(),
		"abyss_world",
		54133754
	)
	_check(not state.is_empty(), "desktop hostile ranged journey creates a real abyss world")
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
	var player: Node3D = game.player
	var world: Node = game.world
	var hostile_runtime: Node = hub.get("hostile_projectile_runtime") as Node
	var combat: Node = hub.get("combat_service") as Node
	var overlay: Node = hub.game_ui.call("get_combat_feedback_overlay")
	_check(hostile_runtime != null, "production hub mounts one shared hostile projectile runtime")
	_check(int(hostile_runtime.call("get_snapshot").get("capacity", 0)) == 24, "hostile projectile runtime owns the exact twenty-four shot capacity")
	_check(combat != null, "production hub exposes CombatService for stable target-resolution evidence")
	_check(overlay != null, "production UI exposes combat results for lifecycle-safe defeat checks")
	if hostile_runtime == null or combat == null or overlay == null:
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.set("_hostile_damage_grace_remaining", 0.0)
	await physics_frame
	await process_frame

	hub.inventory.clear()
	hub.equipment_service.clear()
	hub.inventory.add_item("star_pistol", 1, {
		"durability": 420,
		"magazine_rounds": 2,
		"custom_name": "射手遭遇验收手枪",
	})
	var pistol_index := _find_item_slot(hub.inventory, "star_pistol")
	_check(pistol_index >= 0 and hub.equipment_service.equip_from_inventory(hub.inventory, pistol_index), "real inventory equips the counterattack pistol")

	var marksman_position := Vector3(
		player_block.x + 0.5,
		floor_y + 1.05,
		player_block.z - OPEN_LANE_DISTANCE
	)
	var raw_marksman: Variant = hub.creature_spawner.call(
		"spawn_creature", "abyss_marksman", marksman_position
	)
	_check(raw_marksman is Node3D, "real creature spawner creates the production abyss marksman")
	if raw_marksman is not Node3D:
		await _finish(game, hub)
		return
	var marksman: Node3D = raw_marksman
	var marksman_ref: WeakRef = weakref(marksman)
	var marksman_id := int(marksman.get_instance_id())
	marksman.set("move_speed", 0.0)
	marksman.set("target", player)
	marksman.set("_decision_timer", 999.0)
	marksman.set("_wander_direction", Vector3.ZERO)
	var mounted := await _wait_until(
		func() -> bool:
			var value: Variant = marksman_ref.get_ref()
			if value is not Node or not is_instance_valid(value):
				return false
			var snapshot: Dictionary = value.call("get_hostile_attack_snapshot")
			return (
				bool(snapshot.get("projectile_runtime_available", false))
				and bool(snapshot.get("cover_counter_available", false))
			),
		ACTION_TIMEOUT_MS
	)
	_check(mounted, "spawn signal binds the marksman to shared projectile and cover runtimes")
	hub.creature_spawner.call("set_active", false)
	marksman.set_physics_process(false)
	marksman.call("clear_combat_motion")
	marksman.set("target", player)
	marksman.global_position = marksman_position
	marksman.set("_decision_timer", 999.0)
	marksman.set("_wander_direction", Vector3.ZERO)
	hostile_runtime.call("clear", "desktop_open_lane_setup")
	for _frame in 3:
		await physics_frame
	marksman.call("_refresh_line_of_sight", true)
	var open_lane_snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
	_check(bool(open_lane_snapshot.get("line_of_sight", false)), "fixed production marksman owns a clear open firing lane")
	player.set("_hostile_damage_grace_remaining", 0.0)
	marksman.set("_attack_timer", 0.0)
	var open_windup_started := bool(marksman.call("_begin_attack_windup"))
	_check(open_windup_started, "fixed production marksman begins one deterministic projectile windup")
	var aim_visible := await _wait_until(
		func() -> bool:
			var value: Variant = marksman_ref.get_ref()
			if value is not Node or not is_instance_valid(value):
				return false
			var snapshot: Dictionary = value.call("get_hostile_attack_snapshot")
			return str(snapshot.get("state", "")) == "windup" and bool(snapshot.get("telegraph_visible", false)),
		ACTION_TIMEOUT_MS
	)
	_check(aim_visible, "real marksman aim telegraph is visible")
	await RenderingServer.frame_post_draw
	_save_viewport(_aim_path, "hostile ranged aim screenshot")

	var survival: Node = player.get("survival") as Node
	_check(survival != null, "production player exposes the survival service")
	var health_before := float(survival.get("health")) if survival != null else 0.0
	marksman.call("_advance_attack_windup", 2.0)
	var hostile_hit := await _wait_until(
		func() -> bool:
			return survival != null and float(survival.get("health")) < health_before,
		ACTION_TIMEOUT_MS
	)
	_check(hostile_hit, "dodgeable hostile projectile reaches the production player through CombatService")
	var health_after_hit := float(survival.get("health")) if survival != null else health_before
	var player_damage: Dictionary = player.call("get_hostile_damage_snapshot")
	var runtime_after_open_hit: Dictionary = hostile_runtime.call("get_snapshot")
	_check(int(player_damage.get("accepted_count", 0)) >= 1, "player source-scoped damage authority records the marksman hit")
	_check(int(runtime_after_open_hit.get("hit_count", 0)) >= 1, "shared hostile runtime records the authoritative player impact")
	var open_projectiles_settled := await _wait_until(
		func() -> bool:
			return int(hostile_runtime.call("get_snapshot").get("active_count", -1)) == 0,
		ACTION_TIMEOUT_MS
	)
	_check(open_projectiles_settled, "open-lane projectile settles before the cover isolation phase")

	var wall_z := player_block.z - 4
	_set_cover_wall(world, player_block.x, wall_z, floor_y, true)
	for _frame in 4:
		await physics_frame
	marksman.call("clear_combat_motion")
	marksman.set("target", player)
	marksman.set("_attack_timer", 0.0)
	marksman.call("_refresh_line_of_sight", true)
	var cover_snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
	var cover_blocks_los := not bool(cover_snapshot.get("line_of_sight", true))
	_check(cover_blocks_los, "solid cover blocks hostile projectiles")
	var spawn_count_before_cover := int(hostile_runtime.call("get_snapshot").get("spawn_count", 0))
	var health_before_cover := float(survival.get("health")) if survival != null else 0.0
	player.set("_hostile_damage_grace_remaining", 0.0)
	var hidden_windup_started := bool(marksman.call("_begin_attack_windup"))
	_check(not hidden_windup_started, "immediate blocked line of sight rejects a hidden projectile windup")
	for _frame in IMMEDIATE_COVER_FRAMES:
		await process_frame
	var health_after_cover := float(survival.get("health")) if survival != null else health_before_cover
	_check(int(hostile_runtime.call("get_snapshot").get("spawn_count", 0)) == spawn_count_before_cover, "blocked line of sight prevents hidden projectile spawning")
	_check(health_after_cover + 0.0001 >= health_before_cover, "solid cover prevents additional player damage before bounded reposition")
	_check(int(marksman.call("get_hostile_attack_snapshot").get("reposition_attempt_count", 0)) == 0, "immediate cover window does not consume the long-blocked reposition budget")
	await RenderingServer.frame_post_draw
	_save_viewport(_cover_path, "hostile ranged cover screenshot")

	_set_cover_wall(world, player_block.x, wall_z, floor_y, false)
	for _frame in 4:
		await physics_frame
	var live_marksman: Variant = marksman_ref.get_ref()
	if live_marksman is Node3D and is_instance_valid(live_marksman):
		live_marksman.set_physics_process(false)
		live_marksman.call("clear_combat_motion")
		live_marksman.set("health", 6.0)
		live_marksman.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 4.5)
		marksman_position = live_marksman.global_position
	var defeat_capture := {"result": {}}
	var defeat_callback: Callable = func(result: Dictionary) -> void:
		if int(result.get("target_id", 0)) == marksman_id:
			defeat_capture["result"] = result.duplicate(true)
	combat.connect("outgoing_attack_resolved", defeat_callback)
	await _aim_at(player, marksman_position + Vector3(0.0, 0.9, 0.0))
	_push_mouse_button(true)
	await process_frame
	_push_mouse_button(false)
	var defeated := await _wait_until(
		func() -> bool:
			var captured: Dictionary = defeat_capture.get("result", {})
			return bool(captured.get("defeated", false)) and marksman_ref.get_ref() == null,
		ACTION_TIMEOUT_MS
	)
	_check(defeated, "player firearm defeat releases the marksman safely")
	for _frame in 12:
		await process_frame
	_check(marksman_ref.get_ref() == null, "defeated marksman is unloaded without stale instance access")
	var defeat_result: Dictionary = defeat_capture.get("result", {}).duplicate(true)
	_check(int(defeat_result.get("target_id", 0)) == marksman_id and bool(defeat_result.get("defeated", false)), "CombatService publishes a stable defeated result after target release")
	if combat.is_connected("outgoing_attack_resolved", defeat_callback):
		combat.disconnect("outgoing_attack_resolved", defeat_callback)

	var runtime_after_defeat: Dictionary = hostile_runtime.call("get_snapshot")
	_check(int(runtime_after_defeat.get("active_count", -1)) == 0, "encounter ends with zero active hostile projectiles")
	_check(bool(hub.save_current()), "hostile ranged encounter coexists with the authoritative save")
	hub.return_to_menu()
	var returned := await _wait_until(
		func() -> bool: return str(hub.get("current_world_id")).is_empty(),
		ACTION_TIMEOUT_MS
	)
	_check(returned, "return to menu clears the hostile encounter runtime")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(not loaded.is_empty(), "saved hostile encounter world remains loadable")
	_check(not loaded.has("hostile_projectiles"), "hostile projectiles do not enter world.json")
	game.begin_world_state(loaded)
	var reloaded := await _wait_until(
		func() -> bool:
			return str(hub.get("current_world_id")) == _created_world_id and bool(game.player.get("input_enabled")),
		WORLD_READY_TIMEOUT_MS
	)
	_check(reloaded, "hostile encounter world reloads through production composition")
	_check(int(hostile_runtime.call("get_snapshot").get("active_count", -1)) == 0, "reloaded world starts with no transient hostile projectiles")

	_report = {
		"checks": checks,
		"failures": failures.duplicate(),
		"viewport": [root.size.x, root.size.y],
		"world_id": _created_world_id,
		"marksman_id": marksman_id,
		"open_lane_snapshot": open_lane_snapshot,
		"cover_snapshot": cover_snapshot,
		"health_before": health_before,
		"health_after_hit": health_after_hit,
		"health_before_cover": health_before_cover,
		"health_after_cover": health_after_cover,
		"player_damage": player_damage,
		"runtime_after_open_hit": runtime_after_open_hit,
		"hostile_runtime": hostile_runtime.call("get_snapshot"),
		"defeat_result": defeat_result,
		"aim_screenshot": _aim_path,
		"cover_screenshot": _cover_path,
	}
	_write_report()
	await _finish(game, hub)


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-5, 6):
		for z_offset in range(-18, 5):
			world.call("set_block", Vector3i(center_x + x_offset, floor_y, center_z + z_offset), "stone")
			for y in range(floor_y + 1, floor_y + 7):
				world.call("set_block", Vector3i(center_x + x_offset, y, center_z + z_offset), "air")


func _set_cover_wall(world: Node, center_x: int, z: int, floor_y: int, enabled: bool) -> void:
	for x_offset in range(-1, 2):
		for y_offset in range(1, 4):
			world.call(
				"set_block",
				Vector3i(center_x + x_offset, floor_y + y_offset, z),
				"stone" if enabled else "air"
			)


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 12):
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
	_check(file != null, "hostile ranged JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "hostile ranged JSON report is saved")


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
		print("QA HOSTILE RANGED DESKTOP PASS | checks=%d | aim=%s | cover=%s | report=%s" % [checks, _aim_path, _cover_path, _report_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE RANGED DESKTOP FAILURE: %s" % failure)
	print("QA HOSTILE RANGED DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
