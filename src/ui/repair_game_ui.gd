class_name RepairGameUI
extends "res://src/ui/character_game_ui.gd"

const RepairPanelScript = preload("res://src/ui/repair_panel.gd")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const REPAIR_OVERLAY := ExtensionOverlayIds.REPAIR

var repair_panel: Control
var repair_service: Node
var repair_equipment: Node


func _ready() -> void:
	super._ready()
	repair_panel = RepairPanelScript.new()
	repair_panel.name = "RepairPanel"
	_center_control(repair_panel, Vector2(860, 500))
	add_child(repair_panel)
	repair_panel.visible = false
	repair_panel.panel_closed.connect(_close_overlay)


func setup_repair(p_repair_service: Node, p_repair_equipment: Node) -> void:
	repair_service = p_repair_service
	repair_equipment = p_repair_equipment
	if repair_panel != null and repair_panel.has_method("setup"):
		repair_panel.call("setup", inventory, repair_equipment, repair_service)


func open_repair() -> bool:
	if not _can_change_overlay() or repair_panel == null or repair_service == null:
		return false
	if not bool(repair_panel.call("open_panel")):
		return false
	_set_overlay(REPAIR_OVERLAY)
	repair_panel.visible = true
	return true


func get_repair_panel() -> Node:
	return repair_panel


func _hide_all_overlays() -> void:
	super._hide_all_overlays()
	if repair_panel != null:
		repair_panel.visible = false


func _context_for_overlay() -> StringName:
	if _overlay == REPAIR_OVERLAY:
		return InputContextScript.CONTEXT_REPAIR
	return super._context_for_overlay()
