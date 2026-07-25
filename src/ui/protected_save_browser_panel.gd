class_name ProtectedSaveBrowserPanel
extends "res://src/ui/save_browser_panel.gd"

var _delete_button: Button
var _undo_delete_button: Button
var _pending_delete_world_id := ""
var _last_trash_id := ""
var _last_trashed_world_id := ""


func _ready() -> void:
	super._ready()
	_install_delete_protection_controls()
	_sync_last_trash_state()


func setup(p_save_service) -> void:
	super.setup(p_save_service)
	_sync_last_trash_state()


func refresh() -> void:
	_reset_delete_confirmation()
	super.refresh()
	_sync_last_trash_state()


func apply_query(query: String, sort_mode: String = "") -> void:
	_reset_delete_confirmation()
	super.apply_query(query, sort_mode)


func get_virtualization_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_virtualization_snapshot()
	snapshot["pending_delete_world_id"] = _pending_delete_world_id
	snapshot["delete_confirmation_armed"] = (
		not _pending_delete_world_id.is_empty()
	)
	snapshot["last_trash_id"] = _last_trash_id
	snapshot["last_trashed_world_id"] = _last_trashed_world_id
	snapshot["undo_available"] = not _last_trash_id.is_empty()
	return snapshot


func _select_slot(slot_index: int) -> void:
	_reset_delete_confirmation()
	super._select_slot(slot_index)


func _clear_hidden_selection() -> void:
	var previous_world_id := _selected_world_id
	super._clear_hidden_selection()
	if previous_world_id != _selected_world_id:
		_reset_delete_confirmation()


func _on_visibility_changed() -> void:
	super._on_visibility_changed()
	if visible:
		_sync_last_trash_state()
	else:
		_reset_delete_confirmation()


func _delete_selected() -> void:
	if save_service == null or _selected_world_id.is_empty():
		_status.text = "请先选择一个世界。"
		_reset_delete_confirmation(false)
		return
	if not save_service.has_method("trash_world"):
		_status.text = "回收站服务不可用，未执行删除。"
		_reset_delete_confirmation(false)
		return
	if _pending_delete_world_id != _selected_world_id:
		_pending_delete_world_id = _selected_world_id
		if _delete_button != null:
			_delete_button.text = "确认移到回收站"
		var metadata := _metadata_for_world(_selected_world_id)
		_status.text = "再次点击确认：将“%s”移到回收站，可撤销。" % str(
			metadata.get("name", _selected_world_id)
		)
		return
	var world_id := _selected_world_id
	var metadata := _metadata_for_world(world_id)
	var result: Dictionary = save_service.call("trash_world", world_id)
	_reset_delete_confirmation(false)
	if not bool(result.get("ok", false)):
		_status.text = _trash_failure_message(
			"删除", str(result.get("reason", "unknown"))
		)
		_sync_last_trash_state()
		return
	_last_trash_id = str(result.get("trash_id", ""))
	_last_trashed_world_id = world_id
	_selected_world_id = ""
	super.refresh()
	_sync_last_trash_state()
	_update_undo_button()
	_status.text = "已将“%s”移到回收站，可点击“撤销删除”恢复。" % str(
		metadata.get("name", world_id)
	)


func _undo_last_delete() -> void:
	if save_service == null or not save_service.has_method("restore_trashed_world"):
		_status.text = "回收站恢复服务不可用。"
		return
	_sync_last_trash_state()
	if _last_trash_id.is_empty():
		_status.text = "当前没有可撤销的删除。"
		_update_undo_button()
		return
	var trash_id := _last_trash_id
	var result: Dictionary = save_service.call(
		"restore_trashed_world", trash_id
	)
	if not bool(result.get("ok", false)):
		_status.text = _trash_failure_message(
			"恢复", str(result.get("reason", "unknown"))
		)
		_sync_last_trash_state()
		return
	var world_id := str(result.get("world_id", ""))
	var raw_entry: Variant = result.get("entry", {})
	var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
	_applied_query = ""
	_sync_query_controls()
	_selected_world_id = world_id
	super.refresh()
	_selected_world_id = world_id if _world_by_id.has(world_id) else ""
	_rebuild_filtered_world_ids()
	_render_page()
	_sync_last_trash_state()
	_status.text = "已恢复“%s”。" % str(entry.get("name", world_id))


func _install_delete_protection_controls() -> void:
	if get_child_count() <= 0:
		return
	var root := get_child(0) as VBoxContainer
	if root == null or root.get_child_count() <= 0:
		return
	var header := root.get_child(0) as HBoxContainer
	if header == null:
		return
	for child: Node in header.get_children():
		var button := child as Button
		if button != null and button.text == "删除所选":
			_delete_button = button
			break
	_undo_delete_button = Button.new()
	_undo_delete_button.text = "撤销删除"
	_undo_delete_button.disabled = true
	_undo_delete_button.pressed.connect(_undo_last_delete)
	header.add_child(_undo_delete_button)
	var insertion_index := maxi(0, header.get_child_count() - 2)
	header.move_child(_undo_delete_button, insertion_index)
	_update_undo_button()


func _sync_last_trash_state() -> void:
	if save_service == null or not save_service.has_method("get_last_trashed_world"):
		_last_trash_id = ""
		_last_trashed_world_id = ""
		_update_undo_button()
		return
	var raw_entry: Variant = save_service.call("get_last_trashed_world")
	var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
	_last_trash_id = str(entry.get("trash_id", ""))
	_last_trashed_world_id = str(entry.get("world_id", ""))
	_update_undo_button()


func _update_undo_button() -> void:
	if _undo_delete_button != null:
		_undo_delete_button.disabled = _last_trash_id.is_empty()


func _reset_delete_confirmation(reset_status: bool = false) -> void:
	_pending_delete_world_id = ""
	if _delete_button != null:
		_delete_button.text = "删除所选"
	if reset_status and _status != null:
		_status.text = _catalog_status(_worlds.size())


func _trash_failure_message(operation: String, reason: String) -> String:
	match reason:
		"trash_full":
			return "回收站已满（最多 32 个世界），请先恢复或清理旧条目。"
		"world_exists":
			return "%s失败：同 ID 世界已经存在。" % operation
		"world_missing":
			return "%s失败：世界已经不存在。" % operation
		"trash_missing_or_invalid":
			return "%s失败：回收站条目缺失或损坏。" % operation
		_:
			return "%s失败：%s。" % [operation, reason]
