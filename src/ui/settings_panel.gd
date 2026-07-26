class_name SettingsPanel
extends PanelContainer

signal settings_applied(settings: Dictionary)
signal back_requested

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
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
var _scroll_container: ScrollContainer
var _settings_content: VBoxContainer
var _status: Label
var _actions: HBoxContainer
var _apply_button: Button
var _back_button: Button


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(680, 520)
	_build_ui()


func setup(p_save_service, _p_audio_service = null) -> void:
	save_service = p_save_service
	_load_values()


func show_apply_result(saved: bool) -> void:
	_status.text = "已保存并应用" if saved else "已应用，但设置文件保存失败"
	_status.modulate = Tokens.severity_color("success" if saved else "warning")


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
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_XS)
	add_child(root)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", Tokens.FONT_TITLE)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "按自己的设备和习惯调整星世界"
	subtitle.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	subtitle.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(subtitle)

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "SettingsScroll"
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.custom_minimum_size.y = 300.0
	root.add_child(_scroll_container)
	_settings_content = VBoxContainer.new()
	_settings_content.name = "SettingsContent"
	_settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_content.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_scroll_container.add_child(_settings_content)

	_add_section_title(_settings_content, "操作")
	_sensitivity = _add_slider(_settings_content, "鼠标灵敏度", 0.05, 0.6, 0.01)
	_add_section_title(_settings_content, "视觉与性能")
	var distance_row := HBoxContainer.new()
	_settings_content.add_child(distance_row)
	var distance_label := Label.new()
	distance_label.text = "区块视距"
	distance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	distance_row.add_child(distance_label)
	_render_distance = OptionButton.new()
	_render_distance.custom_minimum_size.x = 220.0
	for value in range(1, 6):
		_render_distance.add_item("%d chunks" % value, value)
	distance_row.add_child(_render_distance)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "全屏显示"
	_settings_content.add_child(_fullscreen)
	_add_section_title(_settings_content, "声音与世界")
	_volume = _add_slider(_settings_content, "主音量", 0.0, 1.0, 0.01)
	_cycle = _add_slider(_settings_content, "昼夜周期（分钟）", 2.0, 30.0, 1.0)
	var autosave_row := HBoxContainer.new()
	_settings_content.add_child(autosave_row)
	var autosave_label := Label.new()
	autosave_label.text = "自动保存"
	autosave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autosave_row.add_child(autosave_label)
	_autosave_interval = OptionButton.new()
	_autosave_interval.custom_minimum_size.x = 220.0
	for minutes: int in SettingsPolicy.allowed_autosave_minutes():
		_autosave_interval.add_item(
			"关闭" if minutes <= 0 else "每 %d 分钟" % minutes,
			minutes
		)
	autosave_row.add_child(_autosave_interval)
	_add_section_title(_settings_content, "引导与可读性")
	_show_tutorial = CheckButton.new()
	_show_tutorial.text = "显示新手引导（F1 可临时隐藏）"
	_settings_content.add_child(_show_tutorial)
	_show_interaction_prompts = CheckButton.new()
	_show_interaction_prompts.text = "显示准星附近的操作提示"
	_settings_content.add_child(_show_interaction_prompts)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 24.0
	_status.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(_status)
	_actions = HBoxContainer.new()
	_actions.name = "SettingsActions"
	_actions.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(_actions)
	_apply_button = Button.new()
	_apply_button.text = "保存并应用"
	_apply_button.custom_minimum_size.y = 44.0
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button.pressed.connect(_apply)
	_actions.add_child(_apply_button)
	_back_button = Button.new()
	_back_button.text = "返回"
	_back_button.custom_minimum_size = Vector2(160, 44)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_actions.add_child(_back_button)


func _add_section_title(parent: Control, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	label.modulate = Tokens.color(Tokens.COLOR_ACCENT)
	parent.add_child(label)


func _add_slider(
	parent: Control, title: String, minimum: float, maximum: float, step: float
) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 220.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 360.0
	row.add_child(slider)
	return slider


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
	})
	_status.text = "正在应用…"
	_status.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	settings_applied.emit(settings)
