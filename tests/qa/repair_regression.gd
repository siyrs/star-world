extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const RepairServiceScript = preload("res://src/repair/repair_service.gd")
const RepairEquipmentAdapterScript = preload("res://src/repair/repair_equipment_adapter.gd")
const RepairRegistryScript = preload("res://src/repair/repair_registry.gd")
const RepairPolicyScript = preload("res://src/repair/repair_policy.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FailingInventory:
	extends "res://src/inventory/inventory_service.gd"
	var fail_next_metadata_update := false

	func update_slot_metadata(index: int, metadata: Dictionary) -> bool:
		if fail_next_metadata_update:
			fail_next_metadata_update = false
			return false
		return super.update_slot_metadata(index, metadata)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_and_policy()
	await _test_inventory_repair_transaction()
	await _test_equipped_item_repair()
	await _test_failure_rolls_back_material()
	await _test_composition_root()
	if failures.is_empty():
		print("QA REPAIR PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA REPAIR FAILURE: %s" % failure)
		print("QA REPAIR FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var registry = RepairRegistryScript.new()
	var policy = RepairPolicyScript.new()
	_check(registry.profile_count() == 6, "repair registry loads all production profiles")
	_check(registry.get_station_block() == "repair_station", "repair registry exposes the station block")
	var profile: Dictionary = registry.get_profile_for_item("iron_pickaxe")
	_check(str(profile.get("material_item", "")) == "iron_ingot", "iron tools use iron ingots")
	var definition := {"id":"iron_pickaxe", "durability":251}
	var context := {
		"item_id":"iron_pickaxe",
		"maximum_durability":251,
		"remaining_durability":50,
	}
	var evaluation: Dictionary = policy.evaluate(profile, definition, context, 1)
	_check(bool(evaluation.get("success", false)), "repair policy accepts a damaged supported item")
	_check(int(evaluation.get("restore_amount", 0)) == 63, "repair ratio rounds up to a deterministic amount")
	_check(int(evaluation.get("target_durability", 0)) == 113, "repair policy computes target durability")
	var missing: Dictionary = policy.evaluate(profile, definition, context, 0)
	_check(str(missing.get("reason", "")) == "material_missing", "repair policy reports missing material")
	context["remaining_durability"] = 251
	var full: Dictionary = policy.evaluate(profile, definition, context, 4)
	_check(str(full.get("reason", "")) == "already_full", "repair policy protects full durability items")


func _test_inventory_repair_transaction() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var equipment_adapter = RepairEquipmentAdapterScript.new()
	var tools = ToolScript.new()
	var repair = RepairServiceScript.new()
	for node in [inventory, equipment, equipment_adapter, tools, repair]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	equipment_adapter.setup(equipment)
	tools.setup(inventory.registry)
	repair.setup(inventory.registry, inventory, equipment_adapter, tools)
	inventory.clear()
	inventory.add_item("iron_pickaxe", 1, {"durability":50, "custom_name":"星星的铁镐"})
	inventory.add_item("iron_ingot", 2)
	var event_counter := {"count":0}
	repair.repair_completed.connect(
		func(_result): event_counter["count"] = int(event_counter.get("count", 0)) + 1
	)
	var target := {"kind":"inventory", "slot_index":0, "target_id":"inventory:0"}
	var preview: Dictionary = repair.get_preview(target)
	_check(bool(preview.get("success", false)), "inventory repair preview is actionable")
	_check(str(preview.get("material_name", "")) == "铁锭", "repair preview has player-facing material name")
	var result: Dictionary = repair.repair_target(target)
	_check(bool(result.get("success", false)), "inventory item repairs successfully")
	_check(inventory.count_item("iron_ingot") == 1, "repair consumes exactly one material")
	var repaired: Dictionary = inventory.get_slot(0)
	_check(int(repaired.get("metadata", {}).get("durability", 0)) == 113, "repair writes the expected durability")
	_check(str(repaired.get("metadata", {}).get("custom_name", "")) == "星星的铁镐", "repair preserves unrelated metadata")
	_check(int(event_counter.get("count", 0)) == 1, "successful repair emits one event")
	inventory.update_slot_metadata(0, {"durability":251, "custom_name":"星星的铁镐"})
	var material_before := inventory.count_item("iron_ingot")
	var full_result: Dictionary = repair.repair_target(target)
	_check(str(full_result.get("reason", "")) == "already_full", "full durability target is rejected")
	_check(inventory.count_item("iron_ingot") == material_before, "full durability rejection consumes no material")
	host.queue_free()
	await process_frame
	await process_frame


func _test_equipped_item_repair() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var equipment_adapter = RepairEquipmentAdapterScript.new()
	var tools = ToolScript.new()
	var repair = RepairServiceScript.new()
	for node in [inventory, equipment, equipment_adapter, tools, repair]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	equipment_adapter.setup(equipment)
	tools.setup(inventory.registry)
	repair.setup(inventory.registry, inventory, equipment_adapter, tools)
	inventory.clear()
	inventory.add_item("iron_helmet", 1, {"durability":20, "custom_name":"守护头盔"})
	inventory.add_item("iron_ingot", 1)
	_check(equipment.equip_from_inventory(inventory, 0, "helmet"), "test fixture equips damaged armor")
	var target := {"kind":"equipment", "slot_id":"helmet", "target_id":"equipment:helmet"}
	var result: Dictionary = repair.repair_target(target)
	_check(bool(result.get("success", false)), "equipped armor repairs without unequipping")
	var helmet: Dictionary = equipment.get_slot("helmet")
	_check(int(helmet.get("metadata", {}).get("durability", 0)) == 62, "equipped armor receives ratio-based durability")
	_check(str(helmet.get("metadata", {}).get("custom_name", "")) == "守护头盔", "equipped repair preserves metadata")
	_check(inventory.count_item("iron_ingot") == 0, "equipped repair consumes inventory material")
	host.queue_free()
	await process_frame
	await process_frame


func _test_failure_rolls_back_material() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = FailingInventory.new()
	var equipment = EquipmentScript.new()
	var equipment_adapter = RepairEquipmentAdapterScript.new()
	var tools = ToolScript.new()
	var repair = RepairServiceScript.new()
	for node in [inventory, equipment, equipment_adapter, tools, repair]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	equipment_adapter.setup(equipment)
	tools.setup(inventory.registry)
	repair.setup(inventory.registry, inventory, equipment_adapter, tools)
	inventory.clear()
	inventory.add_item("stone_sword", 1, {"durability":10, "batch":"rollback"})
	inventory.add_item("cobblestone", 1)
	inventory.fail_next_metadata_update = true
	var target := {"kind":"inventory", "slot_index":0, "target_id":"inventory:0"}
	var result: Dictionary = repair.repair_target(target)
	_check(str(result.get("reason", "")) == "durability_update_failed", "metadata failure rejects the repair transaction")
	_check(inventory.count_item("cobblestone") == 1, "failed repair restores material")
	var sword: Dictionary = inventory.get_slot(0)
	_check(int(sword.get("metadata", {}).get("durability", 0)) == 10, "failed repair leaves durability unchanged")
	_check(str(sword.get("metadata", {}).get("batch", "")) == "rollback", "rollback preserves target metadata")
	host.queue_free()
	await process_frame
	await process_frame


func _test_composition_root() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var repair = hub.get("repair_service")
	var repair_interaction = hub.get("repair_interaction")
	var game_ui = hub.get("game_ui")
	_check(repair != null, "composition root mounts repair service")
	_check(repair_interaction != null, "composition root mounts repair interaction adapter")
	_check(
		repair != null and str(repair.call("get_station_block")) == "repair_station",
		"runtime repair service resolves the production station",
	)
	_check(
		hub.block_interaction.get_interaction_hint_for_item("repair_station", "").contains("修理台"),
		"repair interaction extension publishes a clear world hint",
	)
	_check(game_ui != null and game_ui.has_method("get_repair_panel"), "repair-enabled game UI exposes the repair panel")
	_check(hub.input_context.set_context(&"repair"), "repair is a valid input context")
	hub.input_context.set_context(&"menu")
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
