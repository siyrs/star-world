extends SceneTree

const CoordinatorScript = preload("res://src/entity/bounded_pickup_stack_coordinator.gd")
const PickupScript = preload("res://src/entity/item_pickup.gd")
const VisualResources = preload("res://src/entity/pickup_visual_resource_cache.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_shared_visual_runtime_and_resources()
	await _test_scene_pause_freezes_pickup_runtime()
	await _test_runtime_budget_and_expiration()
	if failures.is_empty():
		print("QA PICKUP SHARED RUNTIME PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PICKUP SHARED RUNTIME FAILURE: %s" % failure)
		print("QA PICKUP SHARED RUNTIME FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_shared_visual_runtime_and_resources() -> void:
	VisualResources.reset_stats(true)
	var fixture := _make_fixture()
	var host: Node3D = fixture.host
	var spawner: Node3D = fixture.spawner
	var coordinator: Node = fixture.coordinator
	var first = _spawn_pickup(spawner, "rotten_flesh", 2, Vector3(0.0, 4.0, 0.0))
	var second = _spawn_pickup(spawner, "rotten_flesh", 3, Vector3(3.0, 4.0, 0.0))
	for _frame in 3:
		await process_frame
	var first_anchor := first.position
	var second_anchor := second.position
	var step: Dictionary = coordinator.call("advance_shared_runtime", 0.1)
	_check(
		int(step.get("advanced_pickup_count", 0)) == 2,
		"one shared pickup runtime step advances both production pickup nodes",
	)
	_check(
		not first.is_processing() and not second.is_processing(),
		"shared-managed pickups disable their individual process callbacks",
	)
	_check(
		first.position.is_equal_approx(first_anchor) and second.position.is_equal_approx(second_anchor),
		"pickup bobbing never moves the Area3D collision anchors",
	)
	var first_visual: Node3D = first.call("get_visual_root") as Node3D
	var second_visual: Node3D = second.call("get_visual_root") as Node3D
	_check(
		first_visual != null
		and second_visual != null
		and absf(first_visual.position.y) <= PickupScript.BOB_AMPLITUDE + 0.001
		and absf(second_visual.position.y) <= PickupScript.BOB_AMPLITUDE + 0.001,
		"shared runtime moves only bounded visual roots",
	)
	var first_resources: Dictionary = first.call("get_visual_resource_ids")
	var second_resources: Dictionary = second.call("get_visual_resource_ids")
	_check(
		int(first_resources.get("mesh_id", 0)) == int(second_resources.get("mesh_id", -1))
		and int(first_resources.get("material_id", 0)) == int(second_resources.get("material_id", -1))
		and int(first_resources.get("collision_shape_id", 0))
		== int(second_resources.get("collision_shape_id", -1)),
		"same-color pickups share mesh, material, and collision resources",
	)
	var cache_stats: Dictionary = VisualResources.get_stats()
	_check(
		int(cache_stats.get("mesh_create_count", 0)) == 1
		and int(cache_stats.get("shape_create_count", 0)) == 1
		and int(cache_stats.get("material_create_count", 0)) == 1
		and int(cache_stats.get("material_hit_count", 0)) >= 1,
		"pickup visual cache allocates each shared resource once",
	)
	var runtime: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(runtime.get("individual_process_count", -1)) == 0
		and int(runtime.get("tracked_runtime_pickup_count", 0)) == 2
		and int(runtime.get("runtime_process_mode", -1)) == Node.PROCESS_MODE_PAUSABLE,
		"coordinator exposes one pausable runtime and zero individual pickup processes",
	)
	coordinator.call("shutdown")
	host.queue_free()
	await process_frame
	await process_frame


func _test_scene_pause_freezes_pickup_runtime() -> void:
	var fixture := _make_fixture()
	var host: Node3D = fixture.host
	var spawner: Node3D = fixture.spawner
	var coordinator: Node = fixture.coordinator
	var pickup = _spawn_pickup(spawner, "coal", 1, Vector3(0.0, 3.0, 0.0))
	for _frame in 5:
		await process_frame
	var before_pause: Dictionary = coordinator.call("get_snapshot")
	var life_before := float(pickup.get("life_seconds"))
	paused = true
	for _frame in 8:
		await process_frame
	var while_paused: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(while_paused.get("runtime_step_count", -1))
		== int(before_pause.get("runtime_step_count", -2))
		and is_equal_approx(float(pickup.get("life_seconds")), life_before),
		"real SceneTree pause freezes pickup lifetime and visual runtime",
	)
	paused = false
	for _frame in 8:
		await process_frame
	var after_resume: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(after_resume.get("runtime_step_count", 0))
		> int(while_paused.get("runtime_step_count", 0))
		and float(pickup.get("life_seconds")) < life_before,
		"pickup runtime resumes from the same lifetime after unpausing",
	)
	coordinator.call("shutdown")
	host.queue_free()
	await process_frame
	await process_frame


func _test_runtime_budget_and_expiration() -> void:
	var fixture := _make_fixture()
	var host: Node3D = fixture.host
	var spawner: Node3D = fixture.spawner
	var coordinator: Node = fixture.coordinator
	var pickups: Array[Node] = []
	for index in CoordinatorScript.MAX_RUNTIME_NODES:
		var column := index % 16
		var row := int(index / 16)
		var pickup = _spawn_pickup(
			spawner,
			"qa_runtime_item_%03d" % index,
			1,
			Vector3(float(column) * 2.2, 4.0, float(row) * 2.2)
		)
		pickup.set("life_seconds", 0.05)
		pickups.append(pickup)
		if index % 16 == 15:
			await process_frame
	for _frame in 4:
		await process_frame
	var before: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(before.get("pickup_node_count", 0)) == CoordinatorScript.MAX_RUNTIME_NODES
		and int(before.get("tracked_runtime_pickup_count", 0)) == CoordinatorScript.MAX_RUNTIME_NODES,
		"shared pickup runtime tracks the full one-hundred-twenty-eight-node hard budget",
	)
	_check(
		int(before.get("individual_process_count", -1)) == 0,
		"one hundred twenty-eight production pickups still use zero individual process callbacks",
	)
	var step: Dictionary = coordinator.call("advance_shared_runtime", 1.0)
	_check(
		int(step.get("advanced_pickup_count", 0)) == CoordinatorScript.MAX_RUNTIME_NODES
		and is_equal_approx(
			float(step.get("advanced_seconds", 0.0)),
			CoordinatorScript.MAX_RUNTIME_DELTA_SECONDS
		),
		"large pickup deltas clamp while advancing every node inside the runtime budget",
	)
	for _frame in 6:
		await process_frame
	var after: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(after.get("expired_pickup_count", 0)) == CoordinatorScript.MAX_RUNTIME_NODES
		and int(after.get("pickup_node_count", -1)) == 0
		and int(after.get("tracked_runtime_pickup_count", -1)) == 0,
		"shared lifetime expiration removes all expired pickup nodes exactly once",
	)
	_check(
		int(after.get("max_runtime_nodes_observed", 0)) <= CoordinatorScript.MAX_RUNTIME_NODES,
		"shared pickup runtime never exceeds its hard tracked-node budget",
	)
	coordinator.call("shutdown")
	host.queue_free()
	await process_frame
	await process_frame


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var spawner := Node3D.new()
	host.add_child(spawner)
	var coordinator = CoordinatorScript.new()
	host.add_child(coordinator)
	_check(coordinator.setup(spawner, null), "shared pickup runtime binds a production-style spawner")
	coordinator.activate()
	return {"host": host, "spawner": spawner, "coordinator": coordinator}


func _spawn_pickup(spawner: Node3D, item_id: String, count: int, position: Vector3) -> Node:
	var pickup = PickupScript.new()
	pickup.setup(item_id, count, null)
	spawner.add_child(pickup)
	pickup.global_position = position
	return pickup


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
