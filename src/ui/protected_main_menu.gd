class_name ProtectedMainMenu
extends "res://src/ui/responsive_main_menu.gd"

const ProtectedMapPanelScript = preload(
	"res://src/ui/responsive_map_selection_panel.gd"
)
const ProtectedSaveBrowserScript = preload(
	"res://src/ui/responsive_protected_save_browser_panel.gd"
)
const ProtectedSettingsPanelScript = preload(
	"res://src/ui/hardened_settings_panel.gd"
)
const ProtectedUpdatePromptPanelScript = preload(
	"res://src/ui/update_prompt_panel.gd"
)
const PixelTextures = preload("res://src/ui/pixel_ui_textures.gd")
const MenuStarfieldScript = preload("res://src/ui/menu_starfield.gd")
const UiInputPolicyScript = preload("res://src/ui/ui_input_policy.gd")

const STAR_SPLASHES := [
	"把星光建成家！",
	"五片世界等待远征！",
	"机器与农场都在运转！",
	"每颗星都有自己的故事！",
	"探索深渊，仰望群岛！",
	"世界会记住你的创造！",
]


func _ready() -> void:
	super._ready()
	_rewire_primary_commands()
	set_process_unhandled_input(true)
	call_deferred("_focus_primary_action")


func _build_background() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = PixelTextures.stone_background()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.modulate = Color("#273846")
	UiInputPolicyScript.make_passthrough(background)
	add_child(background)

	var starfield := MenuStarfieldScript.new()
	starfield.name = "StarWorldBackdrop"
	starfield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiInputPolicyScript.make_passthrough(starfield)
	add_child(starfield)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#02081270")
	UiInputPolicyScript.make_passthrough(shade)
	add_child(shade)

	var vignette := TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.texture = _build_vignette()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	UiInputPolicyScript.make_passthrough(vignette)
	add_child(vignette)


func _pick_splash() -> String:
	return STAR_SPLASHES[randi() % STAR_SPLASHES.size()]


func _rewire_primary_commands() -> void:
	if _menu_buttons.size() < 2:
		return
	var continue_button: Button = _menu_buttons[0]
	var create_button: Button = _menu_buttons[1]
	_disconnect_button_callbacks(continue_button)
	_disconnect_button_callbacks(create_button)
	continue_button.text = "继续游戏"
	create_button.text = "创建新世界"
	continue_button.pressed.connect(_continue_or_create)
	create_button.pressed.connect(func() -> void: _show_panel(_map_panel))
	_connect_button_audio(continue_button)
	_connect_button_audio(create_button)


func _disconnect_button_callbacks(button: Button) -> void:
	for raw_connection: Variant in button.pressed.get_connections():
		if raw_connection is not Dictionary:
			continue
		var callback: Callable = raw_connection.get("callable", Callable())
		if callback.is_valid() and button.pressed.is_connected(callback):
			button.pressed.disconnect(callback)


func _continue_or_create() -> void:
	if save_service == null or not save_service.has_method("list_worlds"):
		_show_panel(_map_panel)
		return
	var worlds: Array = save_service.call("list_worlds")
	var latest_world: Dictionary = {}
	var latest_time := ""
	for raw_world: Variant in worlds:
		if raw_world is not Dictionary:
			continue
		var candidate: Dictionary = raw_world
		var world_id := str(candidate.get("id", candidate.get("world_id", "")))
		if world_id.is_empty():
			continue
		var updated_at := str(candidate.get("updated_at", candidate.get("created_at", "")))
		if latest_world.is_empty() or updated_at > latest_time:
			latest_world = candidate
			latest_time = updated_at
	var selected_id := str(latest_world.get("id", latest_world.get("world_id", "")))
	if selected_id.is_empty():
		_show_panel(_map_panel)
		return
	_on_load_requested(selected_id)


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
		"primary_text": _menu_buttons[0].text if not _menu_buttons.is_empty() else "",
		"star_backdrop": get_node_or_null("StarWorldBackdrop") != null,
	}
