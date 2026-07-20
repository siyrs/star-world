extends SceneTree

const RecipeRegistryScript = preload("res://src/machine/stonecutter_recipe_registry.gd")
const StonecutterScript = preload("res://src/machine/stonecutter_service.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const SchedulerScript = preload("res://src/machine/machine_runtime_scheduler.gd")
const MigrationScript = preload("res://src/machine/machine_state_migration.gd")
const CompletionPolicyScript = preload("res://src/machine/machine_completion_policy.gd")
const RouterScript = preload("res://src/machine/machine_interaction_router.gd")
const BlockInteractionScript = preload("res://src/interaction/block_interaction_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const OverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


class FakeMachineUI:
	extends Node
	var furnace_open_count := 0
	var stonecutter_open_count := 0
	var last_machine_id := ""
	var last_title := ""

	func open_furnace(machine_id: String, title: String = "熔炉") -> bool:
		furnace_open_count += 1
		last_machine_id = machine_id
		last_title = title
		return true

	func open_stonecutter(
		machine_id: String,
		title: String = "石材切割机"
	) -> bool:
		stonecutter_open_count += 1
		last_machine_id = machine_id
		last_title = title
		return true

	func show_message(
		_message: String,
		_seconds: float = 2.0,
		_severity: String = "info",
		_dedupe_key: String = ""
	) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_recipe_registry()
	_test_state_migration()
	await _test_stonecutter_service()
	await _test_cross_domain_scheduler()
	await _test_machine_interaction_router()
	await _test_production_service_hub()
	if failures.is_empty():
		print("QA STONECUTTER MACHINE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA STONECUTTER MACHINE FAILURE: %s" % failure)
		print(
			"QA STONECUTTER MACHINE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_recipe_registry() -> void:
	var registry = RecipeRegistryScript.new()
	_check(registry.recipe_count() == 3, "stonecutter loads three production recipes")
	_check(registry.get_validation_errors().is_empty(), "production recipe data validates cleanly")
	var cobble: Dictionary = registry.get_recipe_for_input("cobblestone")
	var stone: Dictionary = registry.get_recipe_for_input("stone")
	var bricks: Dictionary = registry.get_recipe_for_input("stone_bricks")
	_check(str(cobble.get("output", {}).get("id", "")) == "stone_bricks", "cobblestone cuts into stone bricks")
	_check(int(stone.get("output", {}).get("count", 0)) == 2, "stone cuts into two slabs")
	_check(int(bricks.get("output", {}).get("count", 0)) == 2, "stone bricks cut into two slabs")
	_check(not registry.has_input("dirt"), "unsupported materials have no implicit stonecutter recipe")


func _test_state_migration() -> void:
	var raw := {
		"version": 99,
		"saved_at_unix": -20,
		"unknown_root": true,
		"furnaces": {
			"furnace@ok": {
				"input":{"item_id":"raw_iron", "count":1},
				"fuel":{"item_id":"coal", "count":1},
				"output":{},
				"progress_seconds":0.0,
				"burn_remaining_seconds":0.0,
				"burn_total_seconds":0.0,
			},
		},
		"stonecutters": {
			"stonecutter@ok": {
				"type":"wrong",
				"input":{"item_id":"stone", "count":999999},
				"output":{},
				"active_recipe_id":"cut_stone_slabs",
				"progress_seconds":INF,
				"unknown_field":"discard",
			},
			"bad\nid": {"input":{}},
		},
	}
	var normalized: Dictionary = MigrationScript.normalize_machine_state(raw)
	_check(int(normalized.get("version", 0)) == 1, "machine root remains schema version one")
	_check(int(normalized.get("saved_at_unix", -1)) == 0, "negative machine save time is normalized")
	_check((normalized.get("furnaces", {}) as Dictionary).size() == 1, "existing furnace state remains available")
	var cutters: Dictionary = normalized.get("stonecutters", {})
	_check(cutters.size() == 1 and cutters.has("stonecutter@ok"), "invalid stonecutter ids are removed")
	var cutter: Dictionary = cutters.get("stonecutter@ok", {})
	_check(str(cutter.get("type", "")) == "stonecutter", "stonecutter type comes from the authoritative domain")
	_check(int(cutter.get("input", {}).get("count", 0)) == 4096, "stonecutter slots are bounded before item-registry validation")
	_check(is_zero_approx(float(cutter.get("progress_seconds", -1.0))), "non-finite stonecutter progress is removed")
	_check(not cutter.has("unknown_field") and not normalized.has("unknown_root"), "stonecutter migration applies a strict whitelist")


func _test_stonecutter_service() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var service = StonecutterScript.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(service)
	await process_frame
	_check(bool(service.setup(inventory.registry)), "stonecutter validates its item and recipe registries")
	_check(service.ensure_machine("stonecutter@one"), "stonecutter creates a stable machine instance")
	inventory.clear()
	inventory.add_item("stone", 2)
	_check(service.transfer_from_inventory(inventory, 0, service.SLOT_INPUT, "stonecutter@one"), "stone input transfers through the production inventory contract")
	var before: Dictionary = service.get_machine_snapshot("stonecutter@one")
	_check(int(before.get("queued_jobs", 0)) == 2, "stonecutter snapshot exposes both queued jobs")
	_check(int(before.get("queued_output_count", 0)) == 4, "stonecutter queue exposes four pending slabs")
	_check(is_equal_approx(float(before.get("estimated_total_seconds", 0.0)), 5.0), "stonecutter snapshot exposes deterministic queue ETA")
	var events: Array[Dictionary] = []
	service.item_processed.connect(
		func(machine_id: String, recipe_id: String, output: Dictionary) -> void:
			events.append({
				"machine_type":"stonecutter",
				"machine_id":machine_id,
				"recipe_id":recipe_id,
				"output":output.duplicate(true),
			})
	)
	var changed: Array[String] = service.advance_time(2.6, true)
	_check(changed == ["stonecutter@one"], "bounded advance reports the changed stonecutter")
	_check(events.size() == 1, "first stonecutter job emits one domain completion")
	var after: Dictionary = service.get_machine_snapshot("stonecutter@one")
	_check(int(after.get("output", {}).get("count", 0)) == 2, "first job creates two stone slabs")
	_check(int(after.get("queued_jobs", 0)) == 1, "one queued job remains after the first completion")
	_check(not service.can_remove_machine("stonecutter@one"), "non-empty stonecutter is protected from removal")
	_check(service.transfer_to_inventory(inventory, service.SLOT_OUTPUT, "stonecutter@one"), "stonecutter output transfers back to inventory")
	_check(inventory.count_item("stone_slab") == 2, "real inventory receives the cut slabs")
	host.queue_free()
	await process_frame
	await process_frame


func _test_cross_domain_scheduler() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var furnace = FurnaceScript.new()
	var cutter = StonecutterScript.new()
	var scheduler = SchedulerScript.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(furnace)
	host.add_child(cutter)
	host.add_child(scheduler)
	await process_frame
	_check(bool(furnace.setup(inventory.registry)), "furnace remains a valid machine domain")
	_check(bool(cutter.setup(inventory.registry)), "stonecutter is a second valid machine domain")
	var now := int(Time.get_unix_time_from_system())
	furnace.deserialize({
		"version":1,
		"saved_at_unix":now,
		"furnaces":{
			"furnace@iron":{
				"type":"furnace",
				"input":{"item_id":"raw_iron", "count":1},
				"fuel":{"item_id":"coal", "count":1},
				"output":{},
				"progress_seconds":0.0,
				"burn_remaining_seconds":0.0,
				"burn_total_seconds":0.0,
			},
		},
	})
	cutter.deserialize({
		"version":1,
		"saved_at_unix":now,
		"stonecutters":{
			"stonecutter@slabs":{
				"type":"stonecutter",
				"input":{"item_id":"stone", "count":2},
				"output":{},
				"progress_seconds":0.0,
			},
		},
	})
	_check(bool(scheduler.register_domain(&"furnace", furnace).get("success", false)), "shared scheduler registers furnace")
	_check(bool(scheduler.register_domain(&"stonecutter", cutter).get("success", false)), "shared scheduler registers stonecutter")
	var events: Array[Dictionary] = []
	furnace.item_smelted.connect(
		func(machine_id: String, recipe_id: String, output: Dictionary) -> void:
			events.append({"machine_type":"furnace", "machine_id":machine_id, "recipe_id":recipe_id, "output":output.duplicate(true)})
	)
	cutter.item_processed.connect(
		func(machine_id: String, recipe_id: String, output: Dictionary) -> void:
			events.append({"machine_type":"stonecutter", "machine_id":machine_id, "recipe_id":recipe_id, "output":output.duplicate(true)})
	)
	var batch: Dictionary = scheduler.advance_time(6.1, true)
	_check(int(batch.get("advanced_domain_count", 0)) == 2, "one scheduler tick advances both production machine domains")
	_check(int(batch.get("changed_machine_count", 0)) == 2, "cross-domain batch reports both changed machine instances")
	_check(events.size() == 3, "one furnace job and two cutting jobs complete in the same batch")
	_check(int(furnace.get_machine_snapshot("furnace@iron").get("output", {}).get("count", 0)) == 1, "shared tick produces one iron ingot")
	_check(int(cutter.get_machine_snapshot("stonecutter@slabs").get("output", {}).get("count", 0)) == 4, "shared tick produces four stone slabs")
	var summary: Dictionary = CompletionPolicyScript.build(events, inventory.registry)
	_check(int(summary.get("machine_type_count", 0)) == 2, "completion summary preserves both machine domain types")
	_check("furnace" in (summary.get("machine_types", []) as Array) and "stonecutter" in (summary.get("machine_types", []) as Array), "completion summary identifies furnace and stonecutter")
	_check(int(summary.get("completed_jobs", 0)) == 3, "completion summary preserves all cross-domain jobs")
	var runtime: Dictionary = scheduler.get_snapshot()
	_check(int(runtime.get("domain_count", 0)) == 2 and int(runtime.get("machine_count", 0)) == 2, "scheduler diagnostics aggregate two domains and two machines")
	host.queue_free()
	await process_frame
	await process_frame


func _test_machine_interaction_router() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var furnace = FurnaceScript.new()
	var cutter = StonecutterScript.new()
	var ui = FakeMachineUI.new()
	var router = RouterScript.new()
	var interaction = BlockInteractionScript.new()
	var world = FakeWorld.new()
	root.add_child(host)
	for node: Node in [inventory, furnace, cutter, ui, router, interaction, world]:
		host.add_child(node)
	await process_frame
	furnace.setup(inventory.registry)
	cutter.setup(inventory.registry)
	router.setup_ui(ui)
	_check(bool(router.register_machine_type(&"furnace", furnace, &"open_furnace", ["input","fuel","output"], "熔炉", "furnace full").get("success", false)), "router registers furnace machine type")
	_check(bool(router.register_machine_type(&"stonecutter", cutter, &"open_stonecutter", ["input","output"], "石材切割机", "stonecutter full").get("success", false)), "router registers stonecutter machine type")
	_check(str(router.register_machine_type(&"stonecutter", cutter, &"open_stonecutter", ["input"], "duplicate", "").get("reason", "")) == "duplicate_machine_type", "router rejects duplicate machine types")
	interaction.setup(ui, null, inventory, router)
	var position := Vector3i(3, 8, -5)
	_check(interaction.interact(world, position, "stonecutter"), "block interaction opens stonecutter through the generic router")
	var machine_id := interaction.get_machine_id(world, position, "stonecutter")
	_check(machine_id == "stonecutter@3,8,-5", "stonecutter uses stable type-prefixed position ids")
	_check(ui.stonecutter_open_count == 1 and ui.last_machine_id == machine_id, "router invokes the real stonecutter UI port")
	inventory.clear()
	inventory.add_item("cobblestone", 1)
	_check(cutter.transfer_from_inventory(inventory, 0, cutter.SLOT_INPUT, machine_id), "router-owned stonecutter receives real input")
	_check(not interaction.can_break_block(world, position, "stonecutter"), "generic block interaction protects non-empty stonecutter")
	cutter.transfer_to_inventory(inventory, cutter.SLOT_INPUT, machine_id)
	_check(interaction.can_break_block(world, position, "stonecutter"), "empty stonecutter becomes removable")
	interaction.on_block_removed(world, position, "stonecutter")
	_check(not cutter.has_machine(machine_id), "block removal deletes only the matching stonecutter state")
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_service_hub() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var participant: Node = hub.get("machine_runtime_participant")
	var scheduler: Node = hub.get("machine_runtime")
	var cutter: Node = hub.get("stonecutter_service")
	var router: Node = hub.get("machine_interaction_router")
	_check(participant != null and scheduler != null and cutter != null and router != null, "production hub exposes stonecutter Machine Base ports")
	_check(hub.get_node_or_null("StonecutterService") == cutter, "stonecutter keeps a stable production node path")
	_check(hub.get_node_or_null("MachineInteractionRouter") == router, "machine router keeps a stable production node path")
	var scheduler_snapshot: Dictionary = scheduler.call("get_snapshot")
	_check(int(scheduler_snapshot.get("domain_count", 0)) == 2, "production scheduler owns furnace and stonecutter domains")
	_check(router.call("has_machine_type", &"furnace") and router.call("has_machine_type", &"stonecutter"), "production router exposes both machine types")
	_check(hub.game_ui.has_method("open_stonecutter") and hub.game_ui.get_stonecutter_panel() != null, "production GameUI mounts the stonecutter overlay")
	_check(OverlayIds.has_unique_ids() and OverlayIds.STONECUTTER == 9, "stonecutter overlay id remains unique")
	var state: Dictionary = hub.save_service.create_world(
		"stonecutter-machine-%d" % Time.get_ticks_msec(),
		"star_continent",
		741205
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	var now := int(Time.get_unix_time_from_system())
	state["machines"] = {
		"version":1,
		"saved_at_unix":now,
		"furnaces":{
			"furnace@one":{"type":"furnace", "input":{"item_id":"raw_iron", "count":1}, "fuel":{"item_id":"coal", "count":1}, "output":{}, "progress_seconds":0.0, "burn_remaining_seconds":0.0, "burn_total_seconds":0.0},
		},
		"stonecutters":{
			"stonecutter@one":{"type":"stonecutter", "input":{"item_id":"stone", "count":2}, "output":{}, "progress_seconds":0.0},
		},
	}
	hub.call("_begin_world", state)
	hub.call("activate_gameplay")
	var announced: Array[Dictionary] = []
	participant.machine_batch_announced.connect(
		func(summary: Dictionary) -> void: announced.append(summary.duplicate(true))
	)
	scheduler.call("advance_time", 6.1, true)
	for _frame in 3:
		await process_frame
	_check(announced.size() == 1, "production participant coalesces furnace and stonecutter completions")
	if not announced.is_empty():
		_check(int(announced[0].get("machine_type_count", 0)) == 2, "production completion batch records both machine types")
	_check(bool(hub.call("save_current")), "stonecutter joins the production atomic save transaction")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check((loaded.get("machines", {}).get("furnaces", {}) as Dictionary).size() == 1, "production save preserves furnace state")
	_check((loaded.get("machines", {}).get("stonecutters", {}) as Dictionary).size() == 1, "production save preserves stonecutter state")
	var character: Dictionary = hub.call("get_character_snapshot")
	_check(int(character.get("machine_runtime", {}).get("domain_count", 0)) == 2, "character diagnostics expose both machine domains")
	_check(character.has("machine_interactions"), "character diagnostics expose generic machine interaction state")
	hub.call("return_to_menu")
	_check(not scheduler.call("is_active"), "return-to-menu stops both machine domains")
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	for _frame in 5:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
