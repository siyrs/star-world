class_name InventorySlotButton
extends Button

signal slot_clicked(index: int)
signal slot_activated(index: int)

const IconFactory = preload("res://src/ui/item_icon_factory.gd")

var slot_index: int = -1

var _icon_rect: TextureRect
var _count_label: Label
var _durability_bar: ColorRect
var _durability_back: ColorRect


func configure(index: int) -> void:
	slot_index = index
	custom_minimum_size = Vector2(68, 62)
	clip_text = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(func(): slot_clicked.emit(slot_index))
	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.offset_left = 10
	_icon_rect.offset_top = 6
	_icon_rect.offset_right = -10
	_icon_rect.offset_bottom = -6
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)
	_count_label = Label.new()
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.offset_left = -30
	_count_label.offset_top = -20
	_count_label.offset_right = -4
	_count_label.offset_bottom = -2
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	_count_label.add_theme_color_override("font_shadow_color", Color("#000000C0"))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)
	_durability_back = ColorRect.new()
	_durability_back.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_durability_back.offset_left = 8
	_durability_back.offset_top = -6
	_durability_back.offset_right = -8
	_durability_back.offset_bottom = -3
	_durability_back.color = Color("#000000A0")
	_durability_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durability_back.visible = false
	add_child(_durability_back)
	_durability_bar = ColorRect.new()
	_durability_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_durability_bar.offset_left = 8
	_durability_bar.offset_top = -6
	_durability_bar.offset_bottom = -3
	_durability_bar.color = Color("#7BD87B")
	_durability_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durability_bar.visible = false
	add_child(_durability_bar)


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
	if _icon_rect == null:
		return
	if slot.is_empty():
		_icon_rect.texture = null
		_count_label.text = ""
		_durability_back.visible = false
		_durability_bar.visible = false
		tooltip_text = "空"
		self_modulate = _display_color(Color.WHITE, selected, swap_source)
		return
	var item_id := str(slot.get("item_id", ""))
	var item: Dictionary = registry.get_item(item_id) if registry != null else {}
	var item_name := str(item.get("name", item_id))
	var count := int(slot.get("count", 0))
	_icon_rect.texture = IconFactory.get_icon(item_id, item)
	var maximum_durability := maxi(0, int(item.get("durability", 0)))
	if maximum_durability > 0:
		var metadata: Dictionary = slot.get("metadata", {})
		var remaining := clampi(
			int(metadata.get("durability", maximum_durability)), 0, maximum_durability
		)
		var ratio := float(remaining) / float(maximum_durability)
		_count_label.text = ""
		_durability_back.visible = true
		_durability_bar.visible = true
		_durability_bar.offset_right = 8.0 + 52.0 * ratio
		_durability_bar.color = Color("#7BD87B").lerp(Color("#E05B52"), 1.0 - ratio)
		tooltip_text = "%s (%s)\n耐久: %d / %d" % [
			item_name, item_id, remaining, maximum_durability
		]
	else:
		_count_label.text = "×%d" % count if count > 1 else ""
		_durability_back.visible = false
		_durability_bar.visible = false
		tooltip_text = "%s (%s)\n数量: %d" % [item_name, item_id, count]
	var item_color := Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	self_modulate = _display_color(item_color, selected, swap_source)


func _display_color(item_color: Color, selected: bool, swap_source: bool) -> Color:
	if swap_source:
		return item_color.lerp(Color("#72D8FF"), 0.28)
	if selected:
		return item_color.lerp(Color("#FFE171"), 0.35)
	return item_color.lerp(Color.WHITE, 0.58)
