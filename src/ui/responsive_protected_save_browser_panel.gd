class_name ResponsiveProtectedSaveBrowserPanel
extends "res://src/ui/protected_save_browser_panel.gd"

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
	var compact := size.y < 570.0
	var list_scroll := get_node_or_null("ActiveSaveContent/InsetPanel/VBoxContainer/SaveListScroll") as ScrollContainer
	if list_scroll == null:
		for node: Node in find_children("SaveListScroll", "ScrollContainer", true, false):
			list_scroll = node as ScrollContainer
			break
	if list_scroll != null:
		list_scroll.custom_minimum_size.y = 190.0 if compact else 330.0
	for node: Node in find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.theme_type_variation == "MutedLabel":
			label.visible = not compact
