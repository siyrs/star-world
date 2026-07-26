extends SceneTree

const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FailingSaveService:
	extends Node

	func save_world(_world_id: String, _state: Dictionary) -> bool:
		return false


class FakeWorld:
	extends Node
	var profile_id := "star_continent"
	var blocks: Dictionary = {}

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(
			floori(float(position.x) / 16.0), floori(float(position.z) / 16.0)
		)

	func get_initial_block(position: Vector3i) -> String:
		return get_block(position)

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		blocks[_key(position)] = block_id
		return true

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, maxf(1.05, candidate.y), candidate.z)

	func serialize_state() -> Dictionary:
		return {"version":1, "block_overrides":blocks.duplicate(true)}

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var authoritative_save: Node = hub.get("save_service") as Node
	var report: Node = hub.get("runtime_health_report_service") as Node
	_check(
		authoritative_save != null and report != null,
		"production hub exposes authoritative save and runtime health services"
	)
	var state: Dictionary = authoritative_save.call(
		"create_world",
		"qa-health-failed-return-%d" % Time.get_ticks_msec(),
		"star_continent",
		420726
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "failed-return regression creates a temporary world")
	if world_id.is_empty():
		await _finish(hub, authoritative_save, world_id)
		return
	hub.call("_begin_world", state)
	var world := FakeWorld.new()
	var player := Node3D.new()
	root.add_child(world)
	root.add_child(player)
	hub.call("attach_game", world, player)
	_check(
		bool(report.call("get_snapshot").get("world_attached", false)),
		"runtime health observes the active production world"
	)

	var failing_save := FailingSaveService.new()
	failing_save.name = "FailingSaveFixture"
	hub.add_child(failing_save)
	hub.set("save_service", failing_save)
	hub.call("return_to_menu")
	var failed_snapshot: Dictionary = report.call("get_snapshot")
	_check(
		str(hub.get("current_world_id")) == world_id,
		"failed final save keeps the player in the current world"
	)
	_check(
		bool(failed_snapshot.get("world_attached", false)),
		"failed final save keeps F3 attached to the world still in use"
	)
	_check(
		int(failed_snapshot.get("save", {}).get("failure_count", 0)) >= 1
		and not bool(failed_snapshot.get("save", {}).get("last_success", true)),
		"failed final save remains visible as critical operational evidence"
	)

	hub.set("save_service", authoritative_save)
	failing_save.queue_free()
	hub.call("return_to_menu")
	var completed_snapshot: Dictionary = report.call("get_snapshot")
	_check(
		str(hub.get("current_world_id")).is_empty(),
		"successful final save completes the real return-to-menu path"
	)
	_check(
		not bool(completed_snapshot.get("world_attached", true)),
		"runtime health detaches only after world ownership is actually released"
	)
	await _finish(hub, authoritative_save, world_id)
	world.queue_free()
	player.queue_free()
	await process_frame


func _finish(hub: Node, save: Node, world_id: String) -> void:
	if save != null and is_instance_valid(save) and not world_id.is_empty():
		if bool(save.call("world_exists", world_id)):
			save.call("delete_world", world_id)
	if hub != null and is_instance_valid(hub):
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
		hub.queue_free()
	for _frame in 6:
		await process_frame
	if failures.is_empty():
		print("QA RUNTIME HEALTH FAILED RETURN PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RUNTIME HEALTH FAILED RETURN FAILURE: %s" % failure)
		print(
			"QA RUNTIME HEALTH FAILED RETURN FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
