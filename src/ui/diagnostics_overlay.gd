class_name DiagnosticsOverlay
extends CanvasLayer

signal overlay_visibility_changed(visible: bool)

const Actions = preload("res://src/input/gameplay_input_actions.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")

var telemetry: Node
var gameplay_input: Node
var _panel: PanelContainer
var _label: Label
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
	return _label.text if _label != null else ""


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_panel = PanelContainer.new()
	_panel.theme = ThemeFactory.create_theme()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -570.0
	_panel.offset_right = -18.0
	_panel.offset_top = 18.0
	_panel.offset_bottom = 330.0
	root.add_child(_panel)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.text = "F3 运行诊断\n等待采样…"
	_panel.add_child(_label)


func _event_toggles_diagnostics(event: InputEvent) -> bool:
	if gameplay_input != null and gameplay_input.has_method("event_toggles_diagnostics"):
		return bool(gameplay_input.call("event_toggles_diagnostics", event))
	return event.is_action_pressed(Actions.TOGGLE_DIAGNOSTICS)


func _on_snapshot_updated(snapshot: Dictionary) -> void:
	if _label == null:
		return
	_label.text = _format_snapshot(snapshot)


func _format_snapshot(snapshot: Dictionary) -> String:
	var health: Dictionary = snapshot.get("health", {})
	var status := str(health.get("status", "healthy"))
	var status_text := {
		"healthy": "正常",
		"warning": "警告",
		"critical": "严重",
	}.get(status, status)
	var streaming: Dictionary = snapshot.get("streaming", {})
	var position_text := "未连接"
	var player_position: Array = snapshot.get("player_position", [])
	if player_position.size() >= 3:
		position_text = "%.1f, %.1f, %.1f" % [
			float(player_position[0]), float(player_position[1]), float(player_position[2])
		]
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
		"玩家位置：%s" % position_text,
	]
	var issues: Array = health.get("issues", [])
	if issues.is_empty():
		lines.append("健康检查：未发现超阈值指标")
	else:
		lines.append("健康检查：")
		for issue in issues:
			lines.append("• %s" % str(issue))
	return "\n".join(lines)


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
