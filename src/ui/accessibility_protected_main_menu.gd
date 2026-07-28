class_name AccessibilityProtectedMainMenu
extends "res://src/ui/protected_main_menu.gd"

const AccessibilityPolicy = preload(
	"res://src/settings/ui_accessibility_policy.gd"
)

var _ui_accessibility_service: Node


func setup_accessibility(service: Node) -> void:
	_disconnect_accessibility_service()
	_ui_accessibility_service = service
	if _ui_accessibility_service == null:
		return
	var callback := Callable(self, "_on_accessibility_input_mode_changed")
	if (
		_ui_accessibility_service.has_signal("input_mode_changed")
		and not _ui_accessibility_service.is_connected("input_mode_changed", callback)
	):
		_ui_accessibility_service.connect("input_mode_changed", callback)
	_on_accessibility_input_mode_changed(
		StringName(_ui_accessibility_service.call("get_input_mode"))
	)


func _exit_tree() -> void:
	_disconnect_accessibility_service()


func _on_accessibility_input_mode_changed(mode: StringName) -> void:
	if mode == AccessibilityPolicy.MODE_MOUSE:
		_release_owned_focus()
		return
	if _main_panel != null and _main_panel.visible:
		call_deferred("_focus_primary_action")
		return
	for panel: Control in [_map_panel, _save_panel, _settings_panel, _update_panel]:
		if panel != null and panel.visible:
			call_deferred("_focus_first_interactive", panel)
			return


func _focus_primary_action() -> void:
	if not _can_own_focus():
		return
	super._focus_primary_action()


func _focus_first_interactive(panel: Control) -> void:
	if not _can_own_focus():
		return
	super._focus_first_interactive(panel)


func _can_own_focus() -> bool:
	return (
		_ui_accessibility_service == null
		or bool(_ui_accessibility_service.call("prefers_focus_navigation"))
	)


func _release_owned_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


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


func get_accessibility_navigation_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_navigation_snapshot()
	snapshot["input_mode"] = (
		StringName(_ui_accessibility_service.call("get_input_mode"))
		if _ui_accessibility_service != null
		else AccessibilityPolicy.MODE_KEYBOARD
	)
	snapshot["ui_scale"] = (
		float(_ui_accessibility_service.call("get_ui_scale"))
		if _ui_accessibility_service != null
		else AccessibilityPolicy.DEFAULT_SCALE
	)
	return snapshot
