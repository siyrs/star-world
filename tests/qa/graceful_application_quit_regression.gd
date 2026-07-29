extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const READY_FRAMES := 720
const MENU_FRAMES := 240
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _world_ids: Array[String] = []
var _prepared_sources: Array[String] = []
var _blocked_sources: Array[String] = []


class FailingSaveService:
	extends Node

	func save_world(_world_id: String, _state: Dictionary) -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GameScene.instantiate()
	game.application_exit_enabled = false
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	var save := hub.get("save_service") as Node if hub != null else null
	var recovery := hub.get("world_session_recovery_service") as Node if hub != null else null
	var main_menu := hub.get("main_menu") as Node if hub != null else null
	var game_ui := hub.get("game_ui") as Node if hub != null else null
	_check(
		hub != null
		and save != null
		and recovery != null
		and main_menu != null
		and game_ui != null,
		"production game mounts crash-safe quit and session recovery composition"
	)
	if hub == null or save == null or recovery == null or main_menu == null or game_ui == null:
		await _finish(game, save)
		return
	game.application_quit_prepared.connect(
		func(source: StringName) -> void: _prepared_sources.append(str(source))
	)
	game.application_quit_blocked.connect(
		func(source: StringName) -> void: _blocked_sources.append(str(source))
	)

	var first_state: Dictionary = save.create_world(
		"Graceful Quit Success %d" % Time.get_ticks_msec(),
		"star_continent",
		520729
	)
	var first_world := str(first_state.get("metadata", {}).get("id", ""))
	if not first_world.is_empty():
		_world_ids.append(first_world)
	_check(not first_world.is_empty(), "graceful quit regression creates a success world")
	if first_world.is_empty():
		await _finish(game, save)
		return
	game.call("begin_world_state", first_state)
	_check(
		await _wait_for_world_ready(game, hub, first_world),
		"success world reaches playable production state"
	)
	_check(
		str(recovery.call("get_recovery_candidate").get("world_id", "")) == first_world,
		"playable world owns an abnormal-exit recovery marker"
	)
	_check(
		bool(game.call("request_application_quit", &"window_close")),
		"window-close request completes the authoritative final-save path"
	)
	_check(
		await _wait_for_menu(hub),
		"successful application quit releases gameplay before process exit"
	)
	var first_quit: Dictionary = game.call("get_application_quit_snapshot")
	var first_hub_quit: Dictionary = hub.call("get_application_quit_snapshot")
	_check(
		_prepared_sources == ["window_close"]
		and _blocked_sources.is_empty()
		and int(first_quit.get("success_count", 0)) == 1
		and int(first_hub_quit.get("success_count", 0)) == 1,
		"window-close coordination emits one successful single-flight fact"
	)
	_check(
		recovery.call("get_recovery_candidate").is_empty(),
		"clean final save clears the interrupted-session marker"
	)
	_check(
		not save.load_world(first_world).is_empty(),
		"clean application quit leaves the authoritative world loadable"
	)

	var second_state: Dictionary = save.create_world(
		"Graceful Quit Failure %d" % Time.get_ticks_msec(),
		"desert_ruins",
		520730
	)
	var second_world := str(second_state.get("metadata", {}).get("id", ""))
	if not second_world.is_empty():
		_world_ids.append(second_world)
	_check(not second_world.is_empty(), "graceful quit regression creates a failure world")
	if second_world.is_empty():
		await _finish(game, save)
		return
	game.call("begin_world_state", second_state)
	_check(
		await _wait_for_world_ready(game, hub, second_world),
		"failure world reaches playable production state"
	)
	game_ui.call("toggle_pause")
	await process_frame
	var failing_save := FailingSaveService.new()
	failing_save.name = "FailingApplicationQuitSave"
	hub.add_child(failing_save)
	hub.set("save_service", failing_save)
	_check(
		not bool(game.call("request_application_quit", &"pause_menu")),
		"failed final save blocks application exit"
	)
	var failed_quit: Dictionary = game.call("get_application_quit_snapshot")
	var failed_hub_quit: Dictionary = hub.call("get_application_quit_snapshot")
	var pause_status := _find_label(game_ui, "PauseStatus")
	_check(
		str(hub.get("current_world_id")) == second_world
		and int(failed_quit.get("failure_count", 0)) == 1
		and int(failed_hub_quit.get("failure_count", 0)) == 1
		and _blocked_sources == ["pause_menu"],
		"failed quit preserves world ownership and records one blocked request"
	)
	_check(
		str(recovery.call("get_recovery_candidate").get("world_id", "")) == second_world,
		"failed quit preserves the recovery marker for the still-active world"
	)
	_check(
		pause_status != null
		and pause_status.text.contains("已取消退出")
		and bool(hub.simulation_pause.call("is_paused")),
		"pause UI explains failure while the simulation remains safely paused"
	)

	hub.set("save_service", save)
	failing_save.queue_free()
	await process_frame
	_check(
		bool(game.call("request_application_quit", &"pause_menu")),
		"restoring the authoritative save service allows a safe retry"
	)
	_check(
		await _wait_for_menu(hub)
		and str(hub.get("current_world_id")).is_empty()
		and recovery.call("get_recovery_candidate").is_empty(),
		"successful retry releases the world and clears recovery evidence"
	)

	main_menu.quit_requested.emit()
	for _frame in 3:
		await process_frame
	var menu_quit: Dictionary = game.call("get_application_quit_snapshot")
	_check(
		str(menu_quit.get("last_source", "")) == "main_menu"
		and _prepared_sources.has("main_menu"),
		"main-menu quit is an intent routed through the game composition root"
	)
	game.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	for _frame in 4:
		await process_frame
	var wm_quit: Dictionary = game.call("get_application_quit_snapshot")
	_check(
		str(wm_quit.get("last_source", "")) == "window_close"
		and _prepared_sources.count("window_close") == 2,
		"real WM close notification uses the same bounded quit coordinator"
	)

	await _finish(game, save)


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world := game.get("world") as Node
		if (
			world != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


func _wait_for_menu(hub: Node) -> bool:
	for _frame in MENU_FRAMES:
		await process_frame
		if hub == null or not is_instance_valid(hub):
			return false
		var menu := hub.get("main_menu") as Control
		if str(hub.get("current_world_id")).is_empty() and menu != null and menu.visible:
			return true
	return false


func _find_label(node: Node, node_name: String) -> Label:
	if node is Label and node.name == node_name:
		return node as Label
	for child: Node in node.get_children():
		var result := _find_label(child, node_name)
		if result != null:
			return result
	return null


func _finish(game: Node, save: Node) -> void:
	if game != null and is_instance_valid(game):
		var hub := game.get("service_hub") as Node
		if hub != null and hub.get("simulation_pause") != null:
			hub.simulation_pause.call("reset")
		if hub != null and not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
		var audio := hub.get("audio_service") as Node if hub != null else null
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	for world_id: String in _world_ids:
		if (
			save != null
			and is_instance_valid(save)
			and bool(save.call("world_exists", world_id))
		):
			save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	_check(auto_accept_quit, "game teardown restores SceneTree automatic quit behavior")
	if failures.is_empty():
		print("QA GRACEFUL APPLICATION QUIT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA GRACEFUL APPLICATION QUIT FAILURE: %s" % failure)
		print(
			"QA GRACEFUL APPLICATION QUIT FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
