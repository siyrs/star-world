extends SceneTree

const PlayerScene = preload("res://scenes/game/player.tscn")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const FactoryScript = preload("res://src/entity/creature_factory.gd")

var checks := 0
var failures: Array[String] = []


class WaterWorld:
	extends Node

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func get_block(position: Vector3i) -> String:
		return "water" if position.y >= 0 and position.y <= 3 else "air"

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, 1.05, candidate.z)

	func get_spawn_position() -> Vector3:
		return Vector3(0.5, 1.2, 0.5)


class SwimInput:
	extends Node

	var movement := Vector2(0.0, -1.0)
	var swim_up := false

	func ensure_bindings() -> void:
		pass

	func get_movement_vector() -> Vector2:
		return movement

	func is_jump_just_pressed() -> bool:
		return false

	func is_jump_pressed() -> bool:
		return swim_up

	func is_sprint_pressed() -> bool:
		return false

	func get_hotbar_selection_just_pressed() -> int:
		return -1

	func is_quick_save_just_pressed() -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_water_movement()
	await _test_hostile_damage_pacing()
	_test_passive_survival_pacing()
	if failures.is_empty():
		print("QA WATER SURVIVAL PASS | checks=%d" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("QA WATER SURVIVAL FAILURE: %s" % failure)
	print("QA WATER SURVIVAL FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_water_movement() -> void:
	var host := Node3D.new()
	var world := WaterWorld.new()
	var input := SwimInput.new()
	var survival = SurvivalScript.new()
	var player = PlayerScene.instantiate()
	root.add_child(host)
	host.add_child(world)
	host.add_child(input)
	host.add_child(survival)
	host.add_child(player)
	await process_frame
	player.set_physics_process(false)
	player.bind_world(world)
	player.bind_input_service(input)
	player.bind_survival(survival)
	player.global_position = Vector3(0.5, 1.2, 0.5)
	player.set_input_enabled(true)
	_check(bool(player.call("_is_in_fluid")), "water is detected around the player's body")
	var start: Vector3 = player.global_position
	player.call("_physics_process", 0.5)
	_check(
		Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
		> 0.15,
		"WASD produces horizontal movement while submerged"
	)
	_check(
		player.global_position.y < 1.8,
		"water movement does not snap the player onto the terrain surface"
	)
	input.swim_up = true
	player.velocity.y = 0.0
	var saturation_before: float = survival.saturation
	for _frame in 10:
		player.call("_physics_process", 0.02)
	_check(player.velocity.y > 0.0, "holding Space produces sustained upward swim velocity")
	_check(
		is_equal_approx(survival.saturation, saturation_before),
		"holding swim-up does not consume jump exhaustion every frame"
	)
	host.queue_free()
	await process_frame


func _test_hostile_damage_pacing() -> void:
	var host := Node.new()
	var world := WaterWorld.new()
	var survival = SurvivalScript.new()
	var player = PlayerScene.instantiate()
	root.add_child(host)
	host.add_child(world)
	host.add_child(survival)
	host.add_child(player)
	await process_frame
	player.set_physics_process(false)
	player.bind_survival(survival)
	player.bind_world(world)
	_check(
		float(player.get("_hostile_damage_grace_remaining")) >= 89.0,
		"loading a world gives the player enough time to get oriented safely"
	)
	var initial_health: float = survival.health
	player.take_damage(1.0, "zombie")
	_check(
		is_equal_approx(survival.health, initial_health),
		"world-entry grace prevents an unseen immediate zombie hit"
	)
	player.set("_hostile_damage_grace_remaining", 0.0)
	player.take_damage(1.0, "zombie")
	_check(
		is_equal_approx(survival.health, initial_health - 1.0),
		"a zombie hit applies the reduced configured damage"
	)
	player.take_damage(1.0, "zombie")
	_check(
		is_equal_approx(survival.health, initial_health - 1.0),
		"rapid repeated zombie hits are ignored during hurt cooldown"
	)
	var factory = FactoryScript.new()
	var zombie = factory.create("zombie", Vector3.ZERO, player)
	_check(is_equal_approx(float(zombie.attack_damage), 1.0), "zombie base damage is survivable")
	zombie.queue_free()
	host.queue_free()
	await process_frame


func _test_passive_survival_pacing() -> void:
	var survival = SurvivalScript.new()
	survival.saturation = 0.0
	survival.hunger = 20.0
	survival.call("_process", 60.0)
	_check(
		is_equal_approx(survival.hunger, 20.0),
		"one idle minute does not consume a hunger point"
	)
	survival.call("_process", 31.0)
	_check(
		is_equal_approx(survival.hunger, 19.0),
		"passive hunger decreases gradually after the relaxed interval"
	)
	survival.call("_process", 80.0)
	survival.deserialize(
		{"health": 20.0, "hunger": 20.0, "saturation": 0.0, "alive": true}
	)
	survival.call("_process", 20.0)
	_check(
		is_equal_approx(survival.hunger, 20.0),
		"loading a save resets stale passive hunger timing"
	)
	survival.hunger = 0.0
	var health_before: float = survival.health
	survival.call("_process", 7.0)
	_check(
		is_equal_approx(survival.health, health_before),
		"starvation does not damage the player every few seconds"
	)
	survival.call("_process", 1.1)
	_check(
		is_equal_approx(survival.health, health_before - 1.0),
		"starvation damage remains gradual after its longer interval"
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
