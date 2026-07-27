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
	var viewport_size := get_viewport_rect().size
	var compact: bool = viewport_size.x < 1120.0 or viewport_size.y < 650.0
	if compact:
		UiKit.set_margin(_menu_margin, 16, 12, 16, 12)
		_main_layout.add_theme_constant_override("separation", CompactTokens.SPACE_LG)
		if _command_panel != null:
			_command_panel.custom_minimum_size.x = 320.0
		if _hero_title != null:
			_hero_title.add_theme_font_size_override("font_size", 40)
	_configure_compact_hero(compact)
	_configure_compact_command_deck(compact)


func _configure_compact_hero(compact: bool) -> void:
	if _hero_column == null:
		return
	_hero_column.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_EXPAND_FILL
	)
	_hero_column.add_theme_constant_override(
		"separation", CompactTokens.SPACE_SM if compact else CompactTokens.SPACE_MD
	)
	for child: Node in _hero_column.get_children():
		if child == _hero_title:
			(child as Control).visible = true
			continue
		if child is Label:
			var label := child as Label
			if label.theme_type_variation == "EyebrowLabel":
				label.visible = true
			elif label.theme_type_variation == "MutedLabel":
				label.visible = not compact
				if label.text.begins_with("在星光照亮"):
					label.custom_minimum_size = Vector2(430, 64) if not compact else Vector2.ZERO
			continue
		if child is HBoxContainer and child.name == "FeatureBadges":
			(child as Control).visible = not compact
			continue
		if child is PanelContainer and (child as PanelContainer).theme_type_variation == "GlassPanel":
			(child as Control).visible = not compact
			continue
		if child is Control and child.get_class() == "Control":
			var spacer := child as Control
			spacer.visible = not compact
			spacer.size_flags_vertical = (
				Control.SIZE_EXPAND_FILL if not compact else Control.SIZE_SHRINK_BEGIN
			)


func _configure_compact_command_deck(compact: bool) -> void:
	if _main_layout == null or _command_panel == null:
		return
	var command_wrap := _main_layout.get_node_or_null("CommandWrap") as VBoxContainer
	if command_wrap != null:
		command_wrap.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_EXPAND_FILL
		)
		for child: Node in command_wrap.get_children():
			if child is Control and child.get_class() == "Control":
				var spacer := child as Control
				spacer.visible = not compact
				spacer.size_flags_vertical = (
					Control.SIZE_EXPAND_FILL if not compact else Control.SIZE_SHRINK_BEGIN
				)
	if compact:
		_command_panel.add_theme_stylebox_override(
			"panel",
			CompactTokens.elevated_panel_style(
				"#0A1B2BF7",
				CompactTokens.COLOR_BORDER_STRONG,
				1,
				CompactTokens.RADIUS_LG,
				12.0,
				8,
				Vector2(0.0, 3.0)
			)
		)
	else:
		_command_panel.remove_theme_stylebox_override("panel")
	var content := _command_panel.get_child(0) as VBoxContainer if _command_panel.get_child_count() > 0 else null
	if content != null:
		content.add_theme_constant_override(
			"separation", 6 if compact else CompactTokens.SPACE_SM
		)
		for child: Node in content.get_children():
			if child is HSeparator:
				(child as Control).visible = not compact
			elif child is Label:
				var label := child as Label
				if label == _status:
					label.visible = true
				elif label == _version_label:
					label.visible = not compact
				elif label.theme_type_variation in ["EyebrowLabel", "MutedLabel", "SubduedLabel"]:
					label.visible = not compact
	for index in _menu_buttons.size():
		var button: Button = _menu_buttons[index]
		button.custom_minimum_size.x = 292.0 if compact else 338.0
		button.custom_minimum_size.y = (
			42.0 if compact and index == 0 else (
				36.0 if compact else (
					CompactTokens.CONTROL_HEIGHT_LG if index == 0 else CompactTokens.CONTROL_HEIGHT_MD
				)
			)
		)
	if _status != null:
		_status.custom_minimum_size.y = 20.0 if compact else 36.0
	if _version_label != null:
		_version_label.visible = not compact
