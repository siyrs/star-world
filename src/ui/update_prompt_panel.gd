class_name UpdatePromptPanel
extends PanelContainer

signal dismissed

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
	custom_minimum_size = Vector2(680, 500)
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


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	_title = Label.new()
	_title.text = "发现新版本"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	root.add_child(_title)
	_version_label = Label.new()
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.modulate = Color("#8FD7F0")
	root.add_child(_version_label)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = false
	_notes.fit_content = false
	_notes.scroll_active = true
	_notes.custom_minimum_size = Vector2(620, 260)
	root.add_child(_notes)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = true
	_progress.visible = false
	root.add_child(_progress)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	root.add_child(actions)
	_primary_button = Button.new()
	_primary_button.text = "下载并自动更新"
	_primary_button.custom_minimum_size = Vector2(250, 52)
	_primary_button.pressed.connect(_on_primary_pressed)
	actions.add_child(_primary_button)
	_later_button = Button.new()
	_later_button.text = "稍后"
	_later_button.custom_minimum_size = Vector2(150, 52)
	_later_button.pressed.connect(_on_later_pressed)
	actions.add_child(_later_button)


func _on_update_available(release: Dictionary) -> void:
	_release = release.duplicate(true)
	_download_started = false
	visible = true
	_title.text = "发现新版本"
	_version_label.text = "当前 v%s  →  最新 v%s" % [
		str(update_service.get("current_version")),
		str(_release.get("version", "")),
	]
	_notes.text = str(_release.get("notes", "本次 Release 未提供更新说明。"))
	_status.text = "更新来自 GitHub Release，下载包会进行 SHA-256 与清单双重校验。"
	_progress.visible = false
	_progress.value = 0.0
	_primary_button.text = "下载并自动更新"
	_primary_button.disabled = false
	_later_button.visible = true
	_later_button.disabled = false


func _on_status_changed(state: StringName, message: String) -> void:
	_status.text = message
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
		visible = true
		_primary_button.disabled = false
		_primary_button.text = "重试更新"
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


func _on_install_started(version: String) -> void:
	_title.text = "正在安装 v%s" % version
	_status.text = "游戏即将退出；安装助手会切换版本、验证启动，失败时自动回滚。"


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
	var amount := float(maxi(0, value))
	for unit: String in ["B", "KB", "MB", "GB"]:
		if amount < 1024.0 or unit == "GB":
			return "%.1f %s" % [amount, unit]
		amount /= 1024.0
	return "%.1f GB" % amount
