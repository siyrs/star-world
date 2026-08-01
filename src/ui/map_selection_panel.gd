class_name MapSelectionPanel
extends PanelContainer

signal create_requested(world_name: String, map_id: String, seed_value: int)
signal back_requested

const DATA_PATH := "res://data/map_profiles.json"
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const ResourceDistributionRegistryScript = preload("res://src/world/resource_distribution_registry.gd")
const WorldDecorationRegistryScript = preload("res://src/world/world_decoration_registry.gd")

var _profiles: Array = []
var _selected_map_id: String = ""
var _world_name: LineEdit
var _seed: LineEdit
var _details: RichTextLabel
var _map_buttons: VBoxContainer
var _profile_buttons: Dictionary = {}
var _selected_badge: Label
var _resource_summary_label: Label
var _create_button: Button
var _back_button: Button
var _rng := RandomNumberGenerator.new()
var _resource_registry = ResourceDistributionRegistryScript.new()
var _decoration_registry = WorldDecorationRegistryScript.new()


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(900, 520)
	_load_profiles()
	_build_ui()
	if not _profiles.is_empty():
		_select_profile(str(_profiles[0].get("id", "")))


func _load_profiles() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		_profiles = parsed.get("maps", [])


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_MD)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_SM)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("创建世界"))
	var title := UiKit.make_title("选择远征世界")
	heading.add_child(title)
	var subtitle := UiKit.make_subtitle(
		"先选择地图生态，再定义世界名称与种子。每张地图拥有独立资源、危险、地标与环境特征。"
	)
	heading.add_child(subtitle)
	_back_button = UiKit.style_button(
		Button.new(),
		"GhostButton",
		Vector2(118, Tokens.CONTROL_HEIGHT_MD)
	)
	_back_button.text = "返回"
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(_back_button)

	root.add_child(UiKit.make_divider())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_LG)
	root.add_child(body)

	var catalog_panel := UiKit.make_card("InsetPanel", Vector2(300, 0))
	catalog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(catalog_panel)
	var catalog_root := VBoxContainer.new()
	catalog_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	catalog_panel.add_child(catalog_root)
	catalog_root.add_child(
		UiKit.make_section_header("地图目录", "五种稳定地图签名 · 旧 Seed 结果保持兼容")
	)
	var map_scroll := ScrollContainer.new()
	map_scroll.name = "MapCatalogScroll"
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_root.add_child(map_scroll)
	_map_buttons = VBoxContainer.new()
	_map_buttons.name = "MapButtons"
	_map_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_buttons.add_theme_constant_override("separation", Tokens.SPACE_SM)
	map_scroll.add_child(_map_buttons)
	var group := ButtonGroup.new()
	for raw_profile: Variant in _profiles:
		if raw_profile is not Dictionary:
			continue
		var profile: Dictionary = raw_profile
		var button := Button.new()
		button.theme_type_variation = "CardButton"
		button.text = "%s\n%s · %s" % [
			str(profile.get("name", "未知世界")),
			str(profile.get("difficulty", "未知难度")),
			str(profile.get("generator", "标准生成")),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(266, 66)
		var map_id := str(profile.get("id", ""))
		button.set_meta("map_id", map_id)
		button.pressed.connect(func() -> void: _select_profile(map_id))
		_map_buttons.add_child(button)
		_profile_buttons[map_id] = button

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", Tokens.SPACE_MD)
	body.add_child(right)

	var briefing_panel := UiKit.make_card("GlassPanel")
	briefing_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(briefing_panel)
	var briefing_root := VBoxContainer.new()
	briefing_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	briefing_panel.add_child(briefing_root)
	var briefing_header := HBoxContainer.new()
	briefing_root.add_child(briefing_header)
	var briefing_title := Label.new()
	briefing_title.text = "地图简报"
	briefing_title.theme_type_variation = "SectionTitle"
	briefing_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing_header.add_child(briefing_title)
	_selected_badge = UiKit.make_badge("等待选择", "info")
	briefing_header.add_child(_selected_badge)
	_details = RichTextLabel.new()
	_details.name = "MapDetails"
	_details.bbcode_enabled = true
	_details.fit_content = false
	_details.scroll_active = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.custom_minimum_size = Vector2(430, 190)
	_details.add_theme_font_size_override("normal_font_size", Tokens.FONT_BODY)
	briefing_root.add_child(_details)
	_resource_summary_label = Label.new()
	_resource_summary_label.name = "WorldIdentitySummary"
	_resource_summary_label.theme_type_variation = "MutedLabel"
	_resource_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing_root.add_child(_resource_summary_label)

	var setup_panel := UiKit.make_card("CardPanel")
	right.add_child(setup_panel)
	var setup_root := VBoxContainer.new()
	setup_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	setup_panel.add_child(setup_root)
	setup_root.add_child(
		UiKit.make_section_header(
			"世界档案",
			"名称可以随时识别；相同 Seed 与地图会生成相同基础资源、地标与装饰。"
		)
	)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	setup_root.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "世界名称"
	name_label.custom_minimum_size.x = 92
	name_label.theme_type_variation = "CaptionLabel"
	name_row.add_child(name_label)
	_world_name = LineEdit.new()
	_world_name.placeholder_text = "为这次远征命名"
	_world_name.text = "我的星球"
	_world_name.max_length = 48
	_world_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_name.custom_minimum_size.y = Tokens.CONTROL_HEIGHT_MD
	name_row.add_child(_world_name)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	setup_root.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "世界 Seed"
	seed_label.custom_minimum_size.x = 92
	seed_label.theme_type_variation = "CaptionLabel"
	seed_row.add_child(seed_label)
	_seed = LineEdit.new()
	_seed.placeholder_text = "数字或文本"
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.custom_minimum_size.y = Tokens.CONTROL_HEIGHT_MD
	_seed.text = str(_rng.randi())
	seed_row.add_child(_seed)
	var random_button := UiKit.style_button(
		Button.new(),
		"ToolbarButton",
		Vector2(92, Tokens.CONTROL_HEIGHT_MD)
	)
	random_button.text = "随机"
	random_button.pressed.connect(func() -> void: _seed.text = str(_rng.randi()))
	seed_row.add_child(random_button)

	_create_button = UiKit.style_button(
		Button.new(),
		"PrimaryButton",
		Vector2(0, Tokens.CONTROL_HEIGHT_LG)
	)
	_create_button.text = "创建并进入世界"
	_create_button.pressed.connect(_emit_create)
	setup_root.add_child(_create_button)


func _select_profile(map_id: String) -> void:
	_selected_map_id = map_id
	for profile_id: Variant in _profile_buttons.keys():
		var raw_button: Variant = _profile_buttons.get(profile_id)
		if raw_button is Button:
			UiKit.set_selected_card(raw_button as Button, str(profile_id) == map_id)
	for raw_profile: Variant in _profiles:
		if raw_profile is not Dictionary:
			continue
		var profile: Dictionary = raw_profile
		if str(profile.get("id", "")) != map_id:
			continue
		var resource_summary := get_resource_summary(map_id)
		var decoration_summary := get_decoration_summary(map_id)
		_selected_badge.text = str(profile.get("difficulty", "未知难度"))
		_selected_badge.add_theme_color_override(
			"font_color",
			Tokens.color(
				Tokens.COLOR_WARNING
				if str(profile.get("difficulty", "")).contains("高")
				else Tokens.COLOR_ACCENT_SOFT
			)
		)
		_details.text = (
			"[font_size=30][color=%s]%s[/color][/font_size]\n"
			+ "[color=%s]%s[/color]\n\n"
			+ "[color=%s][b]生成规则[/b][/color]  %s\n"
			+ "[color=%s][b]生存难度[/b][/color]  %s"
		) % [
			Tokens.MC_PANEL_TEXT,
			str(profile.get("name", "")),
			Tokens.MC_PANEL_TEXT_MUTED,
			str(profile.get("description", "")),
			Tokens.MC_PANEL_ACCENT,
			str(profile.get("generator", "")),
			Tokens.MC_PANEL_WARNING,
			str(profile.get("difficulty", "")),
		]
		_resource_summary_label.text = (
			"资源特点 · %s\n地表地标 · %s" % [resource_summary, decoration_summary]
		)
		break


func _emit_create() -> void:
	if _selected_map_id.is_empty():
		return
	var normalized_name := _world_name.text.strip_edges()
	if normalized_name.is_empty():
		normalized_name = "未命名星球"
	var seed_value := int(_seed.text) if _seed.text.is_valid_int() else int(_seed.text.hash())
	create_requested.emit(normalized_name, _selected_map_id, seed_value)


func get_profile(map_id: String) -> Dictionary:
	for raw_profile: Variant in _profiles:
		if raw_profile is Dictionary and str(raw_profile.get("id", "")) == map_id:
			return (raw_profile as Dictionary).duplicate(true)
	return {}


func get_resource_summary(map_id: String) -> String:
	return _resource_registry.get_summary(map_id)


func get_decoration_summary(map_id: String) -> String:
	return _decoration_registry.get_summary(map_id)


func get_selected_map_id() -> String:
	return _selected_map_id


func get_details_text() -> String:
	return _details.text if _details != null else ""


func get_visual_snapshot() -> Dictionary:
	var selected_button: Button = _profile_buttons.get(_selected_map_id) as Button
	return {
		"panel_rect": get_global_rect(),
		"profile_count": _profile_buttons.size(),
		"selected_map_id": _selected_map_id,
		"selected_variation": (
			selected_button.theme_type_variation if selected_button != null else ""
		),
		"details_rect": _details.get_global_rect() if _details != null else Rect2(),
		"create_rect": _create_button.get_global_rect() if _create_button != null else Rect2(),
		"resource_summary": get_resource_summary(_selected_map_id),
		"decoration_summary": get_decoration_summary(_selected_map_id),
	}
