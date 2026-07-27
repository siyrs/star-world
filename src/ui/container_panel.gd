class_name ContainerPanel
extends PanelContainer

signal panel_closed

const SlotScript = preload("res://src/ui/inventory_slot.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")

var inventory
var container_storage
var _active_container_id := ""
var _title: Label
var _status: Label
var _container_grid: GridContainer
var _inventory_grid: GridContainer
var _container_buttons: Array = []
var _inventory_buttons: Array = []
var _container_badge: Label
var _container_card: PanelContainer
var _inventory_card: PanelContainer


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(820, 560)
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
	_status.text = "单击物品可在容器与背包之间移动整组"
	_status.theme_type_variation = "CaptionLabel"
	_rebuild_container_buttons()
	refresh()
	return true


func close_container() -> void:
	_active_container_id = ""
	if container_storage != null:
		container_storage.close_container()


func get_active_container_id() -> String:
	return _active_container_id


func get_visual_snapshot() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"container_card": _container_card.get_global_rect() if _container_card != null else Rect2(),
		"inventory_card": _inventory_card.get_global_rect() if _inventory_card != null else Rect2(),
		"container_slots": _container_buttons.size(),
		"inventory_slots": _inventory_buttons.size(),
		"active_container_id": _active_container_id,
	}


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
	_container_badge.text = "%d 格" % _container_buttons.size()


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
	heading.add_child(UiKit.make_eyebrow("STORAGE TRANSFER"))
	_title = UiKit.make_title("箱子")
	heading.add_child(_title)
	var close_button := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(132, Tokens.CONTROL_HEIGHT_MD)
	)
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)

	_status = Label.new()
	_status.name = "ContainerStatus"
	_status.theme_type_variation = "CaptionLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_stylebox_override(
		"normal",
		Tokens.panel_style(Tokens.COLOR_INSET, Tokens.COLOR_BORDER_SUBTLE, 1, Tokens.RADIUS_XL, 6.0)
	)
	root.add_child(_status)

	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_SM)
	root.add_child(body)

	_container_card = UiKit.make_card("InsetPanel")
	_container_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_container_card)
	var container_root := VBoxContainer.new()
	container_root.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_container_card.add_child(container_root)
	var container_header := HBoxContainer.new()
	container_root.add_child(container_header)
	var container_label := Label.new()
	container_label.text = "容器库存"
	container_label.theme_type_variation = "SectionTitle"
	container_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_header.add_child(container_label)
	_container_badge = UiKit.make_badge("0 格", "info")
	container_header.add_child(_container_badge)
	var container_center := CenterContainer.new()
	container_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_root.add_child(container_center)
	_container_grid = GridContainer.new()
	_container_grid.columns = 9
	_container_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_container_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	container_center.add_child(_container_grid)

	_inventory_card = UiKit.make_card("InsetPanel")
	_inventory_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_inventory_card)
	var inventory_root := VBoxContainer.new()
	inventory_root.add_theme_constant_override("separation", Tokens.SPACE_XS)
	_inventory_card.add_child(inventory_root)
	var inventory_header := HBoxContainer.new()
	inventory_root.add_child(inventory_header)
	var inventory_label := Label.new()
	inventory_label.text = "玩家背包"
	inventory_label.theme_type_variation = "SectionTitle"
	inventory_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_header.add_child(inventory_label)
	inventory_header.add_child(UiKit.make_badge("36 格", "info"))
	var inventory_center := CenterContainer.new()
	inventory_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_root.add_child(inventory_center)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 9
	_inventory_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	_inventory_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	inventory_center.add_child(_inventory_grid)
	for index in 36:
		var slot = SlotScript.new()
		slot.configure(index)
		slot.custom_minimum_size = Vector2(54, 48)
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
		slot.custom_minimum_size = Vector2(54, 48)
		slot.slot_clicked.connect(_on_container_slot_clicked)
		_container_grid.add_child(slot)
		_container_buttons.append(slot)
	_container_badge.text = "%d 格" % slot_count


func _on_container_slot_clicked(index: int) -> void:
	if container_storage == null or _active_container_id.is_empty():
		return
	var moved: bool = bool(
		container_storage.transfer_to_inventory(inventory, index, _active_container_id)
	)
	_status.text = "已移入背包" if moved else "背包空间不足或槽位为空"
	_status.theme_type_variation = "SuccessLabel" if moved else "DangerLabel"
	refresh()


func _on_inventory_slot_clicked(index: int) -> void:
	if container_storage == null or _active_container_id.is_empty():
		return
	var moved: bool = bool(
		container_storage.transfer_from_inventory(inventory, index, _active_container_id)
	)
	_status.text = "已存入容器" if moved else "容器空间不足或槽位为空"
	_status.theme_type_variation = "SuccessLabel" if moved else "DangerLabel"
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
