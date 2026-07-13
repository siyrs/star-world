extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const EquipmentRegistryScript = preload("res://src/equipment/equipment_registry.gd")
const AttributeScript = preload("res://src/attribute/attribute_service.gd")
const CombatScript = preload("res://src/combat/combat_service.gd")
const DamageCalculatorScript = preload("res://src/combat/damage_calculator.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_and_transactions()
	await _test_attributes_and_combat()
	await _test_player_integration()
	await _test_save_and_runtime_composition()
	if failures.is_empty():
		print("QA EQUIPMENT COMBAT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA EQUIPMENT COMBAT FAILURE: %s" % failure)
		print("QA EQUIPMENT COMBAT FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_transactions() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var attributes = AttributeScript.new()
	for node in [inventory, equipment, attributes]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	attributes.setup(equipment)
	var registry = EquipmentRegistryScript.new()
	_check(registry.load_from_file(), "equipment registry loads from dedicated data")
	_check(registry.slot_count() == 5, "equipment registry exposes five ordered slots")
	_check(
		registry.resolve_slot(inventory.registry.get_item("iron_helmet")) == "helmet",
		"armor resolves to its explicit equipment slot",
	)
	inventory.clear()
	inventory.add_item("iron_sword", 1)
	inventory.add_item("iron_helmet", 1)
	inventory.add_item("iron_chestplate", 1)
	_check(equipment.equip_from_inventory(inventory, 0), "weapon equips from an exact inventory slot")
	_check(equipment.equip_from_inventory(inventory, 1), "helmet equips from inventory")
	_check(equipment.equip_from_inventory(inventory, 2), "chestplate equips from inventory")
	_check(inventory.count_item("iron_sword") == 0, "equipped weapon leaves inventory storage")
	_check(str(equipment.get_slot("main_hand").get("item_id", "")) == "iron_sword", "main-hand state owns the equipped weapon")
	_check(is_equal_approx(attributes.get_value("attack_damage"), 6.0), "iron sword contributes to final attack")
	_check(is_equal_approx(attributes.get_value("defense"), 8.0), "armor pieces aggregate defense")
	inventory.add_item("diamond_sword", 1)
	var diamond_index := _find_item_slot(inventory, "diamond_sword")
	_check(diamond_index >= 0 and equipment.equip_from_inventory(inventory, diamond_index), "equipping a replacement performs one transaction")
	_check(inventory.count_item("iron_sword") == 1, "replaced equipment returns to inventory")
	_check(str(equipment.get_slot("main_hand").get("item_id", "")) == "diamond_sword", "replacement becomes the active weapon")
	_check(is_equal_approx(attributes.get_value("attack_damage"), 7.0), "attribute source replaces instead of stacking stale weapon bonuses")
	_check(equipment.unequip_to_inventory(inventory, "helmet"), "equipment can be safely returned to inventory")
	_check(equipment.get_slot("helmet").is_empty(), "unequip clears the domain slot")
	_check(inventory.count_item("iron_helmet") == 1, "unequipped armor returns with quantity preserved")
	var saved: Dictionary = equipment.serialize()
	var restored = EquipmentScript.new()
	host.add_child(restored)
	await process_frame
	restored.setup(inventory.registry)
	_check(restored.deserialize(saved), "equipment state deserializes")
	_check(str(restored.get_slot("main_hand").get("item_id", "")) == "diamond_sword", "equipped weapon survives save round trip")
	var full_inventory = InventoryScript.new(9, 9)
	var protected_equipment = EquipmentScript.new()
	host.add_child(full_inventory)
	host.add_child(protected_equipment)
	await process_frame
	protected_equipment.setup(full_inventory.registry)
	protected_equipment.equip("helmet", {"item_id":"iron_helmet","count":1})
	full_inventory.add_item("dirt", 64 * 9)
	_check(not protected_equipment.unequip_to_inventory(full_inventory, "helmet"), "full inventory rejects unequip")
	_check(not protected_equipment.get_slot("helmet").is_empty(), "failed unequip preserves the equipped item")
	host.queue_free()
	await process_frame
	await process_frame


func _test_attributes_and_combat() -> void:
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var attributes = AttributeScript.new()
	var combat = CombatScript.new()
	root.add_child(inventory)
	root.add_child(equipment)
	root.add_child(attributes)
	root.add_child(combat)
	await process_frame
	equipment.setup(inventory.registry)
	attributes.setup(equipment)
	combat.setup(attributes, equipment)
	equipment.equip("main_hand", {"item_id":"wooden_sword","count":1,"metadata":{"durability":1,"custom_name":"练习剑"}})
	equipment.equip("helmet", {"item_id":"iron_helmet","count":1})
	equipment.equip("chestplate", {"item_id":"iron_chestplate","count":1})
	var calculator = DamageCalculatorScript.new()
	var damage: Dictionary = calculator.calculate_raw(10.0, attributes.get_snapshot(), "zombie")
	_check(float(damage.get("final_damage", 10.0)) < 10.0, "defense reduces incoming damage")
	_check(float(damage.get("mitigation_ratio", 0.0)) > 0.0, "damage result explains mitigation")
	_check(float(damage.get("mitigation_ratio", 1.0)) <= 0.80, "defense mitigation remains bounded")
	var combat_damage: Dictionary = combat.resolve_incoming_damage(10.0, "zombie", true)
	_check(not Array(combat_damage.get("armor_durability", [])).is_empty(), "mitigated hits consume armor durability")
	var helmet: Dictionary = equipment.get_slot("helmet")
	_check(int(helmet.get("metadata", {}).get("durability", 165)) == 164, "armor durability decreases exactly once per hit")
	var attack_result: Dictionary = combat.resolve_outgoing_attack({"defense": 4.0})
	_check(float(attack_result.get("raw_damage", 0.0)) == 4.0, "equipped wooden sword produces the expected attack value")
	var break_result: Dictionary = combat.consume_attack_durability(1)
	_check(bool(break_result.get("broken", false)), "equipped weapon breaks at zero durability")
	_check(equipment.get_slot("main_hand").is_empty(), "broken equipped weapon is removed from its slot")
	attributes.set_modifier_source("test_buff", {"attack_damage":2.0,"movement_speed":0.1}, true)
	var serialized: Dictionary = attributes.serialize()
	var restored_attributes = AttributeScript.new()
	root.add_child(restored_attributes)
	await process_frame
	restored_attributes.deserialize(serialized)
	_check(is_equal_approx(restored_attributes.get_value("attack_damage"), 3.0), "persistent attribute sources survive serialization")
	_check(is_equal_approx(restored_attributes.get_value("movement_speed"), 1.1), "multiplicative-style movement value is restored as a final scalar")
	for node in [inventory, equipment, attributes, combat, restored_attributes]:
		node.queue_free()
	await process_frame
	await process_frame


func _test_player_integration() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var attributes = AttributeScript.new()
	var combat = CombatScript.new()
	var survival = SurvivalScript.new()
	var player = PlayerScene.instantiate()
	for node in [inventory, equipment, attributes, combat, survival, player]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	attributes.setup(equipment)
	combat.setup(attributes, equipment)
	equipment.equip("main_hand", {"item_id":"iron_sword","count":1})
	equipment.equip("helmet", {"item_id":"iron_helmet","count":1})
	equipment.equip("chestplate", {"item_id":"iron_chestplate","count":1})
	player.setup_gameplay_services(
		{
			"inventory": inventory,
			"survival": survival,
			"equipment": equipment,
			"attributes": attributes,
			"combat": combat,
		}
	)
	_check(player.has_method("bind_equipment_service"), "player exposes equipment integration port")
	_check(player.has_method("bind_attribute_service"), "player exposes attribute integration port")
	_check(player.has_method("bind_combat_service"), "player exposes combat integration port")
	_check(is_equal_approx(float(player.call("_get_selected_attack_damage")), 6.0), "player attack reads equipped weapon attributes")
	player.call("_consume_selected_durability", "attack")
	_check(int(equipment.get_slot("main_hand").get("metadata", {}).get("durability", 251)) == 250, "player attacks consume equipped weapon durability")
	player.take_damage(10.0, "zombie")
	_check(survival.health > 10.0 and survival.health < 20.0, "player incoming damage is reduced before survival health changes")
	host.queue_free()
	await process_frame
	await process_frame


func _test_save_and_runtime_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get_node_or_null("EquipmentService") != null, "service hub mounts the equipment domain")
	_check(hub.get_node_or_null("AttributeService") != null, "service hub mounts the attribute domain")
	_check(hub.get_node_or_null("CombatService") != null, "service hub mounts the combat domain")
	_check(hub.game_ui.has_method("get_character_panel"), "game UI exposes the integrated character panel")
	var character_panel: Node = hub.game_ui.call("get_character_panel")
	_check(character_panel != null and character_panel.has_method("setup_character_services"), "inventory overlay is replaced by the character equipment surface")
	var migrated: Dictionary = hub.save_service.call(
		"_migrate", {"save_version":2,"metadata":{},"inventory":{}}
	)
	_check(migrated.get("equipment", null) is Dictionary, "old saves migrate an empty equipment state")
	_check(migrated.get("attributes", null) is Dictionary, "old saves migrate an attribute state")
	var world_name := "equipment-regression-%d" % Time.get_ticks_msec()
	var state: Dictionary = hub.save_service.create_world(world_name, "star_continent", 424242)
	_check(not state.is_empty(), "equipment regression creates a temporary world")
	if not state.is_empty():
		hub.call("_begin_world", state)
		hub.inventory.clear()
		hub.inventory.add_item("iron_helmet", 1)
		_check(hub.equipment_service.equip_from_inventory(hub.inventory, 0), "runtime equipment transaction succeeds")
		_check(hub.save_current({}, {}), "service hub saves equipment in the world transaction")
		var loaded: Dictionary = hub.save_service.load_world(str(state.get("metadata", {}).get("id", "")))
		_check(str(loaded.get("equipment", {}).get("slots", {}).get("helmet", {}).get("item_id", "")) == "iron_helmet", "equipped armor survives the real save service")
		_check(loaded.get("attributes", null) is Dictionary, "attribute base state is included in the save transaction")
		hub.save_service.delete_world(str(state.get("metadata", {}).get("id", "")))
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
