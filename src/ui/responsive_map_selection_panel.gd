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
	var compact := size.x < 930.0 or size.y < 570.0
	if _details != null:
		_details.custom_minimum_size.y = 104.0 if compact else 190.0
	if _create_button != null:
		_create_button.custom_minimum_size.y = 42.0 if compact else CompactTokens.CONTROL_HEIGHT_LG
	if _back_button != null:
		_back_button.custom_minimum_size.y = 38.0 if compact else CompactTokens.CONTROL_HEIGHT_MD
	if _map_buttons != null:
		for child: Node in _map_buttons.get_children():
			if child is Button:
				(child as Button).custom_minimum_size.y = 50.0 if compact else 66.0
	_set_muted_descriptions_visible(not compact)


func _set_muted_descriptions_visible(visible_value: bool) -> void:
	for node: Node in find_children("*", "Label", true, false):
		var label := node as Label
		if label == null:
			continue
		if label.theme_type_variation == "MutedLabel":
			label.visible = visible_value
