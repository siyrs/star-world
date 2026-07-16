class_name GameHUD
extends Control

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const CrosshairScript = preload("res://src/ui/world_crosshair.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var inventory
var survival
var day_night
var _status_panel: PanelContainer
var _hotbar_panel: PanelContainer
var _item_panel: PanelContainer
var _health_bar: ProgressBar
var _hunger_bar: ProgressBar
var _health_label: Label
var _hunger_label: Label
var _time_label: Label
var _item_label: Label
var _hotbar: HBoxContainer
var _slot_buttons: Array = []
var _message_label: Label
var _crosshair: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_status_panel()
	_build_hotbar()
	_build_crosshair()
	_build_fallback_message()
	UiInputPolicy.make_passthrough_tree(self)


func setup(p_inventory, p_survival = null, p_day_night = null) -> void:
	_disconnect_services()
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
	if _message_label == null:
		return
	_message_label.text = message
	_message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(_message_label, "modulate:a", 0.0, 0.35)


func get_layout_rects() -> Dictionary:
	return {
		"status": _status_panel.get_global_rect() if _status_panel != null else Rect2(),
		"selected_item": _item_panel.get_global_rect() if _item_panel != null else Rect2(),
		"hotbar": _hotbar_panel.get_global_rect() if _hotbar_panel != null else Rect2(),
		"crosshair": _crosshair.get_global_rect() if _crosshair != null else Rect2(),
	}


func get_crosshair() -> Control:
	return _crosshair


func _build_status_panel() -> void:
	_status_panel = PanelContainer.new()
	_status_panel.position = Vector2(18, 18)
	_status_panel.size = Vector2(286, 152)
	_status_panel.custom_minimum_size = Vector2(286, 152)
	_status_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style(Tokens.COLOR_SURFACE, Tokens.COLOR_BORDER, 1, Tokens.RADIUS_LG, 12.0)
	)
	add_child(_status_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_status_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "✦ STAR WORLD"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Tokens.color(Tokens.COLOR_ACCENT)
	header.add_child(title)
	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	_time_label.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	header.add_child(_time_label)
	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	content.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size.y = 12.0
	_health_bar.add_theme_stylebox_override(
		"fill",
		Tokens.panel_style(Tokens.COLOR_HEALTH, Tokens.COLOR_HEALTH, 0, Tokens.RADIUS_SM, 1.0)
	)
	content.add_child(_health_bar)
	_hunger_label = Label.new()
	_hunger_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	content.add_child(_hunger_label)
	_hunger_bar = ProgressBar.new()
	_hunger_bar.show_percentage = false
	_hunger_bar.custom_minimum_size.y = 12.0
	_hunger_bar.add_theme_stylebox_override(
		"fill",
		Tokens.panel_style(Tokens.COLOR_HUNGER, Tokens.COLOR_HUNGER, 0, Tokens.RADIUS_SM, 1.0)
	)
	content.add_child(_hunger_bar)


func _build_hotbar() -> void:
	_hotbar_panel = PanelContainer.new()
	_hotbar_panel.anchor_left = 0.5
	_hotbar_panel.anchor_right = 0.5
	_hotbar_panel.anchor_top = 1.0
	_hotbar_panel.anchor_bottom = 1.0
	_hotbar_panel.offset_left = -322.0
	_hotbar_panel.offset_right = 322.0
	_hotbar_panel.offset_top = -98.0
	_hotbar_panel.offset_bottom = -18.0
	_hotbar_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style(Tokens.COLOR_SURFACE, Tokens.COLOR_BORDER_STRONG, 1, Tokens.RADIUS_LG, 8.0)
	)
	add_child(_hotbar_panel)
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_hotbar_panel.add_child(_hotbar)
	for index in 9:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = Vector2(64, 58)
		_hotbar.add_child(slot)
		_slot_buttons.append(slot)
	_item_panel = PanelContainer.new()
	_item_panel.anchor_left = 0.5
	_item_panel.anchor_right = 0.5
	_item_panel.anchor_top = 1.0
	_item_panel.anchor_bottom = 1.0
	_item_panel.offset_left = -180.0
	_item_panel.offset_right = 180.0
	_item_panel.offset_top = -132.0
	_item_panel.offset_bottom = -104.0
	_item_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style("#0D1724D9", "#365E77", 1, Tokens.RADIUS_SM, 4.0)
	)
	add_child(_item_panel)
	_item_label = Label.new()
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	_item_panel.add_child(_item_label)


func _build_crosshair() -> void:
	_crosshair = CrosshairScript.new()
	_crosshair.name = "WorldCrosshair"
	add_child(_crosshair)


func _build_fallback_message() -> void:
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.position = Vector2(-240, 88)
	_message_label.size = Vector2(480, 40)
	_message_label.modulate.a = 0.0
	add_child(_message_label)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "生命   %d / %d" % [ceili(current), ceili(maximum)]


func _on_hunger_changed(current: float, maximum: float) -> void:
	_hunger_bar.max_value = maximum
	_hunger_bar.value = current
	_hunger_label.text = "饥饿   %d / %d" % [ceili(current), ceili(maximum)]


func _on_time_changed(hours: float, day: int) -> void:
	_time_label.text = "第 %d 天  %02d:%02d" % [day, int(hours), int(fmod(hours, 1.0) * 60.0)]


func _on_selected_slot_changed(index: int, slot: Dictionary) -> void:
	if inventory == null:
		return
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		_item_label.text = "[%d] 空手" % (index + 1)
	else:
		var definition: Dictionary = inventory.registry.get_item(item_id)
		var display_name: String = str(inventory.registry.get_display_name(item_id))
		var maximum_durability := maxi(0, int(definition.get("durability", 0)))
		if maximum_durability > 0:
			var metadata: Dictionary = slot.get("metadata", {})
			var remaining := clampi(
				int(metadata.get("durability", maximum_durability)), 0, maximum_durability
			)
			_item_label.text = "[%d] %s · 耐久 %d / %d" % [
				index + 1, display_name, remaining, maximum_durability
			]
		else:
			_item_label.text = "[%d] %s" % [index + 1, display_name]
	for button_index in _slot_buttons.size():
		_slot_buttons[button_index].display_slot(
			inventory.get_slot(button_index), inventory.registry, button_index == index
		)


func _disconnect_services() -> void:
	if inventory != null:
		var refresh_callback := Callable(self, "refresh_inventory")
		if inventory.inventory_changed.is_connected(refresh_callback):
			inventory.inventory_changed.disconnect(refresh_callback)
		var selection_callback := Callable(self, "_on_selected_slot_changed")
		if inventory.selected_slot_changed.is_connected(selection_callback):
			inventory.selected_slot_changed.disconnect(selection_callback)
	if survival != null:
		var health_callback := Callable(self, "_on_health_changed")
		if survival.health_changed.is_connected(health_callback):
			survival.health_changed.disconnect(health_callback)
		var hunger_callback := Callable(self, "_on_hunger_changed")
		if survival.hunger_changed.is_connected(hunger_callback):
			survival.hunger_changed.disconnect(hunger_callback)
	if day_night != null:
		var time_callback := Callable(self, "_on_time_changed")
		if day_night.time_changed.is_connected(time_callback):
			day_night.time_changed.disconnect(time_callback)
