class_name CrashRecoveryGameUI
extends "res://src/ui/accessibility_machine_game_ui.gd"

signal quit_to_desktop_requested

const QuitUiKit = preload("res://src/ui/ui_kit.gd")
const QuitTokens = preload("res://src/ui/design_tokens.gd")

var _safe_quit_button: Button


func _ready() -> void:
	super._ready()
	_install_safe_quit_command()


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
