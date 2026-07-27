class_name ExplorationJournalPanel
extends PanelContainer

signal panel_closed

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const JournalPolicyScript = preload("res://src/exploration/exploration_journal_policy.gd")

var journal_service: Node
var reward_service: Node
var _summary_label: Label
var _milestone_box: VBoxContainer
var _records_box: VBoxContainer
var _milestone_scroll: ScrollContainer
var _record_scroll: ScrollContainer
var _milestone_panel: PanelContainer
var _record_panel: PanelContainer
var _summary_text := ""
var _milestone_texts: Array[String] = []
var _record_texts: Array[String] = []
var _reward_statuses: Dictionary = {}
var _claim_buttons: Dictionary = {}


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(0, 0)
	_build_ui()
	refresh()


func setup(p_journal_service: Node, p_reward_service: Node = null) -> void:
	_disconnect_journal()
	_disconnect_rewards()
	journal_service = p_journal_service
	reward_service = p_reward_service
	if journal_service != null and journal_service.has_signal("journal_changed"):
		journal_service.connect("journal_changed", Callable(self, "_on_journal_changed"))
	if reward_service != null and reward_service.has_signal("rewards_changed"):
		reward_service.connect("rewards_changed", Callable(self, "_on_rewards_changed"))
	refresh()


func refresh() -> void:
	var snapshot: Dictionary = {}
	if journal_service != null and journal_service.has_method("get_snapshot"):
		var raw_snapshot: Variant = journal_service.call("get_snapshot")
		if raw_snapshot is Dictionary:
			snapshot = raw_snapshot
	var reward_snapshot: Dictionary = {}
	if reward_service != null and reward_service.has_method("get_snapshot"):
		var raw_rewards: Variant = reward_service.call("get_snapshot")
		if raw_rewards is Dictionary:
			reward_snapshot = raw_rewards
	_render_summary(snapshot, reward_snapshot)
	_render_milestones(snapshot, reward_snapshot)
	_render_records(snapshot)


func get_summary_text() -> String:
	return _summary_text


func get_milestone_texts() -> Array[String]:
	return _milestone_texts.duplicate()


func get_record_texts() -> Array[String]:
	return _record_texts.duplicate()


func get_reward_status(milestone_id: String) -> String:
	return str(_reward_statuses.get(milestone_id, ""))


func get_claim_button(milestone_id: String) -> Button:
	var raw_button: Variant = _claim_buttons.get(milestone_id)
	return raw_button as Button if raw_button is Button and is_instance_valid(raw_button) else null


func get_layout_rects() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"milestones": _milestone_box.get_global_rect() if _milestone_box != null else Rect2(),
		"records": _records_box.get_global_rect() if _records_box != null else Rect2(),
		"milestone_scroll": (
			_milestone_scroll.get_global_rect() if _milestone_scroll != null else Rect2()
		),
		"record_scroll": _record_scroll.get_global_rect() if _record_scroll != null else Rect2(),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("探索日志"))
	heading.add_child(UiKit.make_title("探索日志"))
	heading.add_child(UiKit.make_subtitle("保留区块级趋势与里程碑，不暴露矿物或危险的精确坐标。"))
	var close_button := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(132, Tokens.CONTROL_HEIGHT_MD)
	)
	close_button.text = "关闭 [J]"
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)

	_summary_label = Label.new()
	_summary_label.name = "ExplorationSummary"
	_summary_label.theme_type_variation = "CaptionLabel"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.custom_minimum_size.y = 48
	_summary_label.add_theme_stylebox_override(
		"normal",
		Tokens.bevel_style(
			"#B0B0B0",
			"#7A7A7A",
			2,
			Tokens.SPACE_SM
		)
	)
	root.add_child(_summary_label)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(body)

	_milestone_panel = UiKit.make_card("CardPanel", Vector2(330, 0))
	_milestone_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_milestone_panel)
	var milestone_root := VBoxContainer.new()
	milestone_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_milestone_panel.add_child(milestone_root)
	var milestone_header := HBoxContainer.new()
	milestone_root.add_child(milestone_header)
	var milestone_title := Label.new()
	milestone_title.text = "里程碑与奖励"
	milestone_title.theme_type_variation = "SectionTitle"
	milestone_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	milestone_header.add_child(milestone_title)
	milestone_header.add_child(UiKit.make_badge("8 项", "warm"))
	_milestone_scroll = ScrollContainer.new()
	_milestone_scroll.name = "MilestoneScroll"
	_milestone_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_milestone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_milestone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_milestone_scroll.custom_minimum_size.y = 270
	milestone_root.add_child(_milestone_scroll)
	_milestone_box = VBoxContainer.new()
	_milestone_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_milestone_box.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_milestone_scroll.add_child(_milestone_box)

	_record_panel = UiKit.make_card("InsetPanel")
	_record_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_record_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_record_panel)
	var record_root := VBoxContainer.new()
	record_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_record_panel.add_child(record_root)
	var record_header := HBoxContainer.new()
	record_root.add_child(record_header)
	var record_title := Label.new()
	record_title.text = "最近发现"
	record_title.theme_type_variation = "SectionTitle"
	record_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_header.add_child(record_title)
	record_header.add_child(UiKit.make_badge("区块级趋势", "info"))
	_record_scroll = ScrollContainer.new()
	_record_scroll.name = "RecordScroll"
	_record_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_record_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_record_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_record_scroll.custom_minimum_size.y = 270
	record_root.add_child(_record_scroll)
	_records_box = VBoxContainer.new()
	_records_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_records_box.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_record_scroll.add_child(_records_box)

	var hint := Label.new()
	hint.text = "奖励领取是原子事务；背包空间不足时继续保留。更早记录仍存在存档中。"
	hint.theme_type_variation = "SubduedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)


func _render_summary(snapshot: Dictionary, reward_snapshot: Dictionary) -> void:
	var records := int(snapshot.get("record_count", 0))
	var chunks := int(snapshot.get("unique_chunk_count", 0))
	var completed := int(snapshot.get("completed_milestone_count", 0))
	var milestone_count := int(snapshot.get("milestone_count", 0))
	var highest_danger := int(snapshot.get("highest_danger_score", 0))
	var claimable := int(reward_snapshot.get("claimable_count", 0))
	var claimed := int(reward_snapshot.get("claimed_count", 0))
	_summary_text = "已记录 %d 条发现 · %d 个区块 · 里程碑 %d / %d · 奖励已领 %d / 待领 %d · 最高危险 %d / 100" % [
		records,
		chunks,
		completed,
		milestone_count,
		claimed,
		claimable,
		highest_danger,
	]
	if records == 0:
		_summary_text += "\n手持简易探矿仪，在合适岩层中按鼠标右键记录第一处发现。"
	_summary_label.text = _summary_text


func _render_milestones(snapshot: Dictionary, reward_snapshot: Dictionary) -> void:
	_clear_container(_milestone_box)
	_milestone_texts.clear()
	_reward_statuses.clear()
	_claim_buttons.clear()
	var reward_by_id := _reward_by_milestone(reward_snapshot)
	var raw_milestones: Variant = snapshot.get("milestones", [])
	if raw_milestones is not Array or raw_milestones.is_empty():
		_add_empty_label(_milestone_box, "暂无里程碑数据")
		return
	for raw_milestone: Variant in raw_milestones:
		if raw_milestone is not Dictionary:
			continue
		var milestone: Dictionary = raw_milestone
		var milestone_id := str(milestone.get("id", ""))
		var reward: Dictionary = reward_by_id.get(milestone_id, {})
		var completed := bool(milestone.get("completed", false))
		var progress := int(milestone.get("progress", 0))
		var target := maxi(1, int(milestone.get("target", 1)))
		var reward_status := str(reward.get("status", ""))
		var status := "完成" if completed else "%d / %d" % [progress, target]
		if reward_status == "claimable":
			status = "可领取"
		elif reward_status == "claimed":
			status = "已领取"
		_reward_statuses[milestone_id] = reward_status
		var reward_label := str(reward.get("reward_label", ""))
		var text := "%s %s · %s\n%s%s" % [
			"✓" if completed else "○",
			str(milestone.get("name", "里程碑")),
			status,
			str(milestone.get("description", "")),
			"\n奖励：%s" % reward_label if not reward_label.is_empty() else "",
		]
		_milestone_texts.append(text)
		var tone := "success" if reward_status == "claimed" else (
			"warm" if reward_status == "claimable" else "info"
		)
		var card := UiKit.make_card("CardPanel")
		card.add_theme_stylebox_override(
			"panel",
			Tokens.bevel_style(
				"#BCBCBC",
				Tokens.tone_border(tone),
				2,
				Tokens.SPACE_SM
			)
		)
		_milestone_box.add_child(card)
		var card_root := VBoxContainer.new()
		card_root.add_theme_constant_override("separation", Tokens.SPACE_XS)
		card.add_child(card_root)
		var label := Label.new()
		label.text = text
		label.theme_type_variation = "CaptionLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if reward_status == "claimed":
			label.add_theme_color_override("font_color", Tokens.color(Tokens.COLOR_SUCCESS))
		card_root.add_child(label)
		if not reward.is_empty():
			var claim_button := UiKit.style_button(
				Button.new(),
				"PrimaryButton" if reward_status == "claimable" else "GhostButton",
				Vector2(0, Tokens.CONTROL_HEIGHT_SM)
			)
			claim_button.text = (
				"领取奖励"
				if reward_status == "claimable"
				else ("已领取" if reward_status == "claimed" else "未解锁")
			)
			claim_button.disabled = reward_status != "claimable"
			claim_button.pressed.connect(Callable(self, "_claim_reward").bind(milestone_id))
			card_root.add_child(claim_button)
			_claim_buttons[milestone_id] = claim_button


func _render_records(snapshot: Dictionary) -> void:
	_clear_container(_records_box)
	_record_texts.clear()
	var raw_records: Variant = snapshot.get("records", [])
	if raw_records is not Array or raw_records.is_empty():
		_add_empty_label(_records_box, "还没有探索发现。")
		return
	for raw_record: Variant in raw_records:
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record
		var text := _record_text(record)
		_record_texts.append(text)
		var danger_score := clampi(int(record.get("danger_score", 0)), 0, 100)
		var card := UiKit.make_card("CardPanel")
		card.add_theme_stylebox_override(
			"panel",
			Tokens.bevel_style(
				"#BCBCBC",
				Tokens.COLOR_DANGER if danger_score >= 70 else "#7A7A7A",
				2,
				Tokens.SPACE_MD
			)
		)
		_records_box.add_child(card)
		var label := Label.new()
		label.text = text
		label.theme_type_variation = "CaptionLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
	if bool(snapshot.get("has_more_records", false)):
		_add_empty_label(_records_box, "更早记录仍保存在存档中；面板仅显示最近条目。")


func _record_text(record: Dictionary) -> String:
	var raw_chunk: Variant = record.get("chunk", [])
	var chunk_text := "未知"
	if raw_chunk is Array and raw_chunk.size() >= 2:
		chunk_text = "%d, %d" % [int(raw_chunk[0]), int(raw_chunk[1])]
	var sequence := maxi(0, int(record.get("sequence", 0)))
	var day := maxi(1, int(record.get("world_day", 1)))
	var time_of_day := fposmod(float(record.get("world_time", 0.0)), 24.0)
	var hour := int(floor(time_of_day))
	var minute := int(floor(fmod(time_of_day, 1.0) * 60.0))
	var headline := "#%d · 第 %d 天 %02d:%02d · %s · 区块 %s" % [
		sequence,
		day,
		hour,
		minute,
		JournalPolicyScript.map_label(str(record.get("profile_id", ""))),
		chunk_text,
	]
	var detail := "%s · %s · 主信号：%s · 危险：%s %d/100" % [
		str(record.get("depth_label", "未知深度")),
		str(record.get("density_label", "未知密度")),
		str(record.get("dominant_label", "无明显矿物")),
		str(record.get("danger_label", "未知")),
		clampi(int(record.get("danger_score", 0)), 0, 100),
	]
	var reasons := _reason_text(record.get("danger_reasons", []))
	return "%s\n%s%s" % [
		headline,
		detail,
		"\n主要风险：%s" % reasons if not reasons.is_empty() else "",
	]


func _reward_by_milestone(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_rewards: Variant = snapshot.get("rewards", [])
	if raw_rewards is not Array:
		return result
	for raw_reward: Variant in raw_rewards:
		if raw_reward is not Dictionary:
			continue
		var milestone_id := str(raw_reward.get("milestone_id", ""))
		if not milestone_id.is_empty():
			result[milestone_id] = raw_reward.duplicate(true)
	return result


func _claim_reward(milestone_id: String) -> void:
	if reward_service != null and reward_service.has_method("claim"):
		reward_service.call("claim", milestone_id)


func _reason_text(raw_reasons: Variant) -> String:
	if raw_reasons is not Array:
		return ""
	var result := ""
	for raw_reason: Variant in raw_reasons:
		var reason := str(raw_reason).strip_edges()
		if reason.is_empty():
			continue
		result += (" · " if not result.is_empty() else "") + reason
		if result.length() >= 120:
			break
	return result


func _add_empty_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "MutedLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(label)


func _clear_container(container: VBoxContainer) -> void:
	if container == null:
		return
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_journal_changed(_snapshot: Dictionary) -> void:
	refresh()


func _on_rewards_changed(_snapshot: Dictionary) -> void:
	refresh()


func _disconnect_journal() -> void:
	if journal_service == null or not journal_service.has_signal("journal_changed"):
		return
	var callback := Callable(self, "_on_journal_changed")
	if journal_service.is_connected("journal_changed", callback):
		journal_service.disconnect("journal_changed", callback)


func _disconnect_rewards() -> void:
	if reward_service == null or not reward_service.has_signal("rewards_changed"):
		return
	var callback := Callable(self, "_on_rewards_changed")
	if reward_service.is_connected("rewards_changed", callback):
		reward_service.disconnect("rewards_changed", callback)


func _exit_tree() -> void:
	_disconnect_journal()
	_disconnect_rewards()
