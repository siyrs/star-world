extends SceneTree

const CoordinatorScript = preload("res://src/entity/bounded_pickup_stack_coordinator.gd")
const PickupScript = preload("res://src/entity/item_pickup.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_mergeable_pickup_visual()
	await _test_pressure_merging_preserves_all_items()
	await _test_node_budget_defers_without_losing_items()
	if failures.is_empty():
		print("QA PICKUP STACK PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PICKUP STACK FAILURE: %s" % failure)
		print("QA PICKUP STACK FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_mergeable_pickup_visual() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	host.add_child(inventory)
	var pickup = PickupScript.new()
	pickup.setup("apple", 2, inventory)
	host.add_child(pickup)
	await process_frame
	_check(pickup.can_merge("apple"), "matching unlocked pickup accepts stack merging")
	_check(not pickup.can_merge("coal"), "different item ids cannot merge into a pickup")
	var leftover := int(pickup.merge_items(3, true))
	_check(leftover == 0 and pickup.item_count == 5, "pickup merge preserves the exact combined item total")
	var label: Label3D = pickup.get_count_label()
	_check(label != null and label.visible and label.text == "×5", "merged pickup displays a readable world-space count")
	var snapshot: Dictionary = pickup.get_pickup_snapshot()
	_check(
		int(snapshot.get("merge_count", 0)) == 1
		and int(snapshot.get("item_count", 0)) == 5,
		"pickup snapshot exposes bounded merge diagnostics",
	)
	host.queue_free()
	await process_frame
	await process_frame


func _test_pressure_merging_preserves_all_items() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var spawner := Node3D.new()
	host.add_child(spawner)
	var coordinator = CoordinatorScript.new()
	host.add_child(coordinator)
	_check(coordinator.setup(spawner, null), "pickup coordinator binds a production-style spawner")
	coordinator.activate()
	for index in 100:
		var pickup = PickupScript.new()
		pickup.setup("rotten_flesh", 1, null)
		spawner.add_child(pickup)
		pickup.global_position = Vector3(0.0, 4.0, 0.0)
		if index % 16 == 15:
			await process_frame
	for _frame in 6:
		await process_frame
	var snapshot: Dictionary = coordinator.get_snapshot()
	_check(
		int(snapshot.get("pickup_node_count", 999)) <= 8,
		"one hundred nearby drops consolidate to the eight-node readability trigger",
	)
	_check(
		int(snapshot.get("visible_item_total", 0)) == 100
		and int(snapshot.get("pending_item_total", -1)) == 0,
		"pressure merging preserves every physical item without a hidden remainder",
	)
	_check(
		int(snapshot.get("merged_item_count", 0)) >= 92
		and int(snapshot.get("merged_pickup_count", 0)) >= 92,
		"coordinator diagnostics prove repeated pickup nodes were removed by merging",
	)
	var stacked_label_found := false
	for child: Node in spawner.get_children():
		if not child.has_method("get_pickup_snapshot"):
			continue
		var pickup_snapshot: Dictionary = child.call("get_pickup_snapshot")
		if int(pickup_snapshot.get("item_count", 0)) > 1:
			stacked_label_found = bool(pickup_snapshot.get("count_label_visible", false))
			break
	_check(stacked_label_found, "at least one consolidated world pickup renders its stack count")
	coordinator.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _test_node_budget_defers_without_losing_items() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var spawner := Node3D.new()
	host.add_child(spawner)
	var coordinator = CoordinatorScript.new()
	host.add_child(coordinator)
	coordinator.setup(spawner, null)
	coordinator.activate()
	for index in CoordinatorScript.MAX_PICKUP_NODES:
		var pickup = PickupScript.new()
		pickup.setup("qa_item_%03d" % index, 1, null)
		spawner.add_child(pickup)
		pickup.global_position = Vector3(float(index) * 3.0, 2.0, 0.0)
		if index % 16 == 15:
			await process_frame
	for _frame in 4:
		await process_frame
	var overflow = PickupScript.new()
	overflow.setup("qa_overflow", 1, null)
	spawner.add_child(overflow)
	overflow.global_position = Vector3(1000.0, 2.0, 0.0)
	for _frame in 4:
		await process_frame
	var deferred: Dictionary = coordinator.get_snapshot()
	_check(
		int(deferred.get("pickup_node_count", 0)) == CoordinatorScript.MAX_PICKUP_NODES
		and int(deferred.get("pending_item_total", 0)) == 1,
		"the one-hundred-twenty-ninth pickup is deferred at the hard node budget",
	)
	_check(
		int(deferred.get("visible_item_total", 0))
		+ int(deferred.get("pending_item_total", 0)) == CoordinatorScript.MAX_PICKUP_NODES + 1,
		"node-budget deferral keeps the exact combined visible and pending total",
	)
	var first_pickup: Node = null
	for child: Node in spawner.get_children():
		if child.has_method("get_pickup_snapshot"):
			first_pickup = child
			break
	_check(first_pickup != null, "budget fixture exposes a pickup that can free capacity")
	if first_pickup != null:
		first_pickup.queue_free()
	for _frame in 8:
		await process_frame
	var materialized: Dictionary = coordinator.get_snapshot()
	_check(
		int(materialized.get("pickup_node_count", 0)) == CoordinatorScript.MAX_PICKUP_NODES
		and int(materialized.get("pending_item_total", -1)) == 0,
		"freeing one node materializes the deferred item through the bounded flush path",
	)
	_check(
		int(materialized.get("visible_item_total", 0)) == CoordinatorScript.MAX_PICKUP_NODES,
		"after one fixture pickup expires, all remaining one hundred twenty-eight items stay physical",
	)
	_check(
		int(materialized.get("max_pickup_nodes_observed", 0)) <= CoordinatorScript.MAX_PICKUP_NODES + 1,
		"pickup pressure never creates an unbounded live-node spike",
	)
	coordinator.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
