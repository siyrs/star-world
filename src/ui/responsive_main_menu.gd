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
	_queue_responsive_layout()


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
