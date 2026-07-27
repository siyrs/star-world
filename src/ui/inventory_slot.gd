class_name InventorySlotButton
extends Button

signal slot_clicked(index: int)
signal slot_activated(index: int)

const IconFactory = preload("res://src/ui/item_icon_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")

var slot_index: int = -1

var _icon_rect: TextureRect
var _count_label: Label
var _index_label: Label
var _durability_bar: ColorRect
var _durability_back: ColorRect


func configure(index: int) -> void:
	slot_index = index
	custom_minimum_size = Vector2(64, 58)
	clip_text = true
	text = ""
	theme_type_variation = "InventorySlot"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(func() -> void: slot_clicked.emit(slot_index))

	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.offset_left = 10
	_icon_rect.offset_top = 8
	_icon_rect.offset_right = -10
	_icon_rect.offset_bottom = -8
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	_index_label = Label.new()
	_index_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_index_label.offset_left = 5
	_index_label.offset_top = 2
	_index_label.offset_right = 22
	_index_label.offset_bottom = 18
	_index_label.text = str(index + 1) if index >= 0 and index < 9 else ""
	_index_label.theme_type_variation = "SubduedLabel"
	_index_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	_index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_index_label)

	_count_label = Label.new()
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.offset_left = -36
	_count_label.offset_top = -23
	_count_label.offset_right = -5
	_count_label.offset_bottom = -3
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	_count_label.add_theme_color_override("font_color", Tokens.color(Tokens.COLOR_TEXT))
	_count_label.add_theme_color_override("font_shadow_color", Color("#000000DD"))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_count_label.add_theme_constant_override("shadow_outline_size", 2)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	_durability_back = ColorRect.new()
	_durability_back.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_durability_back.offset_left = 7
	_durability_back.offset_top = -7
	_durability_back.offset_right = -7
	_durability_back.offset_bottom = -4
	_durability_back.color = Color("#02060ACC")
	_durability_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durability_back.visible = false
	add_child(_durability_back)

	_durability_bar = ColorRect.new()
	_durability_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_durability_bar.offset_left = 7
	_durability_bar.offset_top = -7
	_durability_bar.offset_bottom = -4
	_durability_bar.color = Tokens.color(Tokens.COLOR_SUCCESS)
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
	theme_type_variation = (
		"InventorySlotSwap"
		if swap_source
		else ("InventorySlotSelected" if selected else "InventorySlot")
	)
	if slot.is_empty():
		_icon_rect.texture = null
		_icon_rect.modulate = Color.WHITE
		_count_label.text = ""
		_durability_back.visible = false
		_durability_bar.visible = false
		tooltip_text = "空槽位"
		return

	var item_id := str(slot.get("item_id", ""))
	var item: Dictionary = registry.get_item(item_id) if registry != null else {}
	var item_name := str(item.get("name", item_id))
	var count := int(slot.get("count", 0))
	_icon_rect.texture = IconFactory.get_icon(item_id, item)
	var item_color := Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	_icon_rect.modulate = item_color.lerp(Color.WHITE, 0.42)

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
		_durability_bar.offset_right = 7.0 + 42.0 * ratio
		_durability_bar.color = Tokens.color(Tokens.COLOR_SUCCESS).lerp(
			Tokens.color(Tokens.COLOR_DANGER), 1.0 - ratio
		)
		tooltip_text = "%s\n耐久 %d / %d" % [item_name, remaining, maximum_durability]
	else:
		_count_label.text = "×%d" % count if count > 1 else ""
		_durability_back.visible = false
		_durability_bar.visible = false
		tooltip_text = "%s\n数量 %d" % [item_name, count]
