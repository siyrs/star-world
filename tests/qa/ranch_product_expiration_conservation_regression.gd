extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ProductServiceScript = preload(
	"res://src/husbandry/reliable_animal_product_service.gd"
)

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
		"animal@expiration",
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
		"expiration fixture satisfies production product contracts",
	)
	service.attach_player(player)
	service.deserialize(
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":{
				"animal@expiration":{
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
	var first: Dictionary = service.advance(1.0)
	_check(int(first.get("produced", 0)) == 1, "first timer produces one authoritative egg")
	_check(spawned_events.size() == 1, "new pending quantity announces exactly once")
	_check(_pickup_count(spawner, "egg") == 1, "new pending quantity materializes one pickup")
	_check(
		int(service.get_record("animal@expiration").get("pending_count", 0)) == 1,
		"materialized egg remains authoritative until collection",
	)

	for cycle in 2:
		var pickup := _find_pickup(spawner, "egg")
		_check(pickup != null, "expiration cycle %d starts with a live pickup" % (cycle + 1))
		if pickup != null:
			pickup.call("_expire")
		await process_frame
		await process_frame
		_check(_pickup_count(spawner, "egg") == 0, "expiration cycle %d disposes only the transient node" % (cycle + 1))
		var restored: Dictionary = service.advance(0.0)
		await process_frame
		_check(int(restored.get("produced", -1)) == 0, "expiration recovery %d creates no new product" % (cycle + 1))
		_check(_pickup_count(spawner, "egg") == 1, "expiration recovery %d rematerializes exactly one pickup" % (cycle + 1))
		_check(spawned_events.size() == 1, "expiration recovery %d does not replay production feedback" % (cycle + 1))
		_check(
			int(service.get_record("animal@expiration").get("pending_count", 0)) == 1,
			"expiration recovery %d preserves authoritative pending count" % (cycle + 1),
		)

	var collected := _find_pickup(spawner, "egg")
	if collected != null:
		# _finish_collection receives leftover count. Zero means the one-item stack
		# was fully accepted and must commit one authoritative collection.
		collected.call("_finish_collection", 0)
	await process_frame
	await process_frame
	_check(inventory.count_item("egg") == 0, "direct pickup fixture does not bypass player inventory")
	_check(
		int(service.get_record("animal@expiration").get("pending_count", -1)) == 0,
		"accepted collection clears the authoritative pending quantity",
	)
	_check(_pickup_count(spawner, "egg") == 0, "accepted collection removes the transient pickup")
	_check(spawned_events.size() == 1, "collection itself cannot create another production announcement")
	_check(
		int(service.get_snapshot().get("announcement_ledger_count", 0)) == 1,
		"announcement ledger remains bounded to the tracked animal",
	)

	service.clear()
	_check(int(service.get_snapshot().get("announcement_ledger_count", -1)) == 0, "world clear releases the announcement ledger")
	host.queue_free()
	for _frame in 4:
		await process_frame
	if failures.is_empty():
		print("QA RANCH PRODUCT EXPIRATION CONSERVATION PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA RANCH PRODUCT EXPIRATION CONSERVATION FAILURE: %s" % failure)
	print(
		"QA RANCH PRODUCT EXPIRATION CONSERVATION FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


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
