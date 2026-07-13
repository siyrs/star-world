class_name CharacterGameUI
extends "res://src/ui/game_ui.gd"

const CharacterPanelScript = preload("res://src/ui/character_inventory_panel.gd")


func _ready() -> void:
	super._ready()
	_replace_inventory_panel()


func setup_character_progression(
	equipment_service: Node, attribute_service: Node, _combat_service: Node = null
) -> void:
	if inventory_panel != null and inventory_panel.has_method("setup_character_services"):
		inventory_panel.call("setup_character_services", equipment_service, attribute_service)


func get_character_panel() -> Node:
	return inventory_panel


func _replace_inventory_panel() -> void:
	var previous_panel = inventory_panel
	if previous_panel != null and is_instance_valid(previous_panel):
		remove_child(previous_panel)
		previous_panel.queue_free()
	inventory_panel = CharacterPanelScript.new()
	inventory_panel.name = "CharacterInventoryPanel"
	_center_control(inventory_panel, Vector2(960, 540))
	add_child(inventory_panel)
	inventory_panel.visible = false
	inventory_panel.panel_closed.connect(_close_overlay)
