class_name StonecutterPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const IconFactory = preload("res://src/ui/item_icon_factory.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const SLOT_INPUT := "input"
const SLOT_OUTPUT := "output"

var inventory
var stonecutter_service
var _active_machine_id := ""
var _title: Label
var _status: Label
var _recipe_label: Label
var _queue_label: Label
var _progress: ProgressBar
var _input_button: Button
var _output_button: Button
var _inventory_grid: GridContainer
var _inventory_buttons: Array = []


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(820, 500)
	_build_ui()


func setup(p_inventory, p_stonecutter_service) -> void:
	_disconnect_services()
	inventory = p_inventory
	stonecutter_service = p_stonecutter_service
	if inventory != null:
		inventory.inventory_changed.connect(refresh)
	if stonecutter_service != null:
		stonecutter_service.machine_changed.connect(_on_machine_changed)
		stonecutter_service.active_machine_changed.connect(_on_active_machine_changed)
		stonecutter_service.transfer_rejected.connect(_on_transfer_rejected)
	refresh()


func open_machine(machine_id: String, title: String = "石材切割机") -> bool:
	if stonecutter_service == null or machine_id.is_empty():
		return false
	if not bool(stonecutter_service.open_machine(machine_id)):
		return false
	_active_machine_id = machine_id
	_title.text = title
	_status.text = "点击背包中的石材原料即可投入"
	refresh()
	return true


func close_machine() -> void:
	_active_machine_id = ""
	if stonecutter_service != null:
		stonecutter_service.close_machine()


func get_active_machine_id() -> String:
	return _active_machine_id


func refresh() -> void:
	if _status == null:
		return
	_refresh_inventory()
	if stonecutter_service == null or _active_machine_id.is_empty():
		_show_empty_machine()
		return
	var snapshot: Dictionary = stonecutter_service.get_machine_snapshot(
		_active_machine_id
	)
	if snapshot.is_empty():
		_show_empty_machine()
		return
	_input_button.text = _slot_text("原料", snapshot.get(SLOT_INPUT, {}))
	_output_button.text = _slot_text("产出", snapshot.get(SLOT_OUTPUT, {}))
	_input_button.icon = _slot_icon(snapshot.get(SLOT_INPUT, {}))
	_output_button.icon = _slot_icon(snapshot.get(SLOT_OUTPUT, {}))
	_progress.value = float(snapshot.get("progress_ratio", 0.0))
	var recipe: Dictionary = snapshot.get("recipe", {})
	_recipe_label.text = (
		"当前配方：%s" % str(recipe.get("name", ""))
		if not recipe.is_empty()
		else "当前配方：等待石材"
	)
	var queued_jobs := maxi(0, int(snapshot.get("queued_jobs", 0)))
	var remaining := maxf(0.0, float(snapshot.get("remaining_seconds", 0.0)))
	var total := maxf(0.0, float(snapshot.get("estimated_total_seconds", 0.0)))
	_queue_label.text = (
		"队列 %d · 下一份 %.1f 秒 · 全部 %.1f 秒"
		% [queued_jobs, remaining, total]
		if queued_jobs > 0
		else "队列为空"
	)
	_status.text = str(snapshot.get("status", "等待操作"))


func get_layout_rects() -> Dictionary:
	return {
		"input": _input_button.get_global_rect() if _input_button != null else Rect2(),
		"output": _output_button.get_global_rect() if _output_button != null else Rect2(),
		"inventory": _inventory_grid.get_global_rect() if _inventory_grid != null else Rect2(),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_SM)
	root.add_child(header)
	_title = Label.new()
	_title.text = "石材切割机"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 26)
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.custom_minimum_size = Vector2(140, 40)
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)
	var description := Label.new()
	description.text = "无需燃料；关闭界面后继续切割，世界暂停时同步停止。"
	description.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	description.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(description)
	var machine_panel := PanelContainer.new()
	machine_panel.add_theme_stylebox_override(
		"panel",
		Tokens.panel_style(
			Tokens.COLOR_SURFACE_RAISED,
			Tokens.COLOR_BORDER_STRONG,
			1,
			Tokens.RADIUS_MD,
			Tokens.SPACE_SM
		)
	)
	root.add_child(machine_panel)
	var machine_row := HBoxContainer.new()
	machine_row.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	machine_panel.add_child(machine_row)
	_input_button = _make_machine_slot("原料\n空")
	_input_button.pressed.connect(func() -> void: _take_machine_slot(SLOT_INPUT))
	machine_row.add_child(_input_button)
	var process_column := VBoxContainer.new()
	process_column.custom_minimum_size = Vector2(300, 120)
	process_column.add_theme_constant_override("separation", Tokens.SPACE_XS)
	machine_row.add_child(process_column)
	_recipe_label = Label.new()
	_recipe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recipe_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	process_column.add_child(_recipe_label)
	var progress_caption := Label.new()
	progress_caption.text = "切割进度"
	progress_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_caption.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	progress_caption.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	process_column.add_child(progress_caption)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 12.0
	process_column.add_child(_progress)
	_queue_label = Label.new()
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_queue_label.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	_queue_label.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	process_column.add_child(_queue_label)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 28)
	arrow.modulate = Tokens.color(Tokens.COLOR_ACCENT_WARM)
	machine_row.add_child(arrow)
	_output_button = _make_machine_slot("产出\n空")
	_output_button.pressed.connect(func() -> void: _take_machine_slot(SLOT_OUTPUT))
	machine_row.add_child(_output_button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 24.0
	_status.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	root.add_child(_status)
	var separator := HSeparator.new()
	root.add_child(separator)
	var inventory_header := HBoxContainer.new()
	root.add_child(inventory_header)
	var inventory_title := Label.new()
	inventory_title.text = "玩家背包"
	inventory_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_title.add_theme_font_size_override("font_size", 20)
	inventory_header.add_child(inventory_title)
	var inventory_hint := Label.new()
	inventory_hint.text = "点击投入 · 点击上方槽位取回"
	inventory_hint.modulate = Tokens.color(Tokens.COLOR_TEXT_MUTED)
	inventory_hint.add_theme_font_size_override("font_size", Tokens.FONT_CAPTION)
	inventory_header.add_child(inventory_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 9
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_inventory_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	scroll.add_child(_inventory_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = Vector2(56, 50)
		slot.slot_clicked.connect(_on_inventory_slot_clicked)
		_inventory_grid.add_child(slot)
		_inventory_buttons.append(slot)


func _make_machine_slot(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(145, 105)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button


func _refresh_inventory() -> void:
	if inventory == null:
		return
	for index in _inventory_buttons.size():
		_inventory_buttons[index].display_slot(
			inventory.get_slot(index),
			inventory.registry,
			index == inventory.selected_slot
		)


func _show_empty_machine() -> void:
	_input_button.text = "原料\n空"
	_output_button.text = "产出\n空"
	_progress.value = 0.0
	_recipe_label.text = "当前配方：未连接"
	_queue_label.text = "队列为空"
	_status.text = "石材切割机服务未连接"


func _slot_text(label: String, slot: Dictionary) -> String:
	if slot.is_empty():
		return "%s\n空" % label
	var item_id := str(slot.get("item_id", ""))
	var display_name := (
		str(inventory.registry.get_display_name(item_id))
		if inventory != null
		else item_id
	)
	return "%s\n%s ×%d" % [label, display_name, int(slot.get("count", 0))]


func _slot_icon(slot: Dictionary) -> Texture2D:
	if slot.is_empty() or inventory == null:
		return null
	var item_id := str(slot.get("item_id", ""))
	var item: Dictionary = inventory.registry.get_item(item_id)
	return IconFactory.get_icon(item_id, item)


func _on_inventory_slot_clicked(index: int) -> void:
	if stonecutter_service == null or _active_machine_id.is_empty():
		return
	if not stonecutter_service.transfer_from_inventory_auto(
		inventory,
		index,
		_active_machine_id
	):
		_status.text = "该物品不能切割，或原料槽没有空间"


func _take_machine_slot(slot_name: String) -> void:
	if stonecutter_service == null or _active_machine_id.is_empty():
		return
	if not stonecutter_service.transfer_to_inventory(
		inventory,
		slot_name,
		_active_machine_id
	):
		_status.text = "槽位为空，或背包没有足够空间"


func _on_machine_changed(machine_id: String, _snapshot: Dictionary) -> void:
	if machine_id == _active_machine_id:
		refresh()


func _on_active_machine_changed(machine_id: String) -> void:
	if machine_id.is_empty() and not _active_machine_id.is_empty():
		_active_machine_id = ""


func _on_transfer_rejected(machine_id: String, reason: String) -> void:
	if machine_id != _active_machine_id:
		return
	_status.text = {
		"unsupported_item": "该物品不能在石材切割机中加工",
		"unsupported_input": "该物品不能切割",
		"slot_full_or_mismatch": "原料槽已满，或需要先取走不同物品",
		"inventory_full": "背包空间不足",
	}.get(reason, "无法完成该操作")


func _disconnect_services() -> void:
	if inventory != null:
		var inventory_callback := Callable(self, "refresh")
		if inventory.inventory_changed.is_connected(inventory_callback):
			inventory.inventory_changed.disconnect(inventory_callback)
	if stonecutter_service != null:
		var changed_callback := Callable(self, "_on_machine_changed")
		if stonecutter_service.machine_changed.is_connected(changed_callback):
			stonecutter_service.machine_changed.disconnect(changed_callback)
		var active_callback := Callable(self, "_on_active_machine_changed")
		if stonecutter_service.active_machine_changed.is_connected(active_callback):
			stonecutter_service.active_machine_changed.disconnect(active_callback)
		var rejected_callback := Callable(self, "_on_transfer_rejected")
		if stonecutter_service.transfer_rejected.is_connected(rejected_callback):
			stonecutter_service.transfer_rejected.disconnect(rejected_callback)


func _exit_tree() -> void:
	_disconnect_services()
