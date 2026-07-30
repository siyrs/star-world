class_name HostileEncounterOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var director: Node
var _active := false
var _blocked := false
var _last_snapshot: Dictionary = {}
var _panel: PanelContainer
var _title_label: Label
var _detail_label: Label
var _pressure_bar: ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_panel()
	UiInputPolicy.make_passthrough_tree(self)
	_refresh()


func setup(p_director: Node) -> void:
	_disconnect_director()
	director = p_director
	if director != null and director.has_signal("snapshot_changed"):
		director.connect("snapshot_changed", Callable(self, "_on_snapshot_changed"))
	if director != null and director.has_method("get_snapshot"):
		_on_snapshot_changed(director.call("get_snapshot"))
	_refresh()


func set_active(value: bool) -> void:
	_active = value
	_refresh()


func set_blocked(value: bool) -> void:
	_blocked = value
	_refresh()


func get_snapshot() -> Dictionary:
	return {
		"active": _active,
		"blocked": _blocked,
		"visible": _panel.visible if _panel != null else false,
		"title": _title_label.text if _title_label != null else "",
		"detail": _detail_label.text if _detail_label != null else "",
		"pressure_ratio": _pressure_bar.value if _pressure_bar != null else 0.0,
		"director": _last_snapshot.duplicate(true),
		"rect": _panel.get_global_rect() if _panel != null else Rect2(),
	}


func _exit_tree() -> void:
	_disconnect_director()


func _on_snapshot_changed(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate(true)
	_refresh()


func _refresh() -> void:
	if _panel == null:
		return
	var encounters: Array = _last_snapshot.get("encounters", [])
	var can_show := _active and not _blocked
	var low_health := (
		str(_last_snapshot.get("last_rejection_reason", "")) == "low_health"
		and float(_last_snapshot.get("health_ratio", 1.0)) < 0.35
	)
	_panel.visible = can_show and (not encounters.is_empty() or low_health)
	if not _panel.visible:
		return
	if encounters.is_empty():
		_title_label.text = "遭遇调度暂缓"
		_detail_label.text = "生命过低，新的敌对小队不会加入战斗"
		_pressure_bar.value = 0.0
		return
	var first: Dictionary = encounters[0] if encounters[0] is Dictionary else {}
	var living := int(first.get("living_member_count", 0))
	var initial := maxi(1, int(first.get("initial_member_count", 1)))
	var pressure := maxf(0.0, float(first.get("living_pressure", 0.0)))
	var maximum_pressure := maxf(1.0, float(first.get("initial_pressure", pressure)))
	_title_label.text = "遭遇：%s" % str(first.get("display_name", "敌对小队"))
	_detail_label.text = "剩余 %d/%d · 威胁 %.1f · %s" % [
		living,
		initial,
		pressure,
		_role_summary(first.get("roles", {})),
	]
	_pressure_bar.value = clampf(pressure / maximum_pressure, 0.0, 1.0)


func _role_summary(raw_roles: Variant) -> String:
	if raw_roles is not Dictionary:
		return "协同作战"
	var roles: Dictionary = raw_roles
	var labels: Array[String] = []
	if int(roles.get("vanguard", 0)) > 0:
		labels.append("前卫%d" % int(roles.get("vanguard", 0)))
	if int(roles.get("support", 0)) > 0:
		labels.append("远程%d" % int(roles.get("support", 0)))
	if int(roles.get("finisher", 0)) > 0:
		labels.append("重装%d" % int(roles.get("finisher", 0)))
	return " · ".join(labels) if not labels.is_empty() else "协同作战"


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "HostileEncounterPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -180.0
	_panel.offset_right = 180.0
	_panel.offset_top = 62.0
	_panel.offset_bottom = 132.0
	_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#170B1EE6", Tokens.COLOR_BORDER_STRONG, 2, 7.0)
	)
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	_panel.add_child(content)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	content.add_child(_title_label)
	_detail_label = Label.new()
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	content.add_child(_detail_label)
	_pressure_bar = ProgressBar.new()
	_pressure_bar.min_value = 0.0
	_pressure_bar.max_value = 1.0
	_pressure_bar.show_percentage = false
	_pressure_bar.custom_minimum_size = Vector2(320.0, 9.0)
	content.add_child(_pressure_bar)


func _disconnect_director() -> void:
	if director == null or not is_instance_valid(director):
		return
	var callback := Callable(self, "_on_snapshot_changed")
	if director.has_signal("snapshot_changed") and director.is_connected("snapshot_changed", callback):
		director.disconnect("snapshot_changed", callback)
