class_name ResponsiveExplorationJournalPanel
extends "res://src/ui/exploration_journal_panel.gd"

const CompactTokens = preload("res://src/ui/design_tokens.gd")

var _layout_update_pending := false


func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2.ZERO
	var callback := Callable(self, "_queue_responsive_layout")
	if not resized.is_connected(callback):
		resized.connect(callback)
	_queue_responsive_layout()


func _queue_responsive_layout() -> void:
	if _layout_update_pending:
		return
	_layout_update_pending = true
	call_deferred("_flush_responsive_layout")


func _flush_responsive_layout() -> void:
	_layout_update_pending = false
	var viewport_size := get_viewport_rect().size
	var compact: bool = viewport_size.x < 1120.0 or viewport_size.y < 650.0
	add_theme_stylebox_override(
		"panel",
		CompactTokens.elevated_panel_style(
			CompactTokens.COLOR_SURFACE_RAISED,
			CompactTokens.COLOR_BORDER_STRONG,
			1,
			CompactTokens.RADIUS_LG if compact else CompactTokens.RADIUS_XL,
			10.0 if compact else 14.0,
			7 if compact else 9,
			Vector2(0.0, 3.0)
		)
	)
	if _summary_label != null:
		_summary_label.custom_minimum_size.y = 32.0 if compact else 40.0
		_summary_label.add_theme_stylebox_override(
			"normal",
			CompactTokens.panel_style(
				CompactTokens.COLOR_INSET,
				CompactTokens.COLOR_BORDER_STRONG,
				1,
				CompactTokens.RADIUS_MD,
				6.0 if compact else 8.0
			)
		)
	if _milestone_scroll != null:
		_milestone_scroll.custom_minimum_size.y = 150.0 if compact else 205.0
	if _record_scroll != null:
		_record_scroll.custom_minimum_size.y = 150.0 if compact else 205.0
	_set_descriptions_visible(not compact)
	_set_card_density(compact)
	_set_close_button_density(compact)
	custom_minimum_size = Vector2.ZERO
	update_minimum_size()


func _set_descriptions_visible(visible_value: bool) -> void:
	for node: Node in find_children("*", "Label", true, false):
		var label := node as Label
		if label == null:
			continue
		if label.theme_type_variation in ["EyebrowLabel", "MutedLabel", "SubduedLabel"]:
			label.visible = visible_value


func _set_card_density(compact: bool) -> void:
	for node: Node in find_children("*", "VBoxContainer", true, false):
		(node as VBoxContainer).add_theme_constant_override(
			"separation", 5 if compact else CompactTokens.SPACE_SM
		)
	for node: Node in find_children("*", "HBoxContainer", true, false):
		(node as HBoxContainer).add_theme_constant_override(
			"separation", CompactTokens.SPACE_SM if compact else CompactTokens.SPACE_MD
		)
	for panel in [_milestone_panel, _record_panel]:
		if panel == null:
			continue
		var fill := (
			CompactTokens.COLOR_INSET
			if panel == _record_panel
			else CompactTokens.COLOR_SURFACE_SOFT
		)
		panel.add_theme_stylebox_override(
			"panel",
			CompactTokens.panel_style(
				fill,
				CompactTokens.COLOR_BORDER_SUBTLE,
				1,
				CompactTokens.RADIUS_MD,
				7.0 if compact else 9.0
			)
		)


func _set_close_button_density(compact: bool) -> void:
	for node: Node in find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "关闭 [J]":
			button.custom_minimum_size = Vector2(
				112.0 if compact else 132.0,
				36.0 if compact else 40.0
			)
			return
