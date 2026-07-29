extends SceneTree

const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const RangedRegistryScript = preload("res://src/combat/ranged_weapon_registry.gd")
const ShotPolicyScript = preload("res://src/combat/ranged_shot_policy.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_extension_and_crafting()
	await _test_equipment_and_policy()
	_test_atomic_duplicate_rejection()
	if failures.is_empty():
		print("QA RANGED COMBAT REGISTRY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANGED COMBAT REGISTRY FAILURE: %s" % failure)
		print(
			"QA RANGED COMBAT REGISTRY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_registry_extension_and_crafting() -> void:
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	root.add_child(inventory)
	root.add_child(crafting)
	await process_frame
	crafting.setup(inventory)
	crafting.set_station("workbench")
	_check(inventory.registry.has_item("bow"), "default item registry atomically includes the bow extension")
	_check(inventory.registry.has_item("arrow"), "default item registry atomically includes arrow ammunition")
	_check(inventory.registry.get_max_stack("bow") == 1, "bow remains a durable non-stackable equipment item")
	_check(inventory.registry.get_max_stack("arrow") == 64, "arrows use a bounded standard stack")
	_check(crafting.get_recipe("bow").get("output", {}).get("id", "") == "bow", "crafting registry includes the bow recipe")
	_check(crafting.get_recipe("arrows").get("output", {}).get("count", 0) == 4, "arrow recipe produces a bounded batch of four")
	inventory.clear()
	inventory.add_item("stick", 4)
	inventory.add_item("string", 3)
	inventory.add_item("stone", 1)
	inventory.add_item("feather", 1)
	_check(crafting.craft("bow"), "real crafting transaction creates a bow")
	_check(crafting.craft("arrows"), "real crafting transaction creates arrows")
	_check(inventory.count_item("bow") == 1, "bow output is committed exactly once")
	_check(inventory.count_item("arrow") == 4, "arrow output is committed exactly once")
	_check(inventory.count_item("stick") == 0, "shared ingredients are consumed atomically across both recipes")
	inventory.queue_free()
	crafting.queue_free()
	await process_frame


func _test_equipment_and_policy() -> void:
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	root.add_child(inventory)
	root.add_child(equipment)
	await process_frame
	equipment.setup(inventory.registry)
	inventory.clear()
	inventory.add_item("bow", 1, {"custom_name": "注册表验收弓"})
	var bow_index := _find_item_slot(inventory, "bow")
	_check(bow_index >= 0, "crafted bow can be found in a real inventory slot")
	_check(equipment.equip_from_inventory(inventory, bow_index), "bow equips through the existing atomic equipment transaction")
	_check(str(equipment.get_slot("main_hand").get("item_id", "")) == "bow", "existing main-hand state owns the bow")
	var registry = RangedRegistryScript.new()
	_check(registry.load_from_file(), "strict ranged profile registry loads dedicated data")
	_check(registry.profile_count() == 1, "first ranged release exposes one explicit profile")
	var profile := registry.get_profile("bow")
	_check(str(profile.get("ammo_item_id", "")) == "arrow", "bow profile declares its ammunition contract")
	_check(float(profile.get("maximum_speed", 0.0)) <= 96.0, "projectile speed remains inside the hard registry budget")
	var policy = ShotPolicyScript.new()
	var rejected := policy.evaluate_release(profile, 0.05, Vector3.FORWARD)
	_check(not bool(rejected.get("accepted", true)) and str(rejected.get("reason", "")) == "undercharged", "undercharged release is rejected without a transaction")
	var full := policy.evaluate_release(profile, float(profile.get("draw_seconds", 0.8)), Vector3.FORWARD)
	_check(bool(full.get("accepted", false)), "full draw produces an accepted shot plan")
	_check(is_equal_approx(float(full.get("damage", 0.0)), float(profile.get("maximum_damage", 0.0))), "full draw reaches the configured maximum damage")
	_check(is_equal_approx(float(full.get("speed", 0.0)), float(profile.get("maximum_speed", 0.0))), "full draw reaches the configured maximum speed")
	var saved_inventory := inventory.serialize()
	var saved_equipment := equipment.serialize()
	var restored_inventory = InventoryScript.new()
	var restored_equipment = EquipmentScript.new()
	root.add_child(restored_inventory)
	root.add_child(restored_equipment)
	await process_frame
	restored_equipment.setup(restored_inventory.registry)
	_check(restored_inventory.deserialize(saved_inventory), "inventory containing ranged content survives serialization")
	_check(restored_equipment.deserialize(saved_equipment), "equipped bow survives the existing equipment schema")
	_check(str(restored_equipment.get_slot("main_hand").get("item_id", "")) == "bow", "restored main hand retains the bow")
	for node: Node in [inventory, equipment, restored_inventory, restored_equipment]:
		node.queue_free()
	await process_frame


func _test_atomic_duplicate_rejection() -> void:
	var item_path := "user://ranged-duplicate-items.json"
	var recipe_path := "user://ranged-duplicate-recipes.json"
	_write_text(
		item_path,
		'{"schema_version":1,"items":[{"id":"duplicate","name":"A","max_stack":1},{"id":"duplicate","name":"B","max_stack":1}]}'
	)
	_write_text(
		recipe_path,
		'{"schema_version":1,"recipes":[{"id":"duplicate","station":"hand","ingredients":{},"output":{"id":"stone","count":1}},{"id":"duplicate","station":"hand","ingredients":{},"output":{"id":"stone","count":1}}]}'
	)
	var items = ItemRegistryScript.new()
	_check(not items.load_from_file(item_path), "duplicate item IDs reject the entire staged registry")
	_check(items.item_count() == 0, "failed item staging never commits a partial registry")
	var crafting = CraftingScript.new()
	_check(not crafting.load_recipes(recipe_path), "duplicate recipe IDs reject the entire staged registry")
	_check(crafting.recipe_count() == 0, "failed recipe staging never commits a partial registry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(item_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recipe_path))


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) == item_id:
			return index
	return -1


func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("unable to create fixture: %s" % path)
		return
	file.store_string(content)
	file.close()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
