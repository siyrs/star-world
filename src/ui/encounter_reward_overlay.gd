class_name EncounterRewardOverlay
extends Control

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const DISPLAY_SECONDS := 4.0

var reward_service: Node
var _panel: PanelContainer
var _title_label: Label
var _detail_label: Label
var _remaining := 0.0
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ThemeFactory.create_theme()
	_build_panel()
	_refresh_visibility()


func setup(p_reward_service: Node) -> void:
	_disconnect_service()
	reward_service = p_reward_service
	if reward_service == null:
		return
	for signal_name: String in ["reward_granted", "reward_pending", "reward_rejected"]:
		if not reward_service.has_signal(signal_name):
			continue
		var callback := Callable(self, "_on_reward_event").bind(signal_name)
		if not reward_service.is_connected(signal_name, callback):
			reward_service.connect(signal_name, callback)


func clear() -> void:
	_remaining = 0.0
	_last_result.clear()
	if _title_label != null:
		_title_label.text = ""
	if _detail_label != null:
		_detail_label.text = ""
	_refresh_visibility()


func get_snapshot() -> Dictionary:
	return {
		"visible":_panel.visible if _panel != null else false,
		"remaining_seconds":_remaining,
		"title":_title_label.text if _title_label != null else "",
		"detail":_detail_label.text if _detail_label != null else "",
		"rect":_panel.get_global_rect() if _panel != null else Rect2(),
		"last_result":_last_result.duplicate(true),
	}


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - maxf(0.0, delta))
	_refresh_visibility()


func _on_reward_event(result: Dictionary, signal_name: String) -> void:
	_last_result = result.duplicate(true)
	if signal_name == "reward_granted":
		_show_granted(result)
	elif signal_name == "reward_pending":
		_show_pending(result)
	else:
		_show_rejected(result)


func _show_granted(result: Dictionary) -> void:
	_title_label.text = "%s已领取" % str(result.get("display_name", "遭遇补给"))
	_title_label.modulate = Tokens.color(Tokens.COLOR_SUCCESS)
	var labels: Array = result.get("reward_labels", [])
	var reward_text := " · ".join(PackedStringArray(labels)) if not labels.is_empty() else "奖励已写入背包"
	var shot_count := int(result.get("shot_count", 0))
	var net_ammo := _format_net_ammo(result.get("net_ammo", {}))
	var efficient_text := " · 高效加成" if bool(result.get("efficient", false)) else ""
	_detail_label.text = "%s\n消耗 %d 发%s%s" % [reward_text, shot_count, net_ammo, efficient_text]
	_remaining = DISPLAY_SECONDS
	_refresh_visibility()


func _show_pending(result: Dictionary) -> void:
	_title_label.text = "补给等待领取"
	_title_label.modulate = Tokens.color(Tokens.COLOR_WARNING)
	_detail_label.text = "%s\n背包空间不足，腾出空间后自动原子领取" % str(
		result.get("display_name", "遭遇补给")
	)
	_remaining = DISPLAY_SECONDS
	_refresh_visibility()


func _show_rejected(result: Dictionary) -> void:
	var reason := str(result.get("reason", "rejected"))
	if reason in ["duplicate_completion", "duplicate_encounter_start"]:
		return
	_title_label.text = "补给未领取"
	_title_label.modulate = Tokens.color(Tokens.COLOR_WARNING)
	_detail_label.text = str({
		"members_not_defeated":"成员未全部击败，本次不发放小队奖励",
		"reward_profile_missing":"该遭遇没有奖励配置",
		"pending_capacity":"待领取补给已达到安全上限",
		"inventory_unavailable":"背包服务暂不可用",
		"finished_ammunition_reward":"奖励配置包含成品弹药，已被安全策略拒绝",
		"unsupported_reward_item":"奖励配置包含非制造输入，已被安全策略拒绝",
	}.get(reason, "奖励事务失败：%s" % reason))
	_remaining = DISPLAY_SECONDS
	_refresh_visibility()


func _format_net_ammo(raw_net: Variant) -> String:
	if raw_net is not Dictionary or raw_net.is_empty():
		return ""
	var parts: Array[String] = []
	for item_id: String in ["arrow", "light_round", "shotgun_shell"]:
		var value := int(raw_net.get(item_id, 0))
		if value == 0:
			continue
		var display_name := str({
			"arrow":"箭矢",
			"light_round":"轻型弹",
			"shotgun_shell":"霰弹",
		}.get(item_id, item_id))
		parts.append("%s%+d" % [display_name, value])
	return " · 净弹药 %s" % " / ".join(PackedStringArray(parts)) if not parts.is_empty() else ""


func _refresh_visibility() -> void:
	if _panel != null:
		_panel.visible = _remaining > 0.0


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "EncounterRewardPanel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -348.0
	_panel.offset_right = -20.0
	_panel.offset_top = 112.0
	_panel.offset_bottom = 196.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#100C07E8", Tokens.COLOR_BORDER_STRONG, 2, 7.0)
	)
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	_panel.add_child(content)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", Tokens.FONT_BODY)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_title_label)
	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_detail_label)


func _disconnect_service() -> void:
	if reward_service == null or not is_instance_valid(reward_service):
		return
	for signal_name: String in ["reward_granted", "reward_pending", "reward_rejected"]:
		var callback := Callable(self, "_on_reward_event").bind(signal_name)
		if reward_service.has_signal(signal_name) and reward_service.is_connected(signal_name, callback):
			reward_service.disconnect(signal_name, callback)


func _exit_tree() -> void:
	_disconnect_service()
