class_name CombatFeedbackOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var combat_service: Node
var ranged_combat_service: Node
var _active := false
var _blocked := false
var _hit_remaining := 0.0
var _cooldown_panel: PanelContainer
var _cooldown_label: Label
var _cooldown_bar: ProgressBar
var _ranged_panel: PanelContainer
var _ranged_label: Label
var _ranged_bar: ProgressBar
var _hit_panel: PanelContainer
var _hit_label: Label
var _last_cooldown: Dictionary = {}
var _last_ranged: Dictionary = {}
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_cooldown_panel()
	_build_ranged_panel()
	_build_hit_panel()
	UiInputPolicy.make_passthrough_tree(self)
	_refresh_visibility()


func setup(p_combat_service: Node, p_ranged_combat_service: Node = null) -> void:
	_disconnect_services()
	combat_service = p_combat_service
	ranged_combat_service = p_ranged_combat_service
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
	if ranged_combat_service != null:
		if ranged_combat_service.has_signal("charge_changed"):
			ranged_combat_service.connect(
				"charge_changed", Callable(self, "_on_ranged_status_changed")
			)
		if ranged_combat_service.has_signal("shot_rejected"):
			ranged_combat_service.connect(
				"shot_rejected", Callable(self, "_on_ranged_shot_rejected")
			)
		if ranged_combat_service.has_signal("shot_fired"):
			ranged_combat_service.connect(
				"shot_fired", Callable(self, "_on_ranged_shot_fired")
			)
		if ranged_combat_service.has_method("get_snapshot"):
			_on_ranged_status_changed(ranged_combat_service.call("get_snapshot"))
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
		"ranged": _last_ranged.duplicate(true),
		"last_result": _last_result.duplicate(true),
		"cooldown_visible": _cooldown_panel.visible if _cooldown_panel != null else false,
		"ranged_visible": _ranged_panel.visible if _ranged_panel != null else false,
		"hit_visible": _hit_panel.visible if _hit_panel != null else false,
		"ranged_rect": _ranged_panel.get_global_rect() if _ranged_panel != null else Rect2(),
	}


func _process(delta: float) -> void:
	if _hit_remaining > 0.0:
		_hit_remaining = maxf(0.0, _hit_remaining - maxf(0.0, delta))
		if _hit_remaining <= 0.0 and _hit_panel != null:
			_hit_panel.visible = false
	if combat_service != null and combat_service.has_method("get_cooldown_snapshot"):
		_on_cooldown_changed(combat_service.call("get_cooldown_snapshot"))
	if ranged_combat_service != null and ranged_combat_service.has_method("get_snapshot"):
		_on_ranged_status_changed(ranged_combat_service.call("get_snapshot"))


func _exit_tree() -> void:
	_disconnect_services()


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
	_show_transient_feedback("攻击冷却中", Tokens.color(Tokens.COLOR_WARNING), 0.24)


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


func _on_ranged_status_changed(snapshot: Dictionary) -> void:
	_last_ranged = snapshot.duplicate(true)
	if _ranged_bar == null:
		return
	var ratio := 1.0
	var label := "猎弓已准备"
	if bool(snapshot.get("charging", false)):
		ratio = clampf(float(snapshot.get("charge_ratio", 0.0)), 0.0, 1.0)
		label = "猎弓蓄力  %d%%" % int(round(ratio * 100.0))
	elif not bool(snapshot.get("cooldown_ready", true)):
		ratio = clampf(float(snapshot.get("cooldown_ready_ratio", 0.0)), 0.0, 1.0)
		label = "猎弓恢复  %d%%" % int(round(ratio * 100.0))
	_ranged_bar.value = ratio
	_ranged_label.text = "%s  ·  箭矢 %d" % [label, int(snapshot.get("ammo_count", 0))]
	_refresh_visibility()


func _on_ranged_shot_rejected(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var reason := str(result.get("reason", "rejected"))
	var text := {
		"no_ammo": "没有箭矢",
		"undercharged": "蓄力不足",
		"cooldown": "猎弓冷却中",
		"projectile_capacity": "飞行箭矢已达上限",
	}.get(reason, "远程攻击未生效")
	_show_transient_feedback(str(text), Tokens.color(Tokens.COLOR_WARNING), 0.65)


func _on_ranged_shot_fired(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	_refresh_visibility()


func _show_transient_feedback(text: String, color: Color, duration: float) -> void:
	_hit_label.text = text
	_hit_label.modulate = color
	_hit_remaining = maxf(0.05, duration)
	_refresh_visibility()


func _refresh_visibility() -> void:
	var can_show := _active and not _blocked
	if _cooldown_panel != null:
		_cooldown_panel.visible = (
			can_show
			and not _last_cooldown.is_empty()
			and not bool(_last_cooldown.get("ready", true))
			and not bool(_last_ranged.get("equipped", false))
		)
	if _ranged_panel != null:
		_ranged_panel.visible = can_show and bool(_last_ranged.get("equipped", false))
	if _hit_panel != null:
		_hit_panel.visible = can_show and _hit_remaining > 0.0


func _build_cooldown_panel() -> void:
	_cooldown_panel = _build_status_panel("AttackCooldownPanel")
	_cooldown_label = Label.new()
	_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cooldown_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	var content := _cooldown_panel.get_child(0) as VBoxContainer
	content.add_child(_cooldown_label)
	_cooldown_bar = _build_progress_bar()
	content.add_child(_cooldown_bar)


func _build_ranged_panel() -> void:
	_ranged_panel = _build_status_panel("RangedChargePanel")
	_ranged_label = Label.new()
	_ranged_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ranged_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	var content := _ranged_panel.get_child(0) as VBoxContainer
	content.add_child(_ranged_label)
	_ranged_bar = _build_progress_bar()
	content.add_child(_ranged_bar)


func _build_status_panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -104.0
	panel.offset_right = 104.0
	panel.offset_top = 38.0
	panel.offset_bottom = 78.0
	panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#100C07D9", Tokens.COLOR_BORDER_STRONG, 2, 6.0)
	)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	panel.add_child(content)
	return panel


func _build_progress_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(190.0, 8.0)
	bar.add_theme_stylebox_override(
		"fill",
		Tokens.bevel_style(Tokens.COLOR_ACCENT_WARM, Tokens.COLOR_ACCENT_WARM, 0, 1.0)
	)
	return bar


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
		Tokens.bevel_style("#100C07CC", Tokens.COLOR_BORDER, 2, 6.0)
	)
	add_child(_hit_panel)
	_hit_label = Label.new()
	_hit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hit_label.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	_hit_panel.add_child(_hit_label)


func _disconnect_services() -> void:
	if combat_service != null:
		for binding: Array in [
			["outgoing_attack_resolved", "_on_attack_resolved"],
			["attack_rejected", "_on_attack_rejected"],
			["cooldown_changed", "_on_cooldown_changed"],
		]:
			var signal_name := str(binding[0])
			var callback := Callable(self, str(binding[1]))
			if combat_service.has_signal(signal_name) and combat_service.is_connected(signal_name, callback):
				combat_service.disconnect(signal_name, callback)
	combat_service = null
	if ranged_combat_service != null:
		for binding: Array in [
			["charge_changed", "_on_ranged_status_changed"],
			["shot_rejected", "_on_ranged_shot_rejected"],
			["shot_fired", "_on_ranged_shot_fired"],
		]:
			var signal_name := str(binding[0])
			var callback := Callable(self, str(binding[1]))
			if ranged_combat_service.has_signal(signal_name) and ranged_combat_service.is_connected(signal_name, callback):
				ranged_combat_service.disconnect(signal_name, callback)
	ranged_combat_service = null
