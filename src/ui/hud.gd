class_name GameHUD
extends Control

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")

var inventory
var survival
var day_night
var _health_bar: ProgressBar
var _hunger_bar: ProgressBar
var _health_label: Label
var _hunger_label: Label
var _time_label: Label
var _item_label: Label
var _hotbar: HBoxContainer
var _slot_buttons: Array = []
var _message_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ThemeFactory.create_theme()
	_build_status_panel()
	_build_hotbar()
	_build_crosshair()


func setup(p_inventory, p_survival = null, p_day_night = null) -> void:
	inventory = p_inventory
	survival = p_survival
	day_night = p_day_night
	if inventory != null:
		inventory.inventory_changed.connect(refresh_inventory)
		inventory.selected_slot_changed.connect(_on_selected_slot_changed)
	if survival != null:
		survival.health_changed.connect(_on_health_changed)
		survival.hunger_changed.connect(_on_hunger_changed)
		_on_health_changed(survival.health, survival.max_health)
		_on_hunger_changed(survival.hunger, survival.max_hunger)
	if day_night != null:
		day_night.time_changed.connect(_on_time_changed)
		_on_time_changed(day_night.time_of_day, day_night.day_count)
	refresh_inventory()


func refresh_inventory() -> void:
	if inventory == null or _slot_buttons.is_empty():
		return
	for index in _slot_buttons.size():
		_slot_buttons[index].display_slot(
			inventory.get_slot(index), inventory.registry, index == inventory.selected_slot
		)
	_on_selected_slot_changed(inventory.selected_slot, inventory.get_selected_item())


func show_message(message: String, seconds: float = 2.0) -> void:
	_message_label.text = message
	_message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(_message_label, "modulate:a", 0.0, 0.35)


func _build_status_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(310, 122)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var title := Label.new()
	title.text = "✦ STAR WORLD"
	content.add_child(title)
	_health_label = Label.new()
	content.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.modulate = Color("#F46F72")
	content.add_child(_health_bar)
	_hunger_label = Label.new()
	content.add_child(_hunger_label)
	_hunger_bar = ProgressBar.new()
	_hunger_bar.show_percentage = false
	_hunger_bar.modulate = Color("#E9B755")
	content.add_child(_hunger_bar)
	_time_label = Label.new()
	_time_label.position = Vector2(20, 150)
	add_child(_time_label)
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.position = Vector2(-220, 28)
	_message_label.size = Vector2(440, 42)
	add_child(_message_label)


func _build_hotbar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -98
	panel.offset_bottom = -18
	add_child(panel)
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 4)
	panel.add_child(_hotbar)
	for index in 9:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = Vector2(66, 60)
		slot.slot_clicked.connect(_on_hotbar_slot_clicked)
		_hotbar.add_child(slot)
		_slot_buttons.append(slot)
	_item_label = Label.new()
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.anchor_left = 0.5
	_item_label.anchor_right = 0.5
	_item_label.anchor_top = 1.0
	_item_label.anchor_bottom = 1.0
	_item_label.offset_left = -180
	_item_label.offset_right = 180
	_item_label.offset_top = -126
	_item_label.offset_bottom = -100
	add_child(_item_label)


func _build_crosshair() -> void:
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 30)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-16, -20)
	crosshair.size = Vector2(32, 40)
	add_child(crosshair)


func _on_hotbar_slot_clicked(index: int) -> void:
	if inventory != null:
		inventory.select_slot(index)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "生命  %d / %d" % [ceili(current), ceili(maximum)]


func _on_hunger_changed(current: float, maximum: float) -> void:
	_hunger_bar.max_value = maximum
	_hunger_bar.value = current
	_hunger_label.text = "饥饿  %d / %d" % [ceili(current), ceili(maximum)]


func _on_time_changed(hours: float, day: int) -> void:
	_time_label.text = "第 %d 天  %02d:%02d" % [day, int(hours), int(fmod(hours, 1.0) * 60.0)]


func _on_selected_slot_changed(index: int, slot: Dictionary) -> void:
	if inventory == null:
		return
	var item_id := str(slot.get("item_id", ""))
	_item_label.text = (
		"[%d] %s" % [index + 1, inventory.registry.get_display_name(item_id)]
		if not item_id.is_empty()
		else "[%d] 空手" % (index + 1)
	)
	for button_index in _slot_buttons.size():
		_slot_buttons[button_index].display_slot(
			inventory.get_slot(button_index), inventory.registry, button_index == index
		)
