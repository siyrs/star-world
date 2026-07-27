class_name SettingsPanel
extends PanelContainer

signal settings_applied(settings: Dictionary)
signal back_requested

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")

var save_service
var _sensitivity: HSlider
var _render_distance: OptionButton
var _volume: HSlider
var _fullscreen: CheckButton
var _cycle: HSlider
var _autosave_interval: OptionButton
var _show_tutorial: CheckButton
var _show_interaction_prompts: CheckButton
var _camera_bob: CheckButton
var _scroll_container: ScrollContainer
var _settings_content: VBoxContainer
var _status: Label
var _actions: HBoxContainer
var _apply_button: Button
var _back_button: Button
var _value_labels: Dictionary = {}
var _section_cards: Array[PanelContainer] = []


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(740, 520)
	_build_ui()


func setup(p_save_service, _p_audio_service = null) -> void:
	save_service = p_save_service
	_load_values()


func show_apply_result(saved: bool) -> void:
	_status.text = "设置已保存并应用" if saved else "设置已应用，但配置文件写入失败"
	_status.theme_type_variation = "SuccessLabel" if saved else "DangerLabel"
	_status.modulate = Color.WHITE


func get_scroll_container() -> ScrollContainer:
	return _scroll_container


func get_action_buttons() -> Array[Button]:
	return [_apply_button, _back_button]


func get_layout_snapshot() -> Dictionary:
	return {
		"panel_rect": get_global_rect(),
		"scroll_rect": _scroll_container.get_global_rect() if _scroll_container != null else Rect2(),
		"actions_rect": _actions.get_global_rect() if _actions != null else Rect2(),
		"content_minimum_size": (
			_settings_content.get_combined_minimum_size()
			if _settings_content != null
			else Vector2.ZERO
		),
		"section_card_count": _section_cards.size(),
		"primary_action_variation": (
			_apply_button.theme_type_variation if _apply_button != null else ""
		),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_MD)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("游戏设置"))
	heading.add_child(UiKit.make_title("设置与可访问性"))
	heading.add_child(UiKit.make_subtitle("所有改动会立即应用；自动保存、引导和视距设置会在重启后继续保留。"))
	var profile_badge := UiKit.make_badge("本地配置", "info")
	header.add_child(profile_badge)

	root.add_child(UiKit.make_divider())

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "SettingsScroll"
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.custom_minimum_size.y = 292.0
	root.add_child(_scroll_container)

	_settings_content = VBoxContainer.new()
	_settings_content.name = "SettingsContent"
	_settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_content.add_theme_constant_override("separation", Tokens.SPACE_MD)
	_scroll_container.add_child(_settings_content)

	_build_control_card()
	_build_visual_card()
	_build_world_card()
	_build_guidance_card()

	_status = Label.new()
	_status.name = "SettingsStatus"
	_status.text = "调整完成后点击“保存并应用”"
	_status.theme_type_variation = "CaptionLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 24.0
	root.add_child(_status)

	_actions = HBoxContainer.new()
	_actions.name = "SettingsActions"
	_actions.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(_actions)
	_back_button = UiKit.style_button(
		Button.new(), "GhostButton", Vector2(160, Tokens.CONTROL_HEIGHT_MD)
	)
	_back_button.text = "返回"
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_actions.add_child(_back_button)
	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(action_spacer)
	_apply_button = UiKit.style_button(
		Button.new(), "PrimaryButton", Vector2(250, Tokens.CONTROL_HEIGHT_MD)
	)
	_apply_button.text = "保存并应用"
	_apply_button.pressed.connect(_apply)
	_actions.add_child(_apply_button)


func _build_control_card() -> void:
	var card_root := _make_setting_card(
		"操作与视角",
		"调整鼠标手感。更低的值适合精细建造，更高的值适合快速探索。",
		"01"
	)
	_sensitivity = _add_slider(card_root, "鼠标灵敏度", 0.05, 0.6, 0.01, "%.2f")
	_camera_bob = _make_switch_row(
		card_root,
		"行走视角晃动",
		"移动与冲刺时的轻微镜头起伏；容易晕 3D 的玩家可以关闭。"
	)


func _build_visual_card() -> void:
	var card_root := _make_setting_card(
		"视觉与性能",
		"视距越高，远方地形越完整，但会增加 Chunk 构建和内存压力。",
		"02"
	)
	var distance_row := _make_control_row(card_root, "区块视距", "影响加载范围和设备压力")
	_render_distance = OptionButton.new()
	_render_distance.custom_minimum_size = Vector2(230, Tokens.CONTROL_HEIGHT_MD)
	for value in range(1, 6):
		_render_distance.add_item("%d chunks" % value, value)
	distance_row.add_child(_render_distance)

	_fullscreen = _make_switch_row(
		card_root,
		"全屏显示",
		"以当前显示器分辨率运行，并保留 1024×576 的安全布局。"
	)


func _build_world_card() -> void:
	var card_root := _make_setting_card(
		"声音、时间与存档",
		"世界时间和保存频率独立于画面帧率；暂停时自动保存倒计时不会推进。",
		"03"
	)
	_volume = _add_slider(card_root, "主音量", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_cycle = _add_slider(card_root, "昼夜周期", 2.0, 30.0, 1.0, "%d 分钟")
	var autosave_row := _make_control_row(card_root, "自动保存", "按未暂停的活动时间计算")
	_autosave_interval = OptionButton.new()
	_autosave_interval.custom_minimum_size = Vector2(230, Tokens.CONTROL_HEIGHT_MD)
	for minutes: int in SettingsPolicy.allowed_autosave_minutes():
		_autosave_interval.add_item(
			"关闭" if minutes <= 0 else "每 %d 分钟" % minutes,
			minutes
		)
	autosave_row.add_child(_autosave_interval)


func _build_guidance_card() -> void:
	var card_root := _make_setting_card(
		"引导与可读性",
		"提示会自动避开 HUD、快捷栏和阻塞弹窗，并可随时通过快捷键临时隐藏。",
		"04"
	)
	_show_tutorial = _make_switch_row(
		card_root,
		"显示新手引导（F1 可临时隐藏）",
		"显示当前教学目标、操作提示和完成进度。"
	)
	_show_interaction_prompts = _make_switch_row(
		card_root,
		"显示准星附近的操作提示",
		"面向方块、机器、生物或可交互对象时显示上下文操作。"
	)


func _make_setting_card(title: String, subtitle: String, index: String) -> VBoxContainer:
	var card := UiKit.make_card("CardPanel")
	card.custom_minimum_size.y = 112.0
	_settings_content.add_child(card)
	_section_cards.append(card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	card.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var number := UiKit.make_badge(index, "info")
	header.add_child(number)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = "SectionTitle"
	heading.add_child(title_label)
	var subtitle_label := UiKit.make_subtitle(subtitle)
	heading.add_child(subtitle_label)
	root.add_child(UiKit.make_divider())
	return root


func _make_control_row(parent: Control, title: String, description: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_LG)
	parent.add_child(row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", Tokens.SPACE_2XS)
	row.add_child(identity)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "CaptionLabel"
	identity.add_child(label)
	var hint := Label.new()
	hint.text = description
	hint.theme_type_variation = "SubduedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(hint)
	return row


func _make_switch_row(parent: Control, title: String, description: String) -> CheckButton:
	var row := _make_control_row(parent, title, description)
	var toggle := CheckButton.new()
	toggle.text = "启用"
	toggle.custom_minimum_size = Vector2(126, Tokens.CONTROL_HEIGHT_MD)
	toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(toggle)
	return toggle


func _add_slider(
	parent: Control,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	format: String,
	display_multiplier: float = 1.0
) -> HSlider:
	var row := _make_control_row(parent, title, "拖动滑杆，数值会实时预览")
	var control := VBoxContainer.new()
	control.custom_minimum_size.x = 300.0
	control.add_theme_constant_override("separation", Tokens.SPACE_XS)
	row.add_child(control)
	var value_label := Label.new()
	value_label.theme_type_variation = "MetricLabel"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	control.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(300.0, 24.0)
	control.add_child(slider)
	_value_labels[slider.get_instance_id()] = {
		"label": value_label,
		"format": format,
		"multiplier": display_multiplier,
	}
	slider.value_changed.connect(
		func(value: float) -> void: _update_slider_label(slider, value)
	)
	_update_slider_label(slider, minimum)
	return slider


func _update_slider_label(slider: HSlider, value: float) -> void:
	var raw_data: Variant = _value_labels.get(slider.get_instance_id(), {})
	if raw_data is not Dictionary:
		return
	var data: Dictionary = raw_data
	var label := data.get("label") as Label
	if label == null:
		return
	var display_value := value * float(data.get("multiplier", 1.0))
	var format := str(data.get("format", "%.2f"))
	label.text = format % (roundi(display_value) if format.contains("%d") else display_value)


func _load_values() -> void:
	var defaults := SettingsPolicy.defaults()
	var loaded: Dictionary = (
		save_service.load_settings(defaults)
		if save_service != null
		else defaults.duplicate(true)
	)
	var settings := SettingsPolicy.normalize(loaded)
	_sensitivity.value = float(settings.get("mouse_sensitivity", defaults.mouse_sensitivity))
	_select_option_by_id(
		_render_distance,
		int(settings.get("render_distance", defaults.render_distance))
	)
	_volume.value = float(settings.get("master_volume", defaults.master_volume))
	_fullscreen.button_pressed = bool(settings.get("fullscreen", defaults.fullscreen))
	_cycle.value = float(settings.get("cycle_minutes", defaults.cycle_minutes))
	_select_option_by_id(
		_autosave_interval,
		int(settings.get("autosave_minutes", defaults.autosave_minutes))
	)
	_show_tutorial.button_pressed = bool(
		settings.get("show_tutorial", defaults.show_tutorial)
	)
	_show_interaction_prompts.button_pressed = bool(
		settings.get("show_interaction_prompts", defaults.show_interaction_prompts)
	)
	_camera_bob.button_pressed = bool(settings.get("camera_bob", true))


func _select_option_by_id(option: OptionButton, target_id: int) -> void:
	for index in option.item_count:
		if option.get_item_id(index) == target_id:
			option.select(index)
			return


func _apply() -> void:
	var settings := SettingsPolicy.normalize({
		"mouse_sensitivity": _sensitivity.value,
		"render_distance": _render_distance.get_selected_id(),
		"master_volume": _volume.value,
		"fullscreen": _fullscreen.button_pressed,
		"cycle_minutes": int(_cycle.value),
		"autosave_minutes": _autosave_interval.get_selected_id(),
		"show_tutorial": _show_tutorial.button_pressed,
		"show_interaction_prompts": _show_interaction_prompts.button_pressed,
		"camera_bob": _camera_bob.button_pressed,
	})
	_status.text = "正在保存并应用设置…"
	_status.theme_type_variation = "CaptionLabel"
	_status.modulate = Color.WHITE
	settings_applied.emit(settings)
