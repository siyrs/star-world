class_name InventoryPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")

var inventory
var _grid: GridContainer
var _slot_buttons: Array = []
var _selected_source: int = -1
var _selection_label: Label
var _inventory_card: PanelContainer


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(760, 510)
	_build_ui()


func setup(p_inventory) -> void:
	if inventory == p_inventory:
		refresh()
		return
	_disconnect_inventory()
	inventory = p_inventory
	if inventory != null:
		inventory.inventory_changed.connect(refresh)
		inventory.selected_slot_changed.connect(_on_selected_slot_changed)
	refresh()


func refresh() -> void:
	if inventory == null or _selection_label == null:
		return
	for index in _slot_buttons.size():
		_slot_buttons[index].display_slot(
			inventory.get_slot(index),
			inventory.registry,
			index == inventory.selected_slot,
			index == _selected_source
		)
	var swap_source := str(_selected_source + 1) if _selected_source >= 0 else "未选择"
	_selection_label.text = "当前快捷栏 %d  ·  交换起点 %s" % [
		inventory.selected_slot + 1, swap_source
	]
	_selection_label.theme_type_variation = (
		"MetricLabel" if _selected_source >= 0 else "CaptionLabel"
	)


func cancel_swap_selection() -> void:
	if _selected_source < 0:
		return
	_selected_source = -1
	refresh()


func get_layout_snapshot() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"inventory_card": _inventory_card.get_global_rect() if _inventory_card != null else Rect2(),
		"grid": _grid.get_global_rect() if _grid != null else Rect2(),
		"slot_count": _slot_buttons.size(),
		"selected_source": _selected_source,
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_MD)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("背包 · 36 格"))
	heading.add_child(UiKit.make_title("背包与快捷栏"))
	heading.add_child(UiKit.make_subtitle("前 9 格是快捷栏；选择任意槽位后点击目标槽位可完成交换。"))
	var close_button := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(132, Tokens.CONTROL_HEIGHT_MD)
	)
	close_button.text = "关闭 [E]"
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)

	_selection_label = Label.new()
	_selection_label.name = "InventorySelectionStatus"
	_selection_label.theme_type_variation = "CaptionLabel"
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_label.add_theme_stylebox_override(
		"normal",
		Tokens.bevel_style("#B0B0B0", "#7A7A7A", 2, 7.0)
	)
	root.add_child(_selection_label)

	_inventory_card = UiKit.make_card("InsetPanel")
	_inventory_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_inventory_card)
	var card_root := VBoxContainer.new()
	card_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_inventory_card.add_child(card_root)
	var section_header := HBoxContainer.new()
	card_root.add_child(section_header)
	var section_title := Label.new()
	section_title.text = "物品槽位"
	section_title.theme_type_variation = "SectionTitle"
	section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_header.add_child(section_title)
	section_header.add_child(UiKit.make_badge("9 × 4", "info"))

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_root.add_child(grid_center)
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	grid_center.add_child(_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_activated.connect(_on_slot_activated)
		_grid.add_child(slot)
		_slot_buttons.append(slot)

	var hint := Label.new()
	hint.text = "单击快捷栏切换当前物品 · 两次单击交换槽位 · 右键或双击背包物品快速装备"
	hint.theme_type_variation = "SubduedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)


func _on_slot_clicked(index: int) -> void:
	if inventory == null:
		return
	if _selected_source >= 0:
		if _selected_source == index:
			_selected_source = -1
		else:
			inventory.swap_slots(_selected_source, index)
			_selected_source = -1
			if inventory.is_hotbar_slot(index):
				inventory.select_slot(index)
	elif inventory.is_hotbar_slot(index):
		inventory.select_slot(index)
	else:
		_selected_source = index
	refresh()


func _on_slot_activated(index: int) -> void:
	if inventory == null or inventory.get_slot(index).is_empty():
		return
	if inventory.is_hotbar_slot(index):
		inventory.select_slot(index)
	else:
		inventory.equip_slot(index)
	_selected_source = -1
	refresh()


func _on_selected_slot_changed(_index: int, _slot: Dictionary) -> void:
	refresh()


func _disconnect_inventory() -> void:
	if inventory == null:
		return
	var refresh_callback := Callable(self, "refresh")
	if inventory.inventory_changed.is_connected(refresh_callback):
		inventory.inventory_changed.disconnect(refresh_callback)
	var selection_callback := Callable(self, "_on_selected_slot_changed")
	if inventory.selected_slot_changed.is_connected(selection_callback):
		inventory.selected_slot_changed.disconnect(selection_callback)
