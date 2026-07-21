extends SceneTree

const NotificationPolicyScript = preload(
	"res://src/husbandry/ranch_notification_policy.gd"
)
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


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
	_test_notification_policy()
	await _test_production_ranch_composition()
	if failures.is_empty():
		print("QA RANCH RUNTIME LIFECYCLE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANCH RUNTIME LIFECYCLE FAILURE: %s" % failure)
		print(
			"QA RANCH RUNTIME LIFECYCLE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_notification_policy() -> void:
	var started: Dictionary = NotificationPolicyScript.following_transition(0, 3)
	_check(str(started.get("kind", "")) == "started", "zero-to-positive following creates one start transition")
	_check(str(started.get("message", "")).contains("3 只动物"), "following start explains the attracted animal count")
	_check(NotificationPolicyScript.following_transition(3, 4).is_empty(), "positive count changes do not spam transition messages")
	var stopped: Dictionary = NotificationPolicyScript.following_transition(4, 0)
	_check(str(stopped.get("kind", "")) == "stopped", "positive-to-zero following creates one stop transition")
	var batch: Dictionary = NotificationPolicyScript.product_batch(
		{"egg":3, "raw_chicken":2},
		{"egg":"鸡蛋", "raw_chicken":"生鸡肉"},
		{"animal-a":true, "animal-b":true, "animal-c":true}
	)
	_check(int(batch.get("product_types", 0)) == 2, "product policy keeps distinct product types")
	_check(int(batch.get("total_count", 0)) == 5, "product policy aggregates the full item count")
	_check(int(batch.get("animal_count", 0)) == 3, "product policy counts unique producing animals")
	_check(str(batch.get("message", "")).contains("鸡蛋 ×3"), "product policy creates a player-readable item summary")
	var many_batch: Dictionary = NotificationPolicyScript.product_batch(
		{"a":1, "b":1, "c":1, "d":1},
		{"a":"A", "b":"B", "c":"C", "d":"D"},
		{}
	)
	_check(str(many_batch.get("message", "")).contains("等 4 类"), "product policy bounds the visible type list")


func _test_production_ranch_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 4:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle")
	var husbandry_participant: Node = hub.get("husbandry_runtime_participant")
	var participant: Node = hub.get("ranch_runtime_participant")
	var husbandry: Node = hub.get("husbandry_service")
	var interaction: Node = hub.get("husbandry_interaction")
	var attraction: Node = hub.get("animal_attraction_service")
	var products: Node = hub.get("animal_product_service")
	_check(coordinator != null, "production composition mounts the lifecycle coordinator")
	_check(husbandry_participant != null and participant != null, "production composition mounts husbandry and ranch participants")
	_check(husbandry != null and interaction != null and attraction != null and products != null, "legacy husbandry and ranch service fields remain available")
	if (
		coordinator == null
		or husbandry_participant == null
		or participant == null
		or husbandry == null
		or interaction == null
		or attraction == null
		or products == null
	):
		await _cleanup_hub(hub, "")
		return
	_check(coordinator.has_participant(&"husbandry_runtime"), "coordinator exposes the husbandry runtime feature id")
	_check(coordinator.has_participant(&"ranch_runtime"), "coordinator exposes the ranch runtime feature id")
	_check(coordinator.has_participant(&"exploration_runtime"), "production composition keeps exploration runtime")
	_check(coordinator.has_participant(&"exploration_journal_rewards"), "production composition keeps journal and rewards")
	_check(
		coordinator.get_participant_dependencies(&"ranch_runtime") == ["husbandry_runtime"],
		"ranch runtime declares its husbandry dependency"
	)
	_check(
		coordinator.get_participant_dependencies(&"exploration_journal_rewards") == ["exploration_runtime"],
		"journal and rewards retain their explicit exploration dependency"
	)
	_check(hub.get_node_or_null("AnimalHusbandryService") == husbandry, "husbandry keeps its production node path")
	_check(hub.get_node_or_null("HusbandryInteraction") == interaction, "husbandry interaction keeps its production node path")
	_check(hub.get_node_or_null("AnimalAttractionService") == attraction, "animal attraction keeps its production node path")
	_check(hub.get_node_or_null("AnimalProductService") == products, "animal products keep their production node path")
	_check(interaction.get("product_service") == products, "husbandry prompts consume the participant-owned product service")

	var state: Dictionary = hub.save_service.create_world(
		"ranch-lifecycle-%d" % Time.get_ticks_msec(),
		"star_continent",
		9431207
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "production save service creates a ranch lifecycle world")
	var normalized: Dictionary = coordinator.call("normalize_world_state", state)
	_check(normalized.has("husbandry"), "ordered participant normalization keeps the husbandry domain")
	_check(normalized.has("animal_products"), "ordered participant normalization adds the ranch product domain")
	_check(normalized.has("exploration"), "ordered participant normalization keeps the exploration domain")
	hub.call("_begin_world", state)
	var phase_counts: Dictionary = coordinator.call("get_snapshot").get("phase_counts", {})
	_check(int(phase_counts.get("normalize_world_state", 0)) >= 2, "explicit normalization is diagnosed for direct and production begin paths")

	var fake_player := FakePlayer.new()
	root.add_child(fake_player)
	coordinator.call("attach_game", null, fake_player)
	coordinator.call("activate")
	var husbandry_lifecycle: Dictionary = husbandry_participant.call("get_lifecycle_snapshot")
	_check(fake_player.entity_interaction_service == interaction, "husbandry participant binds the interaction service before ranch activation")
	_check(bool(husbandry_lifecycle.get("active", false)), "husbandry dependency activates before ranch services")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(bool(lifecycle.get("active", false)), "ranch participant activates both production services")
	_check(int(lifecycle.get("bound_player_id", 0)) == fake_player.get_instance_id(), "ranch participant owns the current player reference")

	var following_events: Array[Dictionary] = []
	participant.connect(
		"following_transition_announced",
		func(kind: String, count: int, snapshot: Dictionary) -> void:
			following_events.append({"kind":kind, "count":count, "snapshot":snapshot.duplicate(true)})
	)
	attraction.emit_signal("following_changed", 3)
	attraction.emit_signal("following_changed", 4)
	attraction.emit_signal("following_changed", 0)
	_check(following_events.size() == 2, "three follower count updates produce only start and stop announcements")
	_check(str(following_events[0].get("kind", "")) == "started", "first following announcement is the start transition")
	_check(str(following_events[1].get("kind", "")) == "stopped", "second following announcement is the stop transition")

	var product_batches: Array[Dictionary] = []
	participant.connect(
		"product_batch_announced",
		func(summary: Dictionary) -> void: product_batches.append(summary.duplicate(true))
	)
	products.emit_signal("product_spawned", _product_result("animal-a", 1))
	products.emit_signal("product_spawned", _product_result("animal-b", 1))
	products.emit_signal("product_spawned", _product_result("animal-c", 2))
	await process_frame
	await process_frame
	_check(product_batches.size() == 1, "synchronous products coalesce into one player announcement")
	if not product_batches.is_empty():
		var first_batch: Dictionary = product_batches[0]
		_check(int(first_batch.get("total_count", 0)) == 4, "coalesced product batch preserves every spawned item")
		_check(int(first_batch.get("animal_count", 0)) == 3, "coalesced product batch preserves unique animal count")
		_check(str(first_batch.get("message", "")).contains("鸡蛋 ×4"), "coalesced product batch is player-readable")
	lifecycle = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("product_batch_count", 0)) == 1, "ranch diagnostics count one coalesced batch")
	_check(int(lifecycle.get("product_item_total", 0)) == 4, "ranch diagnostics count all spawned products")
	_check(int(lifecycle.get("product_audio_count", 0)) <= 1, "one coalesced batch plays at most one pickup sound")

	var payload: Dictionary = {}
	coordinator.call("save_into", payload)
	_check(payload.has("husbandry"), "husbandry dependency contributes to the shared save payload")
	_check(payload.has("animal_products"), "ranch participant contributes to the shared save payload")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(character_snapshot.has("husbandry"), "husbandry participant preserves its legacy diagnostics field")
	_check(character_snapshot.has("animal_attraction") and character_snapshot.has("animal_products"), "ranch participant preserves legacy diagnostics fields")
	_check(int(character_snapshot.get("feature_lifecycle", {}).get("participant_count", 0)) == 5, "production diagnostics expose all five lifecycle participants")

	coordinator.call("clear", &"qa_ranch_clear")
	_check(fake_player.entity_interaction_service == null, "reverse clear unbinds the husbandry interaction service")
	lifecycle = participant.call("get_lifecycle_snapshot")
	_check(not bool(lifecycle.get("active", true)) and int(lifecycle.get("bound_player_id", -1)) == 0, "ranch clear releases the active player and services")
	var products_snapshot: Dictionary = products.call("get_snapshot")
	_check(products_snapshot.is_empty() or not bool(products_snapshot.get("active", true)), "ranch clear deactivates product processing")
	fake_player.queue_free()
	await _cleanup_hub(hub, world_id)


func _product_result(husbandry_id: String, count: int) -> Dictionary:
	return {
		"husbandry_id": husbandry_id,
		"species_id": "chicken",
		"display_name": "鸡",
		"product_item": "egg",
		"product_name": "鸡蛋",
		"count": count,
	}


func _cleanup_hub(hub: Node, world_id: String) -> void:
	if hub != null:
		if not world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
		hub.queue_free()
	for _frame in 5:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
