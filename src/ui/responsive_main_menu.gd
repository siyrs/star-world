class_name ResponsiveMainMenu
extends "res://src/ui/main_menu.gd"

const CompactTokens = preload("res://src/ui/design_tokens.gd")

var _layout_update_pending := false


func _ready() -> void:
	super._ready()
	var direct_callback := Callable(self, "_apply_responsive_layout")
	if resized.is_connected(direct_callback):
		resized.disconnect(direct_callback)
	var queued_callback := Callable(self, "_queue_responsive_layout")
	if not resized.is_connected(queued_callback):
		resized.connect(queued_callback)
	set_process_unhandled_input(true)
	_queue_responsive_layout()
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
	var cancellable_panel_visible := (
		(_map_panel != null and _map_panel.visible)
		or (_save_panel != null and _save_panel.visible)
		or (_settings_panel != null and _settings_panel.visible)
	)
	if not cancellable_panel_visible:
		return
	show_main()
	get_viewport().set_input_as_handled()


func _queue_responsive_layout() -> void:
	if _layout_update_pending:
		return
	_layout_update_pending = true
	call_deferred("_flush_responsive_layout")


func _flush_responsive_layout() -> void:
	_layout_update_pending = false
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	super._apply_responsive_layout()
	if _menu_margin == null or _main_layout == null:
		return
	var compact := size.x < 1120.0 or size.y < 650.0
	if compact:
		UiKit.set_margin(_menu_margin, 20, 16, 20, 16)
		_main_layout.add_theme_constant_override("separation", CompactTokens.SPACE_LG)
		if _command_panel != null:
			_command_panel.custom_minimum_size.x = 312.0
		if _hero_title != null:
			_hero_title.add_theme_font_size_override("font_size", 42)
		_set_compact_hero(true)
		_set_compact_commands(true)
	else:
		_set_compact_hero(false)
		_set_compact_commands(false)


func _set_compact_hero(compact: bool) -> void:
	if _hero_column == null:
		return
	var feature_row := _hero_column.get_node_or_null("FeatureBadges") as Control
	if feature_row != null:
		feature_row.visible = not compact
	for child: Node in _hero_column.get_children():
		if child is PanelContainer and (child as PanelContainer).theme_type_variation == "GlassPanel":
			child.visible = not compact
		elif child is Label:
			var label := child as Label
			if label.text.begins_with("在星光照亮"):
				label.custom_minimum_size.x = 0.0 if compact else 430.0
				label.custom_minimum_size.y = 50.0 if compact else 64.0


func _set_compact_commands(compact: bool) -> void:
	for index in _menu_buttons.size():
		var button := _menu_buttons[index]
		button.custom_minimum_size.x = 286.0 if compact else 338.0
		button.custom_minimum_size.y = (
			44.0 if compact and index == 0 else (38.0 if compact else (
				CompactTokens.CONTROL_HEIGHT_LG if index == 0 else CompactTokens.CONTROL_HEIGHT_MD
			))
		)
	if _version_label != null:
		_version_label.visible = not compact
	if _status != null:
		_status.custom_minimum_size.y = 24.0 if compact else 36.0


func _focus_primary_action() -> void:
	if (
		not visible
		or _main_panel == null
		or not _main_panel.visible
		or _menu_buttons.is_empty()
	):
		return
	var primary := _menu_buttons[0]
	if primary != null and is_instance_valid(primary) and not primary.disabled:
		primary.grab_focus()


func _focus_first_interactive(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or not panel.is_visible_in_tree():
		return
	var target := _find_focusable(panel)
	if target != null:
		target.grab_focus()


func _find_focusable(node: Node) -> Control:
	if node is Control:
		var control := node as Control
		var disabled := control is BaseButton and (control as BaseButton).disabled
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not disabled:
			return control
	for child: Node in node.get_children():
		var target := _find_focusable(child)
		if target != null:
			return target
	return null


func get_navigation_snapshot() -> Dictionary:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return {
		"main_visible": _main_panel != null and _main_panel.visible,
		"map_visible": _map_panel != null and _map_panel.visible,
		"save_visible": _save_panel != null and _save_panel.visible,
		"settings_visible": _settings_panel != null and _settings_panel.visible,
		"focus_owner": focus_owner,
		"focus_text": focus_owner.text if focus_owner is BaseButton else "",
	}
