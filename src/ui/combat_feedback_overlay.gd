class_name CombatFeedbackOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")
const DamageDirectionPolicy = preload("res://src/combat/damage_direction_policy.gd")
const DIRECTION_PULSE_SECONDS := 0.7
const INCOMING_TEXT_SECONDS := 1.35

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
var _last_incoming: Dictionary = {}
var _incoming_panel: PanelContainer
var _incoming_label: Label
var _incoming_remaining := 0.0
var _direction_indicators: Dictionary = {}
var _direction_remaining := {
	"front": 0.0,
	"right": 0.0,
	"rear": 0.0,
	"left": 0.0,
}
var _show_direction_pulses := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_cooldown_panel()
	_build_ranged_panel()
	_build_hit_panel()
	_build_incoming_panel()
	_build_direction_indicators()
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
		if combat_service.has_signal("incoming_damage_resolved"):
			combat_service.connect(
				"incoming_damage_resolved", Callable(self, "_on_incoming_damage_resolved")
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
		if ranged_combat_service.has_signal("reload_started"):
			ranged_combat_service.connect(
				"reload_started", Callable(self, "_on_reload_event")
			)
		if ranged_combat_service.has_signal("reload_completed"):
			ranged_combat_service.connect(
				"reload_completed", Callable(self, "_on_reload_event")
			)
		if ranged_combat_service.has_signal("reload_cancelled"):
			ranged_combat_service.connect(
				"reload_cancelled", Callable(self, "_on_reload_event")
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


func apply_settings(settings: Dictionary) -> void:
	_show_direction_pulses = bool(settings.get("show_damage_direction_pulses", true))
	_refresh_visibility()


func get_snapshot() -> Dictionary:
	return {
		"active": _active,
		"blocked": _blocked,
		"cooldown": _last_cooldown.duplicate(true),
		"ranged": _last_ranged.duplicate(true),
		"last_result": _last_result.duplicate(true),
		"last_incoming": _last_incoming.duplicate(true),
		"direction_pulses_enabled": _show_direction_pulses,
		"direction_indicator_pool_size": _direction_indicators.size(),
		"active_damage_directions": _active_damage_directions(),
		"incoming_visible": _incoming_panel.visible if _incoming_panel != null else false,
		"incoming_text": _incoming_label.text if _incoming_label != null else "",
		"cooldown_visible": _cooldown_panel.visible if _cooldown_panel != null else false,
		"ranged_visible": _ranged_panel.visible if _ranged_panel != null else false,
		"hit_visible": _hit_panel.visible if _hit_panel != null else false,
		"ranged_text": _ranged_label.text if _ranged_label != null else "",
		"ranged_rect": _ranged_panel.get_global_rect() if _ranged_panel != null else Rect2(),
	}


func _process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	if _hit_remaining > 0.0:
		_hit_remaining = maxf(0.0, _hit_remaining - safe_delta)
		if _hit_remaining <= 0.0 and _hit_panel != null:
			_hit_panel.visible = false
	if _incoming_remaining > 0.0:
		_incoming_remaining = maxf(0.0, _incoming_remaining - safe_delta)
	for direction: String in DamageDirectionPolicy.DIRECTIONS:
		_direction_remaining[direction] = maxf(
			0.0, float(_direction_remaining.get(direction, 0.0)) - safe_delta
		)
	_refresh_visibility()
	if combat_service != null and combat_service.has_method("get_cooldown_snapshot"):
		_on_cooldown_changed(combat_service.call("get_cooldown_snapshot"))
	if ranged_combat_service != null and ranged_combat_service.has_method("get_snapshot"):
		_on_ranged_status_changed(ranged_combat_service.call("get_snapshot"))


func _exit_tree() -> void:
	_disconnect_services()


func _on_incoming_damage_resolved(result: Dictionary) -> void:
	var final_damage := maxf(0.0, float(result.get("final_damage", 0.0)))
	if final_damage <= 0.0:
		return
	_last_incoming = result.duplicate(true)
	var direction := DamageDirectionPolicy.normalize_direction(
		result.get("damage_direction", "front")
	)
	var absorbed := maxf(0.0, float(result.get("absorbed", 0.0)))
	var absorbed_text := "" if absorbed <= 0.0 else " · 护甲吸收 %.1f" % absorbed
	var source_label := DamageDirectionPolicy.localized_source_label(result.get("source", "damage"))
	_incoming_label.text = "受到 %.1f 伤害 · %s%s%s" % [
		final_damage, DamageDirectionPolicy.localized_label(direction), source_label, absorbed_text,
	]
	_incoming_label.modulate = Tokens.color(Tokens.COLOR_DANGER)
	_incoming_remaining = INCOMING_TEXT_SECONDS
	_direction_remaining[direction] = DIRECTION_PULSE_SECONDS
	_refresh_visibility()


func _on_attack_resolved(result: Dictionary) -> void:
	if str(result.get("status", "")) != "hit":
		return
	_last_result = result.duplicate(true)
	var target_name := str(result.get("target_name", "目标"))
	var damage := float(result.get("final_damage", result.get("damage", 0.0)))
	var pellet_hits := int(result.get("pellet_hits", 0))
	var suffix := ""
	if pellet_hits > 1:
		suffix = "  ·  %d 弹丸" % pellet_hits
	_hit_label.text = (
		"击败 %s%s" % [target_name, suffix]
		if bool(result.get("defeated", false))
		else "命中 %s  ·  %.1f%s" % [target_name, damage, suffix]
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
	var action_kind := str(snapshot.get("action_kind", "charge"))
	if action_kind == "firearm":
		_update_firearm_status(snapshot)
	else:
		_update_charge_status(snapshot)
	_refresh_visibility()


func _update_charge_status(snapshot: Dictionary) -> void:
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


func _update_firearm_status(snapshot: Dictionary) -> void:
	var weapon_name := str(snapshot.get("weapon_display_name", "枪械"))
	var loaded := int(snapshot.get("magazine_rounds", 0))
	var capacity := int(snapshot.get("magazine_capacity", 0))
	var reserve := int(snapshot.get("reserve_ammo_count", 0))
	var ratio := 1.0
	var label := weapon_name
	if bool(snapshot.get("reloading", false)):
		ratio = clampf(float(snapshot.get("reload_ratio", 0.0)), 0.0, 1.0)
		label = "%s 换弹  %d%%" % [weapon_name, int(round(ratio * 100.0))]
	elif not bool(snapshot.get("cooldown_ready", true)):
		ratio = clampf(float(snapshot.get("cooldown_ready_ratio", 0.0)), 0.0, 1.0)
		label = "%s 射击恢复  %d%%" % [weapon_name, int(round(ratio * 100.0))]
	_ranged_bar.value = ratio
	_ranged_label.text = "%s  ·  弹匣 %d/%d  ·  备用 %d" % [
		label, loaded, capacity, reserve,
	]


func _on_ranged_shot_rejected(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var reason := str(result.get("reason", "rejected"))
	var text: String = str({
		"no_ammo": "没有箭矢",
		"undercharged": "蓄力不足",
		"cooldown": "武器尚未准备好",
		"projectile_capacity": "飞行箭矢已达上限",
		"empty_magazine": "弹匣已空，按 R 或左肩键换弹",
		"reloading": "正在换弹",
		"already_reloading": "已经在换弹",
		"no_reserve_ammo": "没有备用弹药",
		"magazine_full": "弹匣已满",
	}.get(reason, "远程攻击未生效"))
	_show_transient_feedback(text, Tokens.color(Tokens.COLOR_WARNING), 0.65)


func _on_ranged_shot_fired(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	_refresh_visibility()


func _on_reload_event(result: Dictionary) -> void:
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
	if _incoming_panel != null:
		_incoming_panel.visible = can_show and _incoming_remaining > 0.0
	for direction: String in DamageDirectionPolicy.DIRECTIONS:
		var indicator: Label = _direction_indicators.get(direction) as Label
		if indicator != null:
			indicator.visible = (
				can_show
				and _show_direction_pulses
				and float(_direction_remaining.get(direction, 0.0)) > 0.0
			)


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
	panel.offset_left = -145.0
	panel.offset_right = 145.0
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
	bar.custom_minimum_size = Vector2(260.0, 8.0)
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
	_hit_panel.offset_left = -160.0
	_hit_panel.offset_right = 160.0
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


func _build_incoming_panel() -> void:
	_incoming_panel = PanelContainer.new()
	_incoming_panel.name = "IncomingDamagePanel"
	_incoming_panel.anchor_left = 0.5
	_incoming_panel.anchor_right = 0.5
	_incoming_panel.anchor_top = 0.0
	_incoming_panel.anchor_bottom = 0.0
	_incoming_panel.offset_left = -220.0
	_incoming_panel.offset_right = 220.0
	_incoming_panel.offset_top = 82.0
	_incoming_panel.offset_bottom = 122.0
	_incoming_panel.add_theme_stylebox_override(
		"panel", Tokens.bevel_style("#220907D9", Tokens.COLOR_DANGER, 2, 6.0)
	)
	add_child(_incoming_panel)
	_incoming_label = Label.new()
	_incoming_label.name = "IncomingDamageText"
	_incoming_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_incoming_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_incoming_label.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	_incoming_panel.add_child(_incoming_label)


func _build_direction_indicators() -> void:
	for direction: String in DamageDirectionPolicy.DIRECTIONS:
		var indicator := Label.new()
		indicator.name = "DamageDirection%s" % direction.capitalize()
		indicator.text = str({
			"front":"▼", "right":"◀", "rear":"▲", "left":"▶",
		}.get(direction, "◆"))
		indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		indicator.add_theme_font_size_override("font_size", 42)
		indicator.modulate = Tokens.color(Tokens.COLOR_DANGER)
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_direction_indicator_layout(indicator, direction)
		add_child(indicator)
		_direction_indicators[direction] = indicator


func _apply_direction_indicator_layout(indicator: Label, direction: String) -> void:
	match direction:
		"front":
			indicator.anchor_left = 0.5
			indicator.anchor_right = 0.5
			indicator.offset_left = -40.0
			indicator.offset_right = 40.0
			indicator.offset_top = 132.0
			indicator.offset_bottom = 188.0
		"right":
			indicator.anchor_left = 1.0
			indicator.anchor_right = 1.0
			indicator.anchor_top = 0.5
			indicator.anchor_bottom = 0.5
			indicator.offset_left = -96.0
			indicator.offset_right = -16.0
			indicator.offset_top = -30.0
			indicator.offset_bottom = 30.0
		"rear":
			indicator.anchor_left = 0.5
			indicator.anchor_right = 0.5
			indicator.anchor_top = 1.0
			indicator.anchor_bottom = 1.0
			indicator.offset_left = -40.0
			indicator.offset_right = 40.0
			indicator.offset_top = -116.0
			indicator.offset_bottom = -56.0
		_:
			indicator.anchor_top = 0.5
			indicator.anchor_bottom = 0.5
			indicator.offset_left = 16.0
			indicator.offset_right = 96.0
			indicator.offset_top = -30.0
			indicator.offset_bottom = 30.0


func _active_damage_directions() -> Array[String]:
	var active_directions: Array[String] = []
	for direction: String in DamageDirectionPolicy.DIRECTIONS:
		if float(_direction_remaining.get(direction, 0.0)) > 0.0:
			active_directions.append(direction)
	return active_directions


func _disconnect_services() -> void:
	if combat_service != null:
		for binding: Array in [
			["outgoing_attack_resolved", "_on_attack_resolved"],
			["incoming_damage_resolved", "_on_incoming_damage_resolved"],
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
			["reload_started", "_on_reload_event"],
			["reload_completed", "_on_reload_event"],
			["reload_cancelled", "_on_reload_event"],
		]:
			var signal_name := str(binding[0])
			var callback := Callable(self, str(binding[1]))
			if ranged_combat_service.has_signal(signal_name) and ranged_combat_service.is_connected(signal_name, callback):
				ranged_combat_service.disconnect(signal_name, callback)
	ranged_combat_service = null
