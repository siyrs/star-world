class_name HardenedSettingsPanel
extends "res://src/ui/settings_panel.gd"

var _survival_difficulty: OptionButton
var _ui_scale: OptionButton


func _build_visual_card() -> void:
	var card_root := _make_setting_card(
		"视觉、性能与界面",
		"视距影响设备压力；界面缩放只改变本地 UI，不修改世界或存档内容。",
		"02"
	)
	var distance_row := _make_control_row(card_root, "区块视距", "影响加载范围和设备压力")
	_render_distance = OptionButton.new()
	_render_distance.custom_minimum_size = Vector2(230, Tokens.CONTROL_HEIGHT_MD)
	for value in range(1, 6):
		_render_distance.add_item("%d chunks" % value, value)
	distance_row.add_child(_render_distance)

	var scale_row := _make_control_row(
		card_root,
		"界面缩放",
		"80% 适合小屏，125% 与 150% 适合高 DPI 显示器和远距离阅读。"
	)
	_ui_scale = OptionButton.new()
	_ui_scale.name = "UiScale"
	_ui_scale.custom_minimum_size = Vector2(230, Tokens.CONTROL_HEIGHT_MD)
	for scale: float in SettingsPolicy.allowed_ui_scales():
		_ui_scale.add_item(SettingsPolicy.ui_scale_label(scale))
		_ui_scale.set_item_metadata(_ui_scale.item_count - 1, scale)
	scale_row.add_child(_ui_scale)

	_fullscreen = _make_switch_row(
		card_root,
		"全屏显示",
		"以当前显示器分辨率运行，并保留紧凑与高 DPI 的安全布局。"
	)


func _build_world_card() -> void:
	var card_root := _make_setting_card(
		"声音、时间、生存与存档",
		"世界时间、难度和保存频率独立于画面帧率；难度可随时调整且不会改写世界数据。",
		"03"
	)
	_volume = _add_slider(card_root, "主音量", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_cycle = _add_slider(card_root, "昼夜周期", 2.0, 30.0, 1.0, "%d 分钟")
	var difficulty_row := _make_control_row(
		card_root,
		"生存难度",
		"轻松建造保留原有节奏；平衡生存启用更强的农业与食物循环。"
	)
	_survival_difficulty = OptionButton.new()
	_survival_difficulty.name = "SurvivalDifficulty"
	_survival_difficulty.custom_minimum_size = Vector2(230, Tokens.CONTROL_HEIGHT_MD)
	for profile_id: String in SettingsPolicy.allowed_survival_difficulties():
		_survival_difficulty.add_item(SettingsPolicy.survival_difficulty_label(profile_id))
		_survival_difficulty.set_item_metadata(
			_survival_difficulty.item_count - 1, profile_id
		)
	difficulty_row.add_child(_survival_difficulty)
	var autosave_row := _make_control_row(card_root, "自动保存", "按未暂停的活动时间计算")
	_autosave_interval = OptionButton.new()
	_autosave_interval.custom_minimum_size = Vector2(230, Tokens.CONTROL_HEIGHT_MD)
	for minutes: int in SettingsPolicy.allowed_autosave_minutes():
		_autosave_interval.add_item(
			"关闭" if minutes <= 0 else "每 %d 分钟" % minutes,
			minutes
		)
	autosave_row.add_child(_autosave_interval)


func _load_values() -> void:
	super._load_values()
	var defaults := SettingsPolicy.defaults()
	var loaded: Dictionary = (
		save_service.load_settings(defaults)
		if save_service != null
		else defaults.duplicate(true)
	)
	var settings := SettingsPolicy.normalize(loaded)
	_select_difficulty_by_id(
		str(settings.get("survival_difficulty", defaults.survival_difficulty))
	)
	_select_scale(float(settings.get("ui_scale", defaults.ui_scale)))


func get_survival_difficulty_control() -> OptionButton:
	return _survival_difficulty


func get_ui_scale_control() -> OptionButton:
	return _ui_scale


func _select_difficulty_by_id(profile_id: String) -> void:
	if _survival_difficulty == null:
		return
	for index in _survival_difficulty.item_count:
		if str(_survival_difficulty.get_item_metadata(index)) == profile_id:
			_survival_difficulty.select(index)
			return


func _select_scale(scale: float) -> void:
	if _ui_scale == null:
		return
	var normalized := SettingsPolicy.normalize_ui_scale(scale)
	for index in _ui_scale.item_count:
		if is_equal_approx(float(_ui_scale.get_item_metadata(index)), normalized):
			_ui_scale.select(index)
			return


func _selected_difficulty_id() -> String:
	if _survival_difficulty == null or _survival_difficulty.selected < 0:
		return str(SettingsPolicy.DEFAULTS.survival_difficulty)
	return str(_survival_difficulty.get_item_metadata(_survival_difficulty.selected))


func _selected_ui_scale() -> float:
	if _ui_scale == null or _ui_scale.selected < 0:
		return float(SettingsPolicy.DEFAULTS.ui_scale)
	return SettingsPolicy.normalize_ui_scale(
		_ui_scale.get_item_metadata(_ui_scale.selected)
	)


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
		"survival_difficulty": _selected_difficulty_id(),
		"ui_scale": _selected_ui_scale(),
	})
	_status.text = "正在保存并应用设置…"
	_status.theme_type_variation = "CaptionLabel"
	_status.modulate = Color.WHITE
	settings_applied.emit(settings)
