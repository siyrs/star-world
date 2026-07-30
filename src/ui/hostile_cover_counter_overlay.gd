class_name HostileCoverCounterOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

const COVER_NOTICE_SECONDS := 4.0
const REPOSITION_NOTICE_SECONDS := 3.0

var service: Node
var _panel: PanelContainer
var _title_label: Label
var _detail_label: Label
var _remaining_seconds := 0.0
var _last_event: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_panel()
	UiInputPolicy.make_passthrough_tree(self)
	set_process(true)
	_refresh()


func setup(p_service: Node) -> void:
	_disconnect_service()
	service = p_service
	if service != null and service.has_signal("cover_broken"):
		service.connect("cover_broken", Callable(self, "_on_cover_broken"))
	if service != null and service.has_signal("marksman_repositioned"):
		service.connect("marksman_repositioned", Callable(self, "_on_marksman_repositioned"))
	_refresh()


func clear() -> void:
	_remaining_seconds = 0.0
	_last_event.clear()
	_refresh()


func get_snapshot() -> Dictionary:
	return {
		"visible": _panel.visible if _panel != null else false,
		"title": _title_label.text if _title_label != null else "",
		"detail": _detail_label.text if _detail_label != null else "",
		"remaining_seconds": _remaining_seconds,
		"last_event": _last_event.duplicate(true),
		"rect": _panel.get_global_rect() if _panel != null else Rect2(),
	}


func _process(delta: float) -> void:
	if _remaining_seconds <= 0.0:
		return
	_remaining_seconds = maxf(0.0, _remaining_seconds - maxf(0.0, delta))
	_refresh()


func _on_cover_broken(snapshot: Dictionary) -> void:
	_last_event = snapshot.duplicate(true)
	_remaining_seconds = COVER_NOTICE_SECONDS
	_title_label.text = "临时掩体被突破"
	_detail_label.text = "重击者摧毁 %d 块脆弱掩体 · 本体预算 %d/%d" % [
		int(snapshot.get("changed_blocks", 0)),
		int(snapshot.get("lifetime_break_count", 0)),
		int(snapshot.get("lifetime_break_budget", 0)),
	]
	_refresh()


func _on_marksman_repositioned(snapshot: Dictionary) -> void:
	_last_event = snapshot.duplicate(true)
	_remaining_seconds = REPOSITION_NOTICE_SECONDS
	_title_label.text = "深渊射手正在换位"
	_detail_label.text = "弹道受阻 · 探测 %d/%d · 换位 %d/%d" % [
		int(snapshot.get("probes", 0)),
		6,
		int(snapshot.get("attempt_count", 0)),
		int(snapshot.get("attempt_budget", 0)),
	]
	_refresh()


func _refresh() -> void:
	if _panel != null:
		_panel.visible = _remaining_seconds > 0.0


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "HostileCoverCounterPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -180.0
	_panel.offset_right = 180.0
	_panel.offset_top = 140.0
	_panel.offset_bottom = 202.0
	_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#24170DE6", Tokens.COLOR_BORDER_STRONG, 2, 7.0)
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


func _disconnect_service() -> void:
	if service == null or not is_instance_valid(service):
		return
	var cover_callback := Callable(self, "_on_cover_broken")
	if service.has_signal("cover_broken") and service.is_connected("cover_broken", cover_callback):
		service.disconnect("cover_broken", cover_callback)
	var reposition_callback := Callable(self, "_on_marksman_repositioned")
	if service.has_signal("marksman_repositioned") and service.is_connected(
		"marksman_repositioned", reposition_callback
	):
		service.disconnect("marksman_repositioned", reposition_callback)


func _exit_tree() -> void:
	_disconnect_service()
