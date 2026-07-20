class_name MachineGameUI
extends "res://src/ui/repair_game_ui.gd"

const StonecutterPanelScript = preload("res://src/ui/stonecutter_panel.gd")
const FeatureOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const STONECUTTER_OVERLAY := FeatureOverlayIds.STONECUTTER

var stonecutter_panel: Control
var stonecutter_service: Node


func _ready() -> void:
	super._ready()
	stonecutter_panel = StonecutterPanelScript.new()
	stonecutter_panel.name = "StonecutterPanel"
	_center_control(stonecutter_panel, Vector2(820, 520))
	add_child(stonecutter_panel)
	stonecutter_panel.visible = false
	stonecutter_panel.panel_closed.connect(_close_overlay)


func setup_machine_runtime(p_stonecutter_service: Node) -> void:
	stonecutter_service = p_stonecutter_service
	if stonecutter_panel != null and stonecutter_panel.has_method("setup"):
		stonecutter_panel.call("setup", inventory, stonecutter_service)


func open_stonecutter(
	machine_id: String,
	title: String = "石材切割机"
) -> bool:
	if (
		not _can_change_overlay()
		or stonecutter_panel == null
		or stonecutter_service == null
	):
		return false
	if not bool(stonecutter_panel.call("open_machine", machine_id, title)):
		show_message(
			"无法打开该石材切割机",
			2.5,
			"error",
			"stonecutter_open_failed"
		)
		return false
	_set_overlay(STONECUTTER_OVERLAY)
	stonecutter_panel.visible = true
	return true


func get_stonecutter_panel() -> Node:
	return stonecutter_panel


func end_gameplay() -> void:
	if stonecutter_panel != null and stonecutter_panel.has_method("close_machine"):
		stonecutter_panel.call("close_machine")
	super.end_gameplay()


func _set_overlay(next_overlay: int, force: bool = false) -> void:
	if (
		_overlay == STONECUTTER_OVERLAY
		and next_overlay != STONECUTTER_OVERLAY
		and stonecutter_panel != null
		and stonecutter_panel.has_method("close_machine")
	):
		stonecutter_panel.call("close_machine")
	super._set_overlay(next_overlay, force)
	if _overlay == STONECUTTER_OVERLAY and stonecutter_panel != null:
		stonecutter_panel.visible = true


func _hide_all_overlays() -> void:
	super._hide_all_overlays()
	if stonecutter_panel != null:
		stonecutter_panel.visible = false


func _context_for_overlay() -> StringName:
	if _overlay == STONECUTTER_OVERLAY:
		return InputContextScript.CONTEXT_MACHINE
	return super._context_for_overlay()
