extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const RegistryScript = preload("res://src/combat/ranged_weapon_registry.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_content_and_crafting()
	await _test_equipment_metadata_persistence()
	_test_profile_bounds_and_rejection()
	if failures.is_empty():
		print("QA FIREARM REGISTRY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA FIREARM REGISTRY FAILURE: %s" % failure)
	print("QA FIREARM REGISTRY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_content_and_crafting() -> void:
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	root.add_child(inventory)
	root.add_child(crafting)
	await process_frame
	crafting.setup(inventory)
	crafting.set_station("workbench")
	for item_id: String in [
		"gunpowder", "light_round", "shotgun_shell",
		"star_pistol", "frontier_carbine", "scattergun",
	]:
		_check(inventory.registry.has_item(item_id), "atomic item registry includes firearm content: %s" % item_id)
	_check(inventory.registry.get_max_stack("light_round") == 64, "light rounds retain a bounded stack of sixty-four")
	_check(inventory.registry.get_max_stack("shotgun_shell") == 32, "shotgun shells retain a smaller bounded stack")
	for recipe_id: String in [
		"gunpowder_batch", "light_rounds", "shotgun_shells",
		"star_pistol", "frontier_carbine", "scattergun",
	]:
		_check(not crafting.get_recipe(recipe_id).is_empty(), "atomic crafting registry includes firearm recipe: %s" % recipe_id)
	inventory.clear()
	inventory.add_item("coal", 2)
	inventory.add_item("sand", 2)
	inventory.add_item("iron_ingot", 6)
	inventory.add_item("oak_planks", 1)
	inventory.add_item("string", 1)
	_check(crafting.craft("gunpowder_batch"), "real crafting transaction creates gunpowder")
	_check(crafting.craft("light_rounds"), "real crafting transaction creates twelve light rounds")
	_check(crafting.craft("star_pistol"), "real crafting transaction creates a pistol")
	_check(inventory.count_item("gunpowder") == 2, "ammo crafting consumes exactly half the gunpowder batch")
	_check(inventory.count_item("light_round") == 12, "light round output is committed exactly once")
	_check(inventory.count_item("star_pistol") == 1, "pistol output is committed exactly once")
	inventory.queue_free()
	crafting.queue_free()
	await process_frame


func _test_equipment_metadata_persistence() -> void:
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	root.add_child(inventory)
	root.add_child(equipment)
	await process_frame
	equipment.setup(inventory.registry)
	inventory.clear()
	inventory.add_item("star_pistol", 1, {"durability": 420, "magazine_rounds": 3})
	var pistol_index := _find_item_slot(inventory, "star_pistol")
	_check(pistol_index >= 0 and equipment.equip_from_inventory(inventory, pistol_index), "real equipment transaction equips a firearm instance")
	_check(int(equipment.get_slot("main_hand").get("metadata", {}).get("magazine_rounds", -1)) == 3, "equipment preserves firearm magazine metadata")
	_check(equipment.update_slot_metadata("main_hand", {"magazine_rounds": 7}), "bounded metadata transaction updates the magazine")
	_check(int(equipment.get_slot("main_hand").get("metadata", {}).get("magazine_rounds", -1)) == 7, "magazine update is visible from the authoritative equipment slot")
	var saved_inventory: Dictionary = inventory.serialize()
	var saved_equipment: Dictionary = equipment.serialize()
	var restored_inventory = InventoryScript.new()
	var restored_equipment = EquipmentScript.new()
	root.add_child(restored_inventory)
	root.add_child(restored_equipment)
	await process_frame
	restored_equipment.setup(restored_inventory.registry)
	_check(restored_inventory.deserialize(saved_inventory), "firearm reserve inventory survives serialization")
	_check(restored_equipment.deserialize(saved_equipment), "firearm equipment survives existing version-two schema")
	var restored: Dictionary = restored_equipment.get_slot("main_hand")
	_check(str(restored.get("item_id", "")) == "star_pistol", "restored main hand retains the pistol")
	_check(int(restored.get("metadata", {}).get("magazine_rounds", -1)) == 7, "restored pistol retains exact magazine rounds")
	for node: Node in [inventory, equipment, restored_inventory, restored_equipment]:
		node.queue_free()
	await process_frame


func _test_profile_bounds_and_rejection() -> void:
	var registry = RegistryScript.new()
	_check(registry.load_from_file(), "strict ranged registry atomically composes bow and firearm data")
	_check(registry.profile_count() == 4, "combined ranged registry exposes four explicit profiles")
	var expected_modes := {
		"star_pistol": "semi",
		"frontier_carbine": "auto",
		"scattergun": "pump",
	}
	for weapon_id: String in expected_modes:
		var profile: Dictionary = registry.get_profile(weapon_id)
		_check(str(profile.get("action_kind", "")) == "firearm", "%s uses firearm action semantics" % weapon_id)
		_check(str(profile.get("delivery_kind", "")) == "hitscan", "%s uses bounded hitscan delivery" % weapon_id)
		_check(str(profile.get("fire_mode", "")) == expected_modes[weapon_id], "%s exposes its intended fire mode" % weapon_id)
		_check(int(profile.get("magazine_capacity", 0)) <= 64, "%s magazine remains inside the hard budget" % weapon_id)
		_check(int(profile.get("pellet_count", 0)) <= 12, "%s pellet count remains inside the hard budget" % weapon_id)
		_check(float(profile.get("max_distance", 0.0)) <= 128.0, "%s range remains inside the hard budget" % weapon_id)
	var invalid_path := "user://invalid-firearm-profile.json"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	_check(file != null, "invalid firearm fixture opens for writing")
	if file != null:
		file.store_string('{"schema_version":1,"profiles":[{"id":"broken","weapon_item_id":"broken","ammo_item_id":"light_round","action_kind":"firearm","delivery_kind":"hitscan","fire_mode":"auto","magazine_capacity":99,"reload_seconds":1,"fire_interval_seconds":0.01,"pellet_count":99,"spread_degrees":30,"damage_per_pellet":99,"max_distance":999,"knockback_horizontal":1,"knockback_vertical":0,"hit_stun_seconds":0,"recoil_pitch_degrees":1,"recoil_yaw_degrees":0,"durability_cost":1,"collision_mask":5}]}')
		file.close()
		var invalid_registry = RegistryScript.new()
		_check(not invalid_registry.load_from_file(invalid_path), "unbounded firearm profile rejects the entire registry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) == item_id:
			return index
	return -1


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
