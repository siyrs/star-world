extends SceneTree

const Policy = preload("res://src/machine/machine_automation_policy.gd")
const Automation = preload("res://src/machine/machine_automation_service.gd")
const Router = preload("res://src/machine/machine_interaction_router.gd")
const Scheduler = preload("res://src/machine/machine_runtime_scheduler.gd")
const Inventory = preload("res://src/inventory/inventory_service.gd")
const ContainerStorage = preload("res://src/inventory/container_storage_service.gd")
const Furnace = preload("res://src/machine/furnace_service.gd")
const Stonecutter = preload("res://src/machine/stonecutter_service.gd")
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

	func open_stonecutter(_machine_id: String, _title: String = "石材切割机") -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy()
	await _test_atomic_container_transactions()
	await _test_real_machine_domains()
	await _test_production_hub()
	if failures.is_empty():
		print("QA MACHINE AUTOMATION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE AUTOMATION FAILURE: %s" % failure)
		print("QA MACHINE AUTOMATION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_policy() -> void:
	var parsed: Dictionary = Policy.parse_machine_position(&"furnace", "furnace@-2,10,7")
	_check(bool(parsed.get("success", false)), "stable machine id parses")
	_check(parsed.get("position", Vector3i.ZERO) == Vector3i(-2, 10, 7), "signed coordinates are preserved")
	_check(str(Policy.parse_machine_position(&"stonecutter", "furnace@0,0,0").get("reason", "")) == "machine_id_prefix", "wrong machine prefix is rejected")
	_check(Policy.input_position(Vector3i(1, 5, 2)) == Vector3i(1, 6, 2), "input chest is above")
	_check(Policy.output_position(Vector3i(1, 5, 2)) == Vector3i(1, 4, 2), "output chest is below")
	_check(Policy.container_id(Vector3i(1, 6, 2)) == "chest@1,6,2", "automation reuses stable chest ids")
	_check(Policy.transfer_count(64, 64, 64) == 8, "single transfer is capped at eight")
	_check(
		Policy.MAX_MACHINES_PER_CYCLE == 16
		and Policy.MAX_ITEMS_PER_CYCLE == 64
		and Policy.MAX_CONTAINER_SLOTS_PER_CYCLE == 256
		and Policy.MAX_TRANSFER_ATTEMPTS_PER_CYCLE == 128,
		"all cycle budgets are hard constants"
	)


func _test_atomic_container_transactions() -> void:
	var host := Node.new()
	var inventory = Inventory.new()
	var storage = ContainerStorage.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(storage)
	await process_frame
	storage.setup(inventory.registry)
	var container_id := "chest@atomic"
	storage.ensure_container(container_id, "chest", 2)
	storage.add_item(container_id, "wooden_pickaxe", 1, {"serial":1})
	storage.add_item(container_id, "wooden_pickaxe", 1, {"serial":2})
	var before: Dictionary = storage.get_container(container_id)
	var addition := [{"item_id":"stone", "count":1, "metadata":{}}]
	_check(not storage.can_transact_items(container_id, {}, addition), "full chest preflight rejects complete addition")
	_check(not bool(storage.transact_items(container_id, {}, addition).get("success", false)), "full chest transaction is rejected")
	_check(storage.get_container(container_id) == before, "rejected chest transaction performs zero writes")
	storage.remove_from_slot(container_id, 0, 1)
	storage.remove_from_slot(container_id, 1, 1)
	storage.add_item(container_id, "stone", 4)
	var swapped: Dictionary = storage.transact_items(
		container_id,
		{"stone":2},
		[{"item_id":"cobblestone", "count":2, "metadata":{}}]
	)
	_check(bool(swapped.get("success", false)), "chest removal and addition commit together")
	_check(_count_container_item(storage, container_id, "stone") == 2, "atomic chest removes exact source count")
	_check(_count_container_item(storage, container_id, "cobblestone") == 2, "atomic chest adds exact target count")
	host.queue_free()
	await process_frame
	await process_frame


func _test_real_machine_domains() -> void:
	var host := Node.new()
	var inventory = Inventory.new()
	var storage = ContainerStorage.new()
	var furnace = Furnace.new()
	var cutter = Stonecutter.new()
	var router = Router.new()
	var automation = Automation.new()
	var scheduler = Scheduler.new()
	var world = FakeWorld.new()
	var ui = FakeMachineUI.new()
	root.add_child(host)
	for node: Node in [inventory, storage, furnace, cutter, router, automation, scheduler, world, ui]:
		host.add_child(node)
	await process_frame
	storage.setup(inventory.registry)
	_check(bool(furnace.setup(inventory.registry)), "furnace initializes")
	_check(bool(cutter.setup(inventory.registry)), "stonecutter initializes")
	router.setup_ui(ui)
	_check(bool(router.register_machine_type(&"furnace", furnace, &"open_furnace", ["input","fuel","output"], "熔炉", "not empty").get("success", false)), "router registers furnace")
	_check(bool(router.register_machine_type(&"stonecutter", cutter, &"open_stonecutter", ["input","output"], "石材切割机", "not empty").get("success", false)), "router registers stonecutter")

	var furnace_pos := Vector3i(0, 10, 0)
	var cutter_pos := Vector3i(3, 10, 0)
	var furnace_id := _machine_id("furnace", furnace_pos)
	var cutter_id := _machine_id("stonecutter", cutter_pos)
	furnace.ensure_machine(furnace_id)
	cutter.ensure_machine(cutter_id)
	_configure_stack(world, storage, furnace_pos, "furnace")
	_configure_stack(world, storage, cutter_pos, "stonecutter")
	var furnace_input := Policy.container_id(Policy.input_position(furnace_pos))
	var furnace_output := Policy.container_id(Policy.output_position(furnace_pos))
	var cutter_input := Policy.container_id(Policy.input_position(cutter_pos))
	var cutter_output := Policy.container_id(Policy.output_position(cutter_pos))
	storage.add_item(furnace_input, "raw_iron", 2)
	storage.add_item(furnace_input, "coal", 1)
	storage.add_item(cutter_input, "stone", 2)
	storage.add_item(cutter_input, "apple", 3)

	_check(bool(automation.setup(router, storage)), "automation validates production ports")
	_check(bool(scheduler.register_domain(&"furnace", furnace).get("success", false)), "scheduler registers furnace")
	_check(bool(scheduler.register_domain(&"stonecutter", cutter).get("success", false)), "scheduler registers cutter")
	_check(bool(scheduler.register_domain(&"automation", automation).get("success", false)), "scheduler registers one automation domain")
	automation.attach_world(world)
	var supply_batch: Dictionary = scheduler.advance_time(0.5, true)
	var supply: Dictionary = supply_batch.get("domain_summaries", {}).get("automation", {})
	_check(int(supply.get("items_moved", 0)) == 5, "first cycle supplies exact machine inputs")
	_check(int(furnace.get_slot(furnace_id, "input").get("count", 0)) == 2, "upper chest supplies ore")
	_check(int(furnace.get_slot(furnace_id, "fuel").get("count", 0)) == 1, "upper chest supplies fuel")
	_check(int(cutter.get_slot(cutter_id, "input").get("count", 0)) == 2, "upper chest supplies stone")
	_check(_count_container_item(storage, cutter_input, "apple") == 3, "unsupported item remains untouched")

	var production_batch: Dictionary = scheduler.advance_time(12.1, true)
	var production: Dictionary = production_batch.get("domain_summaries", {}).get("automation", {})
	_check(int(production.get("output_items", 0)) == 6, "same batch collects both machine outputs")
	_check(_count_container_item(storage, furnace_output, "iron_ingot") == 2, "lower furnace chest receives ingots")
	_check(_count_container_item(storage, cutter_output, "stone_slab") == 4, "lower cutter chest receives slabs")
	_check(furnace.get_slot(furnace_id, "output").is_empty(), "furnace output clears only after chest commit")
	_check(cutter.get_slot(cutter_id, "output").is_empty(), "cutter output clears only after chest commit")

	var blocked_pos := Vector3i(6, 10, 0)
	var blocked_id := _machine_id("stonecutter", blocked_pos)
	cutter.open_machine(blocked_id)
	cutter.close_machine()
	_configure_stack(world, storage, blocked_pos, "stonecutter")
	var blocked_input := Policy.container_id(Policy.input_position(blocked_pos))
	var blocked_output := Policy.container_id(Policy.output_position(blocked_pos))
	storage.add_item(blocked_input, "stone", 1)
	for index in Policy.CONTAINER_SLOT_COUNT:
		storage.add_item(blocked_output, "wooden_pickaxe", 1, {"serial":index})
	automation.advance_machine_runtime(0.5, true)
	var full_before: Dictionary = storage.get_container(blocked_output)
	scheduler.advance_time(3.0, true)
	_check(storage.get_container(blocked_output) == full_before, "full lower chest performs zero partial writes")
	_check(int(cutter.get_slot(blocked_id, "output").get("count", 0)) == 2, "full lower chest leaves machine output intact")

	var cache_before := int(automation.get_runtime_snapshot().get("cache_rebuild_count", 0))
	var budget_ids: Array[String] = []
	for index in 20:
		var position := Vector3i(20 + index * 3, 10, 0)
		var id := _machine_id("stonecutter", position)
		budget_ids.append(id)
		world.set_block(position, "stonecutter")
		world.set_block(Policy.input_position(position), "chest")
		var input_id := Policy.container_id(Policy.input_position(position))
		storage.ensure_container(input_id, "chest", Policy.CONTAINER_SLOT_COUNT)
		storage.add_item(input_id, "stone", 1)
		cutter.open_machine(id)
		cutter.close_machine()
	var bounded: Dictionary = automation.advance_machine_runtime(0.5, true)
	_check(int(bounded.get("scanned_machine_count", 0)) <= 16, "cycle scans at most sixteen machines")
	_check(int(bounded.get("items_moved", 0)) <= 64, "cycle moves at most sixty-four items")
	_check(int(bounded.get("slots_scanned", 0)) <= 256, "cycle scans at most 256 chest slots")
	_check(int(bounded.get("transfer_attempts", 0)) <= 128, "cycle performs at most 128 transfer probes")
	automation.advance_machine_runtime(0.5, true)
	var supplied := 0
	for id: String in budget_ids:
		if int(cutter.get_slot(id, "input").get("count", 0)) == 1:
			supplied += 1
	_check(supplied == 20, "round-robin reaches machines beyond the first sixteen")
	_check(int(automation.get_runtime_snapshot().get("cache_rebuild_count", 0)) == cache_before, "normal cycles do not rebuild the full machine directory")

	var paused_chest := Policy.container_id(Policy.input_position(Vector3i(20, 10, 0)))
	storage.add_item(paused_chest, "stone", 1)
	var paused_before: Dictionary = storage.get_container(paused_chest)
	automation.advance_machine_runtime(1.0, false)
	_check(storage.get_container(paused_chest) == paused_before, "offline/no-event runtime performs zero automation")
	_check(not furnace.serialize().has("automation_jobs") and not cutter.serialize().has("automation_jobs"), "machine persistence excludes automation tasks")
	_check(not storage.serialize().has("automation_jobs"), "container persistence excludes automation tasks")
	var snapshot: Dictionary = automation.get_runtime_snapshot()
	_check(int(snapshot.get("tracked_machine_count", 0)) >= 23, "diagnostics expose event-maintained candidates")
	_check(int(snapshot.get("max_items_in_cycle", 0)) <= 64, "diagnostics preserve observed throughput budget")

	automation.shutdown()
	scheduler.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_hub() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var automation: Node = hub.get("machine_automation_service") as Node
	var scheduler: Node = hub.get("machine_runtime") as Node
	_check(automation != null, "production hub exposes automation service")
	_check(hub.get_node_or_null("MachineAutomationService") == automation, "automation has stable production node path")
	var runtime: Dictionary = scheduler.call("get_snapshot") if scheduler != null else {}
	_check("automation" in (runtime.get("registered_domains", []) as Array), "production scheduler owns automation domain")
	_check(int(runtime.get("domain_count", 0)) == 3, "production runtime has three domains")
	var character: Dictionary = hub.call("get_character_snapshot")
	_check(character.get("machine_runtime", {}).get("domains", {}).has("automation"), "character snapshot contains automation diagnostics")
	var save_service: Node = hub.get("save_service") as Node
	var created: Dictionary = save_service.call("create_world", "machine-automation-regression-%d" % Time.get_ticks_msec(), "star_continent", 771903)
	var world_id := str(created.get("metadata", {}).get("id", ""))
	var saved: Dictionary = save_service.call("load_world", world_id)
	_check(not saved.has("automation_jobs"), "world root excludes transient automation")
	_check(not saved.get("machines", {}).has("automation"), "machine schema remains unchanged")
	if not world_id.is_empty():
		save_service.call("delete_world", world_id)
	var audio: Node = hub.get("audio_service") as Node
	if audio != null:
		audio.call("shutdown")
	hub.queue_free()
	await process_frame
	await process_frame


func _configure_stack(world: FakeWorld, storage: Node, position: Vector3i, block_id: String) -> void:
	world.set_block(position, block_id)
	var input_position := Policy.input_position(position)
	var output_position := Policy.output_position(position)
	world.set_block(input_position, "chest")
	world.set_block(output_position, "chest")
	storage.call("ensure_container", Policy.container_id(input_position), "chest", Policy.CONTAINER_SLOT_COUNT)
	storage.call("ensure_container", Policy.container_id(output_position), "chest", Policy.CONTAINER_SLOT_COUNT)


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
