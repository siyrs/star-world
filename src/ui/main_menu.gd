class_name MainMenu
extends Control

signal new_world_requested(world_state: Dictionary)
signal continue_world_requested(world_state: Dictionary)
signal settings_changed(settings: Dictionary)
signal quit_requested

const SaveServiceScript = preload("res://src/save/save_service.gd")
const MapPanelScript = preload("res://src/ui/map_selection_panel.gd")
const SaveBrowserScript = preload("res://src/ui/save_browser_panel.gd")
const SettingsPanelScript = preload("res://src/ui/settings_panel.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")

var save_service
var audio_service
var _main_panel: PanelContainer
var _map_panel
var _save_panel
var _settings_panel
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_background()
	_build_main_panel()
	_build_subpanels()
	if save_service == null:
		save_service = SaveServiceScript.new()
		save_service.name = "LocalSaveService"
		add_child(save_service)
	_setup_panels()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func setup(p_save_service, p_audio_service = null) -> void:
	save_service = p_save_service
	audio_service = p_audio_service
	if is_node_ready():
		_setup_panels()


func show_main() -> void:
	visible = true
	_main_panel.visible = true
	_map_panel.visible = false
	_save_panel.visible = false
	_settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_background() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#07111F")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var stars := Label.new()
	stars.text = "✦     ·       ✧          ·    ✦       ·        ✧\n\n       ·        ✦     ·          ✧          ·\n\n  ✧         ·           ✦       ·      ✧"
	stars.add_theme_font_size_override("font_size", 34)
	stars.modulate = Color("#4F7899")
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stars)


func _build_main_panel() -> void:
	_main_panel = PanelContainer.new()
	_main_panel.anchor_left = 0.5
	_main_panel.anchor_right = 0.5
	_main_panel.anchor_top = 0.5
	_main_panel.anchor_bottom = 0.5
	_main_panel.offset_left = -280
	_main_panel.offset_right = 280
	_main_panel.offset_top = -330
	_main_panel.offset_bottom = 330
	add_child(_main_panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 13)
	_main_panel.add_child(content)
	var title := Label.new()
	title.text = "星 的 世 界"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "STAR WORLD  ·  沙盒生存建造"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color("#8FD7F0")
	content.add_child(subtitle)
	_add_menu_button(content, "开始游戏", func(): _show_panel(_map_panel))
	_add_menu_button(content, "地图选择", func(): _show_panel(_map_panel))
	_add_menu_button(content, "存档 / 继续", func(): _save_panel.refresh(); _show_panel(_save_panel))
	_add_menu_button(content, "设置", func(): _show_panel(_settings_panel))
	_add_menu_button(content, "退出", _quit)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	var version := Label.new()
	version.text = "v1.0.0  ·  Godot 4"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.modulate = Color("#7892A7")
	content.add_child(version)


func _add_menu_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(470, 58)
	button.pressed.connect(callback)
	if audio_service != null:
		button.pressed.connect(audio_service.play_ui)
	parent.add_child(button)


func _build_subpanels() -> void:
	_map_panel = MapPanelScript.new()
	_center_panel(_map_panel, Vector2(860, 610))
	add_child(_map_panel)
	_map_panel.visible = false
	_map_panel.create_requested.connect(_on_create_requested)
	_map_panel.back_requested.connect(show_main)
	_save_panel = SaveBrowserScript.new()
	_center_panel(_save_panel, Vector2(820, 590))
	add_child(_save_panel)
	_save_panel.visible = false
	_save_panel.load_requested.connect(_on_load_requested)
	_save_panel.back_requested.connect(show_main)
	_settings_panel = SettingsPanelScript.new()
	_center_panel(_settings_panel, Vector2(650, 520))
	add_child(_settings_panel)
	_settings_panel.visible = false
	_settings_panel.settings_applied.connect(func(settings): settings_changed.emit(settings))
	_settings_panel.back_requested.connect(show_main)


func _center_panel(panel: Control, panel_size: Vector2) -> void:
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_bottom = panel_size.y * 0.5


func _setup_panels() -> void:
	if _save_panel != null:
		_save_panel.setup(save_service)
	if _settings_panel != null:
		_settings_panel.setup(save_service, audio_service)


func _show_panel(panel: Control) -> void:
	_main_panel.visible = false
	_map_panel.visible = panel == _map_panel
	_save_panel.visible = panel == _save_panel
	_settings_panel.visible = panel == _settings_panel


func _on_create_requested(world_name: String, map_id: String, seed_value: int) -> void:
	var profile: Dictionary = _map_panel.get_profile(map_id)
	var state: Dictionary = save_service.create_world(world_name, map_id, seed_value, {"map_profile":profile})
	if state.is_empty():
		_status.text = "创建世界失败，请检查写入权限。"
		show_main()
		return
	visible = false
	new_world_requested.emit(state)


func _on_load_requested(world_id: String) -> void:
	var state: Dictionary = save_service.load_world(world_id)
	if state.is_empty():
		_status.text = "无法读取该存档。"
		show_main()
		return
	visible = false
	continue_world_requested.emit(state)


func _quit() -> void:
	quit_requested.emit()
	get_tree().quit()
