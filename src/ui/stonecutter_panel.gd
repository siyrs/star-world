class_name StonecutterPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const IconFactory = preload("res://src/ui/item_icon_factory.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const SLOT_INPUT := "input"
const SLOT_OUTPUT := "output"
const MACHINE_SLOTS: Array[String] = [SLOT_INPUT, SLOT_OUTPUT]

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
var _status_kind := "idle"
var _status_reason := ""
var _status_target_id := ""
var _feedback_revision := 0
var _pending_action_target_id := ""


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	custom_minimum_size = Vector2(820, 500)
	_build_ui()


func setup(p_inventory, p_stonecutter_service) -> void:
	_disconnect_services()
	inventory = p_inventory
	stonecutter_service = p_stonecutter_service
	if inventory != null and inventory.has_signal("inventory_changed"):
		inventory.inventory_changed.connect(refresh)
	if stonecutter_service != null:
		if stonecutter_service.has_signal("machine_changed"):
			stonecutter_service.machine_changed.connect(_on_machine_changed)
		if stonecutter_service.has_signal("active_machine_changed"):
			stonecutter_service.active_machine_changed.connect(_on_active_machine_changed)
		if stonecutter_service.has_signal("item_transferred"):
			stonecutter_service.item_transferred.connect(_on_item_transferred)
		if stonecutter_service.has_signal("item_processed"):
			stonecutter_service.item_processed.connect(_on_item_processed)
		if stonecutter_service.has_signal("transfer_rejected"):
			stonecutter_service.transfer_rejected.connect(_on_transfer_rejected)
	_reset_feedback()
	refresh()


func open_machine(machine_id: String, title: String = "石材切割机") -> bool:
	if stonecutter_service == null or machine_id.is_empty():
		return false
	if not bool(stonecutter_service.open_machine(machine_id)):
		return false
	_active_machine_id = machine_id
	_title.text = title
	_reset_feedback()
	refresh()
	_set_status(
		"点击背包中的石材原料即可投入",
		"idle",
		"opened",
		_machine_target_id(machine_id),
	)
	return true


func close_machine() -> void:
	_active_machine_id = ""
	_reset_feedback()
	if stonecutter_service != null:
		stonecutter_service.close_machine()


func get_active_machine_id() -> String:
	return _active_machine_id


func get_machine_slot_button(slot_name: String) -> Button:
	match slot_name:
		SLOT_INPUT:
			return _input_button
		SLOT_OUTPUT:
			return _output_button
		_:
			return null


func get_inventory_button(index: int) -> Button:
	if index < 0 or index >= _inventory_buttons.size():
		return null
	return _inventory_buttons[index] as Button


func get_visual_snapshot() -> Dictionary:
	var machine_snapshot: Dictionary = {}
	if (
		stonecutter_service != null
		and not _active_machine_id.is_empty()
		and stonecutter_service.has_method("get_machine_snapshot")
	):
		machine_snapshot = stonecutter_service.get_machine_snapshot(_active_machine_id)
	var machine_slots: Dictionary = {}
	for slot_name: String in MACHINE_SLOTS:
		var button := get_machine_slot_button(slot_name)
		var slot: Dictionary = machine_snapshot.get(slot_name, {})
		machine_slots[slot_name] = {
			"target_id": (
				str(button.get_meta("target_id", ""))
				if button != null
				else ""
			),
			"slot_name": (
				str(button.get_meta("slot_name", ""))
				if button != null
				else ""
			),
			"direction": (
				str(button.get_meta("direction", ""))
				if button != null
				else ""
			),
			"item_id": str(slot.get("item_id", "")),
			"count": int(slot.get("count", 0)),
			"text": button.text if button != null else "",
			"disabled": button.disabled if button != null else true,
		}
	var inventory_targets: Dictionary = {}
	for index in _inventory_buttons.size():
		var button := _inventory_buttons[index] as Button
		if button == null:
			continue
		var slot: Dictionary = (
			inventory.get_slot(index)
			if inventory != null and inventory.has_method("get_slot")
			else {}
		)
		var target_id := str(button.get_meta("target_id", ""))
		inventory_targets[target_id] = {
			"slot_index": int(button.get_meta("slot_index", -1)),
			"item_id": str(slot.get("item_id", "")),
			"count": int(slot.get("count", 0)),
			"disabled": button.disabled,
			"tooltip": button.tooltip_text,
		}
	return {
		"visible": visible,
		"machine_id": _active_machine_id,
		"status_kind": _status_kind,
		"status_reason": _status_reason,
		"status_target_id": _status_target_id,
		"status_text": _status.text if _status != null else "",
		"recipe_text": _recipe_label.text if _recipe_label != null else "",
		"queue_text": _queue_label.text if _queue_label != null else "",
		"progress_ratio": _progress.value if _progress != null else 0.0,
		"machine_slots": machine_slots,
		"inventory_target_count": inventory_targets.size(),
		"inventory_targets": inventory_targets,
	}


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
	if _status_kind == "idle":
		_set_status(
			str(snapshot.get("status", "等待操作")),
			"idle",
			"machine_status",
			_machine_target_id(_active_machine_id),
		)


func get_layout_rects() -> Dictionary:
	return {
		"panel": get_global_rect(),
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
	close_button.set_meta("target_id", "stonecutter:close")
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
		Tokens.bevel_style(
			"#BCBCBC",
			"#7A7A7A",
			2,
			Tokens.SPACE_SM,
		),
	)
	root.add_child(machine_panel)
	var machine_row := HBoxContainer.new()
	machine_row.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	machine_panel.add_child(machine_row)
	_input_button = _make_machine_slot("原料\n空", SLOT_INPUT)
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
	arrow.modulate = Color("#B8860B")
	machine_row.add_child(arrow)
	_output_button = _make_machine_slot("产出\n空", SLOT_OUTPUT)
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
		slot.set_meta("target_id", _inventory_target_id(index))
		slot.set_meta("slot_index", index)
		slot.set_meta("direction", "inventory_to_machine")
		slot.slot_clicked.connect(_on_inventory_slot_clicked)
		_inventory_grid.add_child(slot)
		_inventory_buttons.append(slot)


func _make_machine_slot(label: String, slot_name: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(145, 105)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.set_meta("target_id", _machine_slot_target_id(slot_name))
	button.set_meta("slot_name", slot_name)
	button.set_meta("direction", "machine_to_inventory")
	return button


func _refresh_inventory() -> void:
	if inventory == null:
		return
	for index in _inventory_buttons.size():
		_inventory_buttons[index].display_slot(
			inventory.get_slot(index),
			inventory.registry,
			index == inventory.selected_slot,
		)


func _show_empty_machine() -> void:
	_input_button.text = "原料\n空"
	_output_button.text = "产出\n空"
	_progress.value = 0.0
	_recipe_label.text = "当前配方：未连接"
	_queue_label.text = "队列为空"
	_set_status("石材切割机服务未连接", "warning", "machine_unavailable")


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
	var target_id := _inventory_target_id(index)
	if stonecutter_service == null or _active_machine_id.is_empty():
		_set_status(
			"石材切割机服务未连接",
			"warning",
			"machine_unavailable",
			target_id,
		)
		return
	var revision_before := _feedback_revision
	_pending_action_target_id = target_id
	var transferred := bool(
		stonecutter_service.transfer_from_inventory_auto(
			inventory,
			index,
			_active_machine_id,
		)
	)
	_pending_action_target_id = ""
	if not transferred and _feedback_revision == revision_before:
		_set_status(
			"该物品不能切割，或原料槽没有空间",
			"warning",
			"transfer_failed",
			target_id,
		)


func _take_machine_slot(slot_name: String) -> void:
	var target_id := _machine_slot_target_id(slot_name)
	if stonecutter_service == null or _active_machine_id.is_empty():
		_set_status(
			"石材切割机服务未连接",
			"warning",
			"machine_unavailable",
			target_id,
		)
		return
	var revision_before := _feedback_revision
	_pending_action_target_id = target_id
	var transferred := bool(
		stonecutter_service.transfer_to_inventory(
			inventory,
			slot_name,
			_active_machine_id,
		)
	)
	_pending_action_target_id = ""
	if not transferred and _feedback_revision == revision_before:
		_set_status(
			"槽位为空，或背包没有足够空间",
			"warning",
			"transfer_failed",
			target_id,
		)


func _on_machine_changed(machine_id: String, _snapshot: Dictionary) -> void:
	if machine_id == _active_machine_id:
		refresh()


func _on_active_machine_changed(machine_id: String) -> void:
	if machine_id.is_empty() and not _active_machine_id.is_empty():
		_active_machine_id = ""
		_reset_feedback()


func _on_item_transferred(
	machine_id: String,
	direction: String,
	slot_name: String,
	item_id: String,
	count: int,
) -> void:
	if machine_id != _active_machine_id:
		return
	var display_name := _display_name(item_id)
	var slot_label := _slot_label(slot_name)
	var message := "已完成物品转移"
	if direction == "inventory_to_machine":
		message = "已投入 %s ×%d 到%s" % [display_name, count, slot_label]
	else:
		message = "已从%s取回 %s ×%d" % [slot_label, display_name, count]
	_set_status(
		message,
		"success",
		direction,
		_machine_slot_target_id(slot_name),
	)


func _on_item_processed(
	machine_id: String,
	_recipe_id: String,
	output: Dictionary,
) -> void:
	if machine_id != _active_machine_id:
		return
	var item_id := str(output.get("item_id", ""))
	_set_status(
		"切割完成：%s ×%d" % [
			_display_name(item_id),
			int(output.get("count", 0)),
		],
		"success",
		"item_processed",
		_machine_slot_target_id(SLOT_OUTPUT),
	)


func _on_transfer_rejected(machine_id: String, reason: String) -> void:
	if machine_id != _active_machine_id:
		return
	var messages := {
		"unsupported_item": "该物品不能在石材切割机中加工",
		"unsupported_input": "该物品不能切割",
		"slot_full_or_mismatch": "原料槽已满，或需要先取走不同物品",
		"inventory_full": "背包空间不足，切割产出仍安全保留在机器中",
	}
	var target_id := (
		_pending_action_target_id
		if not _pending_action_target_id.is_empty()
		else _machine_target_id(machine_id)
	)
	_set_status(
		str(messages.get(reason, "无法完成该操作")),
		"warning",
		reason,
		target_id,
	)


func _display_name(item_id: String) -> String:
	if (
		inventory != null
		and inventory.get("registry") != null
		and inventory.registry.has_method("get_display_name")
	):
		return str(inventory.registry.get_display_name(item_id))
	return item_id


func _slot_label(slot_name: String) -> String:
	return {
		SLOT_INPUT: "原料槽",
		SLOT_OUTPUT: "产出槽",
	}.get(slot_name, "机器槽位")


func _set_status(
	message: String,
	kind: String,
	reason: String = "",
	target_id: String = "",
) -> void:
	_status_kind = kind
	_status_reason = reason
	_status_target_id = target_id
	_feedback_revision += 1
	if _status == null:
		return
	_status.text = message
	match kind:
		"success":
			_status.modulate = Tokens.color(Tokens.COLOR_SUCCESS)
		"warning":
			_status.modulate = Tokens.color(Tokens.COLOR_DANGER)
		_:
			_status.modulate = Color.WHITE


func _reset_feedback() -> void:
	_status_kind = "idle"
	_status_reason = ""
	_status_target_id = ""
	_pending_action_target_id = ""


func _machine_target_id(machine_id: String) -> String:
	return "stonecutter:%s" % machine_id


func _machine_slot_target_id(slot_name: String) -> String:
	return "stonecutter-slot:%s" % slot_name


func _inventory_target_id(index: int) -> String:
	return "inventory:%d" % index


func _disconnect_services() -> void:
	if inventory != null and inventory.has_signal("inventory_changed"):
		var inventory_callback := Callable(self, "refresh")
		if inventory.inventory_changed.is_connected(inventory_callback):
			inventory.inventory_changed.disconnect(inventory_callback)
	if stonecutter_service != null:
		var changed_callback := Callable(self, "_on_machine_changed")
		if (
			stonecutter_service.has_signal("machine_changed")
			and stonecutter_service.machine_changed.is_connected(changed_callback)
		):
			stonecutter_service.machine_changed.disconnect(changed_callback)
		var active_callback := Callable(self, "_on_active_machine_changed")
		if (
			stonecutter_service.has_signal("active_machine_changed")
			and stonecutter_service.active_machine_changed.is_connected(active_callback)
		):
			stonecutter_service.active_machine_changed.disconnect(active_callback)
		var transferred_callback := Callable(self, "_on_item_transferred")
		if (
			stonecutter_service.has_signal("item_transferred")
			and stonecutter_service.item_transferred.is_connected(transferred_callback)
		):
			stonecutter_service.item_transferred.disconnect(transferred_callback)
		var processed_callback := Callable(self, "_on_item_processed")
		if (
			stonecutter_service.has_signal("item_processed")
			and stonecutter_service.item_processed.is_connected(processed_callback)
		):
			stonecutter_service.item_processed.disconnect(processed_callback)
		var rejected_callback := Callable(self, "_on_transfer_rejected")
		if (
			stonecutter_service.has_signal("transfer_rejected")
			and stonecutter_service.transfer_rejected.is_connected(rejected_callback)
		):
			stonecutter_service.transfer_rejected.disconnect(rejected_callback)


func _exit_tree() -> void:
	_disconnect_services()
