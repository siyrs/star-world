class_name HardenedSettingsPanel
extends "res://src/ui/settings_panel.gd"

var _survival_difficulty: OptionButton


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


func get_survival_difficulty_control() -> OptionButton:
	return _survival_difficulty


func _select_difficulty_by_id(profile_id: String) -> void:
	if _survival_difficulty == null:
		return
	for index in _survival_difficulty.item_count:
		if str(_survival_difficulty.get_item_metadata(index)) == profile_id:
			_survival_difficulty.select(index)
			return


func _selected_difficulty_id() -> String:
	if _survival_difficulty == null or _survival_difficulty.selected < 0:
		return str(SettingsPolicy.DEFAULTS.survival_difficulty)
	return str(_survival_difficulty.get_item_metadata(_survival_difficulty.selected))


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
	})
	_status.text = "正在保存并应用设置…"
	_status.theme_type_variation = "CaptionLabel"
	_status.modulate = Color.WHITE
	settings_applied.emit(settings)
