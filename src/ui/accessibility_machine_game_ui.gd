class_name AccessibilityMachineGameUI
extends "res://src/ui/machine_game_ui.gd"

const AccessibilityPolicy = preload(
	"res://src/settings/ui_accessibility_policy.gd"
)

var _ui_accessibility_service: Node


func setup_accessibility(service: Node) -> void:
	_disconnect_accessibility_service()
	_ui_accessibility_service = service
	if _ui_accessibility_service == null:
		return
	var mode_callback := Callable(self, "_on_accessibility_input_mode_changed")
	if (
		_ui_accessibility_service.has_signal("input_mode_changed")
		and not _ui_accessibility_service.is_connected("input_mode_changed", mode_callback)
	):
		_ui_accessibility_service.connect("input_mode_changed", mode_callback)
	_on_accessibility_input_mode_changed(
		StringName(_ui_accessibility_service.call("get_input_mode"))
	)


func _exit_tree() -> void:
	_disconnect_accessibility_service()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_controller_overlay_command(event):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _handle_controller_overlay_command(event: InputEvent) -> bool:
	if _overlay == Overlay.NONE:
		return false
	match AccessibilityPolicy.controller_command(event):
		AccessibilityPolicy.COMMAND_ACCEPT:
			var focus_owner: Control = get_viewport().gui_get_focus_owner()
			if focus_owner is BaseButton and is_ancestor_of(focus_owner):
				(focus_owner as BaseButton).pressed.emit()
				return true
		AccessibilityPolicy.COMMAND_CANCEL:
			if _overlay != Overlay.DEATH:
				close_overlay()
				return true
	return false


func _set_overlay(next_overlay: int, force: bool = false) -> void:
	super._set_overlay(next_overlay, force)
	if _overlay != Overlay.NONE:
		call_deferred("_restore_accessibility_focus")


func _on_accessibility_input_mode_changed(mode: StringName) -> void:
	if mode == AccessibilityPolicy.MODE_MOUSE:
		_release_owned_focus()
		return
	if _overlay != Overlay.NONE:
		call_deferred("_restore_accessibility_focus")


func _restore_accessibility_focus() -> void:
	if (
		_ui_accessibility_service == null
		or not bool(_ui_accessibility_service.call("prefers_focus_navigation"))
		or _overlay == Overlay.NONE
	):
		return
	var focus_root := _focus_root_for_overlay()
	var target := _find_visible_focusable(focus_root) if focus_root != null else null
	if target != null:
		target.grab_focus()


func _focus_root_for_overlay() -> Control:
	match _overlay:
		Overlay.INVENTORY:
			return inventory_panel
		Overlay.CRAFTING:
			return crafting_panel
		Overlay.FURNACE:
			return furnace_panel
		Overlay.CONTAINER:
			return container_panel
		Overlay.PAUSE:
			return _pause_panel
		Overlay.DEATH:
			return _death_panel
		EXPLORATION_JOURNAL_OVERLAY:
			return exploration_journal_panel
		REPAIR_OVERLAY:
			return repair_panel
		STONECUTTER_OVERLAY:
			return stonecutter_panel
	for child: Node in get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			var fallback := _find_visible_focusable(child)
			if fallback != null:
				return child as Control
	return null


func _release_owned_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _find_visible_focusable(node: Node) -> Control:
	if node == null:
		return null
	if node is Control:
		var control := node as Control
		var disabled := false
		if control is BaseButton:
			disabled = (control as BaseButton).disabled
		if (
			control.is_visible_in_tree()
			and control.focus_mode != Control.FOCUS_NONE
			and not disabled
		):
			return control
	for child: Node in node.get_children():
		var target := _find_visible_focusable(child)
		if target != null:
			return target
	return null


func _disconnect_accessibility_service() -> void:
	if _ui_accessibility_service == null:
		return
	var callback := Callable(self, "_on_accessibility_input_mode_changed")
	if (
		_ui_accessibility_service.has_signal("input_mode_changed")
		and _ui_accessibility_service.is_connected("input_mode_changed", callback)
	):
		_ui_accessibility_service.disconnect("input_mode_changed", callback)
	_ui_accessibility_service = null


func get_accessibility_focus_snapshot() -> Dictionary:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var focus_root := _focus_root_for_overlay()
	return {
		"overlay": _overlay,
		"input_mode": (
			StringName(_ui_accessibility_service.call("get_input_mode"))
			if _ui_accessibility_service != null
			else AccessibilityPolicy.MODE_KEYBOARD
		),
		"focus_owner": focus_owner,
		"focus_root": focus_root,
		"focus_inside_game_ui": focus_owner != null and is_ancestor_of(focus_owner),
		"focus_inside_active_overlay": (
			focus_owner != null
			and focus_root != null
			and (focus_owner == focus_root or focus_root.is_ancestor_of(focus_owner))
		),
	}
