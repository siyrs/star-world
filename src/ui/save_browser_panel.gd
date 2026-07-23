class_name SaveBrowserPanel
extends PanelContainer

signal load_requested(world_id: String)
signal back_requested

const ThemeFactory = preload("res://src/ui/theme_factory.gd")

var save_service
var _list: VBoxContainer
var _status: Label
var _selected_world_id: String = ""


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(820, 590)
	_build_ui()


func setup(p_save_service) -> void:
	save_service = p_save_service
	refresh()


func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if save_service == null:
		_status.text = "存档服务未连接"
		return
	var worlds: Array = save_service.list_worlds()
	_status.text = _catalog_status(worlds.size())
	for metadata in worlds:
		var row := HBoxContainer.new()
		var select_button := Button.new()
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.text = "%s\n%s  Seed %s  更新 %s  存档 %s" % [
			metadata.get("name", "未命名"),
			metadata.get("map_id", ""),
			metadata.get("seed", 0),
			metadata.get("updated_at", ""),
			_format_bytes(int(metadata.get("save_bytes", 0))),
		]
		var world_id := str(metadata.get("id", ""))
		select_button.pressed.connect(
			func() -> void:
				_selected_world_id = world_id
				_status.text = "已选: %s · 存档 %s" % [
					metadata.get("name", world_id),
					_format_bytes(int(metadata.get("save_bytes", 0))),
				]
		)
		row.add_child(select_button)
		var load_button := Button.new()
		load_button.text = "继续"
		load_button.pressed.connect(func() -> void: load_requested.emit(world_id))
		row.add_child(load_button)
		_list.add_child(row)


func _catalog_status(world_count: int) -> String:
	if save_service == null or not save_service.has_method("get_catalog_diagnostics"):
		return "共 %d 个世界" % world_count
	var diagnostics: Dictionary = save_service.call("get_catalog_diagnostics")
	var elapsed_ms := float(diagnostics.get("last_elapsed_milliseconds", 0.0))
	var repairs := int(diagnostics.get("last_repair_count", 0))
	var status := "共 %d 个世界 · 目录 %.1f ms" % [world_count, elapsed_ms]
	if repairs > 0:
		status += " · 已修复 %d 个旧目录" % repairs
	return status


func _format_bytes(value: int) -> String:
	var safe_value := maxi(0, value)
	if safe_value < 1024:
		return "%d B" % safe_value
	if safe_value < 1024 * 1024:
		return "%.1f KB" % (float(safe_value) / 1024.0)
	if safe_value < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(safe_value) / float(1024 * 1024))
	return "%.1f GB" % (float(safe_value) / float(1024 * 1024 * 1024))


func _build_ui() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "世界存档"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var delete_button := Button.new()
	delete_button.text = "删除所选"
	delete_button.pressed.connect(_delete_selected)
	header.add_child(delete_button)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)
	_status = Label.new()
	root.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _delete_selected() -> void:
	if save_service != null and not _selected_world_id.is_empty():
		save_service.delete_world(_selected_world_id)
		_selected_world_id = ""
		refresh()
