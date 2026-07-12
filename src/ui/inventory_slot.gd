class_name InventorySlotButton
extends Button

signal slot_clicked(index: int)

var slot_index: int = -1


func configure(index: int) -> void:
	slot_index = index
	custom_minimum_size = Vector2(68, 62)
	clip_text = true
	pressed.connect(func(): slot_clicked.emit(slot_index))


func display_slot(slot: Dictionary, registry, selected: bool = false) -> void:
	if slot.is_empty():
		text = "\u00b7"
		tooltip_text = "空"
		self_modulate = Color("#FFFFFF") if not selected else Color("#FFE07A")
		return
	var item_id := str(slot.get("item_id", ""))
	var item: Dictionary = registry.get_item(item_id) if registry != null else {}
	var item_name := str(item.get("name", item_id))
	var count := int(slot.get("count", 0))
	text = "%s\n×%d" % [_short_name(item_name), count]
	tooltip_text = "%s (%s)\n数量: %d" % [item_name, item_id, count]
	var item_color := Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	self_modulate = item_color.lerp(Color.WHITE, 0.58) if not selected else item_color.lerp(Color("#FFE171"), 0.35)


func _short_name(value: String) -> String:
	return value.left(6)
