class_name RepairProgressionServiceHub
extends "res://src/ui/character_progression_service_hub.gd"

const RepairServiceScript = preload("res://src/repair/repair_service.gd")
const RepairEquipmentAdapterScript = preload("res://src/repair/repair_equipment_adapter.gd")
const RepairInteractionAdapterScript = preload("res://src/repair/repair_interaction_adapter.gd")

var repair_service: Node
var repair_equipment: Node
var repair_interaction: Node


func _ready() -> void:
	super._ready()
	repair_equipment = _add_service(
		RepairEquipmentAdapterScript.new(), "RepairEquipmentAdapter"
	)
	repair_equipment.call("setup", equipment_service)
	repair_service = _add_service(RepairServiceScript.new(), "RepairService")
	repair_service.call(
		"setup", inventory.registry, inventory, repair_equipment, tool_service
	)
	repair_interaction = _add_service(
		RepairInteractionAdapterScript.new(), "RepairInteraction"
	)
	repair_interaction.call("setup", game_ui, repair_service)
	if block_interaction != null and block_interaction.has_method("register_extension"):
		block_interaction.call("register_extension", repair_interaction)
	if game_ui != null and game_ui.has_method("setup_repair"):
		game_ui.call("setup_repair", repair_service, repair_equipment)
	if repair_service.has_signal("repair_completed"):
		repair_service.connect("repair_completed", Callable(self, "_on_repair_completed"))


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["repair"] = (
		repair_service.call("get_snapshot") if repair_service != null else {}
	)
	return snapshot


func _exit_tree() -> void:
	if (
		block_interaction != null
		and repair_interaction != null
		and block_interaction.has_method("unregister_extension")
	):
		block_interaction.call("unregister_extension", repair_interaction)
	super._exit_tree()


func _on_repair_completed(result: Dictionary) -> void:
	_publish_character_message(
		str(result.get("message", "修理完成")),
		"success",
		"repair:%s" % str(result.get("target_id", "item")),
		2.6
	)
	if audio_service != null and audio_service.has_method("play_craft"):
		audio_service.call("play_craft")
