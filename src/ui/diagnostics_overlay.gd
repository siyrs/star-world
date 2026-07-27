class_name DiagnosticsOverlay
extends CanvasLayer

signal overlay_visibility_changed(visible: bool)

const Actions = preload("res://src/input/gameplay_input_actions.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")
const HealthFormatter = preload(
	"res://src/diagnostics/runtime_health_report_formatter.gd"
)
const PASSTHROUGH_MOUSE_FILTER := Control.MOUSE_FILTER_IGNORE

var telemetry: Node
var gameplay_input: Node
var _panel: PanelContainer
var _label: Label
var _health_label: Label
var _status_badge: Label
var _runtime_card: PanelContainer
var _operations_card: PanelContainer
var _overlay_visible := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	Actions.ensure_default_bindings()
	_build_ui()
	set_overlay_visible(false)
	UiInputPolicy.make_passthrough_tree(self)


func setup(p_telemetry: Node, p_gameplay_input: Node = null) -> void:
	_disconnect_telemetry()
	telemetry = p_telemetry
	gameplay_input = p_gameplay_input
	if telemetry != null and telemetry.has_signal("snapshot_updated"):
		var callback := Callable(self, "_on_snapshot_updated")
		if not telemetry.is_connected("snapshot_updated", callback):
			telemetry.connect("snapshot_updated", callback)
		if telemetry.has_method("get_latest_snapshot"):
			_on_snapshot_updated(telemetry.call("get_latest_snapshot"))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if _event_toggles_diagnostics(event):
		set_overlay_visible(not _overlay_visible)
		get_viewport().set_input_as_handled()


func set_overlay_visible(value: bool) -> void:
	_overlay_visible = value
	visible = value
	overlay_visibility_changed.emit(_overlay_visible)
	if value and telemetry != null and telemetry.has_method("sample_now"):
		_on_snapshot_updated(telemetry.call("sample_now"))


func toggle() -> void:
	set_overlay_visible(not _overlay_visible)


func is_overlay_visible() -> bool:
	return _overlay_visible


func get_display_text() -> String:
	var sections: Array[String] = []
	if _label != null:
		sections.append(_label.text)
	if _health_label != null:
		sections.append(_health_label.text)
	return "\n\n".join(sections)


func get_panel_rect() -> Rect2:
	return _panel.get_global_rect() if _panel != null else Rect2()


func get_visual_snapshot() -> Dictionary:
	return {
		"panel": get_panel_rect(),
		"runtime_card": _runtime_card.get_global_rect() if _runtime_card != null else Rect2(),
		"operations_card": (
			_operations_card.get_global_rect() if _operations_card != null else Rect2()
		),
		"status_badge": _status_badge.text if _status_badge != null else "",
		"visible": _overlay_visible,
	}


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_panel = PanelContainer.new()
	_panel.name = "DiagnosticsDashboard"
	_panel.theme = ThemeFactory.create_theme()
	_panel.theme_type_variation = "DiagnosticsBackdrop"
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 18.0
	_panel.offset_right = -18.0
	_panel.offset_top = 18.0
	_panel.offset_bottom = -18.0
	root.add_child(_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_MD)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	content.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("LIVE RUNTIME TELEMETRY"))
	var title := UiKit.make_title("运行诊断中心")
	heading.add_child(title)
	var subtitle := UiKit.make_subtitle("F3 关闭 · 只读采样 · 不修改世界、存档或领域状态")
	heading.add_child(subtitle)
	_status_badge = UiKit.make_badge("等待采样", "info")
	header.add_child(_status_badge)

	content.add_child(UiKit.make_divider())
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", Tokens.SPACE_MD)
	content.add_child(columns)

	_runtime_card = _create_diagnostics_card(
		columns,
		"实时运行",
		"帧、Chunk、输入、玩家与流式策略",
		"F3 运行诊断\n等待采样…"
	)
	_label = _runtime_card.get_meta("content_label") as Label
	_operations_card = _create_diagnostics_card(
		columns,
		"运行与保存健康",
		"领域预算、存档、目录与检查点时间线",
		"F3 运行与保存健康\n等待领域快照…"
	)
	_health_label = _operations_card.get_meta("content_label") as Label


func _create_diagnostics_card(
	parent: Control,
	title: String,
	subtitle: String,
	initial_text: String
) -> PanelContainer:
	var card := UiKit.make_card("DiagnosticsCard")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var card_root := VBoxContainer.new()
	card_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	card.add_child(card_root)
	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = "SectionTitle"
	card_root.add_child(title_label)
	var subtitle_label := UiKit.make_subtitle(subtitle)
	card_root.add_child(subtitle_label)
	card_root.add_child(UiKit.make_divider())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_root.add_child(scroll)
	var label := _create_column_label(initial_text)
	scroll.add_child(label)
	card.set_meta("content_label", label)
	return card


func _create_column_label(initial_text: String) -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = PASSTHROUGH_MOUSE_FILTER
	label.focus_mode = Control.FOCUS_NONE
	label.theme_type_variation = "CaptionLabel"
	label.add_theme_font_size_override("font_size", 13)
	label.text = initial_text
	return label


func _event_toggles_diagnostics(event: InputEvent) -> bool:
	if gameplay_input != null and gameplay_input.has_method("event_toggles_diagnostics"):
		return bool(gameplay_input.call("event_toggles_diagnostics", event))
	return event.is_action_pressed(Actions.TOGGLE_DIAGNOSTICS)


func _on_snapshot_updated(snapshot: Dictionary) -> void:
	if _label != null:
		_label.text = _format_snapshot(snapshot)
	if _health_label != null:
		var operations: Dictionary = (
			snapshot.get("operations", {})
			if snapshot.get("operations", {}) is Dictionary
			else {}
		)
		_health_label.text = HealthFormatter.format(operations)
	var health: Dictionary = snapshot.get("health", {})
	var status := str(health.get("status", "healthy"))
	if _status_badge != null:
		_status_badge.text = {
			"healthy":"运行正常",
			"warning":"存在告警",
			"critical":"严重压力",
		}.get(status, status)
		_status_badge.add_theme_color_override(
			"font_color", Tokens.severity_color(status)
		)
		_status_badge.add_theme_stylebox_override(
			"normal",
			Tokens.bevel_style(
				"#100C07EE",
				_color_to_hex(Tokens.severity_color(status)),
				2,
				7.0
			)
		)


func _format_snapshot(snapshot: Dictionary) -> String:
	var health: Dictionary = snapshot.get("health", {})
	var status: String = str(health.get("status", "healthy"))
	var status_labels: Dictionary = {
		"healthy": "正常",
		"warning": "警告",
		"critical": "严重",
	}
	var status_text: String = str(status_labels.get(status, status))
	var streaming: Dictionary = snapshot.get("streaming", {})
	var adaptive: Dictionary = snapshot.get("adaptive_streaming", {})
	var adaptive_profile: Dictionary = adaptive.get("profile", {})
	var adaptive_state := "关闭"
	if bool(adaptive.get("enabled", false)):
		adaptive_state = (
			_adaptive_level_name(str(adaptive.get("level_name", "balanced")))
			if bool(adaptive.get("attached", false))
			else "等待世界"
		)
	var position_text := "未连接"
	var player_position: Array = snapshot.get("player_position", [])
	if player_position.size() >= 3:
		position_text = "%.1f, %.1f, %.1f" % [
			float(player_position[0]), float(player_position[1]), float(player_position[2])
		]
	var velocity_text := "未连接"
	var player_velocity: Array = snapshot.get("player_velocity", [])
	if player_velocity.size() >= 3:
		velocity_text = "%.2f, %.2f, %.2f" % [
			float(player_velocity[0]), float(player_velocity[1]), float(player_velocity[2])
		]
	var input_status: Dictionary = snapshot.get("gameplay_input", {})
	var movement: Vector2 = input_status.get("movement", Vector2.ZERO)
	var last_nonzero: Vector2 = input_status.get("last_nonzero_movement", Vector2.ZERO)
	var lines: Array[String] = [
		"F3 运行诊断  |  状态：%s" % status_text,
		"FPS %.0f  |  帧 %.1f ms（峰值 %.1f）| 卡顿 %d" % [
			float(snapshot.get("fps", 0.0)),
			float(snapshot.get("frame_ms_avg", 0.0)),
			float(snapshot.get("frame_ms_peak", 0.0)),
			int(snapshot.get("stutter_count", 0)),
		],
		"区块 已加载 %d  构建中 %d  排队 %d  预算耗时 %.2f ms" % [
			int(streaming.get("loaded", 0)),
			int(streaming.get("building", 0)),
			int(streaming.get("pending", 0)),
			float(streaming.get("last_work_usec", 0)) / 1000.0,
		],
		"流式策略 %s  |  预算 %.1f ms / %d 格 / %d 步  |  调整 %d" % [
			adaptive_state,
			float(adaptive_profile.get("budget_ms", 0.0)),
			int(adaptive_profile.get("cells_per_step", 0)),
			int(adaptive_profile.get("max_steps_per_frame", 0)),
			int(adaptive.get("change_count", 0)),
		],
		"策略原因：%s" % str(adaptive.get("last_reason", "无")),
		"节点 %d  |  内存 %.1f MiB  |  Draw calls %d" % [
			int(snapshot.get("node_count", 0)),
			float(snapshot.get("memory_mib", 0.0)),
			int(snapshot.get("draw_calls", 0)),
		],
		"生物 %d  |  掉落物 %d" % [
			int(snapshot.get("creature_count", 0)), int(snapshot.get("pickup_count", 0))
		],
		"输入 %s  |  鼠标 %s  |  暂停 %s" % [
			str(snapshot.get("input_context", "unknown")),
			_mouse_mode_name(int(snapshot.get("mouse_mode", Input.MOUSE_MODE_VISIBLE))),
			"是" if bool(snapshot.get("paused", false)) else "否",
		],
		"角色输入 %s  |  物理更新 %s" % [
			"启用" if bool(snapshot.get("player_input_enabled", false)) else "禁用",
			"运行" if bool(snapshot.get("player_physics_processing", false)) else "停止",
		],
		"输入服务 %s  |  当前向量 %.1f, %.1f  |  最近有效 %.1f, %.1f" % [
			"激活" if bool(input_status.get("active", false)) else "未激活",
			movement.x,
			movement.y,
			last_nonzero.x,
			last_nonzero.y,
		],
		"最近按键：%s  |  W动作 %s  |  W物理键 %s" % [
			str(input_status.get("last_key_event", "无")),
			"按下" if bool(input_status.get("forward_action_pressed", false)) else "松开",
			"按下" if bool(input_status.get("w_key_pressed", false)) else "松开",
		],
		"玩家位置：%s" % position_text,
		"玩家速度：%s  |  着地 %s" % [
			velocity_text,
			"是" if bool(snapshot.get("player_on_floor", false)) else "否",
		],
		"碰撞：%s" % (
			"无"
			if snapshot.get("player_collisions", []).is_empty()
			else "；".join(snapshot.get("player_collisions", []))
		),
	]
	var issues: Array = health.get("issues", [])
	if issues.is_empty():
		lines.append("健康检查：未发现超阈值指标")
	else:
		lines.append("健康检查：")
		for issue in issues:
			lines.append("• %s" % str(issue))
	return "\n".join(lines)


func _adaptive_level_name(level_name: String) -> String:
	return str({
		"conservative": "保守",
		"guarded": "受限",
		"balanced": "均衡",
		"throughput": "吞吐",
	}.get(level_name, level_name))


func _mouse_mode_name(mode: int) -> String:
	match mode:
		Input.MOUSE_MODE_CAPTURED:
			return "捕获"
		Input.MOUSE_MODE_CONFINED:
			return "限制"
		Input.MOUSE_MODE_CONFINED_HIDDEN:
			return "限制隐藏"
		Input.MOUSE_MODE_HIDDEN:
			return "隐藏"
		_:
			return "可见"


func _disconnect_telemetry() -> void:
	if telemetry == null or not telemetry.has_signal("snapshot_updated"):
		return
	var callback := Callable(self, "_on_snapshot_updated")
	if telemetry.is_connected("snapshot_updated", callback):
		telemetry.disconnect("snapshot_updated", callback)


func _color_to_hex(value: Color) -> String:
	return "#%s" % value.to_html(true)
