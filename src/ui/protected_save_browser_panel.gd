class_name ProtectedSaveBrowserPanel
extends "res://src/ui/save_browser_panel.gd"

const ProtectedSaveServiceScript = preload(
	"res://src/save/protected_save_service.gd"
)
const TrashManagerPanelScript = preload(
	"res://src/ui/save_trash_manager_panel.gd"
)
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")

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
var _save_list_card: PanelContainer
var _query_card: PanelContainer


func _ready() -> void:
	super._ready()
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(920, 550)
	for child: Node in get_children():
		if child is VBoxContainer:
			_active_content = child as Control
			break
	_install_delete_protection_controls()
	_build_trash_manager()
	_sync_last_trash_state()
	_apply_action_styles()


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
	snapshot["visual"] = {
		"panel": get_global_rect(),
		"query_card": _query_card.get_global_rect() if _query_card != null else Rect2(),
		"list_card": _save_list_card.get_global_rect() if _save_list_card != null else Rect2(),
		"delete_variation": _delete_button.theme_type_variation if _delete_button != null else "",
	}
	return snapshot


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "ActiveSaveContent"
	root.add_theme_constant_override("separation", Tokens.SPACE_MD)
	add_child(root)

	# This remains the first child for the protected-deletion composition contract.
	var header := HBoxContainer.new()
	header.name = "SaveBrowserHeader"
	header.add_theme_constant_override("separation", Tokens.SPACE_SM)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("WORLD ARCHIVE"))
	heading.add_child(UiKit.make_title("世界存档"))
	heading.add_child(UiKit.make_subtitle("搜索、排序、继续远征，或通过受保护回收站管理世界。"))

	var delete_button := UiKit.style_button(
		Button.new(), "DangerButton", Vector2(126, Tokens.CONTROL_HEIGHT_MD)
	)
	delete_button.text = "删除所选"
	delete_button.pressed.connect(_delete_selected)
	header.add_child(delete_button)
	var back := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(104, Tokens.CONTROL_HEIGHT_MD)
	)
	back.text = "返回"
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)

	_status = Label.new()
	_status.name = "SaveBrowserStatus"
	_status.theme_type_variation = "CaptionLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 32
	_status.add_theme_stylebox_override(
		"normal",
		Tokens.bevel_style("#B0B0B0", "#7A7A7A", 2, 7.0)
	)
	root.add_child(_status)

	_query_card = UiKit.make_card("CardPanel")
	root.add_child(_query_card)
	var query_bar := HBoxContainer.new()
	query_bar.name = "SaveQueryBar"
	query_bar.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_query_card.add_child(query_bar)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "搜索名称 / ID / 地图 / Seed"
	_search_input.max_length = QueryPolicy.MAX_QUERY_LENGTH
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.custom_minimum_size.y = Tokens.CONTROL_HEIGHT_MD
	_search_input.text_submitted.connect(_on_search_submitted)
	query_bar.add_child(_search_input)
	var search_button := UiKit.style_button(
		Button.new(), "SecondaryButton", Vector2(96, Tokens.CONTROL_HEIGHT_MD)
	)
	search_button.text = "搜索"
	search_button.pressed.connect(_apply_search_from_controls)
	query_bar.add_child(search_button)
	var clear_button := UiKit.style_button(
		Button.new(), "ToolbarButton", Vector2(82, Tokens.CONTROL_HEIGHT_MD)
	)
	clear_button.text = "清除"
	clear_button.pressed.connect(clear_query)
	query_bar.add_child(clear_button)
	_sort_option = OptionButton.new()
	_sort_option.custom_minimum_size = Vector2(154, Tokens.CONTROL_HEIGHT_MD)
	_sort_option.add_item("最近更新")
	_sort_option.set_item_metadata(0, QueryPolicy.SORT_UPDATED_DESC)
	_sort_option.add_item("名称 A-Z")
	_sort_option.set_item_metadata(1, QueryPolicy.SORT_NAME_ASC)
	_sort_option.add_item("存档从大到小")
	_sort_option.set_item_metadata(2, QueryPolicy.SORT_SIZE_DESC)
	_sort_option.item_selected.connect(_on_sort_selected)
	query_bar.add_child(_sort_option)

	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", Tokens.SPACE_SM)
	root.add_child(pager)
	_previous_page_button = UiKit.style_button(
		Button.new(), "ToolbarButton", Vector2(102, Tokens.CONTROL_HEIGHT_SM)
	)
	_previous_page_button.text = "上一页"
	_previous_page_button.pressed.connect(_show_previous_page)
	pager.add_child(_previous_page_button)
	_page_label = Label.new()
	_page_label.theme_type_variation = "CaptionLabel"
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(_page_label)
	_next_page_button = UiKit.style_button(
		Button.new(), "ToolbarButton", Vector2(102, Tokens.CONTROL_HEIGHT_SM)
	)
	_next_page_button.text = "下一页"
	_next_page_button.pressed.connect(_show_next_page)
	pager.add_child(_next_page_button)

	_save_list_card = UiKit.make_card("InsetPanel")
	_save_list_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_save_list_card)
	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_save_list_card.add_child(list_root)
	var list_header := HBoxContainer.new()
	list_root.add_child(list_header)
	var list_title := Label.new()
	list_title.text = "远征档案"
	list_title.theme_type_variation = "SectionTitle"
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(list_title)
	list_header.add_child(UiKit.make_badge("虚拟化 24 行", "info"))
	var scroll := ScrollContainer.new()
	scroll.name = "SaveListScroll"
	scroll.custom_minimum_size = Vector2(830, 330)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", Tokens.SPACE_SM)
	scroll.add_child(_list)
	_build_row_pool()
	_sync_query_controls()
	_render_page()


func _build_row_pool() -> void:
	for slot_index in MAX_VISIBLE_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Tokens.SPACE_SM)
		var select_button := UiKit.style_button(
			Button.new(), "CardButton", Vector2(0, 64)
		)
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.pressed.connect(
			Callable(self, "_select_slot").bind(slot_index)
		)
		row.add_child(select_button)
		var load_button := UiKit.style_button(
			Button.new(), "SecondaryButton", Vector2(112, 64)
		)
		load_button.text = "继续"
		load_button.pressed.connect(
			Callable(self, "_load_slot").bind(slot_index)
		)
		row.add_child(load_button)
		row.visible = false
		_list.add_child(row)
		_row_slots.append({
			"row": row,
			"select": select_button,
			"load": load_button,
		})
		_row_world_ids.append("")
		_row_create_count += 1


func _render_page() -> void:
	super._render_page()
	for slot_index in _row_slots.size():
		var slot: Dictionary = _row_slots[slot_index]
		var select_button := slot.get("select") as Button
		var load_button := slot.get("load") as Button
		if select_button == null:
			continue
		var world_id := _row_world_ids[slot_index] if slot_index < _row_world_ids.size() else ""
		UiKit.set_selected_card(select_button, not world_id.is_empty() and world_id == _selected_world_id)
		if load_button != null:
			load_button.theme_type_variation = "PrimaryButton" if world_id == _selected_world_id else "SecondaryButton"


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
		_status.theme_type_variation = "DangerLabel"
		_reset_delete_confirmation(false)
		return
	if _trash_service == null or not _trash_service.has_method("trash_world"):
		_status.text = "回收站服务不可用，未执行删除。"
		_status.theme_type_variation = "DangerLabel"
		_reset_delete_confirmation(false)
		return
	if _pending_delete_world_id != _selected_world_id:
		_pending_delete_world_id = _selected_world_id
		if _delete_button != null:
			_delete_button.text = "确认移到回收站"
			_delete_button.theme_type_variation = "DangerButton"
		var metadata := _metadata_for_world(_selected_world_id)
		_status.text = "再次点击确认：将“%s”移到回收站，可撤销。" % str(
			metadata.get("name", _selected_world_id)
		)
		_status.theme_type_variation = "DangerLabel"
		return
	var world_id := _selected_world_id
	var metadata := _metadata_for_world(world_id)
	var result: Dictionary = _trash_service.call("trash_world", world_id)
	_reset_delete_confirmation(false)
	if not bool(result.get("ok", false)):
		_status.text = _trash_failure_message(
			"删除", str(result.get("reason", "unknown"))
		)
		_status.theme_type_variation = "DangerLabel"
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
	_status.theme_type_variation = "SuccessLabel"


func _undo_last_delete() -> void:
	if _trash_service == null or not _trash_service.has_method("restore_trashed_world"):
		_status.text = "回收站恢复服务不可用。"
		_status.theme_type_variation = "DangerLabel"
		return
	_sync_last_trash_state()
	if _last_trash_id.is_empty():
		_status.text = "当前没有可撤销的删除。"
		_status.theme_type_variation = "CaptionLabel"
		_update_undo_button()
		return
	var trash_id := _last_trash_id
	var result: Dictionary = _trash_service.call("restore_trashed_world", trash_id)
	if not bool(result.get("ok", false)):
		_status.text = _trash_failure_message(
			"恢复", str(result.get("reason", "unknown"))
		)
		_status.theme_type_variation = "DangerLabel"
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
	_status.theme_type_variation = "SuccessLabel"


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
	_undo_delete_button = UiKit.style_button(
		Button.new(), "SecondaryButton", Vector2(112, Tokens.CONTROL_HEIGHT_MD)
	)
	_undo_delete_button.text = "撤销删除"
	_undo_delete_button.disabled = true
	_undo_delete_button.pressed.connect(_undo_last_delete)
	header.add_child(_undo_delete_button)
	_trash_manager_button = UiKit.style_button(
		Button.new(), "GhostButton", Vector2(132, Tokens.CONTROL_HEIGHT_MD)
	)
	_trash_manager_button.text = "管理回收站"
	_trash_manager_button.pressed.connect(_show_trash_manager)
	header.add_child(_trash_manager_button)
	if back_button != null:
		var back_index := back_button.get_index()
		header.move_child(_undo_delete_button, back_index)
		header.move_child(_trash_manager_button, back_index + 1)
	_update_undo_button()


func _apply_action_styles() -> void:
	if _delete_button != null:
		UiKit.style_button(_delete_button, "DangerButton", Vector2(126, Tokens.CONTROL_HEIGHT_MD))
	if _undo_delete_button != null:
		UiKit.style_button(_undo_delete_button, "SecondaryButton", Vector2(112, Tokens.CONTROL_HEIGHT_MD))
	if _trash_manager_button != null:
		UiKit.style_button(_trash_manager_button, "GhostButton", Vector2(132, Tokens.CONTROL_HEIGHT_MD))


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
		_status.theme_type_variation = "DangerLabel"
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
		_delete_button.theme_type_variation = "DangerButton"
	if reset_status and _status != null:
		_status.text = _catalog_status(_worlds.size())
		_status.theme_type_variation = "CaptionLabel"


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
