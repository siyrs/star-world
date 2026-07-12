class_name InventoryPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")

var inventory
var _grid: GridContainer
var _slot_buttons: Array = []
var _selected_source: int = -1
var _selection_label: Label


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(710, 520)
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
	var swap_source := str(_selected_source + 1) if _selected_source >= 0 else "无"
	_selection_label.text = "当前使用：快捷栏 %d    交换起点：%s" % [inventory.selected_slot + 1, swap_source]


func cancel_swap_selection() -> void:
	if _selected_source < 0:
		return
	_selected_source = -1
	refresh()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "背包  36 格 / 可堆叠"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭 [E]"
	close_button.pressed.connect(func(): panel_closed.emit())
	header.add_child(close_button)
	_selection_label = Label.new()
	root.add_child(_selection_label)
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 5)
	_grid.add_theme_constant_override("v_separation", 5)
	root.add_child(_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_activated.connect(_on_slot_activated)
		_grid.add_child(slot)
		_slot_buttons.append(slot)
	var hint := Label.new()
	hint.text = "单击快捷栏切换当前物品；单击背包槽位后再点目标槽位可交换；右键或双击背包物品可快速装备。"
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
