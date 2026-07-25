class_name ProtectedMainMenu
extends "res://src/ui/main_menu.gd"

const ProtectedMapPanelScript = preload(
	"res://src/ui/map_selection_panel.gd"
)
const ProtectedSaveBrowserScript = preload(
	"res://src/ui/protected_save_browser_panel.gd"
)
const ProtectedSettingsPanelScript = preload(
	"res://src/ui/settings_panel.gd"
)
const ProtectedUpdatePromptPanelScript = preload(
	"res://src/ui/update_prompt_panel.gd"
)


func _build_subpanels() -> void:
	_map_panel = ProtectedMapPanelScript.new()
	_center_panel(_map_panel, Vector2(860, 610))
	add_child(_map_panel)
	_map_panel.visible = false
	_map_panel.create_requested.connect(_on_create_requested)
	_map_panel.back_requested.connect(show_main)
	_save_panel = ProtectedSaveBrowserScript.new()
	_center_panel(_save_panel, Vector2(820, 590))
	add_child(_save_panel)
	_save_panel.visible = false
	_save_panel.load_requested.connect(_on_load_requested)
	_save_panel.back_requested.connect(show_main)
	_settings_panel = ProtectedSettingsPanelScript.new()
	_center_panel(_settings_panel, Vector2(700, 560))
	add_child(_settings_panel)
	_settings_panel.visible = false
	_settings_panel.settings_applied.connect(
		func(settings: Dictionary) -> void: settings_changed.emit(settings)
	)
	_settings_panel.back_requested.connect(show_main)
	_update_panel = ProtectedUpdatePromptPanelScript.new()
	_center_panel(_update_panel, Vector2(680, 500))
	add_child(_update_panel)
	_update_panel.visible = false
	_update_panel.dismissed.connect(show_main)
