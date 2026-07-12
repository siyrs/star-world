extends SceneTree

const Actions = preload("res://src/input/gameplay_input_actions.gd")
const GameplayInputScript = preload("res://src/input/gameplay_input_service.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const MovementControllerScript = preload("res://src/player/player_movement_controller.gd")
const SpawnResolverScript = preload("res://src/player/player_spawn_resolver.gd")
const GameScene = preload("res://scenes/game/game.tscn")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class SpawnWorld:
	extends Node

	func get_block(position: Vector3i) -> String:
		return "stone" if position.y <= 0 else "air"

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, 1.05, candidate.z)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_binding_repair()
	_test_movement_direction()
	_test_spawn_recovery()
	await _test_player_state_recovery()
	await _test_integrated_wasd_lifecycle()
	if failures.is_empty():
		print("QA MOVEMENT LIFECYCLE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA MOVEMENT LIFECYCLE FAILURE: %s" % failure)
		print("QA MOVEMENT LIFECYCLE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_binding_repair() -> void:
	InputMap.erase_action(Actions.MOVE_FORWARD)
	var input_service = GameplayInputScript.new()
	var repaired: Array = input_service.ensure_bindings(true)
	root.add_child(input_service)
	_check(
		repaired.has(Actions.MOVE_FORWARD),
		"missing movement actions are repaired by the input module",
	)
	var physical_w := InputEventKey.new()
	physical_w.physical_keycode = KEY_W
	physical_w.pressed = true
	_check(
		InputMap.event_is_action(physical_w, Actions.MOVE_FORWARD),
		"physical W is mapped to forward movement",
	)
	var logical_w := InputEventKey.new()
	logical_w.keycode = KEY_W
	logical_w.pressed = true
	_check(
		InputMap.event_is_action(logical_w, Actions.MOVE_FORWARD),
		"logical W fallback is mapped to forward movement",
	)
	_check(Actions.has_required_bindings(), "all required gameplay bindings are present")
	var context = InputContextScript.new()
	root.add_child(context)
	context.set_context(InputContextScript.CONTEXT_GAMEPLAY)
	Input.action_press(Actions.MOVE_FORWARD)
	_check(Input.is_action_pressed(Actions.MOVE_FORWARD), "synthetic W state is active")
	context.set_context(InputContextScript.CONTEXT_INVENTORY)
	_check(
		not Input.is_action_pressed(Actions.MOVE_FORWARD),
		"leaving gameplay releases stale movement actions",
	)
	context.queue_free()
	input_service.queue_free()


func _test_movement_direction() -> void:
	var direction := MovementControllerScript.world_direction(Basis.IDENTITY, Vector2(0.0, -1.0))
	_check(
		direction.distance_to(Vector3.FORWARD) < 0.0001,
		"forward input resolves to the camera-facing negative Z axis",
	)
	var diagonal := MovementControllerScript.world_direction(Basis.IDENTITY, Vector2(1.0, -1.0))
	_check(is_equal_approx(diagonal.length(), 1.0), "diagonal movement is normalized")


func _test_spawn_recovery() -> void:
	var world := SpawnWorld.new()
	var resolver = SpawnResolverScript.new()
	var resolved: Vector3 = resolver.resolve(world, Vector3(0.5, 0.2, 0.5), Vector3(2.5, 1.05, 2.5))
	_check(resolved.y > 1.0, "a saved position inside terrain is moved above the surface")
	_check(
		resolver.is_position_clear(world, resolved),
		"the recovered player position has body clearance",
	)
	var below_world: Vector3 = resolver.resolve(
		world, Vector3(0.5, -50.0, 0.5), Vector3(2.5, 1.05, 2.5)
	)
	_check(below_world.y >= 1.0, "a saved position below the world is rejected")


func _test_player_state_recovery() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	player.velocity = Vector3(4.0, -9.0, 3.0)
	player.reset_motion()
	_check(player.velocity == Vector3.ZERO, "world transitions clear stale player velocity")
	player.restore_orientation({"rotation": [1.2, 9.0, -0.8], "look_pitch": deg_to_rad(120.0)})
	_check(
		is_zero_approx(player.rotation.x) and is_zero_approx(player.rotation.z),
		"restored player orientation remains yaw-only",
	)
	_check(
		player.camera_pivot.rotation.x <= deg_to_rad(89.0),
		"restored camera pitch is clamped to a usable range",
	)
	_check(
		player.jump_velocity >= sqrt(2.0 * 20.0),
		"default jump velocity can clear a one-block voxel under project gravity",
	)
	player.queue_free()
	await process_frame


func _test_integrated_wasd_lifecycle() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var state := {
		"metadata":
		{
			"id": "qa-movement",
			"name": "QA Movement",
			"map_id": "star_continent",
			"seed": 884422,
		},
		"player": {},
		"inventory": {},
		"world": {"block_overrides": {}},
		"survival": {"health": 20.0, "hunger": 20.0},
		"day_night": {"time_of_day": 9.0, "day": 1},
	}
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	var hub: Node = game.service_hub
	_check(
		hub.input_context.get_context() == InputContextScript.CONTEXT_GAMEPLAY,
		"world activation ends in the gameplay input context",
	)
	_check(game.player.input_enabled, "world activation enables the player through input context")
	_check(
		game.player.input_service == hub.gameplay_input,
		"the player receives the shared gameplay input service",
	)
	var start_position: Vector3 = game.player.global_position
	Input.action_press(Actions.MOVE_FORWARD)
	for _frame in 20:
		await physics_frame
	Input.action_release(Actions.MOVE_FORWARD)
	var moved_distance := (
		Vector2(
			game.player.global_position.x - start_position.x,
			game.player.global_position.z - start_position.z
		)
		. length()
	)
	_check(moved_distance > 0.2, "holding W moves the integrated player horizontally")

	hub.game_ui.open_inventory()
	await process_frame
	_check(not game.player.input_enabled, "inventory context disables gameplay movement")
	var blocked_position: Vector3 = game.player.global_position
	Input.action_press(Actions.MOVE_FORWARD)
	for _frame in 8:
		await physics_frame
	Input.action_release(Actions.MOVE_FORWARD)
	var blocked_distance := (
		Vector2(
			game.player.global_position.x - blocked_position.x,
			game.player.global_position.z - blocked_position.z
		)
		. length()
	)
	_check(blocked_distance < 0.01, "WASD cannot leak through a blocking UI overlay")

	hub.game_ui.close_overlay()
	await process_frame
	_check(game.player.input_enabled, "closing the overlay restores WASD movement")
	var resumed_position: Vector3 = game.player.global_position
	Input.action_press(Actions.MOVE_RIGHT)
	for _frame in 12:
		await physics_frame
	Input.action_release(Actions.MOVE_RIGHT)
	var resumed_distance := (
		Vector2(
			game.player.global_position.x - resumed_position.x,
			game.player.global_position.z - resumed_position.z
		)
		. length()
	)
	_check(resumed_distance > 0.1, "movement resumes after the UI overlay closes")

	hub.audio_service.stop_ambient()
	game.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
