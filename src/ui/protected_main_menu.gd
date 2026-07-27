class_name ProtectedMainMenu
extends "res://src/ui/responsive_main_menu.gd"

const ProtectedMapPanelScript = preload(
	"res://src/ui/responsive_map_selection_panel.gd"
)
const ProtectedSaveBrowserScript = preload(
	"res://src/ui/responsive_protected_save_browser_panel.gd"
)
const ProtectedSettingsPanelScript = preload(
	"res://src/ui/settings_panel.gd"
)
const ProtectedUpdatePromptPanelScript = preload(
	"res://src/ui/update_prompt_panel.gd"
)


func _ready() -> void:
	super._ready()
	set_process_unhandled_input(true)
	call_deferred("_focus_primary_action")


func show_main() -> void:
	super.show_main()
	call_deferred("_focus_primary_action")


func _show_panel(panel: Control) -> void:
	super._show_panel(panel)
	if panel != null and panel.visible:
		call_deferred("_focus_first_interactive", panel)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _loading:
		return
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	var cancellable_panel_visible: bool = (
		(_map_panel != null and _map_panel.visible)
		or (_save_panel != null and _save_panel.visible)
		or (_settings_panel != null and _settings_panel.visible)
	)
	if not cancellable_panel_visible:
		return
	show_main()
	get_viewport().set_input_as_handled()


func _build_subpanels() -> void:
	_map_panel = ProtectedMapPanelScript.new()
	_center_panel(_map_panel, Vector2(1000, 650))
	add_child(_map_panel)
	_map_panel.visible = false
	_map_panel.create_requested.connect(_on_create_requested)
	_map_panel.back_requested.connect(show_main)

	_save_panel = ProtectedSaveBrowserScript.new()
	_center_panel(_save_panel, Vector2(1000, 650))
	add_child(_save_panel)
	_save_panel.visible = false
	_save_panel.load_requested.connect(_on_load_requested)
	_save_panel.back_requested.connect(show_main)

	_settings_panel = ProtectedSettingsPanelScript.new()
	_center_panel(_settings_panel, Vector2(780, 570))
	add_child(_settings_panel)
	_settings_panel.visible = false
	_settings_panel.settings_applied.connect(
		func(settings: Dictionary) -> void: settings_changed.emit(settings)
	)
	_settings_panel.back_requested.connect(show_main)

	_update_panel = ProtectedUpdatePromptPanelScript.new()
	_center_panel(_update_panel, Vector2(760, 540))
	add_child(_update_panel)
	_update_panel.visible = false
	_update_panel.dismissed.connect(show_main)


func _focus_primary_action() -> void:
	if (
		not visible
		or _main_panel == null
		or not _main_panel.visible
		or _menu_buttons.is_empty()
	):
		return
	var primary: Button = _menu_buttons[0]
	if is_instance_valid(primary) and not primary.disabled:
		primary.grab_focus()


func _focus_first_interactive(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or not panel.is_visible_in_tree():
		return
	var target: Control = _find_focusable(panel)
	if target != null:
		target.grab_focus()


func _find_focusable(node: Node) -> Control:
	if node is Control:
		var control := node as Control
		var disabled := false
		if control is BaseButton:
			disabled = (control as BaseButton).disabled
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not disabled:
			return control
	for child: Node in node.get_children():
		var target: Control = _find_focusable(child)
		if target != null:
			return target
	return null


func get_navigation_snapshot() -> Dictionary:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var focus_text := ""
	if focus_owner is BaseButton:
		focus_text = (focus_owner as BaseButton).text
	return {
		"main_visible": _main_panel != null and _main_panel.visible,
		"map_visible": _map_panel != null and _map_panel.visible,
		"save_visible": _save_panel != null and _save_panel.visible,
		"settings_visible": _settings_panel != null and _settings_panel.visible,
		"focus_owner": focus_owner,
		"focus_text": focus_text,
	}
