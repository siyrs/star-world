extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const AttractionRegistryScript = preload(
	"res://src/husbandry/animal_attraction_registry.gd"
)
const AttractionPolicyScript = preload(
	"res://src/husbandry/animal_attraction_policy.gd"
)
const AttractionServiceScript = preload(
	"res://src/husbandry/animal_attraction_service.gd"
)
const ProductRegistryScript = preload(
	"res://src/husbandry/animal_product_registry.gd"
)
const ProductPolicyScript = preload(
	"res://src/husbandry/animal_product_policy.gd"
)
const ProductServiceScript = preload(
	"res://src/husbandry/animal_product_service.gd"
)
const ProductMigrationScript = preload(
	"res://src/husbandry/animal_product_state_migration.gd"
)
const FurnaceRegistryScript = preload(
	"res://src/machine/furnace_recipe_registry.gd"
)
const ChickenScript = preload("res://src/entity/chicken.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeAnimal:
	extends Node3D
	var species_id: String = "chicken"
	var attraction_target: Node3D
	var attraction_duration: float = 0.0
	var attraction_stop_distance: float = 0.0
	var attraction_calls: int = 0
	var clear_calls: int = 0

	func _ready() -> void:
		add_to_group("animals")
		add_to_group("creatures")

	func set_attraction_target(
		target: Node3D, duration_seconds: float, stop_distance: float
	) -> void:
		attraction_target = target
		attraction_duration = duration_seconds
		attraction_stop_distance = stop_distance
		attraction_calls += 1

	func clear_attraction_target() -> void:
		attraction_target = null
		clear_calls += 1


class FakeHusbandry:
	extends Node
	signal state_changed(entity_id: int)
	var managed: Dictionary = {}
	var live: Dictionary = {}

	func set_record(husbandry_id: String, record: Dictionary, entity: Node3D) -> void:
		managed[husbandry_id] = record.duplicate(true)
		live[husbandry_id] = entity
		entity.set_meta("husbandry_id", husbandry_id)
		state_changed.emit(entity.get_instance_id())

	func get_managed_records() -> Dictionary:
		return managed.duplicate(true)

	func get_record(husbandry_id: String) -> Dictionary:
		return managed.get(husbandry_id, {}).duplicate(true)

	func get_live_entity(husbandry_id: String) -> Node3D:
		var value: Variant = live.get(husbandry_id)
		return value as Node3D if value is Node3D and is_instance_valid(value) else null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registries_and_policies()
	await _test_generic_creature_attraction()
	await _test_attraction_service()
	await _test_product_transactions_and_offline_state()
	await _test_composition_root()
	if failures.is_empty():
		print("QA RANCH PRODUCTS PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANCH PRODUCTS FAILURE: %s" % failure)
		print(
			"QA RANCH PRODUCTS FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_registries_and_policies() -> void:
	var attraction_registry = AttractionRegistryScript.new()
	var attraction_policy = AttractionPolicyScript.new()
	var product_registry = ProductRegistryScript.new()
	var product_policy = ProductPolicyScript.new()
	_check(attraction_registry.species_count() == 3, "attraction registry loads three passive species")
	var chicken_attraction: Dictionary = attraction_registry.get_profile("chicken")
	_check(float(chicken_attraction.get("follow_radius", 0.0)) == 9.0, "chicken attraction radius is data driven")
	var follow: Dictionary = attraction_policy.evaluate(
		chicken_attraction, "wheat_seeds", "wheat_seeds", 5.0
	)
	_check(bool(follow.get("should_follow", false)), "correct feed attracts a nearby chicken")
	_check(not bool(follow.get("hold_position", true)), "distant attracted chicken keeps moving")
	var hold: Dictionary = attraction_policy.evaluate(
		chicken_attraction, "wheat_seeds", "wheat_seeds", 1.0
	)
	_check(bool(hold.get("hold_position", false)), "attracted chicken stops near the player")
	var wrong: Dictionary = attraction_policy.evaluate(
		chicken_attraction, "wheat_seeds", "carrot", 5.0
	)
	_check(str(wrong.get("reason", "")) == "wrong_feed", "wrong feed never attracts the chicken")
	_check(product_registry.profile_count() == 1, "product registry loads the first production profile")
	var egg_profile: Dictionary = product_registry.get_profile_for_species("chicken")
	_check(str(egg_profile.get("product_item", "")) == "egg", "managed chickens produce eggs")
	var adult := {"species_id":"chicken", "stage":"adult"}
	var baby := {"species_id":"chicken", "stage":"baby"}
	_check(product_policy.is_eligible(egg_profile, adult), "adult managed chicken is product eligible")
	_check(not product_policy.is_eligible(egg_profile, baby), "baby chicken cannot produce eggs")
	var advanced: Dictionary = product_policy.advance(
		egg_profile,
		{"species_id":"chicken", "remaining_seconds":0.1, "pending_count":0},
		1.0
	)
	_check(int(advanced.get("produced_count", 0)) == 1, "product policy advances a ready timer exactly once")
	var capped: Dictionary = product_policy.advance(
		egg_profile,
		{"species_id":"chicken", "remaining_seconds":0.0, "pending_count":6},
		1000.0
	)
	_check(int((capped.get("state", {}) as Dictionary).get("pending_count", 0)) == 6, "product policy enforces the pending cap")
	var furnace = FurnaceRegistryScript.new()
	var egg_recipe: Dictionary = furnace.get_recipe_for_input("egg")
	_check(str(egg_recipe.get("output", {}).get("id", "")) == "cooked_egg", "egg production connects to the furnace food loop")
	var migrated: Dictionary = ProductMigrationScript.normalize_world_state(
		{"save_version":2, "metadata":{}}
	)
	_check(migrated.has("animal_products"), "old world state receives an animal product domain")
	_check(
		(migrated.get("animal_products", {}).get("records", {}) as Dictionary).is_empty(),
		"animal product migration never invents production records",
	)


func _test_generic_creature_attraction() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var player := Node3D.new()
	var chicken = ChickenScript.new()
	host.add_child(player)
	host.add_child(chicken)
	await process_frame
	player.global_position = Vector3.ZERO
	chicken.global_position = Vector3(0.0, 1.0, -5.0)
	chicken.set_attraction_target(player, 1.0, 1.8)
	var direction: Vector3 = chicken.call("_choose_direction")
	_check(chicken.has_active_attraction(), "base creature exposes an active attraction capability")
	_check(direction.z > 0.5, "base creature attraction points toward the player")
	chicken.global_position = Vector3(0.0, 1.0, -1.0)
	var stopped: Vector3 = chicken.call("_choose_direction")
	_check(stopped.length_squared() < 0.001, "base creature holds position inside the stop distance")
	chicken.clear_attraction_target()
	_check(not chicken.has_active_attraction(), "base creature attraction can be cleared without changing hostility")
	host.queue_free()
	await process_frame
	await process_frame


func _test_attraction_service() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var spawner := Node3D.new()
	var player := Node3D.new()
	var chicken = FakeAnimal.new()
	var service = AttractionServiceScript.new()
	for node in [inventory, spawner, player, service]:
		host.add_child(node)
	spawner.add_child(chicken)
	await process_frame
	player.global_position = Vector3.ZERO
	chicken.global_position = Vector3(0.0, 0.0, -5.0)
	inventory.clear()
	inventory.add_item("wheat_seeds", 1)
	inventory.select_slot(0)
	service.setup(inventory, spawner)
	service.attach_player(player)
	service.activate()
	var following := int(service.refresh_now())
	_check(following == 1, "attraction service tracks the nearby chicken")
	_check(chicken.attraction_target == player, "attraction service sends the player target through a capability")
	_check(chicken.attraction_duration > 0.25, "attraction timeout overlaps the refresh interval")
	inventory.clear()
	inventory.add_item("carrot", 1)
	inventory.select_slot(0)
	following = int(service.refresh_now())
	_check(following == 0, "switching to the wrong feed clears attraction")
	_check(chicken.attraction_target == null, "wrong feed releases the creature target")
	inventory.clear()
	inventory.add_item("wheat_seeds", 1)
	inventory.select_slot(0)
	chicken.global_position = Vector3(0.0, 0.0, -20.0)
	following = int(service.refresh_now())
	_check(following == 0, "animals outside the configured radius do not follow")
	service.clear()
	host.queue_free()
	await process_frame
	await process_frame


func _test_product_transactions_and_offline_state() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var spawner := Node3D.new()
	var player := Node3D.new()
	var chicken := Node3D.new()
	var husbandry = FakeHusbandry.new()
	var service = ProductServiceScript.new()
	for node in [inventory, spawner, player, husbandry, service]:
		host.add_child(node)
	spawner.add_child(chicken)
	await process_frame
	player.global_position = Vector3.ZERO
	chicken.global_position = Vector3(0.0, 0.0, -3.0)
	husbandry.set_record(
		"animal@qa-chicken",
		{
			"species_id":"chicken",
			"display_name":"鸡",
			"stage":"adult",
			"position":[0.0, 0.0, -3.0],
		},
		chicken
	)
	service.setup(inventory.registry, inventory, husbandry, spawner)
	service.attach_player(player)
	service.deserialize(
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":{
				"animal@qa-chicken":{
					"species_id":"chicken",
					"remaining_seconds":0.1,
					"pending_count":0,
				}
			},
		}
	)
	service.activate()
	var result: Dictionary = service.advance(1.0)
	_check(int(result.get("produced", 0)) == 1, "ready managed chicken produces one egg")
	_check(int(result.get("spawned", 0)) == 1, "nearby produced egg becomes one world pickup")
	var pickup := _find_pickup(spawner, "egg")
	_check(pickup != null, "egg pickup is created through the existing pickup system")
	_check(pickup != null and int(pickup.get("item_count")) == 1, "egg pickup preserves the produced quantity")
	var focus := {
		"type":"entity",
		"entity_id":chicken.get_instance_id(),
		"species_id":"chicken",
	}
	_check(str(service.get_status_for_focus(focus)).contains("下次鸡蛋"), "managed chicken prompt shows the next production timer")

	player.global_position = Vector3(100.0, 0.0, 0.0)
	service.deserialize(
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":{
				"animal@qa-chicken":{
					"species_id":"chicken",
					"remaining_seconds":0.1,
					"pending_count":0,
				}
			},
		}
	)
	result = service.advance(1.0)
	_check(int(result.get("spawned", 0)) == 0, "products stay pending while the player is far away")
	_check(int(service.get_record("animal@qa-chicken").get("pending_count", 0)) == 1, "far product remains in persistent pending state")
	_check(str(service.get_status_for_focus(focus)).contains("待收集"), "prompt exposes pending products")
	player.global_position = Vector3.ZERO
	result = service.advance(0.0)
	_check(int(result.get("spawned", 0)) == 1, "pending product spawns when the player returns")
	_check(int(service.get_record("animal@qa-chicken").get("pending_count", -1)) == 0, "spawned pending product is committed exactly once")

	service.deserialize(
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()) - 10000,
			"records":{
				"animal@qa-chicken":{
					"species_id":"chicken",
					"remaining_seconds":30.0,
					"pending_count":0,
				}
			},
		}
	)
	var offline_record: Dictionary = service.get_record("animal@qa-chicken")
	_check(int(offline_record.get("pending_count", 0)) > 0, "offline time advances animal production")
	_check(int(offline_record.get("pending_count", 0)) <= 6, "offline production respects the configured pending cap")

	husbandry.set_record(
		"animal@qa-chicken",
		{
			"species_id":"chicken",
			"display_name":"幼年鸡",
			"stage":"baby",
			"position":[0.0, 0.0, -3.0],
		},
		chicken
	)
	service.advance(0.0)
	_check(service.get_record("animal@qa-chicken").is_empty(), "baby transition removes adult production state")
	var baby_status := str(service.get_status_for_focus(focus))
	_check(baby_status.contains("成年后"), "baby prompt explains when production begins")
	service.clear()
	host.queue_free()
	await process_frame
	await process_frame


func _test_composition_root() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get("animal_attraction_service") != null, "composition root mounts animal attraction")
	_check(hub.get("animal_product_service") != null, "composition root mounts animal products")
	_check(
		hub is RanchProgressionServiceHub,
		"production service scene selects the ranch composition root",
	)
	_check(
		hub.husbandry_interaction.get("product_service") == hub.animal_product_service,
		"entity prompt adapter receives the animal product read model",
	)
	var snapshot: Dictionary = hub.get_character_snapshot()
	_check(snapshot.has("animal_attraction") and snapshot.has("animal_products"), "ranch services participate in diagnostics snapshots")
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _find_pickup(spawner: Node, item_id: String) -> Node:
	for child: Node in spawner.get_children():
		if str(child.get("item_id")) == item_id:
			return child
	return null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
