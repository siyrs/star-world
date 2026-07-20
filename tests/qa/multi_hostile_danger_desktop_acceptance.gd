extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://multi-hostile-danger-desktop.png"
const CLEANUP_FRAMES := 8
const HOSTILE_COUNT := 5

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
	var runtime: Node = hub.get("exploration_runtime_participant") if hub != null else null
	var coordinator: Node = hub.get("feature_lifecycle") if hub != null else null
	var machine_runtime: Node = hub.get("machine_runtime") if hub != null else null
	_check(
		hub != null and runtime != null and coordinator != null and machine_runtime != null,
		"production game mounts exploration and Machine Base runtime services"
	)
	if hub == null or runtime == null or coordinator == null or machine_runtime == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Multi-Hostile-Danger-%d" % Time.get_ticks_msec(),
		"star_continent",
		9274315
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop multi-hostile journey creates a temporary world")
	game.begin_world_state(state)
	for _frame in 12:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var spawner: Node = hub.creature_spawner
	var danger: Node = hub.exploration_danger_service
	var hud: Node = hub.game_ui.hud
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production world starts before multi-hostile acceptance")
	_check(spawner != null and danger != null and hud != null, "production ecology, danger and HUD services are available")
	_check(int(coordinator.call("get_snapshot").get("participant_count", 0)) == 5, "production coordinator retains all five lifecycle participants")
	_check(coordinator.call("has_participant", &"machine_runtime"), "Machine Base remains the lifecycle root during combat")
	if player == null or world == null or spawner == null or danger == null or hud == null:
		await _finish(game, hub)
		return

	var arena: Dictionary = _build_flat_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	var camera := player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.rotation = Vector3(deg_to_rad(-38.0), 0.0, 0.0)
	spawner.call("set_active", true)
	spawner.call("clear_creatures")
	for _frame in 3:
		await process_frame

	var batches: Array[Dictionary] = []
	runtime.connect(
		"danger_refresh_batch_completed",
		func(summary: Dictionary) -> void: batches.append(summary.duplicate(true))
	)
	var lifecycle_before: Dictionary = runtime.call("get_lifecycle_snapshot")
	var refresh_before_spawn := int(lifecycle_before.get("immediate_refresh_count", 0))
	var events_before_spawn := int(lifecycle_before.get("immediate_event_count", 0))
	var hostiles: Array[Node3D] = []
	for index in HOSTILE_COUNT:
		var angle := TAU * float(index) / float(HOSTILE_COUNT)
		var position := player.global_position + Vector3(sin(angle) * 8.0, 0.0, cos(angle) * 8.0)
		var raw_hostile: Variant = spawner.call("spawn_creature", "zombie", position)
		if raw_hostile is Node3D:
			var hostile: Node3D = raw_hostile
			hostile.set_physics_process(false)
			hostile.set("target", player)
			hostiles.append(hostile)
	for _frame in 3:
		await process_frame
	_check(hostiles.size() == HOSTILE_COUNT, "production spawner creates five nearby hostile bodies")
	var lifecycle_after_spawn: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(lifecycle_after_spawn.get("immediate_refresh_count", 0)) == refresh_before_spawn + 1, "five synchronous ecology events perform one danger assessment")
	_check(int(lifecycle_after_spawn.get("immediate_event_count", 0)) >= events_before_spawn + HOSTILE_COUNT, "runtime diagnostics retain all raw spawn events")
	var danger_after_spawn: Dictionary = danger.call("get_snapshot")
	_check(int(danger_after_spawn.get("hostile_count", 0)) == HOSTILE_COUNT, "single assessment observes all five hostiles")
	var spawn_batch: Dictionary = batches.back() if not batches.is_empty() else {}
	_check(bool(spawn_batch.get("environment_reused", false)), "spawn event batch reuses the existing environment sample")

	var refresh_before_windup := int(lifecycle_after_spawn.get("immediate_refresh_count", 0))
	var events_before_windup := int(lifecycle_after_spawn.get("immediate_event_count", 0))
	var windups_started := 0
	for index in hostiles.size():
		var hostile: Node3D = hostiles[index]
		var angle := TAU * float(index) / float(hostiles.size())
		hostile.global_position = player.global_position + Vector3(sin(angle) * 1.25, 0.0, cos(angle) * 1.25)
		hostile.set("target", player)
		if bool(hostile.call("_begin_attack_windup")):
			windups_started += 1
	for _frame in 3:
		await process_frame
	_check(windups_started == HOSTILE_COUNT, "all five production hostiles enter their real windup state")
	var lifecycle_after_windup: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(lifecycle_after_windup.get("immediate_refresh_count", 0)) == refresh_before_windup + 1, "five simultaneous attack-state events perform one danger assessment")
	_check(int(lifecycle_after_windup.get("immediate_event_count", 0)) >= events_before_windup + HOSTILE_COUNT, "runtime diagnostics preserve every windup event")
	_check(int(lifecycle_after_windup.get("coalesced_danger_event_count", 0)) >= 8, "runtime diagnostics prove that spawn and windup work was coalesced")
	var danger_during_windup: Dictionary = danger.call("get_snapshot")
	_check(int(danger_during_windup.get("windup_count", 0)) == HOSTILE_COUNT, "danger snapshot exposes five incoming attacks")
	_check(float(danger_during_windup.get("soonest_impact_seconds", -1.0)) > 0.0, "danger snapshot exposes the soonest incoming impact")
	_check(bool(hud.call("is_danger_warning_visible")), "production HUD displays the aggregate incoming attack warning")
	var warning_text := str(hud.call("get_danger_warning_text"))
	_check(warning_text.contains("×5") and warning_text.contains("最快"), "production HUD communicates count and urgency without requiring focus")
	var telegraph_count := 0
	for hostile: Node3D in hostiles:
		var attack: Dictionary = hostile.call("get_hostile_attack_snapshot")
		if bool(attack.get("telegraph_visible", false)):
			telegraph_count += 1
	_check(telegraph_count == HOSTILE_COUNT, "all five real non-collision warning circles remain visible")
	var windup_batch: Dictionary = batches.back() if not batches.is_empty() else {}
	_check(bool(windup_batch.get("environment_reused", false)), "windup event batch reuses the same bounded environment sample")
	var assessment_during_windup: Dictionary = danger.call("get_diagnostics")
	_check(int(assessment_during_windup.get("max_samples_observed", 0)) <= 125, "production danger never exceeds the 125-sample hard cap")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the overlapping hostile warnings")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "multi-hostile evidence uses the 1024x576 product resolution")
		_save_image(image)

	var refresh_before_cancel := int(lifecycle_after_windup.get("immediate_refresh_count", 0))
	for hostile: Node3D in hostiles:
		hostile.call("_cancel_attack_windup", "interrupted")
	for _frame in 3:
		await process_frame
	var lifecycle_after_cancel: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(lifecycle_after_cancel.get("immediate_refresh_count", 0)) == refresh_before_cancel + 1, "five synchronous cancellations perform one danger assessment")
	_check(int((danger.call("get_snapshot") as Dictionary).get("windup_count", -1)) == 0, "danger snapshot clears incoming attacks after interruption")
	_check(not bool(hud.call("is_danger_warning_visible")), "HUD clears the aggregate warning after all attacks stop")

	hub.inventory.clear()
	var refresh_before_mixed := int(lifecycle_after_cancel.get("immediate_refresh_count", 0))
	hub.day_night.set_time(21.0)
	for index in 3:
		hostiles[index].set("drops", {"rotten_flesh":1})
		hostiles[index].call("die")
	spawner.call("clear_creature_population")
	for _frame in 4:
		await process_frame
	var lifecycle_after_mixed: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(lifecycle_after_mixed.get("immediate_refresh_count", 0)) == refresh_before_mixed + 1, "same-frame phase, deaths, unloads and ecology changes perform one assessment")
	var last_triggers: Array = lifecycle_after_mixed.get("last_refresh_triggers", [])
	_check("phase_changed" in last_triggers and "ecology_changed" in last_triggers and "threat_changed" in last_triggers, "mixed refresh diagnostics preserve every unique trigger")
	_check(int((danger.call("get_snapshot") as Dictionary).get("hostile_count", -1)) == 0, "mixed batch observes the fully cleared hostile population")
	var pickups := _find_pickups(spawner, "rotten_flesh")
	var collected_before_move := int(hub.inventory.count_item("rotten_flesh"))
	_check(pickups.size() + collected_before_move == 3, "three simultaneous deaths preserve every real pickup through population clearing")
	for pickup: Node3D in pickups:
		if is_instance_valid(pickup):
			pickup.global_position = player.global_position + Vector3(0.0, 0.7, 0.0)
			await physics_frame
			await process_frame
	_check(hub.inventory.count_item("rotten_flesh") == 3, "physical collection transfers all three preserved drops")

	_check(bool(hub.save_current()), "multi-hostile runtime keeps the production save transaction healthy")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(not loaded.has("danger_refresh") and not loaded.has("hostile_windups") and not loaded.has("danger_runtime"), "transient batching and windup telemetry never enter the world save")
	_check(loaded.has("machines") and loaded.get("machines", {}).has("furnaces"), "Machine Base keeps its compatible save domain during combat")
	var drops_before_reload := int(hub.inventory.count_item("rotten_flesh"))
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	var after_menu: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(after_menu.get("pending_danger_event_count", -1)) == 0, "return-to-menu clears pending danger events")
	_check(not bool(machine_runtime.call("is_active")), "return-to-menu stops Machine Base during combat cleanup")
	game.begin_world_state(loaded)
	var reload_ready := await _wait_for_world_ready(game, hub, 180)
	_check(reload_ready, "full reload reaches a bounded production-ready state")
	if reload_ready:
		_check(not bool(hub.game_ui.hud.call("is_danger_warning_visible")), "full reload does not restore transient incoming attacks")
		_check(hub.inventory.count_item("rotten_flesh") == drops_before_reload, "full reload restores preserved enemy drops exactly once")
		_check(bool(machine_runtime.call("is_active")), "full reload restores Machine Base lifecycle")
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node, max_frames: int) -> bool:
	for _frame in max_frames:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var reloaded_world: Node = game.get("world") as Node
		var reloaded_player: Node = game.get("player") as Node
		if reloaded_world == null or reloaded_player == null:
			continue
		if not bool(reloaded_world.get("is_started")):
			continue
		if str(hub.get("current_world_id")) != _world_id:
			continue
		return true
	return false


func _build_flat_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for x_offset in range(-10, 11):
		for z_offset in range(-10, 11):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	return {
		"player_position": Vector3(float(origin.x) + 0.5, float(floor_y) + 1.05, float(origin.z) + 0.5),
	}


func _find_pickups(spawner: Node, item_id: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in spawner.get_children():
		if child is Node3D and str(child.get("item_id")) == item_id:
			result.append(child as Node3D)
	return result


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "multi-hostile danger screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA MULTI HOSTILE DANGER DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MULTI HOSTILE DANGER DESKTOP FAILURE: %s" % failure)
		print("QA MULTI HOSTILE DANGER DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
