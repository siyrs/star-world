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
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
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
var _version_label: Label
var _hero_title: Label
var _hero_summary: Label
var _hero_column: VBoxContainer
var _command_panel: PanelContainer
var _main_layout: HBoxContainer
var _menu_margin: MarginContainer
var _local_save_service: Node
var _menu_buttons: Array[Button] = []
var _loading := false
var _panel_sizes: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_background()
	_build_main_panel()
	_build_subpanels()
	_build_loading_panel()
	_setup_panels()
	resized.connect(_apply_responsive_layout)
	call_deferred("_ensure_standalone_services")
	call_deferred("_apply_responsive_layout")
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
	_apply_responsive_layout()
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
	_apply_responsive_layout()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_error(message: String) -> void:
	_status.text = message
	_status.theme_type_variation = "DangerLabel"


func show_settings_result(saved: bool) -> void:
	if _settings_panel != null and _settings_panel.has_method("show_apply_result"):
		_settings_panel.call("show_apply_result", saved)


func get_update_panel() -> Node:
	return _update_panel


func get_visual_snapshot() -> Dictionary:
	var button_variations: Array[String] = []
	for button: Button in _menu_buttons:
		button_variations.append(button.theme_type_variation)
	return {
		"main_panel": _main_panel.get_global_rect() if _main_panel != null else Rect2(),
		"hero": _hero_column.get_global_rect() if _hero_column != null else Rect2(),
		"command_panel": _command_panel.get_global_rect() if _command_panel != null else Rect2(),
		"main_layout": _main_layout.get_global_rect() if _main_layout != null else Rect2(),
		"button_count": _menu_buttons.size(),
		"button_variations": button_variations,
		"title_font_size": (
			_hero_title.get_theme_font_size("font_size") if _hero_title != null else 0
		),
		"loading": _loading,
	}


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
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if bool(settings.get("fullscreen", false))
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	show_settings_result(saved)


func _build_background() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Tokens.color(Tokens.COLOR_BACKGROUND_DEEP)
	UiInputPolicy.make_passthrough(background)
	add_child(background)

	var gradient := TextureRect.new()
	gradient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gradient.texture = _build_horizon_glow()
	gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient.stretch_mode = TextureRect.STRETCH_SCALE
	UiInputPolicy.make_passthrough(gradient)
	add_child(gradient)

	var starfield := StarfieldScript.new()
	starfield.name = "CelestialBackdrop"
	starfield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiInputPolicy.make_passthrough(starfield)
	add_child(starfield)

	var vignette := TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.texture = _build_vignette()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	UiInputPolicy.make_passthrough(vignette)
	add_child(vignette)


func _build_horizon_glow() -> ImageTexture:
	var image := Image.create(2, 320, false, Image.FORMAT_RGBA8)
	for y in 320:
		var t := float(y) / 319.0
		var base := Tokens.color(Tokens.COLOR_BACKGROUND_DEEP).lerp(
			Tokens.color(Tokens.COLOR_BACKGROUND_ALT), t
		)
		var cyan_glow := exp(-pow((t - 0.68) / 0.22, 2.0))
		var warm_glow := exp(-pow((t - 0.94) / 0.12, 2.0))
		base = base.lerp(Color("#123F59"), cyan_glow * 0.42)
		base = base.lerp(Color("#5B4A2E"), warm_glow * 0.20)
		for x in 2:
			image.set_pixel(x, y, base)
	return ImageTexture.create_from_image(image)


func _build_vignette() -> ImageTexture:
	var image := Image.create(128, 72, false, Image.FORMAT_RGBA8)
	for y in 72:
		for x in 128:
			var uv := Vector2(float(x) / 127.0, float(y) / 71.0)
			var edge := maxf(absf(uv.x - 0.5) * 1.55, absf(uv.y - 0.5) * 1.25)
			var alpha := smoothstep(0.42, 0.83, edge) * 0.62
			image.set_pixel(x, y, Color(0.0, 0.015, 0.03, alpha))
	return ImageTexture.create_from_image(image)


func _build_main_panel() -> void:
	_main_panel = PanelContainer.new()
	_main_panel.name = "MainCommandSurface"
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.theme_type_variation = "MenuCanvas"
	add_child(_main_panel)

	_menu_margin = MarginContainer.new()
	_menu_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.add_child(_menu_margin)

	_main_layout = HBoxContainer.new()
	_main_layout.name = "MainMenuLayout"
	_main_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_layout.add_theme_constant_override("separation", Tokens.SPACE_3XL)
	_menu_margin.add_child(_main_layout)

	_build_hero_column()
	_build_command_panel()


func _build_hero_column() -> void:
	_hero_column = VBoxContainer.new()
	_hero_column.name = "HeroColumn"
	_hero_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_column.add_theme_constant_override("separation", Tokens.SPACE_MD)
	_main_layout.add_child(_hero_column)

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_column.add_child(top_spacer)

	_hero_column.add_child(UiKit.make_eyebrow("SINGLE PLAYER · VOXEL SURVIVAL · BUILD & EXPLORE"))
	_hero_title = UiKit.make_title("星 的 世 界", true)
	_hero_title.add_theme_color_override("font_color", Tokens.color(Tokens.COLOR_TEXT))
	_hero_title.add_theme_color_override("font_shadow_color", Color("#0A7CA8AA"))
	_hero_title.add_theme_constant_override("shadow_offset_x", 0)
	_hero_title.add_theme_constant_override("shadow_offset_y", 5)
	_hero_title.add_theme_constant_override("shadow_outline_size", 12)
	_hero_column.add_child(_hero_title)

	var tagline := Label.new()
	tagline.text = "在星光照亮的方块世界里，建立基地、经营生产、穿越五种生态，并把每一次远征保存成自己的故事。"
	tagline.theme_type_variation = "MutedLabel"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(430, 64)
	tagline.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hero_column.add_child(tagline)

	var feature_row := HBoxContainer.new()
	feature_row.name = "FeatureBadges"
	feature_row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_hero_column.add_child(feature_row)
	feature_row.add_child(UiKit.make_badge("5 张世界地图", "info"))
	feature_row.add_child(UiKit.make_badge("自动保存与恢复", "success"))
	feature_row.add_child(UiKit.make_badge("离线单人世界", "warm"))

	var manifesto := UiKit.make_card("GlassPanel", Vector2(500, 100))
	manifesto.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hero_column.add_child(manifesto)
	var manifesto_content := VBoxContainer.new()
	manifesto_content.add_theme_constant_override("separation", Tokens.SPACE_XS)
	manifesto.add_child(manifesto_content)
	var manifesto_title := Label.new()
	manifesto_title.text = "远征状态"
	manifesto_title.theme_type_variation = "SectionTitle"
	manifesto_content.add_child(manifesto_title)
	_hero_summary = Label.new()
	_hero_summary.text = "世界目录、原子存档、自动恢复和 Windows Release 验收均已启用。"
	_hero_summary.theme_type_variation = "MutedLabel"
	_hero_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manifesto_content.add_child(_hero_summary)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_column.add_child(bottom_spacer)


func _build_command_panel() -> void:
	var command_wrap := VBoxContainer.new()
	command_wrap.name = "CommandWrap"
	command_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_layout.add_child(command_wrap)
	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	command_wrap.add_child(top_spacer)

	_command_panel = UiKit.make_card("CommandPanel", Vector2(390, 0))
	_command_panel.name = "CommandDeck"
	command_wrap.add_child(_command_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_command_panel.add_child(content)

	content.add_child(UiKit.make_eyebrow("COMMAND DECK"))
	var title := UiKit.make_title("开始远征")
	content.add_child(title)
	var subtitle := UiKit.make_subtitle("创建新世界、继续已有旅程，或调整运行设置。")
	content.add_child(subtitle)
	content.add_child(UiKit.make_divider())

	_add_menu_button(
		content,
		"开始游戏",
		func() -> void: _show_panel(_map_panel),
		"MenuPrimaryButton",
		Tokens.CONTROL_HEIGHT_LG
	)
	_add_menu_button(
		content,
		"地图选择",
		func() -> void: _show_panel(_map_panel),
		"MenuButton"
	)
	_add_menu_button(
		content,
		"存档 / 继续",
		func() -> void:
			_save_panel.refresh()
			_show_panel(_save_panel),
		"MenuButton"
	)
	_add_menu_button(content, "设置", func() -> void: _show_panel(_settings_panel), "MenuButton")
	_add_menu_button(content, "检查更新", _request_update_check, "GhostButton")
	_add_menu_button(content, "退出", _quit, "DangerButton")

	_status = Label.new()
	_status.name = "MenuStatus"
	_status.theme_type_variation = "CaptionLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 36
	content.add_child(_status)

	_version_label = Label.new()
	_version_label.text = "v%s  ·  Godot 4  ·  本地单人版" % AppVersion.display_version()
	_version_label.theme_type_variation = "SubduedLabel"
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_version_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	command_wrap.add_child(bottom_spacer)


func _add_menu_button(
	parent: Control,
	label: String,
	callback: Callable,
	variation: String = "MenuButton",
	minimum_height: float = Tokens.CONTROL_HEIGHT_MD
) -> void:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(338, minimum_height)
	button.pressed.connect(callback)
	button.mouse_entered.connect(
		func() -> void:
			var tween := button.create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(button, "position:x", 5.0, 0.10)
	)
	button.mouse_exited.connect(
		func() -> void:
			var tween := button.create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(button, "position:x", 0.0, 0.12)
	)
	parent.add_child(button)
	_menu_buttons.append(button)
	_connect_button_audio(button)


func _bind_menu_audio() -> void:
	for button: Button in _menu_buttons:
		_connect_button_audio(button)


func _connect_button_audio(button: Button) -> void:
	if audio_service == null or not audio_service.has_method("play_ui"):
		return
	var callback := Callable(audio_service, "play_ui")
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _build_subpanels() -> void:
	_map_panel = MapPanelScript.new()
	_center_panel(_map_panel, Vector2(960, 610))
	add_child(_map_panel)
	_map_panel.visible = false
	_map_panel.create_requested.connect(_on_create_requested)
	_map_panel.back_requested.connect(show_main)

	_save_panel = SaveBrowserScript.new()
	_center_panel(_save_panel, Vector2(960, 610))
	add_child(_save_panel)
	_save_panel.visible = false
	_save_panel.load_requested.connect(_on_load_requested)
	_save_panel.back_requested.connect(show_main)

	_settings_panel = SettingsPanelScript.new()
	_center_panel(_settings_panel, Vector2(780, 570))
	add_child(_settings_panel)
	_settings_panel.visible = false
	_settings_panel.settings_applied.connect(
		func(settings: Dictionary) -> void: settings_changed.emit(settings)
	)
	_settings_panel.back_requested.connect(show_main)

	_update_panel = UpdatePromptPanelScript.new()
	_center_panel(_update_panel, Vector2(760, 540))
	add_child(_update_panel)
	_update_panel.visible = false
	_update_panel.dismissed.connect(show_main)


func _build_loading_panel() -> void:
	_loading_panel = PanelContainer.new()
	_loading_panel.name = "LoadingPanel"
	_loading_panel.theme_type_variation = "ModalPanel"
	_center_panel(_loading_panel, Vector2(560, 250))
	add_child(_loading_panel)
	_loading_panel.visible = false
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", Tokens.SPACE_LG)
	_loading_panel.add_child(content)
	content.add_child(UiKit.make_eyebrow("PREPARING EXPEDITION"))
	var title := UiKit.make_title("星的世界")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	_loading_label = Label.new()
	_loading_label.text = "正在生成世界…"
	_loading_label.theme_type_variation = "MutedLabel"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_loading_label)
	var progress := ProgressBar.new()
	progress.indeterminate = true
	progress.custom_minimum_size = Vector2(440, 8)
	progress.show_percentage = false
	content.add_child(progress)


func _center_panel(panel: Control, panel_size: Vector2) -> void:
	_panel_sizes[panel.get_instance_id()] = panel_size
	panel.set_meta("star_desired_size", panel_size)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	_fit_center_panel(panel, panel_size)


func _fit_center_panel(panel: Control, desired_size: Vector2) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(1280, 720)
	var safe_size := Vector2(
		minf(desired_size.x, maxf(320.0, viewport_size.x - Tokens.PANEL_SAFE_MARGIN * 2.0)),
		minf(desired_size.y, maxf(260.0, viewport_size.y - Tokens.PANEL_SAFE_MARGIN * 2.0))
	)
	panel.offset_left = -safe_size.x * 0.5
	panel.offset_right = safe_size.x * 0.5
	panel.offset_top = -safe_size.y * 0.5
	panel.offset_bottom = safe_size.y * 0.5


func _apply_responsive_layout() -> void:
	if _menu_margin != null:
		var compact := size.x < 1120.0 or size.y < 650.0
		var horizontal_margin := 34 if compact else 68
		var vertical_margin := 24 if compact else 46
		UiKit.set_margin(
			_menu_margin,
			horizontal_margin,
			vertical_margin,
			horizontal_margin,
			vertical_margin
		)
		if _main_layout != null:
			_main_layout.add_theme_constant_override(
				"separation", Tokens.SPACE_XL if compact else Tokens.SPACE_3XL
			)
		if _command_panel != null:
			_command_panel.custom_minimum_size.x = 350.0 if compact else 390.0
		if _hero_title != null:
			_hero_title.add_theme_font_size_override(
				"font_size", 48 if compact else Tokens.FONT_DISPLAY
			)
	for panel in [_map_panel, _save_panel, _settings_panel, _update_panel, _loading_panel]:
		if panel == null or not is_instance_valid(panel):
			continue
		var desired: Variant = panel.get_meta("star_desired_size", panel.custom_minimum_size)
		_fit_center_panel(panel, desired if desired is Vector2 else panel.custom_minimum_size)


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
	if update_service.has_signal("update_available") and not update_service.is_connected(
		"update_available", available_callback
	):
		update_service.connect("update_available", available_callback)
	var no_update_callback := Callable(self, "_on_no_update_available")
	if update_service.has_signal("no_update_available") and not update_service.is_connected(
		"no_update_available", no_update_callback
	):
		update_service.connect("no_update_available", no_update_callback)
	var failed_callback := Callable(self, "_on_update_check_failed")
	if update_service.has_signal("update_failed") and not update_service.is_connected(
		"update_failed", failed_callback
	):
		update_service.connect("update_failed", failed_callback)
	var notice := (
		str(update_service.call("get_startup_notice"))
		if update_service.has_method("get_startup_notice")
		else ""
	)
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
	_apply_responsive_layout()


func _set_menu_enabled(enabled: bool) -> void:
	for button: Button in _menu_buttons:
		button.disabled = not enabled


func _request_update_check() -> void:
	if update_service == null or not update_service.has_method("check_for_updates"):
		_status.text = "更新服务当前不可用。"
		_status.theme_type_variation = "CaptionLabel"
		return
	_status.text = "正在检查 GitHub Release…"
	_status.theme_type_variation = "CaptionLabel"
	update_service.call("check_for_updates", true)


func _on_update_available(_release: Dictionary) -> void:
	_show_panel(_update_panel)


func _on_no_update_available(version: String) -> void:
	_status.text = "当前 v%s 已是最新版本。" % version
	_status.theme_type_variation = "SuccessLabel"


func _on_update_check_failed(_reason: String, message: String) -> void:
	if _update_panel == null or not _update_panel.visible:
		_status.text = message
		_status.theme_type_variation = "DangerLabel"


func _on_create_requested(world_name: String, map_id: String, seed_value: int) -> void:
	var profile: Dictionary = _map_panel.get_profile(map_id)
	var state: Dictionary = save_service.create_world(
		world_name, map_id, seed_value, {"map_profile": profile}
	)
	if state.is_empty():
		show_main()
		show_error("创建世界失败，请检查写入权限。")
		return
	show_loading("正在生成 %s…" % str(profile.get("name", "世界")))
	new_world_requested.emit(state)


func _on_load_requested(world_id: String) -> void:
	var state: Dictionary = save_service.load_world(world_id)
	if state.is_empty():
		show_main()
		show_error("无法读取该存档。")
		return
	show_loading("正在读取世界…")
	continue_world_requested.emit(state)


func _quit() -> void:
	quit_requested.emit()
	get_tree().quit()
