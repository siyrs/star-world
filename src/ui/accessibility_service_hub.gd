class_name AccessibilityServiceHub
extends "res://src/ui/exploration_progression_service_hub.gd"

const UiAccessibilityServiceScript = preload(
	"res://src/ui/ui_accessibility_service.gd"
)

var ui_accessibility: Node


func _ready() -> void:
	super._ready()
	ui_accessibility = _add_service(
		UiAccessibilityServiceScript.new(),
		"UiAccessibility"
	)
	ui_accessibility.call("setup", current_settings)
	if main_menu != null and main_menu.has_method("setup_accessibility"):
		main_menu.call("setup_accessibility", ui_accessibility)
	if game_ui != null and game_ui.has_method("setup_accessibility"):
		game_ui.call("setup_accessibility", ui_accessibility)


func _exit_tree() -> void:
	if (
		ui_accessibility != null
		and is_instance_valid(ui_accessibility)
		and ui_accessibility.has_method("dispose")
	):
		ui_accessibility.call("dispose")


func _apply_settings(settings: Dictionary) -> void:
	if ui_accessibility != null and ui_accessibility.has_method("apply_settings"):
		ui_accessibility.call("apply_settings", settings)
	super._apply_settings(settings)


func get_ui_accessibility_snapshot() -> Dictionary:
	if ui_accessibility == null or not ui_accessibility.has_method("get_snapshot"):
		return {}
	return ui_accessibility.call("get_snapshot")


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["ui_accessibility"] = get_ui_accessibility_snapshot()
	return snapshot
