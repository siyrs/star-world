class_name GameUI
extends CanvasLayer

signal save_requested
signal return_to_menu_requested
signal respawn_requested
signal input_context_requested(context: StringName)

enum Overlay {
	NONE,
	INVENTORY,
	CRAFTING,
	PAUSE,
	DEATH,
}

const HudScript = preload("res://src/ui/hud.gd")
const InventoryPanelScript = preload("res://src/ui/inventory_panel.gd")
const CraftingPanelScript = preload("res://src/ui/crafting_panel.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")

var inventory
var crafting
var survival
var day_night
var audio_service
var hud
var inventory_panel
var crafting_panel
var _pause_panel: PanelContainer
var _death_panel: PanelContainer
var _death_title: Label
var _overlay: int = Overlay.NONE
var _gameplay_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	hud = HudScript.new()
	add_child(hud)
	inventory_panel = InventoryPanelScript.new()
	_center_control(inventory_panel, Vector2(710, 520))
	add_child(inventory_panel)
	inventory_panel.visible = false
	inventory_panel.panel_closed.connect(_close_overlay)
	crafting_panel = CraftingPanelScript.new()
	_center_control(crafting_panel, Vector2(760, 590))
	add_child(crafting_panel)
	crafting_panel.visible = false
	crafting_panel.panel_closed.connect(_close_overlay)
	_build_pause_panel()
	_build_death_panel()


func setup(p_inventory, p_crafting, p_survival, p_day_night, p_audio = null) -> void:
	inventory = p_inventory
	crafting = p_crafting
	survival = p_survival
	day_night = p_day_night
	audio_service = p_audio
	hud.setup(inventory, survival, day_night)
	inventory_panel.setup(inventory)
	crafting_panel.setup(crafting, inventory)
	if survival != null and survival.has_signal("player_died"):
		var callback := Callable(self, "_on_player_died")
		if not survival.is_connected("player_died", callback):
			survival.connect("player_died", callback)


func begin_gameplay() -> void:
	_gameplay_active = true
	visible = true
	if survival != null and not bool(survival.get("alive")):
		_death_title.text = "你倒下了"
		_set_overlay(Overlay.DEATH, true)
	else:
		_set_overlay(Overlay.NONE, true)


func end_gameplay() -> void:
	_gameplay_active = false
	_overlay = Overlay.NONE
	_hide_all_overlays()
	if inventory_panel != null and inventory_panel.has_method("cancel_swap_selection"):
		inventory_panel.call("cancel_swap_selection")
	visible = false


func open_inventory() -> void:
	if not _can_change_overlay():
		return
	_set_overlay(Overlay.NONE if _overlay == Overlay.INVENTORY else Overlay.INVENTORY)


func open_crafting(station: String = "hand") -> void:
	if not _can_change_overlay():
		return
	crafting_panel.open_station(station)
	_set_overlay(Overlay.CRAFTING)


func toggle_crafting(station: String = "hand") -> void:
	if _overlay == Overlay.CRAFTING:
		_set_overlay(Overlay.NONE)
	else:
		open_crafting(station)


func open_workbench() -> void:
	open_crafting("workbench")


func open_furnace() -> void:
	open_crafting("furnace")


func toggle_pause() -> void:
	if not _can_change_overlay():
		return
	_set_overlay(Overlay.NONE if _overlay == Overlay.PAUSE else Overlay.PAUSE)


func close_overlay() -> void:
	_close_overlay()


func get_active_overlay() -> int:
	return _overlay


func is_gameplay_input_blocked() -> bool:
	return not _gameplay_active or _overlay != Overlay.NONE


func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_active or not visible:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		if _overlay != Overlay.DEATH:
			if _overlay in [Overlay.NONE, Overlay.PAUSE]:
				toggle_pause()
			else:
				_close_overlay()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_E:
			open_inventory()
			get_viewport().set_input_as_handled()
		KEY_C:
			toggle_crafting("hand")
			get_viewport().set_input_as_handled()


func _can_change_overlay() -> bool:
	return _gameplay_active and _overlay != Overlay.DEATH


func _close_overlay() -> void:
	if _overlay == Overlay.DEATH:
		return
	_set_overlay(Overlay.NONE)


func _set_overlay(next_overlay: int, force: bool = false) -> void:
	if not _gameplay_active:
		return
	if next_overlay == _overlay and not force:
		return
	if _overlay == Overlay.INVENTORY and next_overlay != Overlay.INVENTORY:
		if inventory_panel != null and inventory_panel.has_method("cancel_swap_selection"):
			inventory_panel.call("cancel_swap_selection")
	_overlay = next_overlay
	_hide_all_overlays()
	match _overlay:
		Overlay.INVENTORY:
			inventory_panel.visible = true
		Overlay.CRAFTING:
			crafting_panel.visible = true
		Overlay.PAUSE:
			_pause_panel.visible = true
		Overlay.DEATH:
			_death_panel.visible = true
	input_context_requested.emit(_context_for_overlay())


func _hide_all_overlays() -> void:
	if inventory_panel != null:
		inventory_panel.visible = false
	if crafting_panel != null:
		crafting_panel.visible = false
	if _pause_panel != null:
		_pause_panel.visible = false
	if _death_panel != null:
		_death_panel.visible = false


func _context_for_overlay() -> StringName:
	match _overlay:
		Overlay.INVENTORY:
			return InputContextScript.CONTEXT_INVENTORY
		Overlay.CRAFTING:
			return InputContextScript.CONTEXT_CRAFTING
		Overlay.PAUSE:
			return InputContextScript.CONTEXT_PAUSE
		Overlay.DEATH:
			return InputContextScript.CONTEXT_DEATH
		_:
			return InputContextScript.CONTEXT_GAMEPLAY


func _build_pause_panel() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.theme = ThemeFactory.create_theme()
	_center_control(_pause_panel, Vector2(420, 370))
	add_child(_pause_panel)
	_pause_panel.visible = false
	var content := VBoxContainer.new()
	_pause_panel.add_child(content)
	var title := Label.new()
	title.text = "游戏已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)
	var resume := Button.new()
	resume.text = "继续游戏"
	resume.pressed.connect(_close_overlay)
	content.add_child(resume)
	var save := Button.new()
	save.text = "保存世界"
	save.pressed.connect(_save_from_pause)
	content.add_child(save)
	var exit := Button.new()
	exit.text = "保存并返回主菜单"
	exit.pressed.connect(_save_and_return_to_menu)
	content.add_child(exit)


func _build_death_panel() -> void:
	_death_panel = PanelContainer.new()
	_death_panel.theme = ThemeFactory.create_theme()
	_center_control(_death_panel, Vector2(500, 270))
	add_child(_death_panel)
	_death_panel.visible = false
	var content := VBoxContainer.new()
	_death_panel.add_child(content)
	_death_title = Label.new()
	_death_title.text = "你倒下了"
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_title.add_theme_font_size_override("font_size", 34)
	content.add_child(_death_title)
	var respawn := Button.new()
	respawn.text = "重生"
	respawn.pressed.connect(_respawn)
	content.add_child(respawn)
	var menu := Button.new()
	menu.text = "返回主菜单"
	menu.pressed.connect(func(): return_to_menu_requested.emit())
	content.add_child(menu)


func _save_from_pause() -> void:
	save_requested.emit()
	hud.show_message("世界已保存")


func _save_and_return_to_menu() -> void:
	# The service hub owns the save-before-exit transaction. Emitting only the
	# navigation intent avoids writing the same world twice from one button press.
	return_to_menu_requested.emit()


func _on_player_died(cause: String) -> void:
	if not _gameplay_active:
		return
	_death_title.text = "你倒下了\n%s" % cause
	_set_overlay(Overlay.DEATH)


func _respawn() -> void:
	if survival != null:
		survival.respawn()
	respawn_requested.emit()
	_set_overlay(Overlay.NONE)


func _center_control(control: Control, desired_size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -desired_size.x * 0.5
	control.offset_right = desired_size.x * 0.5
	control.offset_top = -desired_size.y * 0.5
	control.offset_bottom = desired_size.y * 0.5
