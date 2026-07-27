class_name ResponsiveMapSelectionPanel
extends "res://src/ui/map_selection_panel.gd"

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
	if _details != null:
		_details.custom_minimum_size.y = 88.0 if compact else 170.0
		_details.add_theme_font_size_override(
			"normal_font_size", CompactTokens.FONT_SMALL if compact else CompactTokens.FONT_BODY
		)
	if _create_button != null:
		_create_button.custom_minimum_size.y = 40.0 if compact else 48.0
	if _back_button != null:
		_back_button.custom_minimum_size.y = 36.0 if compact else 40.0
	if _world_name != null:
		_world_name.custom_minimum_size.y = 36.0 if compact else 40.0
	if _seed != null:
		_seed.custom_minimum_size.y = 36.0 if compact else 40.0
	if _map_buttons != null:
		_map_buttons.add_theme_constant_override(
			"separation", CompactTokens.SPACE_XS if compact else CompactTokens.SPACE_SM
		)
		for child: Node in _map_buttons.get_children():
			if child is Button:
				(child as Button).custom_minimum_size.y = 46.0 if compact else 58.0
	_set_descriptions_visible(not compact)
	_set_container_density(compact)
	custom_minimum_size = Vector2.ZERO
	update_minimum_size()


func _set_descriptions_visible(visible_value: bool) -> void:
	for node: Node in find_children("*", "Label", true, false):
		var label := node as Label
		if label == null:
			continue
		if label.theme_type_variation in ["MutedLabel", "EyebrowLabel"]:
			label.visible = visible_value
	if _resource_summary_label != null:
		_resource_summary_label.visible = visible_value


func _set_container_density(compact: bool) -> void:
	for node: Node in find_children("*", "VBoxContainer", true, false):
		(node as VBoxContainer).add_theme_constant_override(
			"separation", 5 if compact else CompactTokens.SPACE_SM
		)
	for node: Node in find_children("*", "HBoxContainer", true, false):
		(node as HBoxContainer).add_theme_constant_override(
			"separation", CompactTokens.SPACE_SM if compact else CompactTokens.SPACE_MD
		)
	for node: Node in find_children("*", "PanelContainer", true, false):
		var panel := node as PanelContainer
		if panel == self:
			continue
		if panel.theme_type_variation in ["InsetPanel", "GlassPanel", "CardPanel"]:
			panel.add_theme_stylebox_override(
				"panel",
				CompactTokens.panel_style(
					CompactTokens.COLOR_INSET if panel.theme_type_variation == "InsetPanel" else CompactTokens.COLOR_SURFACE_SOFT,
					CompactTokens.COLOR_BORDER_SUBTLE,
					1,
					CompactTokens.RADIUS_MD,
					7.0 if compact else 9.0
				)
			)
