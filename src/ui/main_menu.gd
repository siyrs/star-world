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
const UpdatePromptPanelScript = preload("res://src/ui/update_prompt_panel.gd")
const StarfieldScript = preload("res://src/ui/menu_starfield.gd")
const AppVersion = preload("res://src/update/app_version.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var save_service
var audio_service
var update_service
var _main_panel: PanelContainer
var _map_panel
var _save_panel
var _settings_panel
var _update_panel
var _loading_panel: PanelContainer
var _loading_label: Label
var _status: Label
var _local_save_service: Node
var _menu_buttons: Array[Button] = []
var _loading := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_background()
	_build_main_panel()
	_build_subpanels()
	_build_loading_panel()
	_setup_panels()
	call_deferred("_ensure_standalone_services")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func setup(p_save_service, p_audio_service = null, p_update_service = null) -> void:
	_disconnect_standalone_settings()
	if _local_save_service != null and _local_save_service != p_save_service:
		_local_save_service.queue_free()
		_local_save_service = null
	save_service = p_save_service
	audio_service = p_audio_service
	update_service = p_update_service
	if is_node_ready():
		_setup_panels()
		_bind_menu_audio()
		_setup_update_service()


func show_main() -> void:
	_loading = false
	visible = true
	_loading_panel.visible = false
	_main_panel.visible = true
	_map_panel.visible = false
	_save_panel.visible = false
	_settings_panel.visible = false
	if _update_panel != null:
		_update_panel.visible = false
	_set_menu_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_loading(message: String = "正在生成世界…") -> void:
	_loading = true
	visible = true
	_main_panel.visible = false
	_map_panel.visible = false
	_save_panel.visible = false
	_settings_panel.visible = false
	if _update_panel != null:
		_update_panel.visible = false
	_loading_panel.visible = true
	_loading_label.text = message
	_set_menu_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_error(message: String) -> void:
	_status.text = message


func show_settings_result(saved: bool) -> void:
	if _settings_panel != null and _settings_panel.has_method("show_apply_result"):
		_settings_panel.call("show_apply_result", saved)


func get_update_panel() -> Node:
	return _update_panel


func _ensure_standalone_services() -> void:
	if save_service != null:
		return
	_local_save_service = SaveServiceScript.new()
	_local_save_service.name = "LocalSaveService"
	add_child(_local_save_service)
	save_service = _local_save_service
	_setup_panels()
	var callback := Callable(self, "_apply_standalone_settings")
	if not settings_changed.is_connected(callback):
		settings_changed.connect(callback)


func _disconnect_standalone_settings() -> void:
	var callback := Callable(self, "_apply_standalone_settings")
	if settings_changed.is_connected(callback):
		settings_changed.disconnect(callback)


func _apply_standalone_settings(settings: Dictionary) -> void:
	var saved := save_service != null and bool(save_service.save_settings(settings))
	if audio_service != null and audio_service.has_method("set_master_volume"):
		audio_service.call("set_master_volume", float(settings.get("master_volume", 0.8)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			(
				DisplayServer.WINDOW_MODE_FULLSCREEN
				if bool(settings.get("fullscreen", false))
				else DisplayServer.WINDOW_MODE_WINDOWED
			)
		)
	show_settings_result(saved)


func _build_background() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#0A1626")
	UiInputPolicy.make_passthrough(background)
	add_child(background)
	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.texture = _build_horizon_glow()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	UiInputPolicy.make_passthrough(glow)
	add_child(glow)
	var starfield := StarfieldScript.new()
	starfield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiInputPolicy.make_passthrough(starfield)
	add_child(starfield)


func _build_horizon_glow() -> ImageTexture:
	# Soft vertical gradient: deep space up top, warm horizon glow at the bottom.
	var image := Image.create(1, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		var t := float(y) / 255.0
		var color := Color("#0A1626").lerp(Color("#16324F"), t)
		if t > 0.72:
			color = color.lerp(Color("#3A4E68"), (t - 0.72) / 0.28 * 0.55)
		image.set_pixel(0, y, color)
	return ImageTexture.create_from_image(image)


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
	content.add_theme_constant_override("separation", 10)
	_main_panel.add_child(content)
	var title := Label.new()
	title.text = "星 的 世 界"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 62)
	title.add_theme_color_override("font_color", Color("#EAF7FF"))
	title.add_theme_color_override("font_shadow_color", Color("#1A5E96"))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.add_theme_constant_override("shadow_outline_size", 10)
	content.add_child(title)
	var divider := Label.new()
	divider.text = "✦  ━━━━━━  STAR WORLD  ·  沙盒生存建造  ━━━━━━  ✦"
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider.modulate = Color("#8FD7F0")
	divider.add_theme_font_size_override("font_size", 15)
	content.add_child(divider)
	_add_menu_button(content, "开始游戏", func() -> void: _show_panel(_map_panel))
	_add_menu_button(content, "地图选择", func() -> void: _show_panel(_map_panel))
	_add_menu_button(
		content,
		"存档 / 继续",
		func() -> void:
			_save_panel.refresh()
			_show_panel(_save_panel)
	)
	_add_menu_button(content, "设置", func() -> void: _show_panel(_settings_panel))
	_add_menu_button(content, "检查更新", _request_update_check)
	_add_menu_button(content, "退出", _quit)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	var version := Label.new()
	version.text = "%s  ·  Godot 4" % AppVersion.display_version()
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.modulate = Color("#7892A7")
	content.add_child(version)


func _add_menu_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(470, 52)
	button.pressed.connect(callback)
	button.mouse_entered.connect(
		func() -> void:
			var tween := button.create_tween()
			tween.tween_property(button, "scale", Vector2(1.02, 1.02), 0.1)
	)
	button.mouse_exited.connect(
		func() -> void:
			var tween := button.create_tween()
			tween.tween_property(button, "scale", Vector2.ONE, 0.12)
	)
	button.pivot_offset = button.custom_minimum_size * 0.5
	parent.add_child(button)
	_menu_buttons.append(button)
	_connect_button_audio(button)


func _bind_menu_audio() -> void:
	for button in _menu_buttons:
		_connect_button_audio(button)


func _connect_button_audio(button: Button) -> void:
	if audio_service == null or not audio_service.has_method("play_ui"):
		return
	var callback := Callable(audio_service, "play_ui")
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


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
	_center_panel(_settings_panel, Vector2(700, 560))
	add_child(_settings_panel)
	_settings_panel.visible = false
	_settings_panel.settings_applied.connect(
		func(settings: Dictionary) -> void: settings_changed.emit(settings)
	)
	_settings_panel.back_requested.connect(show_main)
	_update_panel = UpdatePromptPanelScript.new()
	_center_panel(_update_panel, Vector2(680, 500))
	add_child(_update_panel)
	_update_panel.visible = false
	_update_panel.dismissed.connect(show_main)


func _build_loading_panel() -> void:
	_loading_panel = PanelContainer.new()
	_center_panel(_loading_panel, Vector2(520, 220))
	add_child(_loading_panel)
	_loading_panel.visible = false
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	_loading_panel.add_child(content)
	var title := Label.new()
	title.text = "星的世界"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)
	_loading_label = Label.new()
	_loading_label.text = "正在生成世界…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_loading_label)


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
	_setup_update_service()


func _setup_update_service() -> void:
	if _update_panel == null or update_service == null:
		return
	_update_panel.setup(update_service)
	var available_callback := Callable(self, "_on_update_available")
	if update_service.has_signal("update_available") and not update_service.is_connected("update_available", available_callback):
		update_service.connect("update_available", available_callback)
	var no_update_callback := Callable(self, "_on_no_update_available")
	if update_service.has_signal("no_update_available") and not update_service.is_connected("no_update_available", no_update_callback):
		update_service.connect("no_update_available", no_update_callback)
	var failed_callback := Callable(self, "_on_update_check_failed")
	if update_service.has_signal("update_failed") and not update_service.is_connected("update_failed", failed_callback):
		update_service.connect("update_failed", failed_callback)
	var notice := str(update_service.call("get_startup_notice")) if update_service.has_method("get_startup_notice") else ""
	if not notice.is_empty():
		_status.text = notice
	if update_service.has_method("check_on_startup"):
		update_service.call_deferred("check_on_startup")


func _show_panel(panel: Control) -> void:
	if _loading:
		return
	_loading_panel.visible = false
	_main_panel.visible = false
	_map_panel.visible = panel == _map_panel
	_save_panel.visible = panel == _save_panel
	_settings_panel.visible = panel == _settings_panel
	if _update_panel != null:
		_update_panel.visible = panel == _update_panel


func _set_menu_enabled(enabled: bool) -> void:
	for button in _menu_buttons:
		button.disabled = not enabled


func _request_update_check() -> void:
	if update_service == null or not update_service.has_method("check_for_updates"):
		_status.text = "更新服务当前不可用。"
		return
	_status.text = "正在检查 GitHub Release…"
	update_service.call("check_for_updates", true)


func _on_update_available(_release: Dictionary) -> void:
	_show_panel(_update_panel)


func _on_no_update_available(version: String) -> void:
	_status.text = "当前 v%s 已是最新版本。" % version


func _on_update_check_failed(_reason: String, message: String) -> void:
	if _update_panel == null or not _update_panel.visible:
		_status.text = message


func _on_create_requested(world_name: String, map_id: String, seed_value: int) -> void:
	var profile: Dictionary = _map_panel.get_profile(map_id)
	var state: Dictionary = save_service.create_world(
		world_name, map_id, seed_value, {"map_profile": profile}
	)
	if state.is_empty():
		show_main()
		_status.text = "创建世界失败，请检查写入权限。"
		return
	show_loading("正在生成 %s…" % str(profile.get("name", "世界")))
	new_world_requested.emit(state)


func _on_load_requested(world_id: String) -> void:
	var state: Dictionary = save_service.load_world(world_id)
	if state.is_empty():
		show_main()
		_status.text = "无法读取该存档。"
		return
	show_loading("正在读取世界…")
	continue_world_requested.emit(state)


func _quit() -> void:
	quit_requested.emit()
	get_tree().quit()
