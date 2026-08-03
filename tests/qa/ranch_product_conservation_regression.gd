extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ProductServiceScript = preload(
	"res://src/husbandry/reliable_animal_product_service.gd"
)
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


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
	await _test_product_is_committed_only_after_collection()
	await _test_production_composition_uses_reliable_service()
	if failures.is_empty():
		print("QA RANCH PRODUCT CONSERVATION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANCH PRODUCT CONSERVATION FAILURE: %s" % failure)
		print(
			"QA RANCH PRODUCT CONSERVATION FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_product_is_committed_only_after_collection() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var spawner := Node3D.new()
	var player := Node3D.new()
	var chicken := Node3D.new()
	var husbandry = FakeHusbandry.new()
	var service = ProductServiceScript.new()
	for node: Node in [inventory, spawner, player, husbandry, service]:
		host.add_child(node)
	spawner.add_child(chicken)
	await process_frame

	player.global_position = Vector3.ZERO
	chicken.global_position = Vector3(0.0, 0.0, -2.0)
	husbandry.set_record(
		"animal@conservation",
		{
			"species_id":"chicken",
			"display_name":"鸡",
			"stage":"adult",
			"position":[0.0, 0.0, -2.0],
		},
		chicken,
	)
	_check(
		bool(service.setup(inventory.registry, inventory, husbandry, spawner)),
		"reliable product service accepts the production contracts",
	)
	service.attach_player(player)
	service.deserialize(
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":{
				"animal@conservation":{
					"species_id":"chicken",
					"remaining_seconds":0.1,
					"pending_count":0,
				},
			},
		},
	)
	var spawned_events: Array[Dictionary] = []
	service.product_spawned.connect(
		func(result: Dictionary) -> void:
			spawned_events.append(result.duplicate(true))
	)
	service.activate()
	var result: Dictionary = service.advance(1.0)
	_check(int(result.get("produced", 0)) == 1, "one elapsed timer creates one egg")
	_check(int(result.get("spawned", 0)) == 1, "one pending egg is materialized in the world")
	_check(spawned_events.size() == 1, "new production emits one player-facing event")
	_check(
		int(service.get_record("animal@conservation").get("pending_count", 0)) == 1,
		"materializing a pickup does not erase authoritative pending product state",
	)
	_check(
		int(service.get_snapshot().get("active_pickups", 0)) == 1,
		"service tracks exactly one active pickup for the pending record",
	)
	var pickup := _find_pickup(spawner, "egg")
	_check(pickup != null and int(pickup.get("item_count")) == 1, "world pickup mirrors the pending quantity")

	result = service.advance(0.0)
	_check(int(result.get("spawned", 0)) == 0, "repeated synchronization cannot duplicate an active pickup")
	_check(_pickup_count(spawner, "egg") == 1, "only one egg pickup exists before collection")
	var saved_pending: Dictionary = service.serialize()
	_check(
		int(saved_pending.get("records", {}).get("animal@conservation", {}).get("pending_count", 0)) == 1,
		"save payload retains the uncollected product",
	)

	if pickup != null:
		pickup.call("_finish_collection", 1)
	_check(
		int(service.get_record("animal@conservation").get("pending_count", 0)) == 1,
		"zero-acceptance collection leaves authoritative product state untouched",
	)
	_check(pickup != null and int(pickup.get("item_count")) == 1, "zero-acceptance collection leaves the world pickup intact")

	service.deactivate()
	await process_frame
	_check(_pickup_count(spawner, "egg") == 0, "leaving the world removes only the transient pickup node")
	service.attach_player(player)
	service.activate()
	await process_frame
	_check(
		int(service.get_record("animal@conservation").get("pending_count", 0)) == 1,
		"reactivation restores pending product state",
	)
	_check(_pickup_count(spawner, "egg") == 1, "reactivation rematerializes exactly one pickup")
	_check(spawned_events.size() == 1, "restoring an existing product does not replay production feedback")

	pickup = _find_pickup(spawner, "egg")
	if pickup != null:
		pickup.call("_finish_collection", 0)
	await process_frame
	_check(
		int(service.get_record("animal@conservation").get("pending_count", -1)) == 0,
		"accepted collection commits the authoritative pending count",
	)
	_check(_pickup_count(spawner, "egg") == 0, "fully collected pickup is disposed exactly once")
	var final_state: Dictionary = service.serialize()
	_check(
		int(final_state.get("records", {}).get("animal@conservation", {}).get("pending_count", -1)) == 0,
		"final save records the collected product exactly once",
	)

	service.deactivate()
	service.deserialize(
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()) - 10000,
			"records":{
				"animal@conservation":{
					"species_id":"chicken",
					"remaining_seconds":30.0,
					"pending_count":0,
				},
			},
		},
	)
	var offline_pending := int(
		service.get_record("animal@conservation").get("pending_count", 0)
	)
	_check(offline_pending > 0 and offline_pending <= 6, "offline production remains bounded by the configured pending cap")
	service.attach_player(player)
	service.activate()
	await process_frame
	_check(_pickup_count(spawner, "egg") == 1, "offline pending products materialize as one bounded stack")
	_check(spawned_events.size() == 1, "offline restore does not replay historical production feedback")

	service.clear()
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_composition_uses_reliable_service() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 4:
		await process_frame
	var service: Node = hub.get("animal_product_service") as Node
	_check(service != null, "production composition mounts animal products")
	_check(
		service is ReliableAnimalProductService,
		"production composition uses collection-backed product persistence",
	)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	for _frame in 8:
		await process_frame


func _find_pickup(spawner: Node, item_id: String) -> Node:
	for child: Node in spawner.get_children():
		if str(child.get("item_id")) == item_id and not child.is_queued_for_deletion():
			return child
	return null


func _pickup_count(spawner: Node, item_id: String) -> int:
	var count := 0
	for child: Node in spawner.get_children():
		if str(child.get("item_id")) == item_id and not child.is_queued_for_deletion():
			count += 1
	return count


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
