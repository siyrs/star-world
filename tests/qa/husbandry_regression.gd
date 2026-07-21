extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const HusbandryScript = preload("res://src/husbandry/animal_husbandry_service.gd")
const RegistryScript = preload("res://src/husbandry/husbandry_registry.gd")
const PolicyScript = preload("res://src/husbandry/husbandry_policy.gd")
const PopulationPolicyScript = preload("res://src/entity/creature_population_policy.gd")
const SaveScript = preload("res://src/save/save_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeAnimal:
	extends CharacterBody3D
	signal died(species_id: String, drops: Dictionary, world_position: Vector3)
	var species_id: String = "cow"
	var display_name: String = "牛"
	var max_health: float = 10.0
	var health: float = 10.0

	func configure(p_species_id: String, p_display_name: String) -> void:
		species_id = p_species_id
		display_name = p_display_name
		add_to_group("creatures")
		add_to_group("animals")

	func die_for_test() -> void:
		died.emit(species_id, {}, global_position)


class FakeSpawner:
	extends Node3D
	var spawned: Array[Node3D] = []
	var names := {"chicken":"鸡", "cow":"牛", "pig":"猪"}

	func spawn_creature(species_id: String, fixed_position: Variant = null):
		var animal := FakeAnimal.new()
		animal.configure(species_id, str(names.get(species_id, species_id)))
		add_child(animal)
		animal.global_position = fixed_position if fixed_position is Vector3 else Vector3.ZERO
		spawned.append(animal)
		return animal


class FakeWorld:
	extends Node3D
	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, maxf(1.05, candidate.y), candidate.z)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_and_policy()
	await _test_breeding_growth_and_transactions()
	await _test_persistence_population_and_migration()
	await _test_composition_root()
	if failures.is_empty():
		print("QA HUSBANDRY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HUSBANDRY FAILURE: %s" % failure)
		print("QA HUSBANDRY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var registry = RegistryScript.new()
	var policy = PolicyScript.new()
	_check(registry.species_count() == 3, "husbandry registry loads three passive species")
	_check(str(registry.get_species("chicken").get("feed_item", "")) == "wheat_seeds", "chickens use wheat seeds")
	_check(str(registry.get_species("cow").get("feed_item", "")) == "wheat", "cows use wheat")
	_check(str(registry.get_species("pig").get("feed_item", "")) == "carrot", "pigs use carrots")
	_check(not registry.supports_species("zombie"), "hostile zombies are excluded from husbandry")
	var adult := {
		"species_id":"cow",
		"stage":"adult",
		"growth_remaining_seconds":0.0,
		"breed_cooldown_seconds":0.0,
		"love_remaining_seconds":0.0,
	}
	var feed: Dictionary = policy.evaluate_feed(registry.get_species("cow"), adult, "wheat", 1, 24)
	_check(bool(feed.get("success", false)), "policy accepts the correct adult feed")
	_check(StringName(feed.get("action", "")) == &"enter_love", "adult feed enters breeding readiness")
	var wrong: Dictionary = policy.evaluate_feed(registry.get_species("cow"), adult, "carrot", 1, 24)
	_check(str(wrong.get("reason", "")) == "wrong_feed", "policy rejects incorrect feed")
	var baby := adult.duplicate(true)
	baby["stage"] = "baby"
	baby["growth_remaining_seconds"] = 100.0
	var accelerated: Dictionary = policy.evaluate_feed(registry.get_species("cow"), baby, "wheat", 1, 24)
	_check(StringName(accelerated.get("action", "")) == &"accelerate_growth", "baby feed accelerates growth")
	_check(float(accelerated.get("target_growth_remaining_seconds", 100.0)) < 100.0, "baby growth target decreases")


func _test_breeding_growth_and_transactions() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var spawner = FakeSpawner.new()
	var world = FakeWorld.new()
	var player := Node3D.new()
	var service = HusbandryScript.new()
	for node in [inventory, spawner, world, player, service]:
		host.add_child(node)
	await process_frame
	service.setup(inventory.registry, inventory, spawner)
	service.attach_world(world, player)
	service.activate()
	var first: FakeAnimal = spawner.spawn_creature("cow", Vector3(0.0, 1.05, -2.0))
	var second: FakeAnimal = spawner.spawn_creature("cow", Vector3(2.0, 1.05, -2.0))
	inventory.clear()
	inventory.add_item("wheat", 2, {"batch":"breeding"})
	inventory.select_slot(0)
	var first_result: Dictionary = service.interact_entity(first, inventory)
	_check(bool(first_result.get("success", false)), "feeding the first cow succeeds")
	_check(StringName(first_result.get("action", "")) == &"prepare_breeding", "first cow enters breeding readiness")
	_check(inventory.count_item("wheat") == 1, "first feed consumes exactly one wheat")
	_check(service.get_managed_count() == 1, "first fed natural animal becomes managed")
	_check(first.is_in_group("persistent_creatures"), "managed parent is protected from natural despawn")
	var second_result: Dictionary = service.interact_entity(second, inventory)
	_check(bool(second_result.get("success", false)), "feeding the nearby second cow succeeds")
	_check(StringName(second_result.get("action", "")) == &"breed_animals", "second feed completes breeding")
	_check(inventory.count_item("wheat") == 0, "breeding consumes the second wheat exactly once")
	_check(service.get_managed_count() == 3, "two parents and one baby are persisted")
	var baby_id := str(second_result.get("husbandry_id", ""))
	var baby_record: Dictionary = service.get_record(baby_id)
	_check(str(baby_record.get("stage", "")) == "baby", "newborn record starts in baby stage")
	var baby_entity: Node3D = _find_managed_entity(spawner, baby_id)
	_check(baby_entity != null, "breeding creates a live baby creature")
	_check(baby_entity != null and baby_entity.scale.x < 0.7, "baby receives a smaller visual scale")
	_check(
		float(service.get_record(str(first.get_meta("husbandry_id", ""))).get("breed_cooldown_seconds", 0.0)) > 0.0,
		"parents enter a breeding cooldown",
	)
	inventory.add_item("wheat", 1, {"batch":"growth"})
	inventory.select_slot(0)
	var growth_before := float(service.get_record(baby_id).get("growth_remaining_seconds", 0.0))
	var growth_result: Dictionary = service.interact_entity(baby_entity, inventory)
	_check(StringName(growth_result.get("action", "")) == &"feed_baby", "feeding a baby uses the growth action")
	_check(float(service.get_record(baby_id).get("growth_remaining_seconds", 0.0)) < growth_before, "feeding reduces remaining growth time")
	_check(inventory.count_item("wheat") == 0, "baby feeding consumes one feed item")

	var pig: FakeAnimal = spawner.spawn_creature("pig", Vector3(4.0, 1.05, -2.0))
	inventory.add_item("wheat", 1, {"batch":"wrong"})
	inventory.select_slot(0)
	var managed_before := service.get_managed_count()
	var wrong_result: Dictionary = service.interact_entity(pig, inventory)
	_check(str(wrong_result.get("reason", "")) == "wrong_feed", "wrong feed is rejected with an explicit reason")
	_check(inventory.count_item("wheat") == 1, "wrong feed is not consumed")
	_check(service.get_managed_count() == managed_before, "wrong feed does not adopt the animal")

	var saved: Dictionary = service.serialize()
	_check((saved.get("animals", {}) as Dictionary).size() == 3, "managed animals serialize as one bounded domain")
	var first_id := str(first.get_meta("husbandry_id", ""))
	first.die_for_test()
	_check(service.get_record(first_id).is_empty(), "managed animal death removes its persistence record")
	service.clear()
	host.queue_free()
	await process_frame
	await process_frame


func _test_persistence_population_and_migration() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var spawner = FakeSpawner.new()
	var world = FakeWorld.new()
	var player := Node3D.new()
	var service = HusbandryScript.new()
	for node in [inventory, spawner, world, player, service]:
		host.add_child(node)
	await process_frame
	service.setup(inventory.registry, inventory, spawner)
	var saved_at := int(Time.get_unix_time_from_system()) - 1000
	var saved_state := {
		"version":1,
		"saved_at_unix":saved_at,
		"animals":{
			"animal@qa-baby":{
				"species_id":"cow",
				"position":[1.0, 1.05, 2.0],
				"stage":"baby",
				"growth_remaining_seconds":420.0,
				"breed_cooldown_seconds":240.0,
				"love_remaining_seconds":30.0,
				"health":10.0,
			}
		}
	}
	service.deserialize(saved_state)
	var offline_record: Dictionary = service.get_record("animal@qa-baby")
	_check(str(offline_record.get("stage", "")) == "adult", "offline time advances a baby to adulthood")
	_check(float(offline_record.get("breed_cooldown_seconds", 1.0)) == 0.0, "offline time advances breeding cooldown")
	_check(float(offline_record.get("love_remaining_seconds", 1.0)) == 0.0, "offline time expires breeding readiness")
	service.attach_world(world, player)
	service.activate()
	_check(spawner.spawned.size() == 1, "loading restores each managed animal exactly once")
	_check(spawner.spawned[0].is_in_group("persistent_creatures"), "restored animal remains persistent")
	_check(is_equal_approx(spawner.spawned[0].scale.x, 1.0), "offline-grown animal restores at adult scale")

	var natural := FakeAnimal.new()
	natural.configure("cow", "牛")
	host.add_child(natural)
	natural.global_position = Vector3(100.0, 1.0, 0.0)
	spawner.spawned[0].global_position = Vector3(100.0, 1.0, 0.0)
	player.global_position = Vector3.ZERO
	var culled: Array[Node] = PopulationPolicyScript.collect_out_of_range(spawner, player, 56.0)
	_check(spawner.spawned[0] not in culled, "population policy never despawns managed animals")
	var policy_root := Node3D.new()
	host.add_child(policy_root)
	# add_child() rejects nodes that already have a parent; move with reparent().
	natural.reparent(policy_root)
	var natural_culled: Array[Node] = PopulationPolicyScript.collect_out_of_range(policy_root, player, 56.0)
	_check(natural in natural_culled, "unmanaged distant animals remain eligible for despawn")

	var save_service = SaveScript.new()
	host.add_child(save_service)
	await process_frame
	var migrated: Dictionary = save_service.call(
		"_migrate", {"save_version":2, "metadata":{}, "inventory":{}}
	)
	_check(migrated.has("husbandry"), "old saves receive an empty husbandry domain")
	_check((migrated.get("husbandry", {}).get("animals", {}) as Dictionary).is_empty(), "husbandry migration never invents animals")
	service.clear()
	host.queue_free()
	await process_frame
	await process_frame


func _test_composition_root() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get("husbandry_service") != null, "composition root mounts husbandry service")
	_check(hub.get("husbandry_interaction") != null, "composition root mounts entity interaction adapter")
	_check(
		hub.player_experience.get_status().get("entity_interaction_attached", false),
		"player experience receives the entity interaction contract",
	)
	_check(
		hub is HusbandryProgressionServiceHub,
		"production service scene selects the husbandry composition root",
	)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _find_managed_entity(spawner: Node, husbandry_id: String) -> Node3D:
	for child in spawner.get_children():
		if child is Node3D and str(child.get_meta("husbandry_id", "")) == husbandry_id:
			return child
	return null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
