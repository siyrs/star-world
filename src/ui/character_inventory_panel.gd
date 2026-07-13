class_name CharacterInventoryPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")

var inventory: Node
var equipment: Node
var attributes: Node
var _inventory_grid: GridContainer
var _inventory_buttons: Array = []
var _equipment_buttons: Dictionary = {}
var _selected_source: int = -1
var _selection_label: Label
var _status_label: Label
var _attributes_label: Label
var _equipment_surface: Control
var _attributes_surface: Control
var _inventory_surface: Control


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(920, 520)
	_build_ui()


func setup(p_inventory: Node) -> void:
	if inventory == p_inventory:
		refresh()
		return
	_disconnect_inventory()
	inventory = p_inventory
	if inventory != null:
		inventory.connect("inventory_changed", Callable(self, "refresh"))
		inventory.connect("selected_slot_changed", Callable(self, "_on_selected_slot_changed"))
	refresh()


func setup_character_services(p_equipment: Node, p_attributes: Node) -> void:
	_disconnect_character_services()
	equipment = p_equipment
	attributes = p_attributes
	if equipment != null:
		equipment.connect("equipment_changed", Callable(self, "_on_equipment_changed"))
		equipment.connect("transaction_rejected", Callable(self, "_on_transaction_rejected"))
	if attributes != null:
		attributes.connect("attributes_changed", Callable(self, "_on_attributes_changed"))
	refresh()


func refresh() -> void:
	_refresh_inventory()
	_refresh_equipment()
	_refresh_attributes()


func cancel_swap_selection() -> void:
	if _selected_source < 0:
		return
	_selected_source = -1
	refresh()


func get_layout_rects() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"equipment": _equipment_surface.get_global_rect() if _equipment_surface != null else Rect2(),
		"attributes": _attributes_surface.get_global_rect() if _attributes_surface != null else Rect2(),
		"inventory": _inventory_surface.get_global_rect() if _inventory_surface != null else Rect2(),
	}


func get_equipment_button(slot_id: String) -> Button:
	return _equipment_buttons.get(slot_id) as Button


func get_inventory_button(index: int) -> Button:
	return _inventory_buttons[index] as Button if index >= 0 and index < _inventory_buttons.size() else null


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "角色与背包"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "右键装备 · 点击装备槽卸下"
	subtitle.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	header.add_child(subtitle)
	var close_button := Button.new()
	close_button.text = "关闭 [E]"
	close_button.custom_minimum_size = Vector2(108, 38)
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260.0
	left.add_theme_constant_override("separation", Tokens.SPACE_XS)
	body.add_child(left)
	_equipment_surface = left
	var equipment_title := Label.new()
	equipment_title.text = "装备"
	equipment_title.add_theme_font_size_override("font_size", 18)
	equipment_title.modulate = Tokens.color(Tokens.COLOR_ACCENT)
	left.add_child(equipment_title)
	for slot_id in ["main_hand", "helmet", "chestplate", "leggings", "boots"]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 42)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_equipment_pressed.bind(slot_id))
		left.add_child(button)
		_equipment_buttons[slot_id] = button
	var separator := HSeparator.new()
	left.add_child(separator)
	var attributes_title := Label.new()
	attributes_title.text = "角色属性"
	attributes_title.add_theme_font_size_override("font_size", 18)
	attributes_title.modulate = Tokens.color(Tokens.COLOR_ACCENT_WARM)
	left.add_child(attributes_title)
	var attribute_panel := PanelContainer.new()
	attribute_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style(Tokens.COLOR_SURFACE_SOFT, Tokens.COLOR_BORDER, 1, Tokens.RADIUS_MD, 8.0)
	)
	left.add_child(attribute_panel)
	_attributes_surface = attribute_panel
	_attributes_label = Label.new()
	_attributes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attributes_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	attribute_panel.add_child(_attributes_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Tokens.SPACE_XS)
	body.add_child(right)
	_inventory_surface = right
	_selection_label = Label.new()
	_selection_label.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	_selection_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	right.add_child(_selection_label)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 9
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_inventory_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	right.add_child(_inventory_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = Vector2(58, 46)
		slot.slot_clicked.connect(_on_inventory_slot_clicked)
		slot.slot_activated.connect(_on_inventory_slot_activated)
		_inventory_grid.add_child(slot)
		_inventory_buttons.append(slot)
	var hint := Label.new()
	hint.text = "单击切换/交换；右键或双击武器、防具可装备，其他物品快速放入当前快捷栏。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	hint.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	right.add_child(hint)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 22.0
	_status_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	_status_label.modulate = Tokens.color(Tokens.COLOR_ACCENT)
	right.add_child(_status_label)


func _refresh_inventory() -> void:
	if inventory == null or _selection_label == null:
		return
	for index in _inventory_buttons.size():
		var button = _inventory_buttons[index]
		button.display_slot(
			inventory.call("get_slot", index),
			inventory.get("registry"),
			index == int(inventory.get("selected_slot")),
			index == _selected_source
		)
	var swap_source := str(_selected_source + 1) if _selected_source >= 0 else "无"
	_selection_label.text = "当前快捷栏：%d    交换起点：%s" % [
		int(inventory.get("selected_slot")) + 1, swap_source
	]


func _refresh_equipment() -> void:
	for raw_slot_id in _equipment_buttons:
		var slot_id := str(raw_slot_id)
		var button := _equipment_buttons[slot_id] as Button
		var slot_definition: Dictionary = (
			equipment.call("get_slot_definition", slot_id)
			if equipment != null and equipment.has_method("get_slot_definition")
			else {"name": slot_id}
		)
		var slot_name := str(slot_definition.get("name", slot_id))
		var item: Dictionary = (
			equipment.call("get_slot", slot_id)
			if equipment != null and equipment.has_method("get_slot")
			else {}
		)
		if item.is_empty():
			button.text = "%s    · 空" % slot_name
			button.tooltip_text = "%s为空" % slot_name
			button.self_modulate = Color.WHITE
			continue
		var item_id := str(item.get("item_id", ""))
		var definition: Dictionary = _item_definition(item_id)
		var display_name := str(definition.get("name", item_id))
		var durability_text := _durability_text(item, definition)
		button.text = "%s    %s%s" % [
			slot_name,
			display_name,
			" · %s" % durability_text if not durability_text.is_empty() else "",
		]
		button.tooltip_text = "%s\n点击放回背包%s" % [
			display_name,
			"\n%s" % durability_text if not durability_text.is_empty() else "",
		]
		button.self_modulate = Color.from_string(
			str(definition.get("color", "#FFFFFF")), Color.WHITE
		).lerp(Color.WHITE, 0.55)


func _refresh_attributes() -> void:
	if _attributes_label == null:
		return
	var values: Dictionary = {}
	if attributes != null and attributes.has_method("get_values"):
		values = attributes.call("get_values")
	var defense := maxf(0.0, float(values.get("defense", 0.0)))
	var mitigation := minf(0.80, defense / (defense + 20.0)) if defense > 0.0 else 0.0
	_attributes_label.text = (
		"生命上限  %.0f\n攻击      %.1f\n防御      %.1f\n预计减伤  %.0f%%\n移动速度  %.0f%%\n采集速度  %.0f%%"
		% [
			float(values.get("max_health", 20.0)),
			float(values.get("attack_damage", 1.0)),
			defense,
			mitigation * 100.0,
			float(values.get("movement_speed", 1.0)) * 100.0,
			float(values.get("mining_speed", 1.0)) * 100.0,
		]
	)


func _on_inventory_slot_clicked(index: int) -> void:
	if inventory == null:
		return
	if _selected_source >= 0:
		if _selected_source == index:
			_selected_source = -1
		else:
			inventory.call("swap_slots", _selected_source, index)
			_selected_source = -1
			if bool(inventory.call("is_hotbar_slot", index)):
				inventory.call("select_slot", index)
	elif bool(inventory.call("is_hotbar_slot", index)):
		inventory.call("select_slot", index)
	else:
		_selected_source = index
	refresh()


func _on_inventory_slot_activated(index: int) -> void:
	if inventory == null:
		return
	var item: Dictionary = inventory.call("get_slot", index)
	if item.is_empty():
		return
	if equipment != null and equipment.has_method("can_equip_item") and bool(
		equipment.call("can_equip_item", item, "")
	):
		if bool(equipment.call("equip_from_inventory", inventory, index, "")):
			var item_id := str(item.get("item_id", ""))
			_show_status("已装备 %s" % _display_name(item_id), "success")
	else:
		if bool(inventory.call("is_hotbar_slot", index)):
			inventory.call("select_slot", index)
		else:
			inventory.call("equip_slot", index)
	_selected_source = -1
	refresh()


func _on_equipment_pressed(slot_id: String) -> void:
	if equipment == null or inventory == null:
		return
	var item: Dictionary = equipment.call("get_slot", slot_id)
	if item.is_empty():
		_show_status("该装备槽为空", "info")
		return
	if bool(equipment.call("unequip_to_inventory", inventory, slot_id)):
		_show_status("已卸下 %s" % _display_name(str(item.get("item_id", ""))), "success")
	refresh()


func _on_equipment_changed(_snapshot: Dictionary) -> void:
	refresh()


func _on_attributes_changed(_snapshot: Dictionary) -> void:
	_refresh_attributes()


func _on_selected_slot_changed(_index: int, _slot: Dictionary) -> void:
	refresh()


func _on_transaction_rejected(reason: String, _context: Dictionary) -> void:
	var message: String = str(
		{
			"item_not_equippable": "该物品不能放入装备槽",
			"inventory_full": "背包已满，无法替换或卸下装备",
			"source_remove_failed": "装备操作失败，请重试",
			"swap_rollback": "装备交换已回滚，物品没有丢失",
		}.get(reason, "当前无法完成装备操作")
	)
	_show_status(message, "warning")


func _show_status(message: String, severity: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.modulate = Tokens.severity_color(severity)


func _item_definition(item_id: String) -> Dictionary:
	if inventory == null or inventory.get("registry") == null:
		return {}
	return inventory.registry.get_item(item_id)


func _display_name(item_id: String) -> String:
	var definition := _item_definition(item_id)
	return str(definition.get("name", item_id))


func _durability_text(item: Dictionary, definition: Dictionary) -> String:
	var maximum := maxi(0, int(definition.get("durability", 0)))
	if maximum <= 0:
		return ""
	var metadata: Dictionary = item.get("metadata", {})
	var remaining := clampi(int(metadata.get("durability", maximum)), 0, maximum)
	return "耐久 %d / %d" % [remaining, maximum]


func _disconnect_inventory() -> void:
	if inventory == null:
		return
	var refresh_callback := Callable(self, "refresh")
	if inventory.has_signal("inventory_changed") and inventory.is_connected(
		"inventory_changed", refresh_callback
	):
		inventory.disconnect("inventory_changed", refresh_callback)
	var selection_callback := Callable(self, "_on_selected_slot_changed")
	if inventory.has_signal("selected_slot_changed") and inventory.is_connected(
		"selected_slot_changed", selection_callback
	):
		inventory.disconnect("selected_slot_changed", selection_callback)


func _disconnect_character_services() -> void:
	if equipment != null:
		var changed_callback := Callable(self, "_on_equipment_changed")
		if equipment.has_signal("equipment_changed") and equipment.is_connected(
			"equipment_changed", changed_callback
		):
			equipment.disconnect("equipment_changed", changed_callback)
		var rejected_callback := Callable(self, "_on_transaction_rejected")
		if equipment.has_signal("transaction_rejected") and equipment.is_connected(
			"transaction_rejected", rejected_callback
		):
			equipment.disconnect("transaction_rejected", rejected_callback)
	if attributes != null:
		var attributes_callback := Callable(self, "_on_attributes_changed")
		if attributes.has_signal("attributes_changed") and attributes.is_connected(
			"attributes_changed", attributes_callback
		):
			attributes.disconnect("attributes_changed", attributes_callback)
