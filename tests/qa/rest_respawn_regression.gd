extends SceneTree

const RestPolicyScript = preload("res://src/rest/rest_policy.gd")
const RestServiceScript = preload("res://src/rest/rest_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}
	var default_spawn := Vector3(0.5, 4.0, 0.5)

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func get_spawn_position() -> Vector3:
		return default_spawn

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


class FakePlayer:
	extends Node3D
	var world_ref: Node
	var spawn_position := Vector3.ZERO

	func bind_world(p_world: Node) -> void:
		world_ref = p_world
		reset_respawn_position()

	func set_respawn_position(position: Vector3) -> bool:
		if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
			return false
		spawn_position = position
		return true

	func reset_respawn_position() -> void:
		if world_ref != null:
			spawn_position = world_ref.call("get_spawn_position")

	func get_respawn_position() -> Vector3:
		return spawn_position

	func respawn() -> void:
		global_position = spawn_position


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_policy_and_day_night_skip()
	await _test_spawn_sleep_restore_and_removal()
	await _test_obstructed_bed_rejection()
	await _test_runtime_composition_and_migration()
	if failures.is_empty():
		print("QA REST RESPAWN PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA REST RESPAWN FAILURE: %s" % failure)
		print("QA REST RESPAWN FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_policy_and_day_night_skip() -> void:
	var policy = RestPolicyScript.new()
	_check(policy.is_bed_block("oak_bed"), "rest policy recognizes the production bed block")
	_check(policy.is_sleep_time(21.0), "late evening is inside the sleep window")
	_check(policy.is_sleep_time(2.0), "early morning is inside the overnight sleep window")
	_check(not policy.is_sleep_time(12.0), "midday is outside the sleep window")
	_check(policy.get_spawn_offsets().size() >= 5, "rest policy exposes multiple safe spawn candidates")
	var day_night = DayNightScript.new()
	root.add_child(day_night)
	await process_frame
	day_night.day_count = 4
	day_night.set_time(21.0)
	var evening_skip: Dictionary = day_night.skip_to_time(6.5)
	_check(is_equal_approx(day_night.time_of_day, 6.5), "evening sleep advances to configured morning")
	_check(day_night.day_count == 5, "evening sleep advances the calendar day")
	_check(int(evening_skip.get("previous_day", 0)) == 4, "time skip reports its previous day")
	day_night.set_time(2.0)
	var early_day: int = day_night.day_count
	day_night.skip_to_time(6.5)
	_check(day_night.day_count == early_day, "after-midnight sleep stays on the current calendar day")
	day_night.queue_free()
	await process_frame


func _test_spawn_sleep_restore_and_removal() -> void:
	var host := Node.new()
	root.add_child(host)
	var world = FakeWorld.new()
	var player = FakePlayer.new()
	var day_night = DayNightScript.new()
	var rest = RestServiceScript.new()
	for node in [world, player, day_night, rest]:
		host.add_child(node)
	await process_frame
	player.bind_world(world)
	rest.setup(day_night)
	rest.attach_world(world, player)
	var bed := Vector3i(4, 10, 2)
	world.set_test_block(bed, "oak_bed")
	day_night.day_count = 2
	day_night.set_time(12.0)
	var daytime: Dictionary = rest.try_interact(world, null, bed, "oak_bed")
	_check(bool(daytime.get("success", false)), "daytime bed interaction sets a respawn point")
	_check(str(daytime.get("action", "")) == "set_spawn", "daytime interaction does not pretend to sleep")
	_check(rest.has_custom_spawn(), "rest service owns the custom spawn state")
	_check(player.get_respawn_position() != world.default_spawn, "player receives the resolved bed spawn")
	_check(is_equal_approx(day_night.time_of_day, 12.0), "setting a daytime spawn does not change time")
	var saved: Dictionary = rest.serialize()
	_check(bool(saved.get("has_custom_spawn", false)), "custom spawn serializes")
	var restored_player = FakePlayer.new()
	var restored = RestServiceScript.new()
	host.add_child(restored_player)
	host.add_child(restored)
	await process_frame
	restored_player.bind_world(world)
	restored.setup(day_night)
	_check(restored.deserialize(saved), "rest state deserializes")
	restored.attach_world(world, restored_player)
	_check(restored.has_custom_spawn(), "valid saved bed restores a custom spawn")
	_check(
		restored_player.get_respawn_position().is_equal_approx(player.get_respawn_position()),
		"restored player receives the same safe spawn",
	)
	day_night.day_count = 7
	day_night.set_time(21.0)
	var night: Dictionary = restored.try_interact(world, null, bed, "oak_bed")
	_check(bool(night.get("success", false)), "night bed interaction succeeds")
	_check(str(night.get("action", "")) == "sleep", "night interaction uses the sleep action")
	_check(is_equal_approx(day_night.time_of_day, 6.5), "sleep wakes at morning")
	_check(day_night.day_count == 8, "night sleep advances to the next day")
	restored_player.global_position = Vector3(50.0, 50.0, 50.0)
	restored_player.respawn()
	_check(
		restored_player.global_position.is_equal_approx(restored.get_respawn_position()),
		"player respawn returns to the bed spawn",
	)
	restored.on_block_removed(world, bed, "oak_bed")
	_check(not restored.has_custom_spawn(), "breaking the active bed clears custom spawn state")
	_check(
		restored_player.get_respawn_position().is_equal_approx(world.default_spawn),
		"breaking the bed restores the world spawn",
	)
	host.queue_free()
	await process_frame
	await process_frame


func _test_obstructed_bed_rejection() -> void:
	var host := Node.new()
	root.add_child(host)
	var world = FakeWorld.new()
	var player = FakePlayer.new()
	var day_night = DayNightScript.new()
	var rest = RestServiceScript.new()
	for node in [world, player, day_night, rest]:
		host.add_child(node)
	await process_frame
	player.bind_world(world)
	rest.setup(day_night)
	rest.attach_world(world, player)
	var bed := Vector3i(8, 12, -2)
	world.set_test_block(bed, "oak_bed")
	world.set_test_block(bed + Vector3i.UP, "stone")
	var rejected: Dictionary = rest.try_interact(world, null, bed, "oak_bed")
	_check(str(rejected.get("reason", "")) == "spawn_obstructed", "blocked beds explain spawn rejection")
	_check(not rest.has_custom_spawn(), "blocked beds do not replace the current spawn")
	_check(player.get_respawn_position().is_equal_approx(world.default_spawn), "rejection keeps the world spawn")
	host.queue_free()
	await process_frame
	await process_frame


func _test_runtime_composition_and_migration() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get_node_or_null("RestService") != null, "service hub mounts the rest domain")
	_check(hub.get("rest_service") != null, "composition root exposes rest diagnostics and saves")
	_check(
		int(hub.block_interaction.call("get_extension_count")) >= 2,
		"rest registers through the generic interaction extension port",
	)
	var migrated: Dictionary = hub.save_service.call(
		"_migrate", {"save_version": 2, "metadata": {}, "inventory": {}}
	)
	_check(migrated.get("rest", null) is Dictionary, "old saves migrate an empty rest state")
	var state: Dictionary = hub.save_service.create_world(
		"rest-regression-%d" % Time.get_ticks_msec(), "star_continent", 424242
	)
	_check(state.get("rest", null) is Dictionary, "new worlds include rest in the atomic state")
	if not state.is_empty():
		hub.save_service.delete_world(str(state.get("metadata", {}).get("id", "")))
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
