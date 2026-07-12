class_name ContainerPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")

var inventory
var container_storage
var _active_container_id := ""
var _title: Label
var _status: Label
var _container_grid: GridContainer
var _inventory_grid: GridContainer
var _container_buttons: Array = []
var _inventory_buttons: Array = []


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(760, 650)
	_build_ui()


func setup(p_inventory, p_container_storage) -> void:
	_disconnect_services()
	inventory = p_inventory
	container_storage = p_container_storage
	if inventory != null:
		inventory.inventory_changed.connect(refresh)
	if container_storage != null:
		container_storage.container_changed.connect(_on_container_changed)
		container_storage.active_container_changed.connect(_on_active_container_changed)
	refresh()


func open_container(container_id: String, title: String = "箱子") -> bool:
	if container_storage == null or container_id.is_empty():
		return false
	if not container_storage.has_container(container_id):
		return false
	_active_container_id = container_id
	_title.text = title
	_status.text = "单击物品可在箱子与背包之间移动整组"
	_rebuild_container_buttons()
	refresh()
	return true


func close_container() -> void:
	_active_container_id = ""
	if container_storage != null:
		container_storage.close_container()


func get_active_container_id() -> String:
	return _active_container_id


func refresh() -> void:
	if inventory == null or _status == null:
		return
	for index in _inventory_buttons.size():
		_inventory_buttons[index].display_slot(
			inventory.get_slot(index), inventory.registry, index == inventory.selected_slot
		)
	if container_storage == null or _active_container_id.is_empty():
		for button in _container_buttons:
			button.display_slot({}, inventory.registry)
		return
	for index in _container_buttons.size():
		_container_buttons[index].display_slot(
			container_storage.get_slot(_active_container_id, index), inventory.registry
		)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.text = "箱子"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 26)
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var container_label := Label.new()
	container_label.text = "容器"
	container_label.add_theme_font_size_override("font_size", 18)
	root.add_child(container_label)
	_container_grid = GridContainer.new()
	_container_grid.columns = 9
	_container_grid.add_theme_constant_override("h_separation", 5)
	_container_grid.add_theme_constant_override("v_separation", 5)
	root.add_child(_container_grid)
	var separator := HSeparator.new()
	root.add_child(separator)
	var inventory_label := Label.new()
	inventory_label.text = "玩家背包"
	inventory_label.add_theme_font_size_override("font_size", 18)
	root.add_child(inventory_label)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 9
	_inventory_grid.add_theme_constant_override("h_separation", 5)
	_inventory_grid.add_theme_constant_override("v_separation", 5)
	root.add_child(_inventory_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.slot_clicked.connect(_on_inventory_slot_clicked)
		_inventory_grid.add_child(slot)
		_inventory_buttons.append(slot)


func _rebuild_container_buttons() -> void:
	for child in _container_grid.get_children():
		child.queue_free()
	_container_buttons.clear()
	var slot_count: int = int(container_storage.get_slot_count(_active_container_id))
	for index in slot_count:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.slot_clicked.connect(_on_container_slot_clicked)
		_container_grid.add_child(slot)
		_container_buttons.append(slot)


func _on_container_slot_clicked(index: int) -> void:
	if container_storage == null or _active_container_id.is_empty():
		return
	var moved: bool = bool(
		container_storage.transfer_to_inventory(inventory, index, _active_container_id)
	)
	_status.text = "已移入背包" if moved else "背包空间不足或槽位为空"
	refresh()


func _on_inventory_slot_clicked(index: int) -> void:
	if container_storage == null or _active_container_id.is_empty():
		return
	var moved: bool = bool(
		container_storage.transfer_from_inventory(inventory, index, _active_container_id)
	)
	_status.text = "已存入箱子" if moved else "箱子空间不足或槽位为空"
	refresh()


func _on_container_changed(container_id: String) -> void:
	if container_id == _active_container_id:
		refresh()


func _on_active_container_changed(container_id: String) -> void:
	if container_id.is_empty() and not _active_container_id.is_empty():
		_active_container_id = ""


func _disconnect_services() -> void:
	if inventory != null:
		var inventory_callback := Callable(self, "refresh")
		if inventory.inventory_changed.is_connected(inventory_callback):
			inventory.inventory_changed.disconnect(inventory_callback)
	if container_storage != null:
		var changed_callback := Callable(self, "_on_container_changed")
		if container_storage.container_changed.is_connected(changed_callback):
			container_storage.container_changed.disconnect(changed_callback)
		var active_callback := Callable(self, "_on_active_container_changed")
		if container_storage.active_container_changed.is_connected(active_callback):
			container_storage.active_container_changed.disconnect(active_callback)
