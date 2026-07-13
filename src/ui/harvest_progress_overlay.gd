class_name HarvestProgressOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var harvest_service: Node
var tool_service: Node
var experience_coordinator: Node
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _progress: ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_ui()
	UiInputPolicy.make_passthrough_tree(self)
	clear()


func setup(
	p_harvest_service: Node,
	p_tool_service: Node,
	p_experience_coordinator: Node = null
) -> void:
	_disconnect_services()
	harvest_service = p_harvest_service
	tool_service = p_tool_service
	experience_coordinator = p_experience_coordinator
	if harvest_service != null:
		harvest_service.connect(
			"harvest_progress_changed", Callable(self, "_on_harvest_progress_changed")
		)
		harvest_service.connect("harvest_cancelled", Callable(self, "_on_harvest_cancelled"))
		harvest_service.connect("harvest_completed", Callable(self, "_on_harvest_completed"))
		harvest_service.connect("harvest_rejected", Callable(self, "_on_harvest_rejected"))
	if tool_service != null:
		tool_service.connect("item_broken", Callable(self, "_on_item_broken"))


func clear() -> void:
	if _panel != null:
		_panel.visible = false
	if _progress != null:
		_progress.value = 0.0


func get_layout_rect() -> Rect2:
	return _panel.get_global_rect() if _panel != null else Rect2()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -270.0
	_panel.offset_right = 270.0
	_panel.offset_top = -314.0
	_panel.offset_bottom = -246.0
	_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style(
			Tokens.COLOR_SURFACE_RAISED,
			Tokens.COLOR_BORDER_STRONG,
			1,
			Tokens.RADIUS_MD,
			Tokens.SPACE_SM
		)
	)
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	header.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_subtitle.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	_subtitle.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	header.add_child(_subtitle)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 12.0
	_progress.add_theme_stylebox_override(
		"fill",
		Tokens.panel_style(Tokens.COLOR_ACCENT_WARM, Tokens.COLOR_ACCENT_WARM, 0, Tokens.RADIUS_SM, 1.0)
	)
	content.add_child(_progress)


func _on_harvest_progress_changed(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		clear()
		return
	_title.text = "采集中：%s" % str(snapshot.get("display_name", snapshot.get("block_id", "方块")))
	var tool_name := str(snapshot.get("tool_display_name", "空手"))
	if bool(snapshot.get("can_drop", false)):
		_subtitle.text = "%s · %.1f 秒" % [
			tool_name, float(snapshot.get("duration_seconds", 0.0))
		]
		_title.modulate = Tokens.color(Tokens.COLOR_TEXT)
	else:
		var required := str(snapshot.get("recommended_tool_label", "合适工具"))
		var power := str(snapshot.get("minimum_power_label", ""))
		_subtitle.text = "不会掉落 · 需要%s%s" % [
			power,
			required,
		]
		_title.modulate = Tokens.color(Tokens.COLOR_WARNING)
	_progress.value = clampf(float(snapshot.get("ratio", 0.0)), 0.0, 1.0)
	_panel.visible = true


func _on_harvest_cancelled(_reason: String) -> void:
	clear()


func _on_harvest_completed(result: Dictionary) -> void:
	clear()
	if bool(result.get("drop_granted", false)):
		return
	_publish(
		"已破坏%s，但当前工具无法获得掉落" % str(result.get("display_name", "方块")),
		"warning",
		3.2,
		"harvest_no_drop:%s" % str(result.get("block_id", ""))
	)


func _on_harvest_rejected(reason: String, snapshot: Dictionary) -> void:
	clear()
	var message: String = str(
		{
			"unbreakable": "这个方块无法破坏",
			"protected": "请先清空方块中的内容再拆除",
			"inventory_full": "背包没有空间，采集已取消",
			"target_changed": "采集目标发生变化",
			"remove_failed": "方块状态已变化，请重试",
		}.get(reason, "当前无法采集该方块")
	)
	_publish(
		message,
		"warning",
		2.8,
		"harvest_rejected:%s:%s" % [reason, str(snapshot.get("block_id", ""))]
	)


func _on_item_broken(
	_slot_index: int, item_id: String, display_name: String, _reason: String
) -> void:
	_publish(
		"%s 已损坏" % display_name,
		"warning",
		3.2,
		"tool_broken:%s" % item_id
	)


func _publish(message: String, severity: String, duration: float, key: String) -> void:
	if (
		experience_coordinator != null
		and experience_coordinator.has_method("publish_message")
	):
		experience_coordinator.call("publish_message", message, severity, duration, key)


func _disconnect_services() -> void:
	if harvest_service != null:
		for connection in [
			["harvest_progress_changed", "_on_harvest_progress_changed"],
			["harvest_cancelled", "_on_harvest_cancelled"],
			["harvest_completed", "_on_harvest_completed"],
			["harvest_rejected", "_on_harvest_rejected"],
		]:
			var callback := Callable(self, str(connection[1]))
			if harvest_service.is_connected(str(connection[0]), callback):
				harvest_service.disconnect(str(connection[0]), callback)
	if tool_service != null:
		var broken_callback := Callable(self, "_on_item_broken")
		if tool_service.is_connected("item_broken", broken_callback):
			tool_service.disconnect("item_broken", broken_callback)
