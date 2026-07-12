class_name UiInputPolicy
extends RefCounted


static func make_passthrough(control: Control) -> void:
	if control == null:
		return
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.focus_mode = Control.FOCUS_NONE


static func make_passthrough_tree(root: Node) -> void:
	if root == null:
		return
	if root is Control:
		make_passthrough(root)
	for child in root.get_children():
		make_passthrough_tree(child)
