class_name CharacterProgressionServiceHub
extends "res://src/ui/tool_progression_service_hub.gd"

const EquipmentServiceScript = preload("res://src/equipment/equipment_service.gd")
const AttributeServiceScript = preload("res://src/attribute/attribute_service.gd")
const CombatServiceScript = preload("res://src/combat/combat_service.gd")

var equipment_service: Node
var attribute_service: Node
var combat_service: Node


func _ready() -> void:
	super._ready()
	equipment_service = _add_service(EquipmentServiceScript.new(), "EquipmentService")
	equipment_service.call("setup", inventory.registry)
	attribute_service = _add_service(AttributeServiceScript.new(), "AttributeService")
	attribute_service.call("setup", equipment_service)
	combat_service = _add_service(CombatServiceScript.new(), "CombatService")
	combat_service.call("setup", attribute_service, equipment_service)
	if game_ui != null and game_ui.has_method("setup_character_progression"):
		game_ui.call(
			"setup_character_progression", equipment_service, attribute_service, combat_service
		)
	_connect_character_feedback()


func _begin_world(state: Dictionary) -> void:
	if equipment_service != null:
		equipment_service.call("deserialize", state.get("equipment", {}))
	if attribute_service != null:
		attribute_service.call("deserialize", state.get("attributes", {}))
	super._begin_world(state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if player == null:
		return
	if player.has_method("bind_equipment_service"):
		player.call("bind_equipment_service", equipment_service)
	if player.has_method("bind_attribute_service"):
		player.call("bind_attribute_service", attribute_service)
	if player.has_method("bind_combat_service"):
		player.call("bind_combat_service", combat_service)


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if equipment_service != null:
		current_state["equipment"] = equipment_service.call("serialize")
	if attribute_service != null:
		current_state["attributes"] = attribute_service.call("serialize")
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	_clear_character_state()
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		_clear_character_state()


func get_character_snapshot() -> Dictionary:
	return {
		"equipment": (
			equipment_service.call("get_snapshot") if equipment_service != null else {}
		),
		"attributes": (
			attribute_service.call("get_snapshot") if attribute_service != null else {}
		),
		"combat": combat_service.call("get_snapshot") if combat_service != null else {},
	}


func _exit_tree() -> void:
	_clear_character_state()
	super._exit_tree()


func _connect_character_feedback() -> void:
	if equipment_service == null:
		return
	equipment_service.connect("item_equipped", Callable(self, "_on_item_equipped"))
	equipment_service.connect("item_unequipped", Callable(self, "_on_item_unequipped"))
	equipment_service.connect("item_broken", Callable(self, "_on_equipped_item_broken"))


func _on_item_equipped(slot_id: String, item: Dictionary, _previous: Dictionary) -> void:
	var item_id := str(item.get("item_id", ""))
	var display_name := str(inventory.registry.get_display_name(item_id))
	_publish_character_message(
		"已装备 %s" % display_name, "success", "equipment:equip:%s" % slot_id
	)
	if audio_service != null and audio_service.has_method("play_craft"):
		audio_service.call("play_craft")


func _on_item_unequipped(slot_id: String, item: Dictionary) -> void:
	var item_id := str(item.get("item_id", ""))
	var display_name := str(inventory.registry.get_display_name(item_id))
	_publish_character_message(
		"已卸下 %s" % display_name, "info", "equipment:unequip:%s" % slot_id
	)


func _on_equipped_item_broken(
	slot_id: String, _item_id: String, display_name: String, _reason: String
) -> void:
	_publish_character_message(
		"%s 已损坏" % display_name, "warning", "equipment:broken:%s" % slot_id, 3.2
	)


func _publish_character_message(
	message: String, severity: String, dedupe_key: String, duration: float = 2.2
) -> void:
	if player_experience != null and player_experience.has_method("publish_message"):
		player_experience.call("publish_message", message, severity, duration, dedupe_key)


func _clear_character_state() -> void:
	if equipment_service != null and equipment_service.has_method("clear"):
		equipment_service.call("clear")
	if attribute_service != null and attribute_service.has_method("reset"):
		attribute_service.call("reset")
