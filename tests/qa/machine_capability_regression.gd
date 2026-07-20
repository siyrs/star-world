extends SceneTree

const CapabilityPolicyScript = preload("res://src/machine/machine_capability_policy.gd")
const RouterScript = preload("res://src/machine/machine_interaction_router.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const StonecutterScript = preload("res://src/machine/stonecutter_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


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
	_test_pure_policy()
	await _test_atomic_machine_transactions()
	await _test_production_hub_contract()
	if failures.is_empty():
		print("QA MACHINE CAPABILITY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE CAPABILITY FAILURE: %s" % failure)
		print(
			"QA MACHINE CAPABILITY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_pure_policy() -> void:
	var normalized: Dictionary = CapabilityPolicyScript.normalize_slot_contracts([
		{"id":"input", "directions":["insert"], "transaction_limit":32},
		{"id":"output", "directions":["extract"], "transaction_limit":64},
	])
	_check(bool(normalized.get("success", false)), "explicit slot capabilities normalize")
	var by_id: Dictionary = normalized.get("slots_by_id", {})
	_check(
		CapabilityPolicyScript.has_direction(by_id.get("input", {}), "insert"),
		"input capability exposes insert direction"
	)
	_check(
		CapabilityPolicyScript.has_direction(by_id.get("output", {}), "extract"),
		"output capability exposes extract direction"
	)
	_check(
		str(CapabilityPolicyScript.normalize_slot_contracts([
			{"id":"input", "directions":["insert"]},
			{"id":"input", "directions":["extract"]},
		]).get("reason", "")) == "duplicate_slot",
		"duplicate capability slots are rejected"
	)
	_check(
		str(CapabilityPolicyScript.normalize_slot_contracts([
			{"id":"input", "directions":["teleport"]},
		]).get("reason", "")) == "invalid_direction",
		"unknown capability directions are rejected"
	)
	_check(
		str(CapabilityPolicyScript.normalize_requested_count(65, 65, 64).get("reason", ""))
		== "transaction_limit",
		"machine transfers reject more than 64 items"
	)
	_check(
		CapabilityPolicyScript.slot_capacity({}, "stone", {}, 64) == 64,
		"empty machine slot exposes the item stack capacity"
	)
	_check(
		CapabilityPolicyScript.slot_capacity(
			{"item_id":"stone", "count":60}, "stone", {}, 64
		) == 4,
		"matching machine slot exposes only remaining capacity"
	)
	_check(
		CapabilityPolicyScript.slot_capacity(
			{"item_id":"stone", "count":1}, "cobblestone", {}, 64
		) == 0,
		"mixed machine stacks have zero insertion capacity"
	)


func _test_atomic_machine_transactions() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var furnace = FurnaceScript.new()
	var cutter = StonecutterScript.new()
	var router = RouterScript.new()
	var ui = FakeMachineUI.new()
	root.add_child(host)
	for node: Node in [inventory, furnace, cutter, router, ui]:
		host.add_child(node)
	await process_frame
	_check(bool(furnace.setup(inventory.registry)), "production furnace initializes")
	_check(bool(cutter.setup(inventory.registry)), "production stonecutter initializes")
	router.setup_ui(ui)
	_check(
		bool(router.register_machine_type(
			&"furnace", furnace, &"open_furnace", ["input","fuel","output"],
			"熔炉", "furnace not empty"
		).get("success", false)),
		"capability router registers furnace"
	)
	_check(
		bool(router.register_machine_type(
			&"stonecutter", cutter, &"open_stonecutter", ["input","output"],
			"石材切割机", "stonecutter not empty"
		).get("success", false)),
		"capability router registers stonecutter"
	)
	_check(furnace.ensure_machine("furnace@capability"), "furnace instance exists")
	_check(cutter.ensure_machine("stonecutter@capability"), "stonecutter instance exists")

	var furnace_capabilities: Dictionary = router.get_machine_capabilities(
		&"furnace", "furnace@capability"
	)
	var cutter_capabilities: Dictionary = router.get_machine_capabilities(
		&"stonecutter", "stonecutter@capability"
	)
	_check(
		(furnace_capabilities.get("slots", []) as Array).size() == 3,
		"furnace exposes three capability slots"
	)
	_check(
		(cutter_capabilities.get("slots", []) as Array).size() == 2,
		"stonecutter exposes two capability slots"
	)
	_check(
		CapabilityPolicyScript.has_direction(
			router.get_slot_contract(&"furnace", "output"), "extract"
		),
		"furnace output is extract-only through automation"
	)
	_check(
		not CapabilityPolicyScript.has_direction(
			router.get_slot_contract(&"furnace", "output"), "insert"
		),
		"furnace output rejects automated insertion"
	)

	inventory.clear()
	inventory.add_item("raw_iron", 3)
	inventory.add_item("coal", 2)
	inventory.add_item("stone", 4)
	var iron_index := _find_slot(inventory, "raw_iron")
	var coal_index := _find_slot(inventory, "coal")
	var stone_index := _find_slot(inventory, "stone")
	var iron_insert: Dictionary = router.insert_transaction(
		&"furnace", "furnace@capability", "input", inventory, iron_index, 2
	)
	_check(bool(iron_insert.get("success", false)), "capability inserts an exact iron count")
	_check(inventory.count_item("raw_iron") == 1, "exact insert removes only requested iron")
	_check(
		int(furnace.get_slot("furnace@capability", "input").get("count", 0)) == 2,
		"exact insert commits two iron to the furnace"
	)
	var fuel_insert: Dictionary = router.insert_transaction(
		&"furnace", "furnace@capability", "fuel", inventory, coal_index, 1
	)
	_check(bool(fuel_insert.get("success", false)), "capability inserts one fuel item")
	var stone_insert: Dictionary = router.insert_transaction(
		&"stonecutter", "stonecutter@capability", "input", inventory, stone_index, 3
	)
	_check(bool(stone_insert.get("success", false)), "capability inserts three stone items")
	_check(inventory.count_item("stone") == 1, "stonecutter insert preserves the unrequested stone")

	var before_direction_failure: Dictionary = inventory.serialize()
	var direction_failure: Dictionary = router.insert_transaction(
		&"furnace", "furnace@capability", "output", inventory,
		_find_slot(inventory, "raw_iron"), 1
	)
	_check(
		str(direction_failure.get("reason", "")) == "direction_not_allowed",
		"capability rejects insertion into output"
	)
	_check(inventory.serialize() == before_direction_failure, "direction rejection performs zero inventory writes")

	inventory.add_item("apple", 1)
	var apple_index := _find_slot(inventory, "apple")
	var before_unsupported: Dictionary = inventory.serialize()
	var unsupported: Dictionary = router.insert_transaction(
		&"furnace", "furnace@capability", "input", inventory, apple_index, 1
	)
	_check(not bool(unsupported.get("success", false)), "machine service rejects unsupported capability input")
	_check(inventory.serialize() == before_unsupported, "unsupported insert leaves inventory unchanged")
	_check(
		int(furnace.get_slot("furnace@capability", "input").get("count", 0)) == 2,
		"unsupported insert leaves machine input unchanged"
	)

	furnace.advance_time(12.1, true)
	cutter.advance_time(7.6, true)
	_check(
		int(furnace.get_slot("furnace@capability", "output").get("count", 0)) == 2,
		"furnace produces two capability-test outputs"
	)
	_check(
		int(cutter.get_slot("stonecutter@capability", "output").get("count", 0)) == 6,
		"stonecutter produces six capability-test outputs"
	)

	var full_inventory = InventoryScript.new(9, 9)
	host.add_child(full_inventory)
	await process_frame
	for index in 9:
		full_inventory.add_item("wooden_pickaxe", 1, {"serial":index})
	var full_before: Dictionary = full_inventory.serialize()
	var cutter_before: Dictionary = cutter.get_slot("stonecutter@capability", "output")
	var blocked_extract: Dictionary = router.extract_transaction(
		&"stonecutter", "stonecutter@capability", "output", full_inventory, 2
	)
	_check(
		str(blocked_extract.get("reason", "")) == "inventory_full",
		"full inventory rejects capability extraction"
	)
	_check(full_inventory.serialize() == full_before, "failed extraction leaves full inventory byte-for-byte unchanged")
	_check(
		cutter.get_slot("stonecutter@capability", "output") == cutter_before,
		"failed extraction leaves machine output unchanged"
	)

	var partial_extract: Dictionary = router.extract_transaction(
		&"stonecutter", "stonecutter@capability", "output", inventory, 2
	)
	_check(bool(partial_extract.get("success", false)), "capability extracts an exact partial output count")
	_check(inventory.count_item("stone_slab") == 2, "inventory receives exactly two slabs")
	_check(
		int(cutter.get_slot("stonecutter@capability", "output").get("count", 0)) == 4,
		"partial extraction preserves four machine outputs"
	)
	var remaining_extract: Dictionary = router.extract_transaction(
		&"stonecutter", "stonecutter@capability", "output", inventory
	)
	_check(bool(remaining_extract.get("success", false)), "zero count extracts the whole remaining slot")
	_check(inventory.count_item("stone_slab") == 6, "inventory receives the complete remaining slab stack")
	_check(cutter.get_slot("stonecutter@capability", "output").is_empty(), "whole-slot extraction clears machine output")

	var furnace_extract: Dictionary = router.extract_transaction(
		&"furnace", "furnace@capability", "output", inventory, 1
	)
	_check(bool(furnace_extract.get("success", false)), "same capability path extracts furnace output")
	_check(inventory.count_item("iron_ingot") == 1, "inventory receives one furnace output")
	_check(
		int(furnace.get_slot("furnace@capability", "output").get("count", 0)) == 1,
		"furnace retains unrequested output"
	)
	var wrong_extract: Dictionary = router.extract_transaction(
		&"furnace", "furnace@capability", "input", inventory, 1
	)
	_check(
		str(wrong_extract.get("reason", "")) == "direction_not_allowed",
		"automation cannot extract from a declared insert-only slot"
	)

	var router_snapshot: Dictionary = router.get_snapshot()
	_check(int(router_snapshot.get("machine_type_count", 0)) == 2, "capability diagnostics retain both machine types")
	_check(int(router_snapshot.get("transfer_success_count", 0)) == 6, "capability diagnostics count successful transfers")
	_check(int(router_snapshot.get("transfer_rejection_count", 0)) >= 4, "capability diagnostics count rejected transfers")
	_check(int(router_snapshot.get("inserted_item_count", 0)) == 6, "capability diagnostics total inserted items")
	_check(int(router_snapshot.get("extracted_item_count", 0)) == 7, "capability diagnostics total extracted items")

	var machine_save := {
		"version":1,
		"furnaces":furnace.serialize().get("furnaces", {}),
		"stonecutters":cutter.serialize().get("stonecutters", {}),
	}
	_check(not machine_save.has("last_transfer"), "automation transaction diagnostics do not enter machine persistence")
	_check(not machine_save.has("automation_jobs"), "transient automation jobs are not persisted")

	host.queue_free()
	await process_frame
	await process_frame


func _test_production_hub_contract() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var router: Node = hub.get("machine_interaction_router") as Node
	_check(router != null, "production ServiceHub exposes the machine capability router")
	if router != null:
		var furnace_capabilities: Dictionary = router.call("get_machine_capabilities", &"furnace")
		var cutter_capabilities: Dictionary = router.call("get_machine_capabilities", &"stonecutter")
		_check((furnace_capabilities.get("slots", []) as Array).size() == 3, "production furnace capability is mounted")
		_check((cutter_capabilities.get("slots", []) as Array).size() == 2, "production stonecutter capability is mounted")
		var character: Dictionary = hub.call("get_character_snapshot")
		_check(
			(character.get("machine_interactions", {}).get("capabilities", {}) as Dictionary).size() == 2,
			"production character diagnostics expose both capability contracts"
		)
	hub.queue_free()
	await process_frame
	await process_frame


func _find_slot(inventory: Node, item_id: String) -> int:
	var raw_slots: Variant = inventory.get("slots")
	if raw_slots is not Array:
		return -1
	for index in raw_slots.size():
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
