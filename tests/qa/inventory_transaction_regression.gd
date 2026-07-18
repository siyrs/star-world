extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const TransactionPolicyScript = preload("res://src/inventory/inventory_transaction_policy.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_rejections()
	await _test_atomic_bundle_capacity()
	await _test_atomic_consume_and_crafting()
	await _test_metadata_stacking()
	if failures.is_empty():
		print("QA INVENTORY TRANSACTION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA INVENTORY TRANSACTION FAILURE: %s" % failure)
		print("QA INVENTORY TRANSACTION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_policy_rejections() -> void:
	var inventory = InventoryScript.new(9, 9)
	var unknown := TransactionPolicyScript.plan(
		inventory.slots,
		inventory.registry,
		{},
		[{"item_id":"missing_item", "count":1}]
	)
	_check(not bool(unknown.get("success", true)), "transaction policy rejects unknown output items")
	_check(str(unknown.get("reason", "")) == "unknown_item", "unknown item rejection has an explicit reason")
	var invalid := TransactionPolicyScript.plan(
		inventory.slots,
		inventory.registry,
		{},
		[{"item_id":"torch", "count":0}]
	)
	_check(str(invalid.get("reason", "")) == "invalid_addition", "zero-count additions are rejected")


func _test_atomic_bundle_capacity() -> void:
	var inventory = InventoryScript.new(9, 9)
	root.add_child(inventory)
	_check(inventory.add_item("dirt", 512) == 0, "eight full dirt stacks fit before the bundle test")
	var before := inventory.serialize()
	var event_count := [0]
	inventory.inventory_changed.connect(func() -> void: event_count[0] += 1)
	var rejected: Dictionary = inventory.transact_items(
		{},
		[
			{"item_id":"wooden_pickaxe", "count":1},
			{"item_id":"iron_pickaxe", "count":1},
		]
	)
	_check(not bool(rejected.get("success", true)), "multi-item bundle is rejected when only one slot is free")
	_check(str(rejected.get("reason", "")) == "inventory_full", "bundle capacity rejection is explicit")
	_check(inventory.serialize() == before, "failed bundle leaves every inventory slot unchanged")
	_check(int(event_count[0]) == 0, "failed transaction emits no inventory_changed event")
	inventory.remove_from_slot(0, 64)
	event_count[0] = 0
	var accepted: Dictionary = inventory.transact_items(
		{},
		[
			{"item_id":"wooden_pickaxe", "count":1},
			{"item_id":"iron_pickaxe", "count":1},
		]
	)
	_check(bool(accepted.get("success", false)), "bundle succeeds after two slots are available")
	_check(inventory.count_item("wooden_pickaxe") == 1, "atomic bundle adds the wooden tool")
	_check(inventory.count_item("iron_pickaxe") == 1, "atomic bundle adds the iron tool")
	_check(int(event_count[0]) == 1, "successful multi-item transaction emits one inventory_changed event")
	inventory.queue_free()
	await process_frame


func _test_atomic_consume_and_crafting() -> void:
	var inventory = InventoryScript.new(9, 9)
	root.add_child(inventory)
	inventory.add_item("oak_planks", 3)
	inventory.add_item("stick", 2)
	var event_count := [0]
	inventory.inventory_changed.connect(func() -> void: event_count[0] += 1)
	var transaction: Dictionary = inventory.transact_items(
		{"oak_planks":3, "stick":2},
		[{"item_id":"wooden_pickaxe", "count":1}]
	)
	_check(bool(transaction.get("success", false)), "consume-and-grant transaction succeeds")
	_check(inventory.count_item("oak_planks") == 0 and inventory.count_item("stick") == 0, "transaction consumes all requirements")
	_check(inventory.count_item("wooden_pickaxe") == 1, "transaction grants the output")
	_check(int(event_count[0]) == 1, "consume-and-grant transaction publishes one inventory refresh")
	var before_missing := inventory.serialize()
	var missing: Dictionary = inventory.transact_items(
		{"diamond":2},
		[{"item_id":"diamond_pickaxe", "count":1}]
	)
	_check(str(missing.get("reason", "")) == "requirements_missing", "missing requirements reject the transaction")
	_check(inventory.serialize() == before_missing, "missing requirements do not mutate the inventory")
	inventory.queue_free()

	var crafting_inventory = InventoryScript.new(9, 9)
	var crafting = CraftingScript.new()
	root.add_child(crafting_inventory)
	root.add_child(crafting)
	crafting.setup(crafting_inventory)
	crafting.set_station("workbench")
	crafting_inventory.add_item("oak_planks", 3)
	crafting_inventory.add_item("stick", 2)
	var crafting_events := [0]
	crafting_inventory.inventory_changed.connect(func() -> void: crafting_events[0] += 1)
	_check(crafting.craft("wooden_pickaxe"), "production crafting succeeds through the transaction API")
	_check(crafting_inventory.count_item("wooden_pickaxe") == 1, "transactional crafting places the output")
	_check(int(crafting_events[0]) == 1, "transactional crafting emits a single inventory refresh")
	var before_failed_craft := crafting_inventory.serialize()
	_check(not crafting.craft("diamond_pickaxe"), "crafting still rejects missing requirements")
	_check(crafting_inventory.serialize() == before_failed_craft, "failed crafting preserves the exact inventory snapshot")
	crafting.queue_free()
	crafting_inventory.queue_free()
	await process_frame
	await process_frame


func _test_metadata_stacking() -> void:
	var inventory = InventoryScript.new(9, 9)
	root.add_child(inventory)
	inventory.add_item("torch", 60, {"batch":"survey"})
	var transaction: Dictionary = inventory.transact_items(
		{},
		[
			{"item_id":"torch", "count":8, "metadata":{"batch":"survey"}},
			{"item_id":"torch", "count":1, "metadata":{"batch":"other"}},
		]
	)
	_check(bool(transaction.get("success", false)), "transaction supports metadata-aware additions")
	_check(int(inventory.get_slot(0).get("count", 0)) == 64, "matching metadata fills the existing stack first")
	_check(inventory.get_slot(1).get("metadata", {}).get("batch", "") == "survey", "matching overflow keeps its metadata")
	_check(inventory.get_slot(2).get("metadata", {}).get("batch", "") == "other", "different metadata receives a separate stack")
	inventory.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
