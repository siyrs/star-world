extends "res://tests/qa/structural_integrity_batched_regression.gd"

const PickupCoordinatorScript = preload(
	"res://src/entity/bounded_pickup_stack_coordinator.gd"
)
const PickupScript = preload("res://src/entity/item_pickup.gd")

const STRUCTURE_CYCLES := 24
const PICKUP_CYCLES := 5


func _run() -> void:
	var baseline_children := root.get_child_count()
	for cycle_index in STRUCTURE_CYCLES:
		await _test_batched_cleanup_and_dedupe()
		_check(
			root.get_child_count() == baseline_children,
			"structure pressure cycle %02d releases every temporary runtime node" % (cycle_index + 1)
		)
	await _test_repeated_full_pickup_budget_churn(baseline_children)
	if failures.is_empty():
		print(
			"QA LONG TERM STRUCTURE PICKUP CHURN PASS | checks=%d | structures=%d | pickup-cycles=%d"
			% [checks, STRUCTURE_CYCLES * 2, PICKUP_CYCLES]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA LONG TERM STRUCTURE PICKUP CHURN FAILURE: %s" % failure)
	print("QA LONG TERM STRUCTURE PICKUP CHURN FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_repeated_full_pickup_budget_churn(baseline_children: int) -> void:
	for cycle_index in PICKUP_CYCLES:
		var host := Node3D.new()
		root.add_child(host)
		var spawner := Node3D.new()
		host.add_child(spawner)
		var coordinator = PickupCoordinatorScript.new()
		host.add_child(coordinator)
		_check(
			coordinator.setup(spawner, null),
			"pickup pressure cycle %d binds one shared production runtime" % (cycle_index + 1)
		)
		coordinator.activate()
		var pickups: Array[Node3D] = []
		for index in PickupCoordinatorScript.MAX_RUNTIME_NODES:
			var pickup = PickupScript.new()
			pickup.setup("qa_churn_%02d_%03d" % [cycle_index, index], 1, null)
			spawner.add_child(pickup)
			pickup.global_position = Vector3(
				float(index % 16) * 2.1,
				4.0,
				float(int(index / 16)) * 2.1
			)
			pickups.append(pickup)
			if index % 32 == 31:
				await process_frame
		for _frame in 4:
			await process_frame
		var full_snapshot: Dictionary = coordinator.get_snapshot()
		_check(
			int(full_snapshot.get("pickup_node_count", 0))
			== PickupCoordinatorScript.MAX_RUNTIME_NODES
			and int(full_snapshot.get("tracked_runtime_pickup_count", 0))
			== PickupCoordinatorScript.MAX_RUNTIME_NODES
			and int(full_snapshot.get("individual_process_count", -1)) == 0,
			"pickup pressure cycle %d reaches the exact 128-node shared-runtime budget"
			% (cycle_index + 1)
		)
		for pickup: Node3D in pickups:
			if pickup != null and is_instance_valid(pickup):
				pickup.set("life_seconds", 0.01)
		var step: Dictionary = coordinator.advance_shared_runtime(1.0)
		_check(
			int(step.get("advanced_pickup_count", 0))
			== PickupCoordinatorScript.MAX_RUNTIME_NODES,
			"pickup pressure cycle %d advances every bounded node exactly once"
			% (cycle_index + 1)
		)
		for _frame in 8:
			await process_frame
		var empty_snapshot: Dictionary = coordinator.get_snapshot()
		_check(
			int(empty_snapshot.get("pickup_node_count", -1)) == 0
			and int(empty_snapshot.get("tracked_runtime_pickup_count", -1)) == 0
			and int(empty_snapshot.get("expired_pickup_count", 0))
			== PickupCoordinatorScript.MAX_RUNTIME_NODES,
			"pickup pressure cycle %d expires and unregisters all nodes without residue"
			% (cycle_index + 1)
		)
		_check(
			int(empty_snapshot.get("max_runtime_nodes_observed", 0))
			<= PickupCoordinatorScript.MAX_RUNTIME_NODES,
			"pickup pressure cycle %d never exceeds the hard runtime capacity"
			% (cycle_index + 1)
		)
		coordinator.shutdown()
		host.queue_free()
		for _frame in 4:
			await process_frame
		_check(
			root.get_child_count() == baseline_children,
			"pickup pressure cycle %d releases its shared runtime and all visual nodes"
			% (cycle_index + 1)
		)
