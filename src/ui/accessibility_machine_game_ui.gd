class_name AccessibilityMachineGameUI
extends "res://src/ui/machine_game_ui.gd"

signal accessibility_focus_restored(overlay: int)
signal accessibility_focus_restore_failed(overlay: int)
signal quit_to_desktop_requested

const AccessibilityPolicy = preload(
	"res://src/settings/ui_accessibility_policy.gd"
)
const QuitUiKit = preload("res://src/ui/ui_kit.gd")
const QuitTokens = preload("res://src/ui/design_tokens.gd")
const FOCUS_RESTORE_ATTEMPTS := 2

var _ui_accessibility_service: Node
var _focus_restore_request_id := 0
var _focus_restore_success_count := 0
var _focus_restore_failure_count := 0
var _safe_quit_button: Button


func _ready() -> void:
	super._ready()
	_install_safe_quit_command()


func setup_accessibility(service: Node) -> void:
	_disconnect_accessibility_service()
	_ui_accessibility_service = service
	if _ui_accessibility_service == null:
		return
	var mode_callback := Callable(self, "_on_accessibility_input_mode_changed")
	if (
		_ui_accessibility_service.has_signal("input_mode_changed")
		and not _ui_accessibility_service.is_connected("input_mode_changed", mode_callback)
	):
		_ui_accessibility_service.connect("input_mode_changed", mode_callback)
	_on_accessibility_input_mode_changed(
		StringName(_ui_accessibility_service.call("get_input_mode"))
	)


func _exit_tree() -> void:
	_focus_restore_request_id += 1
	_disconnect_accessibility_service()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_controller_overlay_command(event):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _handle_controller_overlay_command(event: InputEvent) -> bool:
	if _overlay == Overlay.NONE:
		return false
	match AccessibilityPolicy.controller_command(event):
		AccessibilityPolicy.COMMAND_ACCEPT:
			var focus_owner: Control = get_viewport().gui_get_focus_owner()
			var focus_root := _focus_root_for_overlay()
			if (
				focus_owner is BaseButton
				and focus_root != null
				and (
					focus_owner == focus_root
					or focus_root.is_ancestor_of(focus_owner)
				)
			):
				(focus_owner as BaseButton).pressed.emit()
				return true
		AccessibilityPolicy.COMMAND_CANCEL:
			if _overlay != Overlay.DEATH:
				close_overlay()
				return true
	return false


func _set_overlay(next_overlay: int, force: bool = false) -> void:
	if (
		_ui_accessibility_service != null
		and _ui_accessibility_service.has_method("begin_ui_transition_guard")
		and (force or next_overlay != _overlay)
	):
		_ui_accessibility_service.call("begin_ui_transition_guard")
	super._set_overlay(next_overlay, force)
	if _overlay != Overlay.NONE:
		_release_focus_outside_active_overlay()
		_queue_accessibility_focus_restore(true)
	else:
		_focus_restore_request_id += 1


func _on_accessibility_input_mode_changed(mode: StringName) -> void:
	if mode == AccessibilityPolicy.MODE_MOUSE:
		_focus_restore_request_id += 1
		_release_owned_focus()
		return
	if _overlay != Overlay.NONE:
		_queue_accessibility_focus_restore(false)


func _queue_accessibility_focus_restore(wait_for_presentation: bool) -> void:
	_focus_restore_request_id += 1
	call_deferred(
		"_restore_accessibility_focus",
		_focus_restore_request_id,
		wait_for_presentation
	)


func _restore_accessibility_focus(
	request_id: int,
	wait_for_presentation: bool
) -> void:
	if wait_for_presentation:
		# The panel becomes visible immediately, but its focus geometry is not stable
		# until the production entrance animation finishes. Reuse the inherited
		# animation contract instead of guessing a frame count in each caller or test.
		await get_tree().create_timer(
			PanelAnimator.DURATION,
			true,
			false,
			true
		).timeout
	for _attempt in FOCUS_RESTORE_ATTEMPTS:
		if request_id != _focus_restore_request_id:
			return
		if (
			_ui_accessibility_service == null
			or not bool(_ui_accessibility_service.call("prefers_focus_navigation"))
			or _overlay == Overlay.NONE
		):
			return
		var focus_root := _focus_root_for_overlay()
		if focus_root != null and focus_root.is_visible_in_tree():
			_release_focus_outside_active_overlay()
			var target := _find_visible_focusable(focus_root)
			if target != null:
				target.grab_focus()
				await get_tree().process_frame
				var focus_owner: Control = get_viewport().gui_get_focus_owner()
				if (
					focus_owner != null
					and (
						focus_owner == focus_root
						or focus_root.is_ancestor_of(focus_owner)
					)
				):
					_focus_restore_success_count += 1
					accessibility_focus_restored.emit(_overlay)
					return
		await get_tree().process_frame
	if request_id == _focus_restore_request_id and _overlay != Overlay.NONE:
		_focus_restore_failure_count += 1
		accessibility_focus_restore_failed.emit(_overlay)


func _focus_root_for_overlay() -> Control:
	match _overlay:
		Overlay.INVENTORY:
			return inventory_panel
		Overlay.CRAFTING:
			return crafting_panel
		Overlay.FURNACE:
			return furnace_panel
		Overlay.CONTAINER:
			return container_panel
		Overlay.PAUSE:
			return _pause_panel
		Overlay.DEATH:
			return _death_panel
		EXPLORATION_JOURNAL_OVERLAY:
			return exploration_journal_panel
		REPAIR_OVERLAY:
			return repair_panel
		STONECUTTER_OVERLAY:
			return stonecutter_panel
	for child: Node in get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			var fallback := _find_visible_focusable(child)
			if fallback != null:
				return child as Control
	return null


func _release_focus_outside_active_overlay() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var focus_root := _focus_root_for_overlay()
	if focus_owner == null or focus_root == null:
		return
	if focus_owner != focus_root and not focus_root.is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _release_owned_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _find_visible_focusable(node: Node) -> Control:
	if node == null:
		return null
	if node is Control:
		var control := node as Control
		var disabled := false
		if control is BaseButton:
			disabled = (control as BaseButton).disabled
		if (
			control.is_visible_in_tree()
			and control.focus_mode != Control.FOCUS_NONE
			and not disabled
		):
			return control
	for child: Node in node.get_children():
		var target := _find_visible_focusable(child)
		if target != null:
			return target
	return null


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


func get_accessibility_focus_snapshot() -> Dictionary:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var focus_root := _focus_root_for_overlay()
	return {
		"overlay": _overlay,
		"input_mode": (
			StringName(_ui_accessibility_service.call("get_input_mode"))
			if _ui_accessibility_service != null
			else AccessibilityPolicy.MODE_KEYBOARD
		),
		"focus_owner": focus_owner,
		"focus_root": focus_root,
		"focus_inside_game_ui": focus_owner != null and is_ancestor_of(focus_owner),
		"focus_inside_active_overlay": (
			focus_owner != null
			and focus_root != null
			and (focus_owner == focus_root or focus_root.is_ancestor_of(focus_owner))
		),
		"focus_restore_request_id": _focus_restore_request_id,
		"focus_restore_success_count": _focus_restore_success_count,
		"focus_restore_failure_count": _focus_restore_failure_count,
	}


func show_quit_progress() -> void:
	if _pause_status != null:
		_pause_status.text = "正在执行最终保存并安全退出…"
		_pause_status.theme_type_variation = "CaptionLabel"
	if _safe_quit_button != null:
		_safe_quit_button.disabled = true
	show_message("正在执行最终保存…", 2.0, "info", "application_quit")


func show_quit_result(success: bool) -> void:
	if _safe_quit_button != null:
		_safe_quit_button.disabled = false
	if success:
		if _pause_status != null:
			_pause_status.text = "最终保存成功，正在安全退出。"
			_pause_status.theme_type_variation = "SuccessLabel"
		return
	if _pause_status != null:
		_pause_status.text = "最终保存失败，已取消退出；世界仍保持打开。"
		_pause_status.theme_type_variation = "DangerLabel"
	show_message(
		"最终保存失败，已取消退出；请检查磁盘空间或写入权限。",
		4.0,
		"error",
		"application_quit"
	)


func get_safe_quit_visual_snapshot() -> Dictionary:
	return {
		"available": _safe_quit_button != null,
		"disabled": _safe_quit_button.disabled if _safe_quit_button != null else true,
		"rect": _safe_quit_button.get_global_rect() if _safe_quit_button != null else Rect2(),
		"text": _safe_quit_button.text if _safe_quit_button != null else "",
	}


func get_visual_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_visual_snapshot()
	snapshot["safe_quit"] = get_safe_quit_visual_snapshot()
	return snapshot


func _install_safe_quit_command() -> void:
	if _pause_panel == null or _safe_quit_button != null:
		return
	var content := _pause_panel.get_child(0) as VBoxContainer
	if content == null:
		return
	_safe_quit_button = QuitUiKit.style_button(
		Button.new(), "DangerButton", Vector2(0, QuitTokens.CONTROL_HEIGHT_MD)
	)
	_safe_quit_button.name = "SafeQuitDesktopButton"
	_safe_quit_button.text = "保存并退出游戏"
	_safe_quit_button.pressed.connect(_request_safe_quit)
	content.add_child(_safe_quit_button)
	content.move_child(_safe_quit_button, maxi(0, content.get_child_count() - 2))
	_center_control(_pause_panel, Vector2(520, 540))


func _request_safe_quit() -> void:
	show_quit_progress()
	quit_to_desktop_requested.emit()
