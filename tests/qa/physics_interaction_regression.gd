extends SceneTree

const PhysicsLayers = preload("res://src/core/physics_layers.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")
const PickupScript = preload("res://src/entity/item_pickup.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_player_and_creature_profiles()
	await _test_pickup_collection_guard()
	if failures.is_empty():
		print("QA PHYSICS INTERACTION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA PHYSICS INTERACTION FAILURE: %s" % failure)
		print("QA PHYSICS INTERACTION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_player_and_creature_profiles() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var player = PlayerScene.instantiate()
	host.add_child(player)
	await process_frame
	_check(
		player.is_in_group(PhysicsLayers.PLAYER_GROUP), "player is registered in the player group"
	)
	_check(player.collision_layer == PhysicsLayers.PLAYER, "player uses the player collision layer")
	_check(
		player.collision_mask == PhysicsLayers.PLAYER_BODY_MASK,
		"player body collides with world and entities",
	)
	var ray: RayCast3D = player.get_node("CameraPivot/Camera3D/InteractionRay")
	_check(
		ray.collision_mask == PhysicsLayers.PLAYER_INTERACTION_MASK,
		"player interaction ray can hit world blocks and creatures",
	)

	var factory = CreatureFactoryScript.new()
	var creature = factory.create("chicken", Vector3(4.0, 4.0, 4.0), null, null)
	host.add_child(creature)
	await process_frame
	creature.set_physics_process(false)
	_check(creature.collision_layer == PhysicsLayers.ENTITIES, "creatures use the entity layer")
	_check(
		creature.collision_mask == PhysicsLayers.ENTITY_BODY_MASK,
		"creatures collide with world, players, and other creatures",
	)
	creature.drops = {}
	creature.die()
	_check(
		creature.collision_layer == 0 and creature.collision_mask == 0,
		"dead creatures release collision immediately",
	)
	host.queue_free()
	await process_frame
	await process_frame


func _test_pickup_collection_guard() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	host.add_child(inventory)
	var player = PlayerScene.instantiate()
	player.position = Vector3(10.0, 10.0, 10.0)
	host.add_child(player)
	var pickup = PickupScript.new()
	pickup.setup("apple", 2, inventory)
	pickup.position = Vector3(20.0, 20.0, 20.0)
	host.add_child(pickup)
	await process_frame
	_check(pickup.collision_layer == PhysicsLayers.PICKUPS, "pickups use their own collision layer")
	_check(pickup.collision_mask == PhysicsLayers.PLAYER, "pickups only monitor player bodies")

	var terrain := StaticBody3D.new()
	terrain.collision_layer = PhysicsLayers.WORLD
	host.add_child(terrain)
	pickup.call("_on_body_entered", terrain)
	_check(inventory.count_item("apple") == 0, "terrain cannot collect a pickup")
	_check(pickup.item_count == 2, "non-player contact leaves pickup quantity unchanged")

	pickup.call("_on_body_entered", player)
	_check(inventory.count_item("apple") == 2, "the player receives the pickup")
	_check(pickup.is_queued_for_deletion(), "fully collected pickups are removed exactly once")
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
