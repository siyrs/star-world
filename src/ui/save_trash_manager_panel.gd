class_name SaveTrashManagerPanel
extends PanelContainer

signal back_requested
signal world_restored(world_id: String, trash_id: String)
signal trash_slot_purged(trash_id: String)

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const MAX_VISIBLE_ROWS := 24
const MAX_TRASH_ENTRIES := 32

var trash_service: Node
var _list: VBoxContainer
var _status: Label
var _page_label: Label
var _previous_page_button: Button
var _next_page_button: Button
var _purge_button: Button
var _entries: Array[Dictionary] = []
var _entry_by_id: Dictionary = {}
var _slot_ids: Array[String] = []
var _row_slots: Array[Dictionary] = []
var _row_trash_ids: Array[String] = []
var _selected_trash_id := ""
var _pending_purge_trash_id := ""
var _page_index := 0
var _row_create_count := 0
var _render_count := 0
var _refresh_count := 0
var _service_list_count := 0


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	custom_minimum_size = Vector2(820, 590)
	_build_ui()
	visibility_changed.connect(_on_visibility_changed)


func setup(p_trash_service: Node, refresh_now: bool = true) -> void:
	trash_service = p_trash_service
	if refresh_now:
		refresh()


func refresh() -> void:
	_reset_purge_confirmation()
	_entries.clear()
	_entry_by_id.clear()
	_slot_ids.clear()
	_page_index = 0
	if trash_service == null:
		_render_page()
		_status.text = "回收站服务未连接"
		return
	var raw_slots: Variant = []
	if trash_service.has_method("list_trash_slots"):
		raw_slots = trash_service.call("list_trash_slots", MAX_TRASH_ENTRIES)
	elif trash_service.has_method("list_trashed_worlds"):
		raw_slots = trash_service.call("list_trashed_worlds", MAX_TRASH_ENTRIES)
	_service_list_count += 1
	if raw_slots is Array:
		for raw_entry: Variant in raw_slots:
			if raw_entry is not Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var trash_id := str(entry.get("trash_id", ""))
			if trash_id.is_empty() or _entry_by_id.has(trash_id):
				continue
			_entries.append(entry)
			_entry_by_id[trash_id] = entry
			_slot_ids.append(trash_id)
	_refresh_count += 1
	_selected_trash_id = "" if not _entry_by_id.has(_selected_trash_id) else _selected_trash_id
	_render_page()
	_status.text = _management_status()


func show_page(index: int) -> void:
	_reset_purge_confirmation()
	_page_index = clampi(index, 0, _page_count() - 1)
	_render_page()


func get_visible_trash_ids() -> Array[String]:
	var result: Array[String] = []
	for trash_id: String in _row_trash_ids:
		if not trash_id.is_empty():
			result.append(trash_id)
	return result


func get_management_snapshot() -> Dictionary:
	var valid_count := 0
	var invalid_count := 0
	for entry: Dictionary in _entries:
		if bool(entry.get("valid", true)):
			valid_count += 1
		else:
			invalid_count += 1
	var diagnostics: Dictionary = {}
	if trash_service != null and trash_service.has_method("get_trash_diagnostics"):
		var raw_diagnostics: Variant = trash_service.call("get_trash_diagnostics")
		if raw_diagnostics is Dictionary:
			diagnostics = raw_diagnostics
	return {
		"row_pool_limit": MAX_VISIBLE_ROWS,
		"row_pool_size": _row_slots.size(),
		"visible_row_count": get_visible_trash_ids().size(),
		"page_index": _page_index,
		"page_count": _page_count(),
		"total_slot_count": _slot_ids.size(),
		"valid_slot_count": valid_count,
		"invalid_slot_count": invalid_count,
		"selected_trash_id": _selected_trash_id,
		"pending_purge_trash_id": _pending_purge_trash_id,
		"purge_confirmation_armed": not _pending_purge_trash_id.is_empty(),
		"row_create_count": _row_create_count,
		"render_count": _render_count,
		"refresh_count": _refresh_count,
		"service_list_count": _service_list_count,
		"trash_capacity": int(diagnostics.get("trash_capacity", MAX_TRASH_ENTRIES)),
		"physical_entry_count": int(diagnostics.get("trash_entry_count", _slot_ids.size())),
		"diagnostic_invalid_count": int(diagnostics.get("invalid_entry_count", invalid_count)),
		"overflow_entry_count": int(diagnostics.get("overflow_entry_count", 0)),
	}


func _render_page() -> void:
	if _list == null:
		return
	_render_count += 1
	var start_index := _page_index * MAX_VISIBLE_ROWS
	for slot_index in MAX_VISIBLE_ROWS:
		var slot: Dictionary = _row_slots[slot_index]
		var row := slot.get("row") as HBoxContainer
		var select_button := slot.get("select") as Button
		var restore_button := slot.get("restore") as Button
		var entry_index := start_index + slot_index
		if entry_index >= _slot_ids.size():
			_row_trash_ids[slot_index] = ""
			row.visible = false
			select_button.text = ""
			restore_button.disabled = true
			continue
		var trash_id := _slot_ids[entry_index]
		var entry := _entry_for(trash_id)
		_row_trash_ids[slot_index] = trash_id
		row.visible = not entry.is_empty()
		restore_button.disabled = entry.is_empty() or not bool(entry.get("restorable", entry.get("valid", true)))
		select_button.text = _entry_text(entry)
		if trash_id == _selected_trash_id:
			select_button.text = "▶ %s" % select_button.text
	_update_page_controls()


func _select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _row_trash_ids.size():
		return
	var trash_id := _row_trash_ids[slot_index]
	if trash_id.is_empty():
		return
	_reset_purge_confirmation()
	_selected_trash_id = trash_id
	var entry := _entry_for(trash_id)
	_status.text = (
		"已选损坏条目：%s · 只能永久清理" % trash_id
		if not bool(entry.get("valid", true))
		else "已选：%s · 删除于 %s" % [
			str(entry.get("name", trash_id)),
			str(entry.get("deleted_at", "未知时间")),
		]
	)
	_render_page()


func _restore_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _row_trash_ids.size():
		return
	var trash_id := _row_trash_ids[slot_index]
	if trash_id.is_empty():
		return
	_restore_trash_id(trash_id)


func _restore_selected() -> void:
	if _selected_trash_id.is_empty():
		_status.text = "请先选择一个有效的回收站条目。"
		return
	_restore_trash_id(_selected_trash_id)


func _restore_trash_id(trash_id: String) -> void:
	_reset_purge_confirmation()
	var entry := _entry_for(trash_id)
	if entry.is_empty() or not bool(entry.get("valid", true)):
		_status.text = "损坏条目不能恢复，只能在二次确认后永久清理。"
		return
	if trash_service == null or not trash_service.has_method("restore_trashed_world"):
		_status.text = "回收站恢复服务不可用。"
		return
	var raw_result: Variant = trash_service.call("restore_trashed_world", trash_id)
	var result: Dictionary = raw_result if raw_result is Dictionary else {}
	if not bool(result.get("ok", false)):
		_status.text = _operation_failure_message("恢复", str(result.get("reason", "unknown")))
		return
	var world_id := str(result.get("world_id", ""))
	var name := str(entry.get("name", world_id))
	_selected_trash_id = ""
	refresh()
	_status.text = "已恢复“%s”。" % name
	world_restored.emit(world_id, trash_id)


func _purge_selected() -> void:
	if _selected_trash_id.is_empty():
		_status.text = "请先选择一个回收站条目。"
		_reset_purge_confirmation()
		return
	var selected_entry := _entry_for(_selected_trash_id)
	if not bool(selected_entry.get("purgeable", true)):
		_status.text = "该目录名不安全，管理页不会拼接或删除此路径。"
		_reset_purge_confirmation()
		return
	if trash_service == null or not trash_service.has_method("purge_trash_slot"):
		_status.text = "永久清理服务不可用，未删除任何文件。"
		_reset_purge_confirmation()
		return
	if _pending_purge_trash_id != _selected_trash_id:
		_pending_purge_trash_id = _selected_trash_id
		_purge_button.text = "确认永久清理"
		var entry := _entry_for(_selected_trash_id)
		_status.text = "再次点击确认：永久清理“%s”，此操作不可撤销。" % str(
			entry.get("name", _selected_trash_id)
		)
		return
	var trash_id := _selected_trash_id
	var entry := _entry_for(trash_id)
	var purged := bool(trash_service.call("purge_trash_slot", trash_id))
	_reset_purge_confirmation()
	if not purged:
		_status.text = "永久清理失败，回收站文件保持不变。"
		return
	var name := str(entry.get("name", trash_id))
	_selected_trash_id = ""
	refresh()
	_status.text = "已永久清理“%s”。" % name
	trash_slot_purged.emit(trash_id)


func _show_previous_page() -> void:
	show_page(_page_index - 1)


func _show_next_page() -> void:
	show_page(_page_index + 1)


func _entry_for(trash_id: String) -> Dictionary:
	var raw_entry: Variant = _entry_by_id.get(trash_id, {})
	return raw_entry if raw_entry is Dictionary else {}


func _page_count() -> int:
	return maxi(1, ceili(float(_slot_ids.size()) / float(MAX_VISIBLE_ROWS)))


func _update_page_controls() -> void:
	if _page_label == null:
		return
	var pages := _page_count()
	_page_label.text = "第 %d / %d 页 · 共 %d / %d 个槽位 · 每页最多 %d 个" % [
		_page_index + 1,
		pages,
		_slot_ids.size(),
		MAX_TRASH_ENTRIES,
		MAX_VISIBLE_ROWS,
	]
	_previous_page_button.disabled = _page_index <= 0
	_next_page_button.disabled = _page_index >= pages - 1


func _management_status() -> String:
	if trash_service == null or not trash_service.has_method("get_trash_diagnostics"):
		return "回收站共 %d 个条目" % _slot_ids.size()
	var raw_diagnostics: Variant = trash_service.call("get_trash_diagnostics")
	var diagnostics: Dictionary = raw_diagnostics if raw_diagnostics is Dictionary else {}
	var capacity := maxi(1, int(diagnostics.get("trash_capacity", MAX_TRASH_ENTRIES)))
	var physical := maxi(0, int(diagnostics.get("trash_entry_count", _slot_ids.size())))
	var invalid := maxi(0, int(diagnostics.get("invalid_entry_count", 0)))
	var valid := maxi(
		0, int(diagnostics.get("valid_entry_count", maxi(0, physical - invalid)))
	)
	var status := "回收站 %d/%d · 有效 %d · 损坏 %d" % [physical, capacity, valid, invalid]
	var overflow := maxi(0, int(diagnostics.get("overflow_entry_count", 0)))
	if overflow > 0:
		status += " · 超出管理窗口 %d" % overflow
	return status


func _entry_text(entry: Dictionary) -> String:
	var trash_id := str(entry.get("trash_id", ""))
	var bytes := _format_bytes(int(entry.get("save_bytes", 0)))
	if not bool(entry.get("valid", true)):
		var action := "仅可永久清理" if bool(entry.get("purgeable", true)) else "路径不安全，禁止操作"
		return "⚠ 损坏的回收站条目\nID %s · 可识别存档 %s · %s" % [trash_id, bytes, action]
	return "%s\n%s  Seed %s  删除 %s  存档 %s" % [
		str(entry.get("name", trash_id)),
		str(entry.get("map_id", "")),
		str(entry.get("seed", 0)),
		str(entry.get("deleted_at", "未知时间")),
		bytes,
	]


func _operation_failure_message(operation: String, reason: String) -> String:
	match reason:
		"world_exists":
			return "%s失败：原 world ID 已经存在，回收站条目保持不变。" % operation
		"trash_missing_or_invalid":
			return "%s失败：回收站条目缺失或损坏。" % operation
		_:
			return "%s失败：%s。" % [operation, reason]


func _reset_purge_confirmation() -> void:
	_pending_purge_trash_id = ""
	if _purge_button != null:
		_purge_button.text = "永久清理所选"


func _on_visibility_changed() -> void:
	if not visible:
		_reset_purge_confirmation()


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
	title.text = "存档回收站"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var restore_button := Button.new()
	restore_button.text = "恢复所选"
	restore_button.pressed.connect(_restore_selected)
	header.add_child(restore_button)
	_purge_button = Button.new()
	_purge_button.text = "永久清理所选"
	_purge_button.pressed.connect(_purge_selected)
	header.add_child(_purge_button)
	var back_button := Button.new()
	back_button.text = "返回存档"
	back_button.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var pager := HBoxContainer.new()
	root.add_child(pager)
	_previous_page_button = Button.new()
	_previous_page_button.text = "上一页"
	_previous_page_button.pressed.connect(_show_previous_page)
	pager.add_child(_previous_page_button)
	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_page_label)
	_next_page_button = Button.new()
	_next_page_button.text = "下一页"
	_next_page_button.pressed.connect(_show_next_page)
	pager.add_child(_next_page_button)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 405)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_build_row_pool()
	_render_page()


func _build_row_pool() -> void:
	for slot_index in MAX_VISIBLE_ROWS:
		var row := HBoxContainer.new()
		var select_button := Button.new()
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.pressed.connect(Callable(self, "_select_slot").bind(slot_index))
		row.add_child(select_button)
		var restore_button := Button.new()
		restore_button.text = "恢复"
		restore_button.pressed.connect(Callable(self, "_restore_slot").bind(slot_index))
		row.add_child(restore_button)
		row.visible = false
		_list.add_child(row)
		_row_slots.append({
			"row": row,
			"select": select_button,
			"restore": restore_button,
		})
		_row_trash_ids.append("")
		_row_create_count += 1
