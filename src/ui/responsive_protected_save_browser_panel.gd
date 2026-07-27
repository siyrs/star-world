class_name ResponsiveProtectedSaveBrowserPanel
extends "res://src/ui/protected_save_browser_panel.gd"

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
		CompactTokens.bevel_style("#C6C6C6", "#555555", 2, 10.0 if compact else 14.0)
	)
	var list_scroll := _find_list_scroll()
	if list_scroll != null:
		list_scroll.custom_minimum_size.y = 120.0 if compact else 260.0
	if _status != null:
		_status.custom_minimum_size.y = 22.0 if compact else 28.0
	if _query_card != null:
		_query_card.add_theme_stylebox_override(
			"panel",
			CompactTokens.bevel_style(
				"#BCBCBC",
				"#7A7A7A",
				2,
				7.0 if compact else 9.0
			)
		)
	if _save_list_card != null:
		_save_list_card.add_theme_stylebox_override(
			"panel",
			CompactTokens.bevel_style(
				"#B0B0B0",
				"#7A7A7A",
				2,
				7.0 if compact else 9.0
			)
		)
	_set_descriptions_visible(not compact)
	_set_query_density(compact)
	_set_container_density(compact)
	custom_minimum_size = Vector2.ZERO
	update_minimum_size()


func _find_list_scroll() -> ScrollContainer:
	for node: Node in find_children("SaveListScroll", "ScrollContainer", true, false):
		return node as ScrollContainer
	return null


func _set_descriptions_visible(visible_value: bool) -> void:
	for node: Node in find_children("*", "Label", true, false):
		var label := node as Label
		if label == null:
			continue
		if label.theme_type_variation in ["MutedLabel", "EyebrowLabel", "SubduedLabel"]:
			label.visible = visible_value


func _set_query_density(compact: bool) -> void:
	var query_bar := find_child("SaveQueryBar", true, false) as HBoxContainer
	if query_bar == null:
		return
	query_bar.add_theme_constant_override(
		"separation", CompactTokens.SPACE_XS if compact else CompactTokens.SPACE_SM
	)
	for child: Node in query_bar.get_children():
		if child is Control:
			(child as Control).custom_minimum_size.y = 36.0 if compact else 40.0
	if _sort_option != null:
		_sort_option.custom_minimum_size.x = 142.0 if compact else 154.0


func _set_container_density(compact: bool) -> void:
	for node: Node in find_children("*", "VBoxContainer", true, false):
		(node as VBoxContainer).add_theme_constant_override(
			"separation", 5 if compact else CompactTokens.SPACE_SM
		)
	for node: Node in find_children("*", "HBoxContainer", true, false):
		var row := node as HBoxContainer
		if row.name != "SaveQueryBar":
			row.add_theme_constant_override(
				"separation", CompactTokens.SPACE_XS if compact else CompactTokens.SPACE_SM
			)
