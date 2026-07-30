extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const CoverPolicy = preload("res://src/entity/hostile_cover_counter_policy.gd")

const OUTPUT_PATH := "user://hostile-cover-broken.png"
const WORLD_READY_TIMEOUT_MS := 120000
const ACTION_TIMEOUT_MS := 30000
const CLEANUP_FRAMES := 64

var checks := 0
var failures: Array[String] = []
var _broken_path := ""
var _reposition_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_broken_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_reposition_path = _broken_path.get_base_dir().path_join("hostile-cover-reposition.png")
	_report_path = _broken_path.get_base_dir().path_join("hostile-cover-report.json")
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production cover journey exposes the service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Hostile-Cover-Desktop-%d" % Time.get_ticks_msec(),
		"abyss_world",
		57190577
	)
	_check(not state.is_empty(), "cover journey creates a real abyss world")
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
	_check(ready, "abyss cover world and player become ready inside the bounded deadline")
	if not ready:
		await _finish(game, hub)
		return

	var player: Node3D = game.player
	var world: Node = game.world
	var spawner: Node = hub.creature_spawner
	var service: Node = hub.get_node_or_null("HostileCoverCounterService")
	var overlay: Node = hub.game_ui.get_node_or_null("HostileCoverCounterOverlay")
	var hostile_runtime: Node = hub.get("hostile_projectile_runtime") as Node
	var survival: Node = player.get("survival") as Node
	_check(service != null, "production composition mounts one hostile cover counter service")
	_check(overlay != null, "production UI mounts one hostile cover counter overlay")
	_check(hostile_runtime != null, "production hub retains the shared hostile projectile runtime")
	_check(survival != null, "production player exposes survival for through-cover damage evidence")
	if service == null or overlay == null or hostile_runtime == null or survival == null:
		await _finish(game, hub)
		return

	hub.day_night.running = false
	hub.day_night.set_time(22.0)
	spawner.clear_creatures()
	spawner.set_process(false)
	var director: Node = hub.get_node_or_null("HostileEncounterDirector")
	if director != null:
		director.set_process(false)
		director.call("clear", "cover_desktop_setup")
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.set("_hostile_damage_grace_remaining", 0.0)
	await physics_frame
	await process_frame
	var bound := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = service.call("get_snapshot")
			return bool(snapshot.get("active", false)) and str(snapshot.get("world_id", "")) == _created_world_id,
		ACTION_TIMEOUT_MS
	)
	_check(bound, "cover counter auto-binds to the authoritative production world")

	var cover_a := Vector3i(player_block.x, floor_y + 2, player_block.z - 2)
	var cover_b := Vector3i(player_block.x, floor_y + 2, player_block.z - 1)
	world.call("set_block", cover_a, "wool")
	world.call("set_block", cover_b, "glass_pane")
	_check(str(world.call("get_block", cover_a)) == "wool", "real world owns the player-placed wool temporary cover")
	_check(str(world.call("get_block", cover_b)) == "glass_pane", "real world owns the player-placed glass-pane temporary cover")

	var brute_position := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 3.5)
	var raw_brute: Variant = spawner.call("spawn_creature", "abyss_brute", brute_position)
	_check(raw_brute is Node3D, "real creature spawner creates the cover-aware abyss brute")
	if raw_brute is not Node3D:
		await _finish(game, hub)
		return
	var brute: Node3D = raw_brute
	brute.set_physics_process(false)
	brute.set("target", player)
	brute.set("attack_range", 4.5)
	brute.set("attack_windup_seconds", 0.15)
	brute.set("attack_cooldown_seconds", 0.6)
	var brute_bound := await _wait_until(
		func() -> bool:
			return bool(brute.call("get_hostile_attack_snapshot").get("cover_counter_available", false)),
		ACTION_TIMEOUT_MS
	)
	_check(brute_bound, "spawn signal binds the brute to the shared cover counter")
	world.call("reset_chunk_rebuild_stats")
	var health_before_cover := float(survival.get("health"))
	brute.set("_attack_timer", 0.0)
	_check(bool(brute.call("_begin_attack_windup")), "real brute begins its production windup against temporary cover")
	brute.call("_advance_attack_windup", 0.3)
	for _frame in 4:
		await process_frame
	var rebuild_after_break: Dictionary = world.call("get_chunk_rebuild_stats")
	var brute_after_break: Dictionary = brute.call("get_hostile_attack_snapshot")
	var break_result: Dictionary = brute_after_break.get("last_cover_break_result", {})
	var break_apply: Dictionary = break_result.get("apply", {})
	var authoritative_break_rebuild: Dictionary = break_apply.get("rebuild", {})
	_check(str(world.call("get_block", cover_a)) == "air" and str(world.call("get_block", cover_b)) == "air", "one real brute attack destroys both temporary cover cells")
	_check(int(brute_after_break.get("cover_break_block_count", 0)) == 2, "brute combat snapshot records exactly two destroyed cover cells")
	_check(int(rebuild_after_break.get("flush_count", 0)) == 1, "two cover cells share exactly one production world rebuild flush")
	_check(str(authoritative_break_rebuild.get("last_reason", "")) == "batch_complete", "cover destruction closes through the existing batch-complete flush boundary")
	_check(float(survival.get("health")) + 0.0001 >= health_before_cover, "cover-breaking attack cannot damage the player through the wall")
	var broken_overlay_ready := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = overlay.call("get_snapshot")
			return bool(snapshot.get("visible", false)) and str(snapshot.get("title", "")).contains("掩体被突破"),
		ACTION_TIMEOUT_MS
	)
	_check(broken_overlay_ready, "cover HUD explains the real brute breakthrough")
	await RenderingServer.frame_post_draw
	_save_viewport(_broken_path, "hostile temporary-cover destruction screenshot")

	var permanent_cover := Vector3i(player_block.x, floor_y + 2, player_block.z - 1)
	world.call("set_block", permanent_cover, "stone")
	var health_before_stone := float(survival.get("health"))
	var flush_before_stone := int(world.call("get_chunk_rebuild_stats").get("flush_count", 0))
	brute.set("_attack_timer", 0.0)
	player.set("_hostile_damage_grace_remaining", 0.0)
	_check(bool(brute.call("_begin_attack_windup")), "real brute begins an attack against permanent stone cover")
	brute.call("_advance_attack_windup", 0.3)
	for _frame in 3:
		await process_frame
	var brute_after_stone: Dictionary = brute.call("get_hostile_attack_snapshot")
	_check(str(world.call("get_block", permanent_cover)) == "stone", "permanent stone base remains intact after the brute attack")
	_check(int(world.call("get_chunk_rebuild_stats").get("flush_count", 0)) == flush_before_stone, "permanent cover block performs no world mutation flush")
	_check(float(survival.get("health")) + 0.0001 >= health_before_stone, "permanent cover also blocks melee damage through the wall")
	_check(int(brute_after_stone.get("cover_blocked_attack_count", 0)) >= 1, "brute diagnostics distinguish a safely blocked permanent-cover attack")

	world.call("set_block", permanent_cover, "air")
	player.set("_hostile_damage_grace_remaining", 0.0)
	var health_before_open := float(survival.get("health"))
	brute.set("_attack_timer", 0.0)
	_check(bool(brute.call("_begin_attack_windup")), "real brute begins the same attack after the lane opens")
	brute.call("_advance_attack_windup", 0.3)
	var open_hit := await _wait_until(
		func() -> bool: return float(survival.get("health")) < health_before_open,
		ACTION_TIMEOUT_MS
	)
	_check(open_hit, "unobstructed brute attack still reaches the production player")

	if survival.has_method("restore_full"):
		survival.call("restore_full")
	else:
		survival.set("health", survival.get("max_health"))
	player.set("_hostile_damage_grace_remaining", 0.0)
	var wall_z := player_block.z - 6
	_set_temporary_wall(world, player_block.x, wall_z, floor_y, true)
	var marksman_position := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 12.0)
	var raw_marksman: Variant = spawner.call("spawn_creature", "abyss_marksman", marksman_position)
	_check(raw_marksman is Node3D, "real creature spawner creates the cover-aware abyss marksman")
	if raw_marksman is not Node3D:
		await _finish(game, hub)
		return
	var marksman: Node3D = raw_marksman
	marksman.set_physics_process(false)
	marksman.set("target", player)
	marksman.set("_decision_timer", 999.0)
	marksman.set("_wander_direction", Vector3.ZERO)
	var marksman_bound := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
			return bool(snapshot.get("cover_counter_available", false)) and bool(snapshot.get("projectile_runtime_available", false)),
		ACTION_TIMEOUT_MS
	)
	_check(marksman_bound, "marksman binds both the cover counter and shared projectile runtime")
	marksman.call("_refresh_line_of_sight", true)
	_check(not bool(marksman.call("get_hostile_attack_snapshot").get("line_of_sight", true)), "temporary wall blocks the production marksman ballistic lane")
	marksman.set("_blocked_lane_seconds", CoverPolicy.REPOSITION_DELAY_SECONDS)
	marksman.set("_reposition_cooldown_remaining", 0.0)
	marksman.call("_choose_direction")
	var reposition_snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
	_check(int(reposition_snapshot.get("reposition_attempt_count", 0)) == 1, "blocked production marksman spends one bounded reposition attempt")
	_check(int(reposition_snapshot.get("reposition_success_count", 0)) == 1, "blocked production marksman finds one local firing lane")
	_check(bool(reposition_snapshot.get("cover_destination_active", false)), "marksman reuses the existing cover destination movement contract")
	var reposition_result: Dictionary = reposition_snapshot.get("last_reposition_result", {})
	_check(int(reposition_result.get("probes", 99)) <= CoverPolicy.MAX_REPOSITION_PROBES, "production reposition uses no more than six probes")
	var destination: Vector3 = reposition_result.get("destination", marksman.global_position)
	_check(destination.distance_to(marksman.global_position) <= CoverPolicy.REPOSITION_RADIUS + 0.2, "production marksman destination stays inside the local radius")
	var reposition_overlay_ready := await _wait_until(
		func() -> bool:
			var snapshot: Dictionary = overlay.call("get_snapshot")
			return bool(snapshot.get("visible", false)) and str(snapshot.get("title", "")).contains("射手正在换位"),
		ACTION_TIMEOUT_MS
	)
	_check(reposition_overlay_ready, "cover HUD explains the real marksman reposition")
	marksman.global_position = destination
	marksman.call("_refresh_line_of_sight", true)
	_check(bool(marksman.call("get_hostile_attack_snapshot").get("line_of_sight", false)), "selected reposition destination restores a clear production firing lane")
	var spawn_before := int(hostile_runtime.call("get_snapshot").get("spawn_count", 0))
	marksman.set("_attack_timer", 0.0)
	_check(bool(marksman.call("_begin_attack_windup")), "repositioned marksman can begin a real projectile windup")
	marksman.call("_advance_attack_windup", 2.0)
	var fired_after_reposition := await _wait_until(
		func() -> bool: return int(hostile_runtime.call("get_snapshot").get("spawn_count", 0)) > spawn_before,
		ACTION_TIMEOUT_MS
	)
	_check(fired_after_reposition, "repositioned marksman fires through the shared hostile projectile runtime")
	await RenderingServer.frame_post_draw
	_save_viewport(_reposition_path, "hostile marksman reposition screenshot")

	var service_before_save: Dictionary = service.call("get_snapshot")
	_check(int(service_before_save.get("cover_break_block_count", 0)) == 2, "session diagnostics retain the exact temporary-cover destruction total")
	_check(int(service_before_save.get("permanent_cover_block_count", 0)) >= 1, "session diagnostics retain permanent-cover damage blocks")
	_check(int(service_before_save.get("marksman_reposition_count", 0)) >= 1, "session diagnostics retain the successful marksman reposition")
	_check(bool(hub.save_current()), "cover counter gameplay coexists with the authoritative save")
	hub.return_to_menu()
	var returned := await _wait_until(
		func() -> bool: return str(hub.get("current_world_id")).is_empty(),
		ACTION_TIMEOUT_MS
	)
	_check(returned, "return to menu clears the cover-counter session")
	var after_return: Dictionary = service.call("get_snapshot")
	_check(int(after_return.get("cover_break_block_count", -1)) == 0 and int(after_return.get("marksman_reposition_count", -1)) == 0, "return-to-menu signal clears all transient cover counters")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(not loaded.is_empty(), "saved cover-counter world remains loadable")
	_check(not loaded.has("hostile_cover_counter") and not loaded.has("cover_counter"), "cover counter runtime never enters world.json")
	game.begin_world_state(loaded)
	var reloaded := await _wait_until(
		func() -> bool:
			return str(hub.get("current_world_id")) == _created_world_id and bool(game.player.get("input_enabled")),
		WORLD_READY_TIMEOUT_MS
	)
	_check(reloaded, "cover-counter world reloads through production composition")
	var reload_snapshot: Dictionary = service.call("get_snapshot")
	_check(int(reload_snapshot.get("cover_break_block_count", -1)) == 0, "reloaded world begins with no old brute destruction budget")
	_check(int(reload_snapshot.get("marksman_reposition_count", -1)) == 0, "reloaded world begins with no old marksman reposition budget")

	_report = {
		"checks": checks,
		"failures": failures.duplicate(),
		"viewport": [root.size.x, root.size.y],
		"world_id": _created_world_id,
		"health_before_cover": health_before_cover,
		"health_before_stone": health_before_stone,
		"health_before_open": health_before_open,
		"service_before_save": service_before_save,
		"after_return": after_return,
		"reload_snapshot": reload_snapshot,
		"rebuild_after_break": rebuild_after_break,
		"authoritative_break_rebuild": authoritative_break_rebuild,
		"brute_after_break": brute_after_break,
		"brute_after_stone": brute_after_stone,
		"marksman_reposition": reposition_snapshot,
		"hostile_runtime": hostile_runtime.call("get_snapshot"),
		"broken_screenshot": _broken_path,
		"reposition_screenshot": _reposition_path,
	}
	_write_report()
	await _finish(game, hub)


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-7, 8):
		for z_offset in range(-18, 5):
			world.call("set_block", Vector3i(center_x + x_offset, floor_y, center_z + z_offset), "stone")
			for y in range(floor_y + 1, floor_y + 7):
				world.call("set_block", Vector3i(center_x + x_offset, y, center_z + z_offset), "air")


func _set_temporary_wall(world: Node, center_x: int, z: int, floor_y: int, enabled: bool) -> void:
	for x_offset in range(-1, 2):
		for y_offset in range(1, 4):
			world.call(
				"set_block",
				Vector3i(center_x + x_offset, floor_y + y_offset, z),
				"wool" if enabled else "air"
			)


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 12):
		var candidate_y := player_block.y - offset - 1
		if str(world.call("get_block", Vector3i(player_block.x, candidate_y, player_block.z))) != "air":
			return candidate_y
	return maxi(1, player_block.y - 1)


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
	_check(file != null, "hostile cover JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "hostile cover JSON report is saved")


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
		print("QA HOSTILE COVER DESKTOP PASS | checks=%d | broken=%s | reposition=%s | report=%s" % [checks, _broken_path, _reposition_path, _report_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE COVER DESKTOP FAILURE: %s" % failure)
	print("QA HOSTILE COVER DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
