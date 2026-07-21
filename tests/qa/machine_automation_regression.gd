extends SceneTree

const PolicyScript = preload("res://src/machine/machine_automation_policy.gd")
const AutomationScript = preload("res://src/machine/machine_automation_service.gd")
const RouterScript = preload("res://src/machine/machine_interaction_router.gd")
const SchedulerScript = preload("res://src/machine/machine_runtime_scheduler.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ContainerStorageScript = preload("res://src/inventory/container_storage_service.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const StonecutterScript = preload("res://src/machine/stonecutter_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}

	func set_block(position: Vector3i, block_id: String) -> void:
		blocks[position] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(position, "air"))


class FakeMachineUI:
	extends Node

	func open_furnace(_machine_id: String, _title: String = "熔炉") -> bool:
		return true

	func open_stonecutter(
		_machine_id: String,
		_title: String = "石材切割机"
	) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy()
	await _test_atomic_container_transactions()
	await _test_bounded_production_automation()
	await _test_production_hub_contract()
	if failures.is_empty():
		print("QA MACHINE AUTOMATION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE AUTOMATION FAILURE: %s" % failure)
		print(
			"QA MACHINE AUTOMATION FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_policy() -> void:
	var parsed: Dictionary = PolicyScript.parse_machine_position(
		&"furnace", "furnace@-2,10,7"
	)
	_check(bool(parsed.get("success", false)), "position-keyed machine ids parse")
	_check(
		parsed.get("position", Vector3i.ZERO) == Vector3i(-2, 10, 7),
		"machine automation preserves signed block coordinates"
	)
	_check(
		str(PolicyScript.parse_machine_position(
			&"stonecutter", "furnace@0,0,0"
		).get("reason", "")) == "machine_id_prefix",
		"automation rejects mismatched machine prefixes"
	)
	_check(
		PolicyScript.input_position(Vector3i(1, 5, 2)) == Vector3i(1, 6, 2),
		"input chest contract is directly above the machine"
	)
	_check(
		PolicyScript.output_position(Vector3i(1, 5, 2)) == Vector3i(1, 4, 2),
		"output chest contract is directly below the machine"
	)
	_check(
		PolicyScript.container_id(Vector3i(1, 6, 2)) == "chest@1,6,2",
		"adjacent chests reuse stable world container ids"
	)
	_check(
		PolicyScript.transfer_count(64, 64, 64) == 8,
		"one lightweight transfer is capped at eight items"
	)
	_check(
		PolicyScript.MAX_MACHINES_PER_CYCLE == 16
		and PolicyScript.MAX_ITEMS_PER_CYCLE == 64
		and PolicyScript.MAX_CONTAINER_SLOTS_PER_CYCLE == 256
		and PolicyScript.MAX_TRANSFER_ATTEMPTS_PER_CYCLE == 128,
		"automation exposes hard machine, item, slot and attempt budgets"
	)


func _test_atomic_container_transactions() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var storage = ContainerStorageScript.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(storage)
	await process_frame
	storage.setup(inventory.registry)
	var container_id := "chest@atomic"
	storage.ensure_container(container_id, "chest", 1)
	storage.add_item(container_id, "wooden_pickaxe", 1, {"serial":1})
	var before: Dictionary = storage.get_container(container_id)
	_check(
		not storage.can_transact_items(
			container_id,
			{},
			[{"item_id":"stone", "count":1, "metadata":{}}]
		),
		"full container preflight rejects a complete addition"
	)
	var rejected: Dictionary = storage.transact_items(
		container_id,
		{},
		[{"item_id":"stone", "count":1, "metadata":{}}]
	)
	_check(not bool(rejected.get("success", false)), "full container transaction is rejected")
	_check(storage.get_container(container_id) == before, "rejected container transaction performs zero writes")
	storage.remove_from_slot(container_id, 0, 1)
	storage.add_item(container_id, "stone", 4)
	var swapped: Dictionary = storage.transact_items(
		container_id,
		{"stone":2},
		[{"item_id":"cobblestone", "count":2, "metadata":{}}]
	)
	_check(bool(swapped.get("success", false)), "container transaction commits removal and addition together")
	_check(_count_container_item(storage, container_id, "stone") == 2, "atomic container transaction removes the exact source count")
	_check(_count_container_item(storage, container_id, "cobblestone") == 2, "atomic container transaction adds the exact target count")
	host.queue_free()
	await process_frame
	await process_frame


func _test_bounded_production_automation() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var storage = ContainerStorageScript.new()
	var furnace = FurnaceScript.new()
	var cutter = StonecutterScript.new()
	var router = RouterScript.new()
	var automation = AutomationScript.new()
	var scheduler = SchedulerScript.new()
	var world = FakeWorld.new()
	var ui = FakeMachineUI.new()
	root.add_child(host)
	for node: Node in [inventory, storage, furnace, cutter, router, automation, scheduler, world, ui]:
		host.add_child(node)
	await process_frame
	storage.setup(inventory.registry)
	_check(bool(furnace.setup(inventory.registry)), "production furnace initializes for automation")
	_check(bool(cutter.setup(inventory.registry)), "production stonecutter initializes for automation")
	router.setup_ui(ui)
	_check(bool(router.register_machine_type(
		&"furnace", furnace, &"open_furnace", ["input","fuel","output"],
		"熔炉", "furnace not empty"
	).get("success", false)), "automation router registers furnace")
	_check(bool(router.register_machine_type(
		&"stonecutter", cutter, &"open_stonecutter", ["input","output"],
		"石材切割机", "stonecutter not empty"
	).get("success", false)), "automation router registers stonecutter")

	var furnace_position := Vector3i(0, 10, 0)
	var cutter_position := Vector3i(3, 10, 0)
	var furnace_id := _machine_id("furnace", furnace_position)
	var cutter_id := _machine_id("stonecutter", cutter_position)
	_check(furnace.ensure_machine(furnace_id), "automation furnace instance exists")
	_check(cutter.ensure_machine(cutter_id), "automation stonecutter instance exists")
	_configure_machine_stack(world, storage, furnace_position, "furnace")
	_configure_machine_stack(world, storage, cutter_position, "stonecutter")
	var furnace_input := PolicyScript.container_id(PolicyScript.input_position(furnace_position))
	var furnace_output := PolicyScript.container_id(PolicyScript.output_position(furnace_position))
	var cutter_input := PolicyScript.container_id(PolicyScript.input_position(cutter_position))
	var cutter_output := PolicyScript.container_id(PolicyScript.output_position(cutter_position))
	storage.add_item(furnace_input, "raw_iron", 2)
	storage.add_item(furnace_input, "coal", 1)
	storage.add_item(cutter_input, "stone", 2)
	storage.add_item(cutter_input, "apple", 3)

	_check(bool(automation.setup(router, storage)), "bounded automation validates its production ports")
	_check(bool(scheduler.register_domain(&"furnace", furnace).get("success", false)), "scheduler registers furnace before automation")
	_check(bool(scheduler.register_domain(&"stonecutter", cutter).get("success", false)), "scheduler registers stonecutter before automation")
	_check(bool(scheduler.register_domain(&"automation", automation).get("success", false)), "scheduler registers bounded automation as one shared domain")
	automation.attach_world(world)
	var first_cycle: Dictionary = scheduler.advance_time(0.5, true)
	var automation_first: Dictionary = first_cycle.get("domain_summaries", {}).get("automation", {})
	_check(int(automation_first.get("items_moved", 0)) == 5, "first cycle supplies exact furnace and cutter inputs")
	_check(int(furnace.get_slot(furnace_id, "input").get("count", 0)) == 2, "upper chest supplies two raw iron")
	_check(int(furnace.get_slot(furnace_id, "fuel").get("count", 0)) == 1, "upper chest supplies one valid fuel")
	_check(int(cutter.get_slot(cutter_id, "input").get("count", 0)) == 2, "upper chest supplies two valid stone inputs")
	_check(_count_container_item(storage, cutter_input, "apple") == 3, "unsupported upper-chest items remain untouched")

	var production_cycle: Dictionary = scheduler.advance_time(12.1, true)
	var automation_production: Dictionary = production_cycle.get("domain_summaries", {}).get("automation", {})
	_check(int(automation_production.get("output_items", 0)) == 6, "same shared batch extracts both machine outputs")
	_check(_count_container_item(storage, furnace_output, "iron_ingot") == 2, "lower furnace chest receives both iron ingots")
	_check(_count_container_item(storage, cutter_output, "stone_slab") == 4, "lower cutter chest receives all stone slabs")
	_check(furnace.get_slot(furnace_id, "output").is_empty(), "automated furnace extraction clears committed output")
	_check(cutter.get_slot(cutter_id, "output").is_empty(), "automated cutter extraction clears committed output")

	var blocked_position := Vector3i(6, 10, 0)
	var blocked_id := _machine_id("stonecutter", blocked_position)
	cutter.open_machine(blocked_id)
	cutter.close_machine()
	_configure_machine_stack(world, storage, blocked_position, "stonecutter")
	var blocked_input := PolicyScript.container_id(PolicyScript.input_position(blocked_position))
	var blocked_output := PolicyScript.container_id(PolicyScript.output_position(blocked_position))
	storage.add_item(blocked_input, "stone", 1)
	for index in PolicyScript.CONTAINER_SLOT_COUNT:
		storage.add_item(blocked_output, "wooden_pickaxe", 1, {"serial":index})
	automation.advance_machine_runtime(0.5, true)
	var blocked_before: Dictionary = storage.get_container(blocked_output)
	scheduler.advance_time(3.0, true)
	_check(storage.get_container(blocked_output) == blocked_before, "full lower chest performs zero partial writes")
	_check(int(cutter.get_slot(blocked_id, "output").get("count", 0)) == 2, "full lower chest leaves machine output intact")

	var cache_before := int(automation.get_runtime_snapshot().get("cache_rebuild_count", 0))
	var budget_ids: Array[String] = []
	for index in 20:
		var position := Vector3i(20 + index * 3, 10, 0)
		var machine_id := _machine_id("stonecutter", position)
		budget_ids.append(machine_id)
		world.set_block(position, "stonecutter")
		world.set_block(PolicyScript.input_position(position), "chest")
		var input_id := PolicyScript.container_id(PolicyScript.input_position(position))
		storage.ensure_container(input_id, "chest", PolicyScript.CONTAINER_SLOT_COUNT)
		storage.add_item(input_id, "stone", 1)
		cutter.open_machine(machine_id)
		cutter.close_machine()
	var bounded_first: Dictionary = automation.advance_machine_runtime(0.5, true)
	_check(int(bounded_first.get("scanned_machine_count", 0)) <= 16, "one cycle scans at most sixteen machines")
	_check(int(bounded_first.get("items_moved", 0)) <= 64, "one cycle moves at most sixty-four items")
	_check(int(bounded_first.get("slots_scanned", 0)) <= 256, "one cycle scans at most 256 container slots")
	_check(int(bounded_first.get("transfer_attempts", 0)) <= 128, "one cycle performs at most 128 transfer probes")
	automation.advance_machine_runtime(0.5, true)
	var supplied_count := 0
	for machine_id: String in budget_ids:
		if int(cutter.get_slot(machine_id, "input").get("count", 0)) == 1:
			supplied_count += 1
	_check(supplied_count == 20, "round-robin cycles eventually serve machines beyond the first sixteen")
	_check(int(automation.get_runtime_snapshot().get("cache_rebuild_count", 0)) == cache_before, "normal cycles use event-maintained candidates instead of rebuilding all machine ids")

	var paused_source_id := PolicyScript.container_id(
		PolicyScript.input_position(Vector3i(20, 10, 0))
	)
	storage.add_item(paused_source_id, "stone", 1)
	var paused_before: Dictionary = storage.get_container(paused_source_id)
	automation.advance_machine_runtime(1.0, false)
	_check(storage.get_container(paused_source_id) == paused_before, "offline or no-event runtime never performs automation transfers")
	_check(not furnace.serialize().has("automation_jobs"), "furnace persistence excludes transient automation")
	_check(not cutter.serialize().has("automation_jobs"), "stonecutter persistence excludes transient automation")
	_check(not storage.serialize().has("automation_jobs"), "container persistence excludes transient automation")
	var snapshot: Dictionary = automation.get_runtime_snapshot()
	_check(int(snapshot.get("tracked_machine_count", 0)) >= 23, "automation diagnostics expose the event-maintained candidate count")
	_check(int(snapshot.get("max_items_in_cycle", 0)) <= 64, "diagnostics preserve the observed throughput hard limit")

	automation.shutdown()
	scheduler.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_hub_contract() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var automation: Node = hub.get("machine_automation_service") as Node
	var scheduler: Node = hub.get("machine_runtime") as Node
	_check(automation != null, "production hub exposes the bounded automation service")
	_check(hub.get_node_or_null("MachineAutomationService") == automation, "automation keeps a stable production node path")
	var runtime_snapshot: Dictionary = scheduler.call("get_snapshot") if scheduler != null else {}
	var registered: Array = runtime_snapshot.get("registered_domains", [])
	_check("automation" in registered, "production scheduler owns the automation domain")
	_check(int(runtime_snapshot.get("domain_count", 0)) == 3, "machine runtime contains furnace, cutter and one automation domain")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	var domains: Dictionary = character_snapshot.get("machine_runtime", {}).get("domains", {})
	_check(domains.has("automation"), "automation diagnostics join the production character snapshot")
	var created: Dictionary = hub.get("save_service").create_world(
		"machine-automation-regression-%d" % Time.get_ticks_msec(),
		"star_continent",
		771903
	)
	var world_id := str(created.get("metadata", {}).get("id", ""))
	var saved: Dictionary = hub.get("save_service").load_world(world_id)
	_check(not saved.has("automation_jobs"), "new world schema does not persist automation tasks")
	_check(not saved.get("machines", {}).has("automation"), "machine schema remains unchanged by transient automation")
	if not world_id.is_empty():
		hub.get("save_service").delete_world(world_id)
	if hub.get("audio_service") != null:
		hub.get("audio_service").call("shutdown")
	hub.queue_free()
	await process_frame
	await process_frame


func _configure_machine_stack(
	world: FakeWorld,
	storage: Node,
	machine_position: Vector3i,
	machine_block_id: String
) -> void:
	world.set_block(machine_position, machine_block_id)
	var input_position := PolicyScript.input_position(machine_position)
	var output_position := PolicyScript.output_position(machine_position)
	world.set_block(input_position, "chest")
	world.set_block(output_position, "chest")
	storage.call(
		"ensure_container",
		PolicyScript.container_id(input_position),
		"chest",
		PolicyScript.CONTAINER_SLOT_COUNT
	)
	storage.call(
		"ensure_container",
		PolicyScript.container_id(output_position),
		"chest",
		PolicyScript.CONTAINER_SLOT_COUNT
	)


func _machine_id(machine_type: String, position: Vector3i) -> String:
	return "%s@%d,%d,%d" % [machine_type, position.x, position.y, position.z]


func _count_container_item(storage: Node, container_id: String, item_id: String) -> int:
	var total := 0
	for index in int(storage.call("get_slot_count", container_id)):
		var slot: Dictionary = storage.call("get_slot", container_id, index)
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
