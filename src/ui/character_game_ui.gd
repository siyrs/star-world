class_name CharacterGameUI
extends "res://src/ui/game_ui.gd"

const CharacterPanelScript = preload("res://src/ui/character_inventory_panel.gd")
const CombatFeedbackOverlayScript = preload("res://src/ui/combat_feedback_overlay.gd")

var combat_feedback_overlay: Node


func _ready() -> void:
	super._ready()
	_replace_inventory_panel()
	combat_feedback_overlay = CombatFeedbackOverlayScript.new()
	combat_feedback_overlay.name = "CombatFeedbackOverlay"
	add_child(combat_feedback_overlay)
	overlay_changed.connect(Callable(self, "_on_overlay_changed_for_combat"))


func setup_character_progression(
	equipment_service: Node, attribute_service: Node, combat_service: Node = null
) -> void:
	if inventory_panel != null and inventory_panel.has_method("setup_character_services"):
		inventory_panel.call("setup_character_services", equipment_service, attribute_service)
	if combat_feedback_overlay != null and combat_feedback_overlay.has_method("setup"):
		combat_feedback_overlay.call("setup", combat_service)


func begin_gameplay() -> void:
	super.begin_gameplay()
	if combat_feedback_overlay != null:
		combat_feedback_overlay.call("set_active", true)
		combat_feedback_overlay.call("set_blocked", get_active_overlay() != Overlay.NONE)


func end_gameplay() -> void:
	if combat_feedback_overlay != null:
		combat_feedback_overlay.call("set_active", false)
	super.end_gameplay()


func get_character_panel() -> Node:
	return inventory_panel


func get_combat_feedback_overlay() -> Node:
	return combat_feedback_overlay


func _replace_inventory_panel() -> void:
	var previous_panel = inventory_panel
	if previous_panel != null and is_instance_valid(previous_panel):
		remove_child(previous_panel)
		previous_panel.queue_free()
	inventory_panel = CharacterPanelScript.new()
	inventory_panel.name = "CharacterInventoryPanel"
	_center_control(inventory_panel, Vector2(920, 520))
	add_child(inventory_panel)
	inventory_panel.visible = false
	inventory_panel.panel_closed.connect(_close_overlay)


func _on_overlay_changed_for_combat(overlay: int, _context: StringName) -> void:
	if combat_feedback_overlay != null:
		combat_feedback_overlay.call("set_blocked", overlay != Overlay.NONE)
