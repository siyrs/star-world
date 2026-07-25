class_name ProtectedSaveBrowserPanel
extends "res://src/ui/save_browser_panel.gd"

const ProtectedSaveServiceScript = preload(
	"res://src/save/protected_save_service.gd"
)
const TrashManagerPanelScript = preload(
	"res://src/ui/save_trash_manager_panel.gd"
)

var _delete_button: Button
var _undo_delete_button: Button
var _trash_manager_button: Button
var _pending_delete_world_id := ""
var _last_trash_id := ""
var _last_trashed_world_id := ""
var _trash_service: Node
var _owns_trash_service := false
var _active_content: Control
var _trash_manager: Control


func _ready() -> void:
	super._ready()
	for child: Node in get_children():
		if child is VBoxContainer:
			_active_content = child as Control
			break
	_install_delete_protection_controls()
	_build_trash_manager()
	_sync_last_trash_state()


func setup(p_save_service) -> void:
	_configure_trash_service(p_save_service)
	super.setup(p_save_service)
	if _trash_manager != null:
		_trash_manager.call("setup", _trash_service, false)
	_sync_last_trash_state()


func refresh() -> void:
	_hide_trash_manager(false)
	_reset_delete_confirmation()
	super.refresh()
	_sync_last_trash_state()


func apply_query(query: String, sort_mode: String = "") -> void:
	_reset_delete_confirmation()
	super.apply_query(query, sort_mode)


func get_virtualization_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_virtualization_snapshot()
	snapshot["pending_delete_world_id"] = _pending_delete_world_id
	snapshot["delete_confirmation_armed"] = not _pending_delete_world_id.is_empty()
	snapshot["last_trash_id"] = _last_trash_id
	snapshot["last_trashed_world_id"] = _last_trashed_world_id
	snapshot["undo_available"] = not _last_trash_id.is_empty()
	snapshot["trash_service_shared"] = _trash_service != null and not _owns_trash_service
	snapshot["trash_manager_visible"] = _trash_manager != null and _trash_manager.visible
	snapshot["trash_manager"] = (
		_trash_manager.call("get_management_snapshot")
		if _trash_manager != null and _trash_manager.has_method("get_management_snapshot")
		else {}
	)
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
		_hide_trash_manager(false)
		_reset_delete_confirmation()


func _delete_selected() -> void:
	if save_service == null or _selected_world_id.is_empty():
		_status.text = "请先选择一个世界。"
		_reset_delete_confirmation(false)
		return
	if _trash_service == null or not _trash_service.has_method("trash_world"):
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
	var result: Dictionary = _trash_service.call("trash_world", world_id)
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
	if _trash_service == null or not _trash_service.has_method("restore_trashed_world"):
		_status.text = "回收站恢复服务不可用。"
		return
	_sync_last_trash_state()
	if _last_trash_id.is_empty():
		_status.text = "当前没有可撤销的删除。"
		_update_undo_button()
		return
	var trash_id := _last_trash_id
	var result: Dictionary = _trash_service.call("restore_trashed_world", trash_id)
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


func _configure_trash_service(candidate: Node) -> void:
	if (
		candidate != null
		and candidate.has_method("trash_world")
		and candidate.has_method("restore_trashed_world")
	):
		if _owns_trash_service and _trash_service != null:
			_trash_service.queue_free()
		_trash_service = candidate
		_owns_trash_service = false
	else:
		if not (_owns_trash_service and _trash_service != null):
			_trash_service = ProtectedSaveServiceScript.new()
			_trash_service.name = "ProtectedDeletionService"
			add_child(_trash_service)
			_owns_trash_service = true
	if _trash_manager != null:
		_trash_manager.call("setup", _trash_service, false)


func _install_delete_protection_controls() -> void:
	if _active_content == null or _active_content.get_child_count() <= 0:
		return
	var header := _active_content.get_child(0) as HBoxContainer
	if header == null:
		return
	var back_button: Button
	for child: Node in header.get_children():
		var button := child as Button
		if button == null:
			continue
		if button.text == "删除所选":
			_delete_button = button
		elif button.text == "返回":
			back_button = button
	_undo_delete_button = Button.new()
	_undo_delete_button.text = "撤销删除"
	_undo_delete_button.disabled = true
	_undo_delete_button.pressed.connect(_undo_last_delete)
	header.add_child(_undo_delete_button)
	_trash_manager_button = Button.new()
	_trash_manager_button.text = "管理回收站"
	_trash_manager_button.pressed.connect(_show_trash_manager)
	header.add_child(_trash_manager_button)
	if back_button != null:
		var back_index := back_button.get_index()
		header.move_child(_undo_delete_button, back_index)
		header.move_child(_trash_manager_button, back_index + 1)
	_update_undo_button()


func _build_trash_manager() -> void:
	_trash_manager = TrashManagerPanelScript.new()
	_trash_manager.name = "TrashManager"
	_trash_manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trash_manager.visible = false
	add_child(_trash_manager)
	_trash_manager.call("setup", _trash_service, false)
	_trash_manager.connect("back_requested", Callable(self, "_on_trash_manager_back"))
	_trash_manager.connect("world_restored", Callable(self, "_on_managed_world_restored"))
	_trash_manager.connect("trash_slot_purged", Callable(self, "_on_managed_slot_purged"))


func _show_trash_manager() -> void:
	if _trash_manager == null:
		_status.text = "回收站管理页不可用。"
		return
	_reset_delete_confirmation()
	_trash_manager.call("setup", _trash_service)
	if _active_content != null:
		_active_content.visible = false
	_trash_manager.visible = true


func _hide_trash_manager(refresh_active: bool = true) -> void:
	if _trash_manager != null:
		_trash_manager.visible = false
	if _active_content != null:
		_active_content.visible = true
	if refresh_active and _list != null and save_service != null:
		super.refresh()
		_sync_last_trash_state()


func _on_trash_manager_back() -> void:
	_hide_trash_manager(true)


func _on_managed_world_restored(world_id: String, _trash_id: String) -> void:
	_selected_world_id = ""
	if _list != null and save_service != null:
		super.refresh()
	_sync_last_trash_state()
	_last_trashed_world_id = world_id


func _on_managed_slot_purged(_trash_id: String) -> void:
	_sync_last_trash_state()


func _sync_last_trash_state() -> void:
	if _trash_service == null or not _trash_service.has_method("get_last_trashed_world"):
		_last_trash_id = ""
		_last_trashed_world_id = ""
		_update_undo_button()
		return
	var raw_entry: Variant = _trash_service.call("get_last_trashed_world")
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
			return "回收站已满（最多 32 个世界），请进入“管理回收站”恢复或永久清理条目。"
		"world_exists":
			return "%s失败：同 ID 世界已经存在。" % operation
		"world_missing":
			return "%s失败：世界已经不存在。" % operation
		"trash_missing_or_invalid":
			return "%s失败：回收站条目缺失或损坏。" % operation
		_:
			return "%s失败：%s。" % [operation, reason]
