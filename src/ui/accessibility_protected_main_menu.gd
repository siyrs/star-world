class_name AccessibilityProtectedMainMenu
extends "res://src/ui/protected_main_menu.gd"

const AccessibilityPolicy = preload(
	"res://src/settings/ui_accessibility_policy.gd"
)
const RecoveryUiKit = preload("res://src/ui/ui_kit.gd")
const RecoveryTokens = preload("res://src/ui/design_tokens.gd")

var _ui_accessibility_service: Node
var _session_recovery_service: Node
var _recovery_card: PanelContainer
var _recovery_summary: Label
var _recovery_detail: Label
var _recovery_button: Button
var _dismiss_recovery_button: Button
var _regular_primary_button: Button
var _recovery_candidate: Dictionary = {}


func _ready() -> void:
	super._ready()
	_regular_primary_button = _menu_buttons[0] if not _menu_buttons.is_empty() else null
	_build_recovery_card()
	_rewire_quit_command()
	call_deferred("_refresh_recovery_candidate")


func setup_accessibility(service: Node) -> void:
	_disconnect_accessibility_service()
	_ui_accessibility_service = service
	if _ui_accessibility_service == null:
		return
	var callback := Callable(self, "_on_accessibility_input_mode_changed")
	if (
		_ui_accessibility_service.has_signal("input_mode_changed")
		and not _ui_accessibility_service.is_connected("input_mode_changed", callback)
	):
		_ui_accessibility_service.connect("input_mode_changed", callback)
	var visibility_callback := Callable(self, "_on_menu_visibility_changed")
	if not visibility_changed.is_connected(visibility_callback):
		visibility_changed.connect(visibility_callback)
	_on_accessibility_input_mode_changed(
		StringName(_ui_accessibility_service.call("get_input_mode"))
	)


func setup_session_recovery(service: Node) -> void:
	_disconnect_recovery_service()
	_session_recovery_service = service
	if _session_recovery_service != null:
		var callback := Callable(self, "_on_recovery_candidate_changed")
		if (
			_session_recovery_service.has_signal("candidate_changed")
			and not _session_recovery_service.is_connected("candidate_changed", callback)
		):
			_session_recovery_service.connect("candidate_changed", callback)
	_refresh_recovery_candidate()


func show_main() -> void:
	super.show_main()
	_refresh_recovery_candidate()


func show_shutdown_ready() -> void:
	show_main()
	_status.text = "当前世界已完成最终保存，可以安全退出。"
	_status.theme_type_variation = "SuccessLabel"


func _exit_tree() -> void:
	var visibility_callback := Callable(self, "_on_menu_visibility_changed")
	if visibility_changed.is_connected(visibility_callback):
		visibility_changed.disconnect(visibility_callback)
	_disconnect_accessibility_service()
	_disconnect_recovery_service()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_controller_command(event):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _handle_controller_command(event: InputEvent) -> bool:
	match AccessibilityPolicy.controller_command(event):
		AccessibilityPolicy.COMMAND_ACCEPT:
			var focus_owner: Control = get_viewport().gui_get_focus_owner()
			if focus_owner is BaseButton and is_ancestor_of(focus_owner):
				(focus_owner as BaseButton).pressed.emit()
				return true
		AccessibilityPolicy.COMMAND_CANCEL:
			if _has_cancellable_subpage():
				show_main()
				return true
	return false


func _has_cancellable_subpage() -> bool:
	return (
		(_map_panel != null and _map_panel.visible)
		or (_save_panel != null and _save_panel.visible)
		or (_settings_panel != null and _settings_panel.visible)
		or (_update_panel != null and _update_panel.visible)
	)


func _on_menu_visibility_changed() -> void:
	if (
		_ui_accessibility_service != null
		and _ui_accessibility_service.has_method("begin_ui_transition_guard")
	):
		_ui_accessibility_service.call("begin_ui_transition_guard")


func _on_accessibility_input_mode_changed(mode: StringName) -> void:
	if mode == AccessibilityPolicy.MODE_MOUSE:
		_release_owned_focus()
		return
	if _main_panel != null and _main_panel.visible:
		call_deferred("_focus_primary_action")
		return
	for panel: Control in [_map_panel, _save_panel, _settings_panel, _update_panel]:
		if panel != null and panel.visible:
			call_deferred("_focus_first_interactive", panel)
			return


func _focus_primary_action() -> void:
	if (
		not _can_own_focus()
		or _main_panel == null
		or not _main_panel.visible
	):
		return
	if (
		_recovery_card != null
		and _recovery_card.visible
		and _recovery_button != null
		and not _recovery_button.disabled
	):
		_recovery_button.grab_focus()
		return
	super._focus_primary_action()


func _focus_first_interactive(panel: Control) -> void:
	if not _can_own_focus():
		return
	super._focus_first_interactive(panel)


func _can_own_focus() -> bool:
	return (
		_ui_accessibility_service == null
		or bool(_ui_accessibility_service.call("prefers_focus_navigation"))
	)


func _release_owned_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _disconnect_accessibility_service() -> void:
	if _ui_accessibility_service == null:
		return
	var callback := Callable(self, "_on_accessibility_input_mode_changed")
	if (
		_ui_accessibility_service.has_signal("input_mode_changed")
		and _ui_accessibility_service.is_connected("input_mode_changed", callback)
	):
		_ui_accessibility_service.disconnect("input_mode_changed", callback)
	_ui_accessibility_service = null


func get_accessibility_navigation_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_navigation_snapshot()
	snapshot["input_mode"] = (
		StringName(_ui_accessibility_service.call("get_input_mode"))
		if _ui_accessibility_service != null
		else AccessibilityPolicy.MODE_KEYBOARD
	)
	snapshot["ui_scale"] = (
		float(_ui_accessibility_service.call("get_ui_scale"))
		if _ui_accessibility_service != null
		else AccessibilityPolicy.DEFAULT_SCALE
	)
	snapshot["session_recovery"] = get_recovery_visual_snapshot()
	return snapshot


func get_recovery_visual_snapshot() -> Dictionary:
	var visible_regular_commands := 0
	for button: Button in _menu_buttons:
		if button.visible:
			visible_regular_commands += 1
	return {
		"visible": _recovery_card != null and _recovery_card.visible,
		"card_rect": _recovery_card.get_global_rect() if _recovery_card != null else Rect2(),
		"recover_button_rect": (
			_recovery_button.get_global_rect() if _recovery_button != null else Rect2()
		),
		"dismiss_button_rect": (
			_dismiss_recovery_button.get_global_rect()
			if _dismiss_recovery_button != null
			else Rect2()
		),
		"regular_primary_visible": (
			_regular_primary_button.visible if _regular_primary_button != null else false
		),
		"visible_regular_command_count": visible_regular_commands,
		"summary": _recovery_summary.text if _recovery_summary != null else "",
		"detail": _recovery_detail.text if _recovery_detail != null else "",
		"candidate": _recovery_candidate.duplicate(true),
	}


func get_visual_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_visual_snapshot()
	snapshot["session_recovery"] = get_recovery_visual_snapshot()
	snapshot["status_text"] = _status.text if _status != null else ""
	return snapshot


func _quit() -> void:
	# UI emits intent only. The stable game composition root owns final save,
	# WM_CLOSE coordination and actual process termination.
	quit_requested.emit()


func _build_recovery_card() -> void:
	if _command_panel == null or _recovery_card != null:
		return
	var content := _command_panel.get_child(0) as VBoxContainer
	if content == null:
		return
	_recovery_card = PanelContainer.new()
	_recovery_card.name = "SessionRecoveryCard"
	_recovery_card.theme_type_variation = "ModalPanel"
	_recovery_card.custom_minimum_size = Vector2(338, 120)
	content.add_child(_recovery_card)
	content.move_child(_recovery_card, 0)
	var card_content := VBoxContainer.new()
	card_content.add_theme_constant_override("separation", RecoveryTokens.SPACE_XS)
	_recovery_card.add_child(card_content)
	_recovery_summary = Label.new()
	_recovery_summary.name = "SessionRecoverySummary"
	_recovery_summary.text = "检测到上次会话未正常结束"
	_recovery_summary.theme_type_variation = "SectionTitle"
	_recovery_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_content.add_child(_recovery_summary)
	_recovery_detail = Label.new()
	_recovery_detail.name = "SessionRecoveryDetail"
	_recovery_detail.theme_type_variation = "MutedLabel"
	_recovery_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recovery_detail.custom_minimum_size.y = 32
	card_content.add_child(_recovery_detail)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", RecoveryTokens.SPACE_SM)
	card_content.add_child(actions)
	_recovery_button = RecoveryUiKit.style_button(
		Button.new(), "PrimaryButton", Vector2(0, RecoveryTokens.CONTROL_HEIGHT_MD)
	)
	_recovery_button.name = "RecoverLastSessionButton"
	_recovery_button.text = "恢复上次世界"
	_recovery_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recovery_button.pressed.connect(_recover_last_session)
	actions.add_child(_recovery_button)
	_dismiss_recovery_button = RecoveryUiKit.style_button(
		Button.new(), "GhostButton", Vector2(0, RecoveryTokens.CONTROL_HEIGHT_MD)
	)
	_dismiss_recovery_button.name = "DismissSessionRecoveryButton"
	_dismiss_recovery_button.text = "忽略并清除"
	_dismiss_recovery_button.pressed.connect(_dismiss_recovery_candidate)
	actions.add_child(_dismiss_recovery_button)
	_recovery_card.visible = false


func _rewire_quit_command() -> void:
	for button: Button in _menu_buttons:
		if button.text != "退出":
			continue
		_disconnect_button_callbacks(button)
		button.pressed.connect(_quit)
		_connect_button_audio(button)
		return


func _refresh_recovery_candidate() -> void:
	if _recovery_card == null:
		return
	_recovery_candidate = {}
	if (
		_session_recovery_service != null
		and is_instance_valid(_session_recovery_service)
		and _session_recovery_service.has_method("get_recovery_candidate")
	):
		var raw_candidate: Variant = _session_recovery_service.call(
			"get_recovery_candidate"
		)
		if raw_candidate is Dictionary:
			_recovery_candidate = raw_candidate.duplicate(true)
	var recovery_visible := not _recovery_candidate.is_empty()
	_recovery_card.visible = recovery_visible
	# Recovery replaces only the duplicate generic primary command. Map selection,
	# save browsing and every management entry stay available at 1024x576.
	if _regular_primary_button != null:
		_regular_primary_button.visible = not recovery_visible
	if recovery_visible:
		var world_name := str(
			_recovery_candidate.get(
				"world_name", _recovery_candidate.get("world_id", "未知世界")
			)
		)
		var map_id := str(_recovery_candidate.get("map_id", "unknown"))
		var checkpoint_count := maxi(
			0, int(_recovery_candidate.get("checkpoint_count", 0))
		)
		_recovery_summary.text = "上次会话未正常结束 · %s" % world_name
		_recovery_detail.text = (
			"地图 %s · 已完成 %d 个检查点 · 从最近权威存档继续"
			% [map_id, checkpoint_count]
		)
	_apply_responsive_layout()
	if _main_panel != null and _main_panel.visible:
		call_deferred("_focus_primary_action")


func _recover_last_session() -> void:
	var world_id := str(_recovery_candidate.get("world_id", ""))
	if world_id.is_empty() or save_service == null:
		_refresh_recovery_candidate()
		return
	var state: Dictionary = save_service.load_world(world_id)
	if state.is_empty():
		if _session_recovery_service != null:
			_session_recovery_service.call("dismiss_candidate")
		show_main()
		show_error("恢复入口对应的权威存档已不可用。")
		return
	show_loading("正在恢复上次异常会话…")
	continue_world_requested.emit(state)


func _dismiss_recovery_candidate() -> void:
	if (
		_session_recovery_service != null
		and _session_recovery_service.has_method("dismiss_candidate")
	):
		_session_recovery_service.call("dismiss_candidate")
	_refresh_recovery_candidate()
	_status.text = "已清除上次异常会话提示，世界存档未被删除。"
	_status.theme_type_variation = "CaptionLabel"


func _on_recovery_candidate_changed(_candidate: Dictionary) -> void:
	_refresh_recovery_candidate()


func _disconnect_recovery_service() -> void:
	if _session_recovery_service == null:
		return
	var callback := Callable(self, "_on_recovery_candidate_changed")
	if (
		_session_recovery_service.has_signal("candidate_changed")
		and _session_recovery_service.is_connected("candidate_changed", callback)
	):
		_session_recovery_service.disconnect("candidate_changed", callback)
	_session_recovery_service = null
