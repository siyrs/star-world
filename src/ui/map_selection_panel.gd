class_name MapSelectionPanel
extends PanelContainer

signal create_requested(world_name: String, map_id: String, seed_value: int)
signal back_requested

const DATA_PATH := "res://data/map_profiles.json"
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const ResourceDistributionRegistryScript = preload("res://src/world/resource_distribution_registry.gd")

var _profiles: Array = []
var _selected_map_id: String = ""
var _world_name: LineEdit
var _seed: LineEdit
var _details: RichTextLabel
var _map_buttons: VBoxContainer
var _rng := RandomNumberGenerator.new()
var _resource_registry = ResourceDistributionRegistryScript.new()


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	_rng.randomize()
	custom_minimum_size = Vector2(860, 610)
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
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "选择世界"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	_map_buttons = VBoxContainer.new()
	_map_buttons.custom_minimum_size.x = 300
	body.add_child(_map_buttons)
	var group := ButtonGroup.new()
	for profile in _profiles:
		var button := Button.new()
		button.text = "%s\n%s" % [str(profile.get("name", "")), str(profile.get("difficulty", ""))]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 72
		var map_id := str(profile.get("id", ""))
		button.pressed.connect(func(): _select_profile(map_id))
		_map_buttons.add_child(button)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.fit_content = false
	_details.custom_minimum_size = Vector2(480, 280)
	right.add_child(_details)
	_world_name = LineEdit.new()
	_world_name.placeholder_text = "世界名称"
	_world_name.text = "我的星球"
	right.add_child(_world_name)
	var seed_row := HBoxContainer.new()
	right.add_child(seed_row)
	_seed = LineEdit.new()
	_seed.placeholder_text = "Seed（数字或文本）"
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.text = str(_rng.randi())
	seed_row.add_child(_seed)
	var random_button := Button.new()
	random_button.text = "随机"
	random_button.pressed.connect(func(): _seed.text = str(_rng.randi()))
	seed_row.add_child(random_button)
	var create_button := Button.new()
	create_button.text = "创建并进入世界"
	create_button.custom_minimum_size.y = 58
	create_button.pressed.connect(_emit_create)
	right.add_child(create_button)


func _select_profile(map_id: String) -> void:
	_selected_map_id = map_id
	for profile in _profiles:
		if str(profile.get("id", "")) != map_id:
			continue
		var resource_summary := get_resource_summary(map_id)
		_details.text = (
			"[font_size=30]%s[/font_size]\n\n%s\n\n[b]资源特点[/b]：%s\n\n生成规则：%s\n难度：%s"
			% [
				profile.get("name", ""),
				profile.get("description", ""),
				resource_summary,
				profile.get("generator", ""),
				profile.get("difficulty", ""),
			]
		)
		break


func _emit_create() -> void:
	if _selected_map_id.is_empty():
		return
	var seed_value := int(_seed.text) if _seed.text.is_valid_int() else int(_seed.text.hash())
	create_requested.emit(_world_name.text.strip_edges(), _selected_map_id, seed_value)


func get_profile(map_id: String) -> Dictionary:
	for profile in _profiles:
		if str(profile.get("id", "")) == map_id:
			return profile.duplicate(true)
	return {}


func get_resource_summary(map_id: String) -> String:
	return _resource_registry.get_summary(map_id)


func get_selected_map_id() -> String:
	return _selected_map_id


func get_details_text() -> String:
	return _details.text if _details != null else ""
