class_name UpdatePromptPanel
extends PanelContainer

signal dismissed

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")

var update_service: Node
var _title: Label
var _version_label: Label
var _notes: RichTextLabel
var _status: Label
var _progress: ProgressBar
var _primary_button: Button
var _later_button: Button
var _release: Dictionary = {}
var _download_started := false


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	theme_type_variation = "ModalPanel"
	custom_minimum_size = Vector2(720, 510)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	visible = false


func setup(service: Node) -> void:
	_disconnect_service()
	update_service = service
	if update_service == null:
		return
	_connect_signal("update_available", Callable(self, "_on_update_available"))
	_connect_signal("update_status_changed", Callable(self, "_on_status_changed"))
	_connect_signal("update_progress_changed", Callable(self, "_on_progress_changed"))
	_connect_signal("update_failed", Callable(self, "_on_update_failed"))
	_connect_signal("update_install_started", Callable(self, "_on_install_started"))


func get_release_version() -> String:
	return str(_release.get("version", ""))


func get_status_text() -> String:
	return _status.text if _status != null else ""


func get_progress_value() -> float:
	return _progress.value if _progress != null else 0.0


func get_primary_button() -> Button:
	return _primary_button


func get_later_button() -> Button:
	return _later_button


func get_visual_snapshot() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"notes": _notes.get_global_rect() if _notes != null else Rect2(),
		"progress_visible": _progress != null and _progress.visible,
		"primary_variation": (
			_primary_button.theme_type_variation if _primary_button != null else ""
		),
		"release_version": get_release_version(),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_MD)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("SECURE RELEASE UPDATE"))
	_title = UiKit.make_title("发现新版本")
	heading.add_child(_title)
	_version_label = UiKit.make_badge("等待版本信息", "info")
	header.add_child(_version_label)

	var trust_card := UiKit.make_card("SuccessPanel")
	root.add_child(trust_card)
	var trust_label := Label.new()
	trust_label.text = "✓ GitHub Release 来源 · SHA-256 与清单双重验证 · 启动失败自动回滚"
	trust_label.theme_type_variation = "SuccessLabel"
	trust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trust_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trust_card.add_child(trust_label)

	var notes_card := UiKit.make_card("InsetPanel")
	notes_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(notes_card)
	var notes_root := VBoxContainer.new()
	notes_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	notes_card.add_child(notes_root)
	var notes_title := Label.new()
	notes_title.text = "版本说明"
	notes_title.theme_type_variation = "SectionTitle"
	notes_root.add_child(notes_title)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = false
	_notes.fit_content = false
	_notes.scroll_active = true
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.custom_minimum_size = Vector2(630, 220)
	_notes.add_theme_font_size_override("normal_font_size", Tokens.FONT_BODY)
	notes_root.add_child(_notes)

	_status = Label.new()
	_status.theme_type_variation = "CaptionLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40.0
	root.add_child(_status)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = true
	_progress.custom_minimum_size.y = 12.0
	_progress.visible = false
	root.add_child(_progress)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(actions)
	_later_button = UiKit.style_button(
		Button.new(), "GhostButton", Vector2(170, Tokens.CONTROL_HEIGHT_LG)
	)
	_later_button.text = "稍后"
	_later_button.pressed.connect(_on_later_pressed)
	actions.add_child(_later_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_primary_button = UiKit.style_button(
		Button.new(), "PrimaryButton", Vector2(280, Tokens.CONTROL_HEIGHT_LG)
	)
	_primary_button.text = "下载并自动更新"
	_primary_button.pressed.connect(_on_primary_pressed)
	actions.add_child(_primary_button)


func _on_update_available(release: Dictionary) -> void:
	_release = release.duplicate(true)
	_download_started = false
	visible = true
	_title.text = "发现新版本"
	_version_label.text = "v%s  →  v%s" % [
		str(update_service.get("current_version")),
		str(_release.get("version", "")),
	]
	_notes.text = str(_release.get("notes", "本次 Release 未提供更新说明。"))
	_status.text = "更新包会在下载完成后执行校验；中断后可从当前进度继续。"
	_status.theme_type_variation = "CaptionLabel"
	_progress.visible = false
	_progress.value = 0.0
	_primary_button.text = "下载并自动更新"
	_primary_button.disabled = false
	_later_button.visible = true
	_later_button.text = "稍后"
	_later_button.disabled = false


func _on_status_changed(state: StringName, message: String) -> void:
	_status.text = message
	_status.theme_type_variation = "CaptionLabel"
	if state in [&"checksum", &"downloading"]:
		_download_started = true
		visible = true
		_progress.visible = true
		_primary_button.disabled = true
		_primary_button.text = "正在下载…"
		_later_button.text = "关闭游戏后可续传"
		_later_button.disabled = true
	elif state == &"ready":
		_primary_button.disabled = true
		_primary_button.text = "正在准备安装…"
	elif state == &"failed":
		_download_started = false
		visible = true
		_status.theme_type_variation = "DangerLabel"
		_primary_button.disabled = false
		_primary_button.text = "重试更新"
		_later_button.visible = true
		_later_button.text = "稍后"
		_later_button.disabled = false
	elif state == &"installing":
		visible = true
		_primary_button.disabled = true
		_primary_button.text = "正在退出并安装…"
		_later_button.visible = false


func _on_progress_changed(downloaded_bytes: int, total_bytes: int) -> void:
	_progress.visible = true
	_progress.value = (
		clampf(float(downloaded_bytes) / float(total_bytes) * 100.0, 0.0, 100.0)
		if total_bytes > 0
		else 0.0
	)
	_status.text = "已下载 %s / %s；断网或断电后会从当前进度继续。" % [
		_format_bytes(downloaded_bytes),
		_format_bytes(total_bytes),
	]


func _on_update_failed(_reason: String, message: String) -> void:
	_status.text = message
	_status.theme_type_variation = "DangerLabel"


func _on_install_started(version: String) -> void:
	_title.text = "正在安装 v%s" % version
	_status.text = "游戏即将退出；安装助手会切换版本、验证启动，失败时自动回滚。"
	_status.theme_type_variation = "CaptionLabel"


func _on_primary_pressed() -> void:
	if update_service == null:
		return
	_primary_button.disabled = true
	if not bool(update_service.call("download_and_install")):
		_primary_button.disabled = false


func _on_later_pressed() -> void:
	if _download_started:
		return
	if update_service != null and update_service.has_method("dismiss_update"):
		update_service.call("dismiss_update")
	visible = false
	dismissed.emit()


func _connect_signal(signal_name: String, callback: Callable) -> void:
	if update_service.has_signal(signal_name) and not update_service.is_connected(signal_name, callback):
		update_service.connect(signal_name, callback)


func _disconnect_service() -> void:
	if update_service == null or not is_instance_valid(update_service):
		return
	for signal_data: Array in [
		["update_available", Callable(self, "_on_update_available")],
		["update_status_changed", Callable(self, "_on_status_changed")],
		["update_progress_changed", Callable(self, "_on_progress_changed")],
		["update_failed", Callable(self, "_on_update_failed")],
		["update_install_started", Callable(self, "_on_install_started")],
	]:
		var signal_name := str(signal_data[0])
		var callback: Callable = signal_data[1]
		if update_service.has_signal(signal_name) and update_service.is_connected(signal_name, callback):
			update_service.disconnect(signal_name, callback)


func _format_bytes(value: int) -> String:
	return UiKit.format_bytes(value)
