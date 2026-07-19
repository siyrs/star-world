extends SceneTree

const MigrationScript = preload("res://src/husbandry/husbandry_state_migration.gd")
const NotificationPolicyScript = preload(
	"res://src/husbandry/husbandry_notification_policy.gd"
)
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var profile_id := "star_continent"

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(floori(float(position.x) / 16.0), floori(float(position.z) / 16.0))

	func get_initial_block(position: Vector3i) -> String:
		return "stone" if position.y >= 1 and position.y <= 63 else "air"

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, maxf(1.05, candidate.y), candidate.z)


class FakePlayer:
	extends Node3D
	var entity_interaction_service: Node
	var prospecting_service: Node

	func bind_entity_interaction_service(service: Node) -> void:
		entity_interaction_service = service

	func bind_prospecting_service(service: Node) -> void:
		prospecting_service = service


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_state_migration()
	_test_notification_policy()
	await _test_production_composition()
	if failures.is_empty():
		print("QA HUSBANDRY RUNTIME LIFECYCLE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HUSBANDRY RUNTIME LIFECYCLE FAILURE: %s" % failure)
		print(
			"QA HUSBANDRY RUNTIME LIFECYCLE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_state_migration() -> void:
	var normalized: Dictionary = MigrationScript.normalize_husbandry_state(
		{
			"version":0,
			"saved_at_unix":-10,
			"animals":{
				"animal@cow":{
					"species_id":"cow",
					"position":[1.0, 2.0, 3.0],
					"stage":"baby",
					"growth_remaining_seconds":999999.0,
					"breed_cooldown_seconds":-5.0,
					"love_remaining_seconds":12.0,
					"health":10.0,
					"unknown_field":"remove-me",
				},
				"animal@zombie":{
					"species_id":"zombie",
					"position":[0.0, 1.0, 0.0],
				},
				"animal@invalid-position":{
					"species_id":"pig",
					"position":[INF, 1.0, 0.0],
				},
			},
		}
	)
	_check(int(normalized.get("version", 0)) == 1, "husbandry migration stabilizes version 1")
	_check(int(normalized.get("saved_at_unix", -1)) == 0, "negative save timestamps are normalized")
	var animals: Dictionary = normalized.get("animals", {})
	_check(animals.size() == 1 and animals.has("animal@cow"), "migration rejects hostile and invalid-position records")
	var cow: Dictionary = animals.get("animal@cow", {})
	_check(float(cow.get("growth_remaining_seconds", 0.0)) == 86400.0, "growth timers respect the migration hard bound")
	_check(float(cow.get("breed_cooldown_seconds", -1.0)) == 0.0, "negative cooldowns are clamped")
	_check(not cow.has("unknown_field"), "husbandry migration uses a strict record whitelist")
	var missing: Dictionary = MigrationScript.normalize_world_state({"metadata":{}})
	_check((missing.get("husbandry", {}).get("animals", {}) as Dictionary).is_empty(), "old worlds receive an empty husbandry domain")


func _test_notification_policy() -> void:
	var events: Array[Dictionary] = [
		{"kind":"newborn", "result":{"husbandry_id":"baby-1", "display_name":"幼年牛"}},
		{"kind":"newborn", "result":{"husbandry_id":"baby-2", "display_name":"牛"}},
		{"kind":"grown", "result":{"husbandry_id":"pig-1", "display_name":"幼年猪"}},
		{"kind":"ignored", "result":{"husbandry_id":"none"}},
	]
	var summary: Dictionary = NotificationPolicyScript.lifecycle_batch(events)
	_check(int(summary.get("newborn_count", 0)) == 2, "notification policy preserves all newborn events")
	_check(int(summary.get("grown_count", 0)) == 1, "notification policy preserves all growth events")
	_check(int(summary.get("animal_count", 0)) == 3, "notification policy counts unique affected animals")
	_check(str(summary.get("message", "")).contains("幼年牛 ×2"), "notification policy groups matching newborn species")
	_check(str(summary.get("message", "")).contains("猪 ×1"), "growth summary removes the baby prefix")
	_check(str(summary.get("audio", "")) == "craft", "newborn batches request one craft sound")


func _test_production_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 4:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle")
	var participant: Node = hub.get("husbandry_runtime_participant")
	var ranch_participant: Node = hub.get("ranch_runtime_participant")
	var service: Node = hub.get("husbandry_service")
	var interaction: Node = hub.get("husbandry_interaction")
	_check(
		coordinator != null
		and coordinator.has_participant(&"husbandry_runtime")
		and coordinator.has_participant(&"ranch_runtime")
		and coordinator.has_participant(&"exploration_runtime")
		and coordinator.has_participant(&"exploration_journal_rewards"),
		"production hub registers all four lifecycle participants"
	)
	_check(participant != null and ranch_participant != null, "production hub exposes husbandry and ranch participants")
	_check(service != null and interaction != null, "legacy husbandry public service fields remain available")
	_check(hub.get_node_or_null("AnimalHusbandryService") == service, "husbandry service keeps its production node path")
	_check(hub.get_node_or_null("HusbandryInteraction") == interaction, "husbandry interaction keeps its production node path")
	_check(
		coordinator.get_participant_dependencies(&"ranch_runtime") == ["husbandry_runtime"],
		"ranch runtime explicitly depends on husbandry runtime"
	)

	var world_state: Dictionary = hub.save_service.create_world(
		"husbandry-lifecycle-%d" % Time.get_ticks_msec(),
		"star_continent",
		4371259
	)
	var world_id := str(world_state.get("metadata", {}).get("id", ""))
	world_state["husbandry"] = {
		"version":1,
		"saved_at_unix":int(Time.get_unix_time_from_system()),
		"animals":{
			"animal@persisted":{
				"species_id":"cow",
				"position":[0.0, 1.05, -2.0],
				"stage":"adult",
				"growth_remaining_seconds":0.0,
				"breed_cooldown_seconds":0.0,
				"love_remaining_seconds":0.0,
				"health":10.0,
			}
		},
	}
	hub.call("_begin_world", world_state)
	var fake_world := FakeWorld.new()
	var fake_player := FakePlayer.new()
	fake_player.global_position = Vector3(0.5, 16.0, 0.5)
	root.add_child(fake_world)
	root.add_child(fake_player)
	coordinator.call("attach_game", fake_world, fake_player)
	coordinator.call("activate")
	_check(fake_player.entity_interaction_service == interaction, "husbandry participant binds the interaction port to the active player")
	_check(bool(service.get("_active")), "husbandry participant activates the production service")
	_check(service.get_managed_count() == 1, "husbandry participant restores the persisted animal record")

	var batches: Array[Dictionary] = []
	participant.connect(
		"lifecycle_batch_announced",
		func(summary: Dictionary) -> void: batches.append(summary.duplicate(true))
	)
	service.emit_signal("baby_born", {"husbandry_id":"baby-a", "display_name":"幼年牛"})
	service.emit_signal("baby_born", {"husbandry_id":"baby-b", "display_name":"牛"})
	service.emit_signal("animal_grew", {"husbandry_id":"pig-a", "display_name":"幼年猪"})
	var batch: Dictionary = participant.call("flush_pending_lifecycle_batch")
	_check(batches.size() == 1, "three synchronous lifecycle events create one participant batch")
	_check(int(batch.get("newborn_count", 0)) == 2 and int(batch.get("grown_count", 0)) == 1, "production participant batch preserves event totals")
	var participant_snapshot: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(participant_snapshot.get("lifecycle_batch_count", 0)) == 1, "husbandry diagnostics count one lifecycle batch")
	_check(int(participant_snapshot.get("lifecycle_audio_count", 0)) == 1, "newborn batch plays exactly one craft sound")

	var payload: Dictionary = {}
	coordinator.call("save_into", payload)
	_check((payload.get("husbandry", {}).get("animals", {}) as Dictionary).has("animal@persisted"), "husbandry participant contributes records to the shared save payload")
	var snapshot: Dictionary = {}
	coordinator.call("snapshot_into", snapshot)
	_check(snapshot.has("husbandry") and snapshot.has("animal_products"), "husbandry and dependent ranch diagnostics share one snapshot")

	coordinator.call("clear", &"qa_husbandry_clear")
	_check(fake_player.entity_interaction_service == null, "reverse cleanup unbinds the old entity interaction port")
	_check((service.call("get_snapshot") as Dictionary).get("managed_animals", -1) == 0, "husbandry clear removes managed runtime state")
	var history: Array = (coordinator.call("get_snapshot") as Dictionary).get("phase_history", [])
	_check(
		not history.is_empty()
		and str(history.back()).contains(
			"exploration_journal_rewards,exploration_runtime,ranch_runtime,husbandry_runtime"
		),
		"clear history records full reverse dependency order"
	)
	coordinator.call("shutdown")
	_check(interaction.get("service") == null, "shutdown disconnects the husbandry interaction adapter")
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	fake_player.queue_free()
	fake_world.queue_free()
	hub.queue_free()
	for _frame in 5:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
