class_name CombatFeedbackOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var combat_service: Node
var _active := false
var _blocked := false
var _hit_remaining := 0.0
var _cooldown_panel: PanelContainer
var _cooldown_label: Label
var _cooldown_bar: ProgressBar
var _hit_panel: PanelContainer
var _hit_label: Label
var _last_cooldown: Dictionary = {}
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_cooldown_panel()
	_build_hit_panel()
	UiInputPolicy.make_passthrough_tree(self)
	_refresh_visibility()


func setup(p_combat_service: Node) -> void:
	_disconnect_service()
	combat_service = p_combat_service
	if combat_service != null:
		if combat_service.has_signal("outgoing_attack_resolved"):
			combat_service.connect(
				"outgoing_attack_resolved", Callable(self, "_on_attack_resolved")
			)
		if combat_service.has_signal("attack_rejected"):
			combat_service.connect("attack_rejected", Callable(self, "_on_attack_rejected"))
		if combat_service.has_signal("cooldown_changed"):
			combat_service.connect("cooldown_changed", Callable(self, "_on_cooldown_changed"))
		if combat_service.has_method("get_cooldown_snapshot"):
			_on_cooldown_changed(combat_service.call("get_cooldown_snapshot"))
	_refresh_visibility()


func set_active(value: bool) -> void:
	_active = value
	_refresh_visibility()


func set_blocked(value: bool) -> void:
	_blocked = value
	_refresh_visibility()


func get_snapshot() -> Dictionary:
	return {
		"active": _active,
		"blocked": _blocked,
		"cooldown": _last_cooldown.duplicate(true),
		"last_result": _last_result.duplicate(true),
		"cooldown_visible": _cooldown_panel.visible if _cooldown_panel != null else false,
		"hit_visible": _hit_panel.visible if _hit_panel != null else false,
	}


func _process(delta: float) -> void:
	if _hit_remaining > 0.0:
		_hit_remaining = maxf(0.0, _hit_remaining - maxf(0.0, delta))
		if _hit_remaining <= 0.0 and _hit_panel != null:
			_hit_panel.visible = false
	if combat_service != null and combat_service.has_method("get_cooldown_snapshot"):
		_on_cooldown_changed(combat_service.call("get_cooldown_snapshot"))


func _exit_tree() -> void:
	_disconnect_service()


func _on_attack_resolved(result: Dictionary) -> void:
	if str(result.get("status", "")) != "hit":
		return
	_last_result = result.duplicate(true)
	var target_name := str(result.get("target_name", "目标"))
	var damage := float(result.get("final_damage", result.get("damage", 0.0)))
	_hit_label.text = (
		"击败 %s" % target_name
		if bool(result.get("defeated", false))
		else "命中 %s  ·  %.1f" % [target_name, damage]
	)
	_hit_label.modulate = Tokens.color(Tokens.COLOR_SUCCESS)
	_hit_remaining = 0.55
	_refresh_visibility()


func _on_attack_rejected(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	if str(result.get("reason", "")) != "cooldown":
		return
	_hit_label.text = "攻击冷却中"
	_hit_label.modulate = Tokens.color(Tokens.COLOR_WARNING)
	_hit_remaining = 0.24
	_refresh_visibility()


func _on_cooldown_changed(snapshot: Dictionary) -> void:
	_last_cooldown = snapshot.duplicate(true)
	if _cooldown_bar == null:
		return
	var ratio := clampf(float(snapshot.get("ready_ratio", 1.0)), 0.0, 1.0)
	_cooldown_bar.value = ratio
	_cooldown_label.text = (
		"攻击已准备"
		if bool(snapshot.get("ready", true))
		else "攻击恢复  %d%%" % int(round(ratio * 100.0))
	)
	_refresh_visibility()


func _refresh_visibility() -> void:
	var can_show := _active and not _blocked
	if _cooldown_panel != null:
		_cooldown_panel.visible = (
			can_show
			and not _last_cooldown.is_empty()
			and not bool(_last_cooldown.get("ready", true))
		)
	if _hit_panel != null:
		_hit_panel.visible = can_show and _hit_remaining > 0.0


func _build_cooldown_panel() -> void:
	_cooldown_panel = PanelContainer.new()
	_cooldown_panel.anchor_left = 0.5
	_cooldown_panel.anchor_right = 0.5
	_cooldown_panel.anchor_top = 0.5
	_cooldown_panel.anchor_bottom = 0.5
	_cooldown_panel.offset_left = -104.0
	_cooldown_panel.offset_right = 104.0
	_cooldown_panel.offset_top = 38.0
	_cooldown_panel.offset_bottom = 78.0
	_cooldown_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style("#0B1420D9", Tokens.COLOR_BORDER_STRONG, 1, Tokens.RADIUS_SM, 6.0)
	)
	add_child(_cooldown_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	_cooldown_panel.add_child(content)
	_cooldown_label = Label.new()
	_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cooldown_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	content.add_child(_cooldown_label)
	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.min_value = 0.0
	_cooldown_bar.max_value = 1.0
	_cooldown_bar.show_percentage = false
	_cooldown_bar.custom_minimum_size = Vector2(190.0, 8.0)
	_cooldown_bar.add_theme_stylebox_override(
		"fill",
		Tokens.panel_style(Tokens.COLOR_ACCENT_WARM, Tokens.COLOR_ACCENT_WARM, 0, Tokens.RADIUS_SM, 1.0)
	)
	content.add_child(_cooldown_bar)


func _build_hit_panel() -> void:
	_hit_panel = PanelContainer.new()
	_hit_panel.anchor_left = 0.5
	_hit_panel.anchor_right = 0.5
	_hit_panel.anchor_top = 0.5
	_hit_panel.anchor_bottom = 0.5
	_hit_panel.offset_left = -130.0
	_hit_panel.offset_right = 130.0
	_hit_panel.offset_top = -70.0
	_hit_panel.offset_bottom = -34.0
	_hit_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style("#09111ACC", Tokens.COLOR_BORDER, 1, Tokens.RADIUS_SM, 6.0)
	)
	add_child(_hit_panel)
	_hit_label = Label.new()
	_hit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hit_label.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	_hit_panel.add_child(_hit_label)


func _disconnect_service() -> void:
	if combat_service == null:
		return
	for binding in [
		["outgoing_attack_resolved", "_on_attack_resolved"],
		["attack_rejected", "_on_attack_rejected"],
		["cooldown_changed", "_on_cooldown_changed"],
	]:
		var signal_name := str(binding[0])
		var callback := Callable(self, str(binding[1]))
		if combat_service.has_signal(signal_name) and combat_service.is_connected(signal_name, callback):
			combat_service.disconnect(signal_name, callback)
	combat_service = null
