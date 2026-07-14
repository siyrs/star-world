class_name RepairPanel
extends PanelContainer

signal panel_closed

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")

var inventory: Node
var equipment: Node
var repair_service: Node
var _list: VBoxContainer
var _summary_label: Label
var _status_label: Label
var _repair_buttons: Dictionary = {}


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(860, 500)
	_build_ui()


func setup(p_inventory: Node, p_equipment: Node, p_repair_service: Node) -> void:
	_disconnect_services()
	inventory = p_inventory
	equipment = p_equipment
	repair_service = p_repair_service
	if inventory != null and inventory.has_signal("inventory_changed"):
		inventory.connect("inventory_changed", Callable(self, "refresh"))
	if equipment != null and equipment.has_signal("equipment_changed"):
		equipment.connect("equipment_changed", Callable(self, "_on_equipment_changed"))
	if repair_service != null:
		if repair_service.has_signal("repair_completed"):
			repair_service.connect("repair_completed", Callable(self, "_on_repair_completed"))
		if repair_service.has_signal("repair_rejected"):
			repair_service.connect("repair_rejected", Callable(self, "_on_repair_rejected"))
	refresh()


func open_panel() -> bool:
	if repair_service == null:
		return false
	_status_label.text = "选择受损物品进行修理"
	_status_label.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	refresh()
	return true


func close_panel() -> void:
	visible = false


func refresh() -> void:
	if _list == null:
		return
	_clear_list()
	_repair_buttons.clear()
	if repair_service == null or not repair_service.has_method("get_all_previews"):
		_add_empty_state("修理服务暂不可用")
		_summary_label.text = ""
		return
	var previews: Array = repair_service.call("get_all_previews")
	var damaged_count: int = 0
	var repairable_count: int = 0
	for preview_value in previews:
		if preview_value is not Dictionary:
			continue
		var preview: Dictionary = preview_value
		if str(preview.get("reason", "")) != "already_full":
			damaged_count += 1
		if bool(preview.get("success", false)):
			repairable_count += 1
		_add_preview_row(preview)
	if previews.is_empty():
		_add_empty_state("背包和装备栏中没有可修理的耐久物品")
	_summary_label.text = "受损 %d 件 · 当前材料可修 %d 件" % [damaged_count, repairable_count]


func get_repair_button(target_id: String) -> Button:
	return _repair_buttons.get(target_id) as Button


func get_layout_rects() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"list": _list.get_global_rect() if _list != null else Rect2(),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "修理台"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "材料按次消耗 · 保留名称与 metadata"
	subtitle.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	header.add_child(subtitle)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.custom_minimum_size = Vector2(118, 40)
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)
	var explanation := Label.new()
	explanation.text = "修理背包与已装备的工具、武器和防具。每次使用一种匹配材料，恢复该物品固定比例的最大耐久。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	explanation.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(explanation)
	_summary_label = Label.new()
	_summary_label.modulate = Tokens.color(Tokens.COLOR_ACCENT)
	_summary_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(_summary_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", Tokens.SPACE_XS)
	scroll.add_child(_list)
	_status_label = Label.new()
	_status_label.custom_minimum_size.y = 26.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(_status_label)


func _add_preview_row(preview: Dictionary) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style(Tokens.COLOR_SURFACE_SOFT, Tokens.COLOR_BORDER, 1, Tokens.RADIUS_MD, 8.0)
	)
	_list.add_child(row)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_SM)
	row.add_child(content)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	content.add_child(details)
	var name_label := Label.new()
	name_label.text = "%s    %s" % [
		str(preview.get("display_name", "物品")),
		str(preview.get("target_label", "")),
	]
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.modulate = Color.from_string(str(preview.get("color", "#FFFFFF")), Color.WHITE).lerp(Color.WHITE, 0.35)
	details.add_child(name_label)
	var durability_row := HBoxContainer.new()
	durability_row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	details.add_child(durability_row)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(260, 18)
	progress.max_value = maxf(1.0, float(preview.get("maximum", 1)))
	progress.value = float(preview.get("current", 0))
	progress.show_percentage = false
	durability_row.add_child(progress)
	var durability_label := Label.new()
	durability_label.text = "%d / %d" % [
		int(preview.get("current", 0)),
		int(preview.get("maximum", 0)),
	]
	durability_label.custom_minimum_size.x = 90.0
	durability_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	durability_row.add_child(durability_label)
	var material_label := Label.new()
	material_label.text = "消耗 %s ×%d · 持有 %d · 本次恢复 %d" % [
		str(preview.get("material_name", "材料")),
		int(preview.get("material_count", 1)),
		int(preview.get("material_available", 0)),
		int(preview.get("restore_amount", 0)),
	]
	material_label.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	material_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	details.add_child(material_label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(120, 58)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var reason: String = str(preview.get("reason", ""))
	button.disabled = not bool(preview.get("success", false))
	if reason == "already_full":
		button.text = "耐久完好"
	elif reason == "material_missing":
		button.text = "材料不足"
	else:
		button.text = "修理"
	button.tooltip_text = _preview_tooltip(preview)
	var target: Dictionary = preview.get("target", {}).duplicate(true)
	button.pressed.connect(_on_repair_pressed.bind(target))
	content.add_child(button)
	_repair_buttons[str(preview.get("target_id", ""))] = button


func _add_empty_state(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.custom_minimum_size.y = 180.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	_list.add_child(label)


func _preview_tooltip(preview: Dictionary) -> String:
	var reason: String = str(preview.get("reason", ""))
	if reason == "already_full":
		return "该物品无需修理"
	if reason == "material_missing":
		return "缺少匹配的修理材料"
	return "消耗 %s ×%d，恢复 %d 点耐久" % [
		str(preview.get("material_name", "材料")),
		int(preview.get("material_count", 1)),
		int(preview.get("restore_amount", 0)),
	]


func _on_repair_pressed(target: Dictionary) -> void:
	if repair_service == null or not repair_service.has_method("repair_target"):
		return
	var result: Dictionary = repair_service.call("repair_target", target)
	_show_status(
		str(result.get("message", "修理完成")),
		"success" if bool(result.get("success", false)) else "warning"
	)
	refresh()


func _on_repair_completed(result: Dictionary) -> void:
	_show_status(str(result.get("message", "修理完成")), "success")
	refresh()


func _on_repair_rejected(_reason: String, context: Dictionary) -> void:
	_show_status(str(context.get("message", "无法修理")), "warning")
	refresh()


func _on_equipment_changed(_snapshot: Dictionary) -> void:
	refresh()


func _show_status(message: String, severity: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.modulate = (
		Tokens.color(Tokens.COLOR_SUCCESS)
		if severity == "success"
		else Tokens.color(Tokens.COLOR_WARNING)
	)


func _clear_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _disconnect_services() -> void:
	if inventory != null and inventory.has_signal("inventory_changed"):
		var inventory_callback := Callable(self, "refresh")
		if inventory.is_connected("inventory_changed", inventory_callback):
			inventory.disconnect("inventory_changed", inventory_callback)
	if equipment != null and equipment.has_signal("equipment_changed"):
		var equipment_callback := Callable(self, "_on_equipment_changed")
		if equipment.is_connected("equipment_changed", equipment_callback):
			equipment.disconnect("equipment_changed", equipment_callback)
	if repair_service != null:
		var completed_callback := Callable(self, "_on_repair_completed")
		if repair_service.has_signal("repair_completed") and repair_service.is_connected("repair_completed", completed_callback):
			repair_service.disconnect("repair_completed", completed_callback)
		var rejected_callback := Callable(self, "_on_repair_rejected")
		if repair_service.has_signal("repair_rejected") and repair_service.is_connected("repair_rejected", rejected_callback):
			repair_service.disconnect("repair_rejected", rejected_callback)
