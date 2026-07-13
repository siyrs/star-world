class_name InventorySlotButton
extends Button

signal slot_clicked(index: int)
signal slot_activated(index: int)

var slot_index: int = -1


func configure(index: int) -> void:
	slot_index = index
	custom_minimum_size = Vector2(68, 62)
	clip_text = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(func(): slot_clicked.emit(slot_index))


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	var activates_slot: bool = mouse_event.button_index == MOUSE_BUTTON_RIGHT
	activates_slot = (
		activates_slot
		or (mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click)
	)
	if activates_slot:
		slot_activated.emit(slot_index)
		accept_event()


func display_slot(
	slot: Dictionary, registry, selected: bool = false, swap_source: bool = false
) -> void:
	if slot.is_empty():
		text = "·"
		tooltip_text = "空"
		self_modulate = _display_color(Color.WHITE, selected, swap_source)
		return
	var item_id := str(slot.get("item_id", ""))
	var item: Dictionary = registry.get_item(item_id) if registry != null else {}
	var item_name := str(item.get("name", item_id))
	var count := int(slot.get("count", 0))
	var maximum_durability := maxi(0, int(item.get("durability", 0)))
	if maximum_durability > 0:
		var metadata: Dictionary = slot.get("metadata", {})
		var remaining := clampi(
			int(metadata.get("durability", maximum_durability)), 0, maximum_durability
		)
		var percentage := roundi(float(remaining) / float(maximum_durability) * 100.0)
		text = "%s\n%d%%" % [_short_name(item_name), percentage]
		tooltip_text = "%s (%s)\n耐久: %d / %d" % [
			item_name, item_id, remaining, maximum_durability
		]
	else:
		text = "%s\n×%d" % [_short_name(item_name), count]
		tooltip_text = "%s (%s)\n数量: %d" % [item_name, item_id, count]
	var item_color := Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	self_modulate = _display_color(item_color, selected, swap_source)


func _display_color(item_color: Color, selected: bool, swap_source: bool) -> Color:
	if swap_source:
		return item_color.lerp(Color("#72D8FF"), 0.28)
	if selected:
		return item_color.lerp(Color("#FFE171"), 0.35)
	return item_color.lerp(Color.WHITE, 0.58)


func _short_name(value: String) -> String:
	return value.left(6)
