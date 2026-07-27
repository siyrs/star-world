class_name SaveBrowserPanel
extends PanelContainer

signal load_requested(world_id: String)
signal back_requested

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const QueryPolicy = preload("res://src/ui/save_browser_query_policy.gd")

const MAX_VISIBLE_ROWS := 24
const MAX_AUTO_SETTLE_PASSES := 6

var save_service
var _list: VBoxContainer
var _status: Label
var _page_label: Label
var _previous_page_button: Button
var _next_page_button: Button
var _search_input: LineEdit
var _sort_option: OptionButton
var _selected_world_id: String = ""
var _worlds: Array = []
var _world_by_id: Dictionary = {}
var _filtered_world_ids: Array[String] = []
var _applied_query := ""
var _sort_mode := QueryPolicy.SORT_UPDATED_DESC
var _page_index := 0
var _row_slots: Array[Dictionary] = []
var _row_world_ids: Array[String] = []
var _row_create_count := 0
var _render_count := 0
var _refresh_count := 0
var _index_rebuild_count := 0
var _query_apply_count := 0
var _auto_settle_pass_count := 0
var _remaining_auto_settle_passes := 0
var _auto_settle_active := false
var _in_refresh := false


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	custom_minimum_size = Vector2(820, 590)
	_build_ui()
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func setup(p_save_service) -> void:
	save_service = p_save_service
	refresh()


func refresh() -> void:
	_perform_refresh(true)


func apply_query(
	query: String,
	sort_mode: String = ""
) -> void:
	_applied_query = QueryPolicy.normalize_query(query)
	if not sort_mode.is_empty():
		_sort_mode = QueryPolicy.normalize_sort_mode(sort_mode)
	_sync_query_controls()
	_query_apply_count += 1
	_page_index = 0
	_rebuild_filtered_world_ids()
	_clear_hidden_selection()
	_render_page()
	_status.text = _catalog_status(_worlds.size())


func clear_query() -> void:
	apply_query("", _sort_mode)


func show_page(index: int) -> void:
	_page_index = clampi(index, 0, _page_count() - 1)
	_render_page()


func get_visible_world_ids() -> Array[String]:
	var result: Array[String] = []
	for world_id: String in _row_world_ids:
		if not world_id.is_empty():
			result.append(world_id)
	return result


func get_virtualization_snapshot() -> Dictionary:
	return {
		"row_pool_limit": MAX_VISIBLE_ROWS,
		"row_pool_size": _row_slots.size(),
		"visible_row_count": get_visible_world_ids().size(),
		"page_index": _page_index,
		"page_count": _page_count(),
		"total_world_count": _worlds.size(),
		"indexed_world_count": _world_by_id.size(),
		"matched_world_count": _filtered_world_ids.size(),
		"applied_query": _applied_query,
		"query_token_count": QueryPolicy.query_tokens(_applied_query).size(),
		"sort_mode": _sort_mode,
		"row_create_count": _row_create_count,
		"render_count": _render_count,
		"refresh_count": _refresh_count,
		"index_rebuild_count": _index_rebuild_count,
		"query_apply_count": _query_apply_count,
		"auto_settle_limit": MAX_AUTO_SETTLE_PASSES,
		"auto_settle_pass_count": _auto_settle_pass_count,
		"remaining_auto_settle_passes": _remaining_auto_settle_passes,
		"auto_settle_active": _auto_settle_active,
	}


func _process(_delta: float) -> void:
	if (
		not _auto_settle_active
		or _in_refresh
		or not is_visible_in_tree()
	):
		set_process(false)
		return
	_auto_settle_active = false
	set_process(false)
	if _remaining_auto_settle_passes <= 0:
		return
	_remaining_auto_settle_passes -= 1
	_auto_settle_pass_count += 1
	_perform_refresh(false)


func _perform_refresh(reset_auto_budget: bool) -> void:
	if _list == null or _in_refresh:
		return
	if save_service == null:
		_worlds.clear()
		_world_by_id.clear()
		_filtered_world_ids.clear()
		_render_page()
		_status.text = "存档服务未连接"
		_stop_auto_settle()
		return
	_in_refresh = true
	var raw_worlds: Array = save_service.list_worlds()
	_rebuild_world_index(raw_worlds)
	_refresh_count += 1
	_rebuild_filtered_world_ids()
	_page_index = clampi(_page_index, 0, _page_count() - 1)
	if (
		not _selected_world_id.is_empty()
		and not _world_by_id.has(_selected_world_id)
	):
		_selected_world_id = ""
	_clear_hidden_selection()
	_render_page()
	if reset_auto_budget:
		_auto_settle_pass_count = 0
		_remaining_auto_settle_passes = MAX_AUTO_SETTLE_PASSES
	_in_refresh = false
	_sync_auto_settle_process()
	_status.text = _catalog_status(_worlds.size())


func _rebuild_world_index(raw_worlds: Array) -> void:
	_worlds.clear()
	_world_by_id.clear()
	for raw_metadata: Variant in raw_worlds:
		if not raw_metadata is Dictionary:
			continue
		var metadata: Dictionary = raw_metadata
		var world_id := str(metadata.get("id", ""))
		if world_id.is_empty() or _world_by_id.has(world_id):
			continue
		_worlds.append(metadata)
		_world_by_id[world_id] = metadata
	_index_rebuild_count += 1


func _rebuild_filtered_world_ids() -> void:
	_filtered_world_ids = QueryPolicy.select_world_ids(
		_worlds,
		_applied_query,
		_sort_mode
	)


func _clear_hidden_selection() -> void:
	if (
		not _selected_world_id.is_empty()
		and not _filtered_world_ids.has(_selected_world_id)
	):
		_selected_world_id = ""


func _sync_auto_settle_process() -> void:
	if not is_node_ready():
		return
	var has_backlog := _has_catalog_backlog()
	if not has_backlog:
		_remaining_auto_settle_passes = 0
	var should_process := (
		is_visible_in_tree()
		and save_service != null
		and has_backlog
		and _remaining_auto_settle_passes > 0
	)
	_auto_settle_active = should_process
	set_process(should_process)


func _stop_auto_settle() -> void:
	_remaining_auto_settle_passes = 0
	_auto_settle_active = false
	set_process(false)


func _has_catalog_backlog() -> bool:
	if (
		save_service == null
		or not save_service.has_method("get_catalog_diagnostics")
	):
		return false
	var diagnostics: Dictionary = save_service.call("get_catalog_diagnostics")
	return (
		maxi(0, int(diagnostics.get("last_deferred_recovery_count", 0))) > 0
		or maxi(0, int(diagnostics.get(
			"last_deferred_authoritative_read_count", 0
		))) > 0
		or maxi(0, int(diagnostics.get(
			"last_deferred_catalog_rebuild_count", 0
		))) > 0
		or maxi(0, int(diagnostics.get("staged_catalog_entry_count", 0))) > 0
	)


func _on_visibility_changed() -> void:
	_sync_auto_settle_process()


func _on_search_submitted(_value: String) -> void:
	_apply_search_from_controls()


func _on_sort_selected(index: int) -> void:
	if _sort_option == null or index < 0 or index >= _sort_option.item_count:
		return
	apply_query(
		_search_input.text if _search_input != null else _applied_query,
		str(_sort_option.get_item_metadata(index))
	)


func _apply_search_from_controls() -> void:
	apply_query(
		_search_input.text if _search_input != null else "",
		_selected_sort_mode()
	)


func _selected_sort_mode() -> String:
	if _sort_option == null or _sort_option.selected < 0:
		return _sort_mode
	return QueryPolicy.normalize_sort_mode(
		str(_sort_option.get_item_metadata(_sort_option.selected))
	)


func _sync_query_controls() -> void:
	if _search_input != null:
		_search_input.text = _applied_query
	if _sort_option == null:
		return
	for index in _sort_option.item_count:
		if str(_sort_option.get_item_metadata(index)) == _sort_mode:
			_sort_option.select(index)
			break


func _render_page() -> void:
	if _list == null:
		return
	_render_count += 1
	var start_index := _page_index * MAX_VISIBLE_ROWS
	for slot_index in MAX_VISIBLE_ROWS:
		var slot: Dictionary = _row_slots[slot_index]
		var row := slot.get("row") as HBoxContainer
		var select_button := slot.get("select") as Button
		var load_button := slot.get("load") as Button
		var world_index := start_index + slot_index
		if world_index >= _filtered_world_ids.size():
			_row_world_ids[slot_index] = ""
			row.visible = false
			select_button.text = ""
			load_button.disabled = true
			continue
		var world_id := _filtered_world_ids[world_index]
		var metadata := _metadata_for_world(world_id)
		_row_world_ids[slot_index] = world_id
		row.visible = not metadata.is_empty()
		load_button.disabled = metadata.is_empty()
		select_button.text = _metadata_text(metadata)
		if world_id == _selected_world_id:
			select_button.text = "▶ %s" % select_button.text
	_update_page_controls()


func _metadata_text(metadata: Dictionary) -> String:
	var metadata_pending := bool(
		metadata.get("authoritative_read_deferred", false)
	)
	var catalog_staged := bool(metadata.get("catalog_staged", false))
	if metadata_pending:
		return "%s\n世界信息待读取 · 存档 %s" % [
			metadata.get("name", "未命名"),
			_format_bytes(int(metadata.get("save_bytes", 0))),
		]
	return "%s\n%s  Seed %s  更新 %s  存档 %s%s" % [
		metadata.get("name", "未命名"),
		metadata.get("map_id", ""),
		metadata.get("seed", 0),
		metadata.get("updated_at", ""),
		_format_bytes(int(metadata.get("save_bytes", 0))),
		" · 目录待写" if catalog_staged else "",
	]


func _select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _row_world_ids.size():
		return
	var world_id := _row_world_ids[slot_index]
	if world_id.is_empty():
		return
	_selected_world_id = world_id
	var metadata := _metadata_for_world(world_id)
	_status.text = "已选: %s · 存档 %s" % [
		metadata.get("name", world_id),
		_format_bytes(int(metadata.get("save_bytes", 0))),
	]
	_render_page()


func _load_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _row_world_ids.size():
		return
	var world_id := _row_world_ids[slot_index]
	if not world_id.is_empty():
		load_requested.emit(world_id)


func _show_previous_page() -> void:
	show_page(_page_index - 1)


func _show_next_page() -> void:
	show_page(_page_index + 1)


func _page_count() -> int:
	return maxi(
		1,
		ceili(float(_filtered_world_ids.size()) / float(MAX_VISIBLE_ROWS))
	)


func _update_page_controls() -> void:
	if _page_label == null:
		return
	var pages := _page_count()
	_page_label.text = "第 %d / %d 页 · 匹配 %d / 共 %d · 每页最多 %d 个" % [
		_page_index + 1,
		pages,
		_filtered_world_ids.size(),
		_worlds.size(),
		MAX_VISIBLE_ROWS,
	]
	_previous_page_button.disabled = _page_index <= 0
	_next_page_button.disabled = _page_index >= pages - 1


func _metadata_for_world(world_id: String) -> Dictionary:
	var raw_metadata: Variant = _world_by_id.get(world_id, {})
	return raw_metadata if raw_metadata is Dictionary else {}


func _catalog_status(world_count: int) -> String:
	if (
		save_service == null
		or not save_service.has_method("get_catalog_diagnostics")
	):
		return _query_status("共 %d 个世界" % world_count)
	var diagnostics: Dictionary = save_service.call("get_catalog_diagnostics")
	var elapsed_ms := float(
		diagnostics.get("last_elapsed_milliseconds", 0.0)
	)
	var repairs := int(diagnostics.get("last_repair_count", 0))
	var deferred := maxi(
		0, int(diagnostics.get("last_deferred_recovery_count", 0))
	)
	var repair_budget := maxi(
		0, int(diagnostics.get("primary_repair_budget", 0))
	)
	var deferred_catalogs := maxi(
		0, int(diagnostics.get("last_deferred_catalog_rebuild_count", 0))
	)
	var catalog_budget := maxi(
		0, int(diagnostics.get("catalog_rebuild_budget", 0))
	)
	var deferred_reads := maxi(
		0, int(diagnostics.get("last_deferred_authoritative_read_count", 0))
	)
	var read_budget := maxi(
		0, int(diagnostics.get("authoritative_read_budget", 0))
	)
	var staged_catalogs := maxi(
		0, int(diagnostics.get("staged_catalog_entry_count", 0))
	)
	var stage_capacity := maxi(
		0, int(diagnostics.get("catalog_stage_capacity", 0))
	)
	var stage_hits := maxi(
		0, int(diagnostics.get("last_stage_hit_count", 0))
	)
	var status := "共 %d 个世界 · 目录 %.1f ms" % [world_count, elapsed_ms]
	if repairs > 0:
		status += " · 已修复 %d 个旧目录" % repairs
	if deferred > 0:
		status += " · 待渐进修复 %d（每次最多 %d）" % [
			deferred, repair_budget
		]
	if deferred_reads > 0:
		status += " · 待读世界 %d（每次最多 %d）" % [
			deferred_reads, read_budget
		]
	if deferred_catalogs > 0:
		status += " · 待建目录 %d（每次最多 %d）" % [
			deferred_catalogs, catalog_budget
		]
	if staged_catalogs > 0:
		status += " · 暂存目录 %d/%d" % [staged_catalogs, stage_capacity]
	if stage_hits > 0:
		status += " · 暂存命中 %d" % stage_hits
	if _auto_settle_active:
		status += " · 自动整理 %d/%d" % [
			_auto_settle_pass_count, MAX_AUTO_SETTLE_PASSES
		]
	if save_service.has_method("get_recovery_diagnostics"):
		var recovery: Dictionary = save_service.call(
			"get_recovery_diagnostics"
		)
		var repaired := maxi(
			0, int(recovery.get("repair_success_count", 0))
		)
		var failures := maxi(
			0, int(recovery.get("repair_failure_count", 0))
		)
		if repaired > 0:
			status += " · 已自愈 %d 个存档" % repaired
		if failures > 0:
			status += " · 主文件修复失败 %d" % failures
	return _query_status(status)


func _query_status(base_status: String) -> String:
	if _applied_query.is_empty() and _filtered_world_ids.size() == _worlds.size():
		return base_status
	return "%s · 搜索匹配 %d" % [
		base_status,
		_filtered_world_ids.size(),
	]


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
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var query_bar := HBoxContainer.new()
	root.add_child(query_bar)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "搜索名称 / ID / 地图 / Seed"
	_search_input.max_length = QueryPolicy.MAX_QUERY_LENGTH
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.text_submitted.connect(_on_search_submitted)
	query_bar.add_child(_search_input)
	var search_button := Button.new()
	search_button.text = "搜索"
	search_button.pressed.connect(_apply_search_from_controls)
	query_bar.add_child(search_button)
	var clear_button := Button.new()
	clear_button.text = "清除"
	clear_button.pressed.connect(clear_query)
	query_bar.add_child(clear_button)
	_sort_option = OptionButton.new()
	_sort_option.add_item("最近更新")
	_sort_option.set_item_metadata(0, QueryPolicy.SORT_UPDATED_DESC)
	_sort_option.add_item("名称 A-Z")
	_sort_option.set_item_metadata(1, QueryPolicy.SORT_NAME_ASC)
	_sort_option.add_item("存档从大到小")
	_sort_option.set_item_metadata(2, QueryPolicy.SORT_SIZE_DESC)
	_sort_option.item_selected.connect(_on_sort_selected)
	query_bar.add_child(_sort_option)
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
	_sync_query_controls()
	_render_page()


func _build_row_pool() -> void:
	for slot_index in MAX_VISIBLE_ROWS:
		var row := HBoxContainer.new()
		var select_button := Button.new()
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.pressed.connect(
			Callable(self, "_select_slot").bind(slot_index)
		)
		row.add_child(select_button)
		var load_button := Button.new()
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


func _delete_selected() -> void:
	if save_service != null and not _selected_world_id.is_empty():
		save_service.delete_world(_selected_world_id)
		_selected_world_id = ""
		refresh()
