class_name SettingsPanel
extends PanelContainer

signal settings_applied(settings: Dictionary)
signal back_requested

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const DEFAULTS := {
	"mouse_sensitivity": 0.18,
	"render_distance": 3,
	"master_volume": 0.8,
	"fullscreen": false,
	"cycle_minutes": 10,
	"show_tutorial": true,
	"show_interaction_prompts": true,
}

var save_service
var _sensitivity: HSlider
var _render_distance: OptionButton
var _volume: HSlider
var _fullscreen: CheckButton
var _cycle: HSlider
var _show_tutorial: CheckButton
var _show_interaction_prompts: CheckButton
var _status: Label


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(680, 620)
	_build_ui()


func setup(p_save_service, _p_audio_service = null) -> void:
	save_service = p_save_service
	_load_values()


func show_apply_result(saved: bool) -> void:
	_status.text = "已保存并应用" if saved else "已应用，但设置文件保存失败"
	_status.modulate = Tokens.severity_color("success" if saved else "warning")


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", Tokens.FONT_TITLE)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "按自己的设备和习惯调整星世界"
	subtitle.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	root.add_child(subtitle)
	_add_section_title(root, "操作")
	_sensitivity = _add_slider(root, "鼠标灵敏度", 0.05, 0.6, 0.01)
	_add_section_title(root, "视觉与性能")
	var distance_row := HBoxContainer.new()
	root.add_child(distance_row)
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
	root.add_child(_fullscreen)
	_add_section_title(root, "声音与世界")
	_volume = _add_slider(root, "主音量", 0.0, 1.0, 0.01)
	_cycle = _add_slider(root, "昼夜周期（分钟）", 2.0, 30.0, 1.0)
	_add_section_title(root, "引导与可读性")
	_show_tutorial = CheckButton.new()
	_show_tutorial.text = "显示新手引导（游戏中按 F1 可临时隐藏）"
	root.add_child(_show_tutorial)
	_show_interaction_prompts = CheckButton.new()
	_show_interaction_prompts.text = "显示准星附近的操作提示"
	root.add_child(_show_interaction_prompts)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 28.0
	root.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(actions)
	var apply_button := Button.new()
	apply_button.text = "保存并应用"
	apply_button.custom_minimum_size.y = 48.0
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(_apply)
	actions.add_child(apply_button)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(160, 48)
	back.pressed.connect(func() -> void: back_requested.emit())
	actions.add_child(back)


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
	var settings: Dictionary = (
		save_service.load_settings(DEFAULTS) if save_service != null else DEFAULTS.duplicate(true)
	)
	_sensitivity.value = float(settings.get("mouse_sensitivity", DEFAULTS.mouse_sensitivity))
	var distance := int(settings.get("render_distance", DEFAULTS.render_distance))
	for index in _render_distance.item_count:
		if _render_distance.get_item_id(index) == distance:
			_render_distance.select(index)
	_volume.value = float(settings.get("master_volume", DEFAULTS.master_volume))
	_fullscreen.button_pressed = bool(settings.get("fullscreen", DEFAULTS.fullscreen))
	_cycle.value = float(settings.get("cycle_minutes", DEFAULTS.cycle_minutes))
	_show_tutorial.button_pressed = bool(settings.get("show_tutorial", DEFAULTS.show_tutorial))
	_show_interaction_prompts.button_pressed = bool(
		settings.get("show_interaction_prompts", DEFAULTS.show_interaction_prompts)
	)


func _apply() -> void:
	var settings := {
		"mouse_sensitivity": _sensitivity.value,
		"render_distance": _render_distance.get_selected_id(),
		"master_volume": _volume.value,
		"fullscreen": _fullscreen.button_pressed,
		"cycle_minutes": int(_cycle.value),
		"show_tutorial": _show_tutorial.button_pressed,
		"show_interaction_prompts": _show_interaction_prompts.button_pressed,
	}
	_status.text = "正在应用…"
	_status.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	settings_applied.emit(settings)
