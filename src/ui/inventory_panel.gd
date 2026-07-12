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
	inventory = p_inventory
	if inventory != null:
		inventory.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if inventory == null:
		return
	for index in _slot_buttons.size():
		_slot_buttons[index].display_slot(inventory.get_slot(index), inventory.registry, index == _selected_source)
	_selection_label.text = "已选槽位: %s（再点一个槽位可交换）" % (str(_selected_source + 1) if _selected_source >= 0 else "无")


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
		_grid.add_child(slot)
		_slot_buttons.append(slot)
	var hint := Label.new()
	hint.text = "提示：数字键 1-9 切换快捷栏，点击两个格子交换物品。"
	root.add_child(hint)


func _on_slot_clicked(index: int) -> void:
	if inventory == null:
		return
	if _selected_source < 0:
		_selected_source = index
	elif _selected_source == index:
		_selected_source = -1
	else:
		inventory.swap_slots(_selected_source, index)
		_selected_source = -1
	refresh()
