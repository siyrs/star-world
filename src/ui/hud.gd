class_name GameHUD
extends Control

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const CrosshairScript = preload("res://src/ui/world_crosshair.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")
const HudIcons = preload("res://src/ui/hud_icon_factory.gd")
const PixelTextures = preload("res://src/ui/pixel_ui_textures.gd")

const SLOT_SIZE := Vector2(56, 56)
const ICON_SIZE := Vector2(18, 18)
const LOW_HEALTH_THRESHOLD := 4.0

var inventory
var survival
var day_night
var danger_service: Node
var _status_panel: PanelContainer
var _danger_panel: PanelContainer
var _danger_label: Label
var _danger_detail: Label
var _danger_warning: Label
var _hotbar_panel: PanelContainer
var _item_panel: PanelContainer
var _health_icons: Array = []
var _hunger_icons: Array = []
var _health_row: HBoxContainer
var _hunger_row: HBoxContainer
var _time_label: Label
var _item_label: Label
var _hotbar: HBoxContainer
var _slot_buttons: Array = []
var _message_panel: PanelContainer
var _message_label: Label
var _crosshair: Control
var _hurt_flash: TextureRect
var _hurt_tween: Tween
var _pulse_elapsed := 0.0
var _current_health := 20.0
var _max_health := 20.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_status_panel()
	_build_danger_panel()
	_build_hotbar()
	_build_vitals_rows()
	_build_crosshair()
	_build_hurt_flash()
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


func setup_danger(service: Node) -> void:
	if danger_service != null and danger_service.has_signal("danger_changed"):
		var callback := Callable(self, "_on_danger_changed")
		if danger_service.is_connected("danger_changed", callback):
			danger_service.disconnect("danger_changed", callback)
	danger_service = service
	if danger_service != null and danger_service.has_signal("danger_changed"):
		danger_service.connect("danger_changed", Callable(self, "_on_danger_changed"))
	if danger_service != null and danger_service.has_method("get_snapshot"):
		var raw_snapshot: Variant = danger_service.call("get_snapshot")
		if raw_snapshot is Dictionary:
			_on_danger_changed(raw_snapshot)
	else:
		_on_danger_changed({})


func refresh_inventory() -> void:
	if inventory == null or _slot_buttons.is_empty():
		return
	for index in _slot_buttons.size():
		_slot_buttons[index].display_slot(
			inventory.get_slot(index), inventory.registry, index == inventory.selected_slot
		)
	_on_selected_slot_changed(inventory.selected_slot, inventory.get_selected_item())


func show_message(message: String, seconds: float = 2.0) -> void:
	if _message_label == null or _message_panel == null:
		return
	_message_label.text = message
	_message_panel.visible = true
	_message_panel.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(_message_panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void: _message_panel.visible = false)


func flash_hurt() -> void:
	if _hurt_flash == null:
		return
	if _hurt_tween != null and _hurt_tween.is_running():
		_hurt_tween.kill()
	_hurt_flash.visible = true
	_hurt_flash.modulate.a = 0.85
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_hurt_flash, "modulate:a", 0.0, 0.4)
	_hurt_tween.tween_callback(func() -> void: _hurt_flash.visible = false)


func get_layout_rects() -> Dictionary:
	return {
		"status": _status_panel.get_global_rect() if _status_panel != null else Rect2(),
		"danger": _danger_panel.get_global_rect() if _danger_panel != null else Rect2(),
		"selected_item": _item_panel.get_global_rect() if _item_panel != null else Rect2(),
		"hotbar": _hotbar_panel.get_global_rect() if _hotbar_panel != null else Rect2(),
		"crosshair": _crosshair.get_global_rect() if _crosshair != null else Rect2(),
		"fallback_message": _message_panel.get_global_rect() if _message_panel != null else Rect2(),
	}


func get_crosshair() -> Control:
	return _crosshair


func get_danger_panel() -> Control:
	return _danger_panel


func get_danger_warning_text() -> String:
	return _danger_warning.text if _danger_warning != null else ""


func is_danger_warning_visible() -> bool:
	return _danger_warning != null and _danger_warning.visible


func _process(delta: float) -> void:
	# Low-health heartbeat: the heart row breathes so danger stays visible in
	# peripheral vision without any text.
	if _health_row == null:
		return
	if _current_health <= LOW_HEALTH_THRESHOLD and _current_health > 0.0:
		_pulse_elapsed += maxf(0.0, delta)
		var pulse := 0.68 + 0.32 * sin(_pulse_elapsed * TAU * 1.2)
		_health_row.modulate = Color(1.0, pulse, pulse, 1.0)
	else:
		_health_row.modulate = Color.WHITE


func _build_status_panel() -> void:
	_status_panel = PanelContainer.new()
	_status_panel.name = "VitalsCard"
	_status_panel.position = Vector2(18, 18)
	_status_panel.custom_minimum_size = Vector2(150, 40)
	_status_panel.theme_type_variation = "HudPanel"
	add_child(_status_panel)
	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.theme_type_variation = "CaptionLabel"
	_status_panel.add_child(_time_label)


func _build_danger_panel() -> void:
	_danger_panel = PanelContainer.new()
	_danger_panel.name = "DangerCard"
	_danger_panel.anchor_left = 1.0
	_danger_panel.anchor_right = 1.0
	_danger_panel.offset_left = -322.0
	_danger_panel.offset_right = -18.0
	_danger_panel.offset_top = 18.0
	_danger_panel.offset_bottom = 132.0
	_danger_panel.custom_minimum_size = Vector2(304, 114)
	_danger_panel.theme_type_variation = "HudPanel"
	add_child(_danger_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_danger_panel.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "区域威胁"
	eyebrow.theme_type_variation = "EyebrowLabel"
	content.add_child(eyebrow)
	_danger_label = Label.new()
	_danger_label.theme_type_variation = "SectionTitle"
	content.add_child(_danger_label)
	_danger_detail = Label.new()
	_danger_detail.theme_type_variation = "CaptionLabel"
	_danger_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_danger_detail)
	_danger_warning = Label.new()
	_danger_warning.theme_type_variation = "DangerLabel"
	_danger_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_danger_warning.visible = false
	content.add_child(_danger_warning)
	_danger_panel.visible = false


func _build_hotbar() -> void:
	_hotbar_panel = PanelContainer.new()
	_hotbar_panel.name = "HotbarDock"
	_hotbar_panel.anchor_left = 0.5
	_hotbar_panel.anchor_right = 0.5
	_hotbar_panel.anchor_top = 1.0
	_hotbar_panel.anchor_bottom = 1.0
	var width := 9.0 * SLOT_SIZE.x + 8.0 * 2.0 + 8.0
	_hotbar_panel.offset_left = -width * 0.5
	_hotbar_panel.offset_right = width * 0.5
	_hotbar_panel.offset_top = -SLOT_SIZE.y - 14.0
	_hotbar_panel.offset_bottom = -10.0
	_hotbar_panel.theme_type_variation = "HudPanel"
	_hotbar_panel.add_theme_stylebox_override(
		"panel", Tokens.bevel_style("#00000066", "#000000AA", 2, 3.0)
	)
	add_child(_hotbar_panel)
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 2)
	_hotbar_panel.add_child(_hotbar)
	for index in 9:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = SLOT_SIZE
		_hotbar.add_child(slot)
		_slot_buttons.append(slot)

	_item_panel = PanelContainer.new()
	_item_panel.name = "SelectedItemCard"
	_item_panel.anchor_left = 0.5
	_item_panel.anchor_right = 0.5
	_item_panel.anchor_top = 1.0
	_item_panel.anchor_bottom = 1.0
	_item_panel.offset_left = -190.0
	_item_panel.offset_right = 190.0
	_item_panel.offset_top = -SLOT_SIZE.y - 60.0
	_item_panel.offset_bottom = -SLOT_SIZE.y - 34.0
	_item_panel.add_theme_stylebox_override(
		"panel", Tokens.bevel_style("#00000066", "#00000000", 0, 2.0)
	)
	add_child(_item_panel)
	_item_label = Label.new()
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_label.theme_type_variation = "CaptionLabel"
	_item_panel.add_child(_item_label)


func _build_vitals_rows() -> void:
	# Minecraft layout: hearts sit above the left edge of the hotbar and
	# drumsticks above its right edge.
	var width := 9.0 * SLOT_SIZE.x + 8.0 * 2.0 + 8.0
	_health_row = _make_icon_row("heart")
	_health_row.anchor_left = 0.5
	_health_row.anchor_right = 0.5
	_health_row.anchor_top = 1.0
	_health_row.anchor_bottom = 1.0
	_health_row.offset_left = -width * 0.5 + 4.0
	_health_row.offset_right = -width * 0.5 + 4.0 + 10.0 * ICON_SIZE.x + 9.0
	_health_row.offset_top = -SLOT_SIZE.y - 14.0 - ICON_SIZE.y - 4.0
	_health_row.offset_bottom = -SLOT_SIZE.y - 14.0 - 4.0
	add_child(_health_row)
	_health_icons = _health_row.get_meta("icons")

	_hunger_row = _make_icon_row("drumstick")
	_hunger_row.anchor_left = 0.5
	_hunger_row.anchor_right = 0.5
	_hunger_row.anchor_top = 1.0
	_hunger_row.anchor_bottom = 1.0
	_hunger_row.offset_left = width * 0.5 - 4.0 - (10.0 * ICON_SIZE.x + 9.0)
	_hunger_row.offset_right = width * 0.5 - 4.0
	_hunger_row.offset_top = -SLOT_SIZE.y - 14.0 - ICON_SIZE.y - 4.0
	_hunger_row.offset_bottom = -SLOT_SIZE.y - 14.0 - 4.0
	add_child(_hunger_row)
	_hunger_icons = _hunger_row.get_meta("icons")


func _make_icon_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%s_row" % kind
	row.add_theme_constant_override("separation", 1)
	row.alignment = (
		BoxContainer.ALIGNMENT_BEGIN if kind == "heart" else BoxContainer.ALIGNMENT_END
	)
	var icons: Array = []
	for _index in 10:
		var rect := TextureRect.new()
		rect.custom_minimum_size = ICON_SIZE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(rect)
		icons.append(rect)
	row.set_meta("icons", icons)
	return row


func _build_crosshair() -> void:
	_crosshair = CrosshairScript.new()
	_crosshair.name = "WorldCrosshair"
	add_child(_crosshair)


func _build_hurt_flash() -> void:
	_hurt_flash = TextureRect.new()
	_hurt_flash.name = "HurtVignette"
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.texture = PixelTextures.hurt_vignette()
	_hurt_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hurt_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_hurt_flash.modulate.a = 0.0
	_hurt_flash.visible = false
	add_child(_hurt_flash)


func _build_fallback_message() -> void:
	_message_panel = PanelContainer.new()
	_message_panel.name = "FallbackToast"
	_message_panel.theme_type_variation = "HudPanel"
	_message_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_panel.position = Vector2(-260, 20)
	_message_panel.size = Vector2(520, 48)
	_message_panel.visible = false
	add_child(_message_panel)
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.theme_type_variation = "CaptionLabel"
	_message_panel.add_child(_message_label)


func _update_icon_row(icons: Array, current: float, maximum: float, kind: String) -> void:
	if icons.is_empty():
		return
	var units := clampi(int(round(current)), 0, int(round(maximum)))
	for index in icons.size():
		var points: int = clampi(units - index * 2, 0, 2)
		var suffix := "full" if points == 2 else ("half" if points == 1 else "empty")
		icons[index].texture = HudIcons.texture("%s_%s" % [kind, suffix])


func _on_health_changed(current: float, maximum: float) -> void:
	var took_damage := current < _current_health - 0.001
	_current_health = current
	_max_health = maximum
	_update_icon_row(_health_icons, current, maximum, "heart")
	if took_damage:
		flash_hurt()


func _on_hunger_changed(current: float, maximum: float) -> void:
	_update_icon_row(_hunger_icons, current, maximum, "drumstick")


func _on_time_changed(hours: float, day: int) -> void:
	_time_label.text = "第 %d 天 · %02d:%02d" % [
		day, int(hours), int(fmod(hours, 1.0) * 60.0)
	]


func _on_danger_changed(snapshot: Dictionary) -> void:
	if _danger_panel == null:
		return
	if snapshot.is_empty():
		_danger_panel.visible = false
		if _danger_warning != null:
			_danger_warning.visible = false
			_danger_warning.text = ""
		return
	var tone := str(snapshot.get("tone", "info"))
	var border := _danger_color(tone)
	_danger_panel.add_theme_stylebox_override(
		"panel", Tokens.bevel_style("#100C07F0", border, 2, 10.0)
	)
	_danger_label.text = "%s · %d / 100" % [
		str(snapshot.get("tier_label", "未知")),
		clampi(int(snapshot.get("score", 0)), 0, 100),
	]
	_danger_label.add_theme_color_override("font_color", Tokens.color(border))
	var raw_reasons: Variant = snapshot.get("reasons", [])
	var reasons: Array[String] = []
	if raw_reasons is Array:
		for raw_reason: Variant in raw_reasons:
			var reason := str(raw_reason)
			if not reason.is_empty() and reasons.size() < 3:
				reasons.append(reason)
	_danger_detail.text = " · ".join(reasons) if not reasons.is_empty() else "当前环境相对稳定"
	_update_incoming_attack_warning(snapshot)
	_danger_panel.visible = true


func _update_incoming_attack_warning(snapshot: Dictionary) -> void:
	if _danger_warning == null:
		return
	var windup_count := maxi(0, int(snapshot.get("windup_count", 0)))
	if windup_count <= 0:
		_danger_warning.text = ""
		_danger_warning.visible = false
		return
	var urgency := str(snapshot.get("windup_urgency_label", "")).strip_edges()
	if urgency.is_empty():
		urgency = "来袭攻击 ×%d" % windup_count
	_danger_warning.text = "⚠ %s" % urgency
	_danger_warning.visible = true


func _danger_color(tone: String) -> String:
	match tone:
		"success": return Tokens.COLOR_SUCCESS
		"warning": return Tokens.COLOR_WARNING
		"error": return Tokens.COLOR_DANGER
		_: return Tokens.COLOR_ACCENT


func _on_selected_slot_changed(index: int, slot: Dictionary) -> void:
	if inventory == null:
		return
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		_item_label.text = ""
	else:
		var definition: Dictionary = inventory.registry.get_item(item_id)
		var display_name: String = str(inventory.registry.get_display_name(item_id))
		var maximum_durability := maxi(0, int(definition.get("durability", 0)))
		if maximum_durability > 0:
			var metadata: Dictionary = slot.get("metadata", {})
			var remaining := clampi(
				int(metadata.get("durability", maximum_durability)), 0, maximum_durability
			)
			_item_label.text = "%s · 耐久 %d / %d" % [
				display_name, remaining, maximum_durability
			]
		else:
			_item_label.text = display_name
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
