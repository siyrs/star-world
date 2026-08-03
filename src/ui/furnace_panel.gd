class_name FurnacePanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const IconFactory = preload("res://src/ui/item_icon_factory.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const SLOT_INPUT := "input"
const SLOT_FUEL := "fuel"
const SLOT_OUTPUT := "output"
const MACHINE_SLOTS: Array[String] = [SLOT_INPUT, SLOT_FUEL, SLOT_OUTPUT]

var inventory
var furnace_service
var _active_machine_id := ""
var _title: Label
var _status: Label
var _recipe_label: Label
var _progress: ProgressBar
var _fuel: ProgressBar
var _input_button: Button
var _fuel_button: Button
var _output_button: Button
var _inventory_grid: GridContainer
var _inventory_buttons: Array = []
var _machine_card: PanelContainer
var _inventory_card: PanelContainer
var _machine_badge: Label
var _status_kind := "idle"
var _status_reason := ""
var _status_target_id := ""
var _feedback_revision := 0


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(900, 520)
	_build_ui()


func setup(p_inventory, p_furnace_service) -> void:
	_disconnect_services()
	inventory = p_inventory
	furnace_service = p_furnace_service
	if inventory != null and inventory.has_signal("inventory_changed"):
		inventory.inventory_changed.connect(refresh)
	if furnace_service != null:
		if furnace_service.has_signal("machine_changed"):
			furnace_service.machine_changed.connect(_on_machine_changed)
		if furnace_service.has_signal("active_machine_changed"):
			furnace_service.active_machine_changed.connect(_on_active_machine_changed)
		if furnace_service.has_signal("item_transferred"):
			furnace_service.item_transferred.connect(_on_item_transferred)
		if furnace_service.has_signal("item_smelted"):
			furnace_service.item_smelted.connect(_on_item_smelted)
		if furnace_service.has_signal("transfer_rejected"):
			furnace_service.transfer_rejected.connect(_on_transfer_rejected)
	_reset_feedback()
	refresh()


func open_machine(machine_id: String, title: String = "熔炉") -> bool:
	if furnace_service == null or machine_id.is_empty():
		return false
	if not furnace_service.open_machine(machine_id):
		return false
	_active_machine_id = machine_id
	_title.text = title
	_machine_badge.text = "共享调度"
	_reset_feedback()
	refresh()
	_set_status(
		"点击背包物品可自动放入原料槽或燃料槽",
		"idle",
		"opened",
		_machine_target_id(machine_id),
	)
	return true


func close_machine() -> void:
	_active_machine_id = ""
	_reset_feedback()
	if furnace_service != null:
		furnace_service.close_machine()


func get_active_machine_id() -> String:
	return _active_machine_id


func get_recipe_text() -> String:
	return _recipe_label.text if _recipe_label != null else ""


func get_machine_slot_button(slot_name: String) -> Button:
	match slot_name:
		SLOT_INPUT:
			return _input_button
		SLOT_FUEL:
			return _fuel_button
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
		furnace_service != null
		and not _active_machine_id.is_empty()
		and furnace_service.has_method("get_machine_snapshot")
	):
		machine_snapshot = furnace_service.get_machine_snapshot(_active_machine_id)
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
		"recipe_text": get_recipe_text(),
		"progress_ratio": _progress.value if _progress != null else 0.0,
		"fuel_ratio": _fuel.value if _fuel != null else 0.0,
		"machine_slots": machine_slots,
		"inventory_target_count": inventory_targets.size(),
		"inventory_targets": inventory_targets,
	}


func refresh() -> void:
	if _status == null:
		return
	_refresh_inventory()
	if furnace_service == null or _active_machine_id.is_empty():
		_show_empty_machine()
		return
	var snapshot: Dictionary = furnace_service.get_machine_snapshot(_active_machine_id)
	if snapshot.is_empty():
		_show_empty_machine()
		return
	_input_button.text = _slot_text("原料", snapshot.get(SLOT_INPUT, {}))
	_fuel_button.text = _slot_text("燃料", snapshot.get(SLOT_FUEL, {}))
	_output_button.text = _slot_text("产出", snapshot.get(SLOT_OUTPUT, {}))
	_input_button.icon = _slot_icon(snapshot.get(SLOT_INPUT, {}))
	_fuel_button.icon = _slot_icon(snapshot.get(SLOT_FUEL, {}))
	_output_button.icon = _slot_icon(snapshot.get(SLOT_OUTPUT, {}))
	_progress.value = float(snapshot.get("progress_ratio", 0.0))
	_fuel.value = float(snapshot.get("fuel_ratio", 0.0))
	var recipe: Dictionary = snapshot.get("recipe", {})
	if recipe.is_empty():
		_recipe_label.text = "等待可烧制原料"
		_machine_badge.text = "待机"
	else:
		var queued_jobs := maxi(0, int(snapshot.get("queued_jobs", 0)))
		var remaining := maxf(0.0, float(snapshot.get("remaining_seconds", 0.0)))
		var total_remaining := maxf(
			remaining,
			float(snapshot.get("estimated_total_seconds", remaining)),
		)
		_recipe_label.text = "%s · 队列 %d · 下一份 %.1f 秒 · 全部 %.1f 秒" % [
			str(recipe.get("name", "")),
			queued_jobs,
			remaining,
			total_remaining,
		]
		_machine_badge.text = (
			"加工中"
			if float(snapshot.get("progress_ratio", 0.0)) > 0.0
			else "已排队"
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
		"machine_card": (
			_machine_card.get_global_rect()
			if _machine_card != null
			else Rect2()
		),
		"inventory_card": (
			_inventory_card.get_global_rect()
			if _inventory_card != null
			else Rect2()
		),
		"input": (
			_input_button.get_global_rect()
			if _input_button != null
			else Rect2()
		),
		"fuel": (
			_fuel_button.get_global_rect()
			if _fuel_button != null
			else Rect2()
		),
		"output": (
			_output_button.get_global_rect()
			if _output_button != null
			else Rect2()
		),
		"inventory": (
			_inventory_grid.get_global_rect()
			if _inventory_grid != null
			else Rect2()
		),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("加工中"))
	_title = UiKit.make_title("熔炉")
	heading.add_child(_title)
	heading.add_child(
		UiKit.make_subtitle(
			"机器由共享调度持续推进；关闭界面后继续加工，世界暂停时同步停止。"
		)
	)
	_machine_badge = UiKit.make_badge("未连接", "warm")
	header.add_child(_machine_badge)
	var close_button := UiKit.style_button(
		Button.new(),
		"GhostButton",
		Vector2(132, Tokens.CONTROL_HEIGHT_MD),
	)
	close_button.text = "关闭 [Esc]"
	close_button.set_meta("target_id", "furnace:close")
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)

	_machine_card = UiKit.make_card("CardPanel")
	root.add_child(_machine_card)
	var machine_root := VBoxContainer.new()
	machine_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_machine_card.add_child(machine_root)
	var machine_header := HBoxContainer.new()
	machine_root.add_child(machine_header)
	var machine_title := Label.new()
	machine_title.text = "处理链路"
	machine_title.theme_type_variation = "SectionTitle"
	machine_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	machine_header.add_child(machine_title)
	var machine_hint := Label.new()
	machine_hint.text = "点击机器槽位取回物品"
	machine_hint.theme_type_variation = "SubduedLabel"
	machine_header.add_child(machine_hint)

	var machine_row := HBoxContainer.new()
	machine_row.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	machine_root.add_child(machine_row)
	_input_button = _make_machine_slot("原料\n空", "MachineSlotButton", SLOT_INPUT)
	_input_button.pressed.connect(func() -> void: _take_machine_slot(SLOT_INPUT))
	machine_row.add_child(_input_button)

	var process_card := UiKit.make_card("InsetPanel", Vector2(330, 118))
	process_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	machine_row.add_child(process_card)
	var process_column := VBoxContainer.new()
	process_column.add_theme_constant_override("separation", Tokens.SPACE_XS)
	process_card.add_child(process_column)
	_recipe_label = Label.new()
	_recipe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recipe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recipe_label.theme_type_variation = "CaptionLabel"
	process_column.add_child(_recipe_label)
	var progress_caption := Label.new()
	progress_caption.text = "烧制进度"
	progress_caption.theme_type_variation = "SubduedLabel"
	process_column.add_child(progress_caption)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 10.0
	process_column.add_child(_progress)
	var fuel_caption := Label.new()
	fuel_caption.text = "燃料余量"
	fuel_caption.theme_type_variation = "SubduedLabel"
	process_column.add_child(fuel_caption)
	_fuel = ProgressBar.new()
	_fuel.min_value = 0.0
	_fuel.max_value = 1.0
	_fuel.show_percentage = false
	_fuel.custom_minimum_size.y = 10.0
	_fuel.add_theme_stylebox_override(
		"fill",
		Tokens.bevel_style("#C9A227", "#E8C93A", 1, 1.0),
	)
	process_column.add_child(_fuel)

	_fuel_button = _make_machine_slot("燃料\n空", "MachineSlotButton", SLOT_FUEL)
	_fuel_button.pressed.connect(func() -> void: _take_machine_slot(SLOT_FUEL))
	machine_row.add_child(_fuel_button)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.theme_type_variation = "PageTitle"
	arrow.add_theme_color_override("font_color", Color("#B8860B"))
	machine_row.add_child(arrow)
	_output_button = _make_machine_slot("产出\n空", "OutputSlotButton", SLOT_OUTPUT)
	_output_button.pressed.connect(func() -> void: _take_machine_slot(SLOT_OUTPUT))
	machine_row.add_child(_output_button)

	_status = Label.new()
	_status.name = "MachineStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.theme_type_variation = "CaptionLabel"
	_status.custom_minimum_size.y = 26.0
	_status.add_theme_stylebox_override(
		"normal",
		Tokens.bevel_style("#B0B0B0", "#7A7A7A", 2, 6.0),
	)
	root.add_child(_status)

	_inventory_card = UiKit.make_card("InsetPanel")
	_inventory_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_inventory_card)
	var inventory_root := VBoxContainer.new()
	inventory_root.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_inventory_card.add_child(inventory_root)
	var inventory_header := HBoxContainer.new()
	inventory_root.add_child(inventory_header)
	var inventory_title := Label.new()
	inventory_title.text = "玩家背包"
	inventory_title.theme_type_variation = "SectionTitle"
	inventory_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_header.add_child(inventory_title)
	var inventory_hint := Label.new()
	inventory_hint.text = "点击投入 · 原料与燃料自动分类"
	inventory_hint.theme_type_variation = "SubduedLabel"
	inventory_header.add_child(inventory_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 166)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_root.add_child(scroll)
	var inventory_center := CenterContainer.new()
	inventory_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inventory_center)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 9
	_inventory_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_inventory_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	inventory_center.add_child(_inventory_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = Vector2(58, 50)
		slot.set_meta("target_id", _inventory_target_id(index))
		slot.set_meta("slot_index", index)
		slot.set_meta("direction", "inventory_to_machine")
		slot.slot_clicked.connect(_on_inventory_slot_clicked)
		_inventory_grid.add_child(slot)
		_inventory_buttons.append(slot)


func _make_machine_slot(
	label: String,
	variation: String,
	slot_name: String,
) -> Button:
	var button := UiKit.style_button(
		Button.new(),
		variation,
		Vector2(142, 104),
	)
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
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
	_fuel_button.text = "燃料\n空"
	_output_button.text = "产出\n空"
	_input_button.icon = null
	_fuel_button.icon = null
	_output_button.icon = null
	_progress.value = 0.0
	_fuel.value = 0.0
	_recipe_label.text = "等待机器连接"
	_machine_badge.text = "未连接"
	_set_status("熔炉服务未连接", "warning", "machine_unavailable")


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
	if furnace_service == null or _active_machine_id.is_empty():
		_set_status(
			"熔炉服务未连接",
			"warning",
			"machine_unavailable",
			_inventory_target_id(index),
		)
		return
	var revision_before := _feedback_revision
	var transferred := bool(
		furnace_service.transfer_from_inventory_auto(
			inventory,
			index,
			_active_machine_id,
		)
	)
	if not transferred and _feedback_revision == revision_before:
		_set_status(
			"该物品不能投入，或目标槽位没有空间",
			"warning",
			"transfer_failed",
			_inventory_target_id(index),
		)


func _take_machine_slot(slot_name: String) -> void:
	if furnace_service == null or _active_machine_id.is_empty():
		_set_status(
			"熔炉服务未连接",
			"warning",
			"machine_unavailable",
			_machine_slot_target_id(slot_name),
		)
		return
	var revision_before := _feedback_revision
	var transferred := bool(
		furnace_service.transfer_to_inventory(
			inventory,
			slot_name,
			_active_machine_id,
		)
	)
	if not transferred and _feedback_revision == revision_before:
		_set_status(
			"槽位为空，或背包没有足够空间",
			"warning",
			"transfer_failed",
			_machine_slot_target_id(slot_name),
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
	var target_id := _machine_slot_target_id(slot_name)
	if direction == "inventory_to_machine":
		message = "已投入 %s ×%d 到%s" % [display_name, count, slot_label]
	else:
		message = "已从%s取回 %s ×%d" % [slot_label, display_name, count]
	_set_status(message, "success", direction, target_id)


func _on_item_smelted(
	machine_id: String,
	_recipe_id: String,
	output: Dictionary,
) -> void:
	if machine_id != _active_machine_id:
		return
	var item_id := str(output.get("item_id", ""))
	_set_status(
		"烧制完成：%s ×%d" % [
			_display_name(item_id),
			int(output.get("count", 0)),
		],
		"success",
		"item_smelted",
		_machine_slot_target_id(SLOT_OUTPUT),
	)


func _on_transfer_rejected(machine_id: String, reason: String) -> void:
	if machine_id != _active_machine_id:
		return
	var messages := {
		"unsupported_item": "该物品既不是可烧制原料，也不是燃料",
		"unsupported_input": "该物品不能烧制",
		"unsupported_fuel": "该物品不能作为燃料",
		"slot_full_or_mismatch": "槽位已满，或需要先取走不同物品",
		"inventory_full": "背包空间不足，产出仍安全保留在熔炉中",
	}
	_set_status(
		str(messages.get(reason, "无法完成该操作")),
		"warning",
		reason,
		_machine_target_id(machine_id),
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
		SLOT_FUEL: "燃料槽",
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
			_status.theme_type_variation = "CaptionLabel"
			_status.modulate = Tokens.color(Tokens.COLOR_SUCCESS)
		"warning":
			_status.theme_type_variation = "DangerLabel"
			_status.modulate = Color.WHITE
		_:
			_status.theme_type_variation = "CaptionLabel"
			_status.modulate = Color.WHITE


func _reset_feedback() -> void:
	_status_kind = "idle"
	_status_reason = ""
	_status_target_id = ""


func _machine_target_id(machine_id: String) -> String:
	return "furnace:%s" % machine_id


func _machine_slot_target_id(slot_name: String) -> String:
	return "furnace-slot:%s" % slot_name


func _inventory_target_id(index: int) -> String:
	return "inventory:%d" % index


func _disconnect_services() -> void:
	if inventory != null and inventory.has_signal("inventory_changed"):
		var inventory_callback := Callable(self, "refresh")
		if inventory.inventory_changed.is_connected(inventory_callback):
			inventory.inventory_changed.disconnect(inventory_callback)
	if furnace_service != null:
		var changed_callback := Callable(self, "_on_machine_changed")
		if (
			furnace_service.has_signal("machine_changed")
			and furnace_service.machine_changed.is_connected(changed_callback)
		):
			furnace_service.machine_changed.disconnect(changed_callback)
		var active_callback := Callable(self, "_on_active_machine_changed")
		if (
			furnace_service.has_signal("active_machine_changed")
			and furnace_service.active_machine_changed.is_connected(active_callback)
		):
			furnace_service.active_machine_changed.disconnect(active_callback)
		var transferred_callback := Callable(self, "_on_item_transferred")
		if (
			furnace_service.has_signal("item_transferred")
			and furnace_service.item_transferred.is_connected(transferred_callback)
		):
			furnace_service.item_transferred.disconnect(transferred_callback)
		var smelted_callback := Callable(self, "_on_item_smelted")
		if (
			furnace_service.has_signal("item_smelted")
			and furnace_service.item_smelted.is_connected(smelted_callback)
		):
			furnace_service.item_smelted.disconnect(smelted_callback)
		var rejected_callback := Callable(self, "_on_transfer_rejected")
		if (
			furnace_service.has_signal("transfer_rejected")
			and furnace_service.transfer_rejected.is_connected(rejected_callback)
		):
			furnace_service.transfer_rejected.disconnect(rejected_callback)
