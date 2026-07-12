class_name GameUI
extends CanvasLayer

signal save_requested
signal return_to_menu_requested
signal respawn_requested

const HudScript = preload("res://src/ui/hud.gd")
const InventoryPanelScript = preload("res://src/ui/inventory_panel.gd")
const CraftingPanelScript = preload("res://src/ui/crafting_panel.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")

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


func _ready() -> void:
	layer = 10
	hud = HudScript.new()
	add_child(hud)
	inventory_panel = InventoryPanelScript.new()
	_center_control(inventory_panel, Vector2(710, 520))
	add_child(inventory_panel)
	inventory_panel.visible = false
	inventory_panel.panel_closed.connect(func(): _close_panels())
	crafting_panel = CraftingPanelScript.new()
	_center_control(crafting_panel, Vector2(760, 590))
	add_child(crafting_panel)
	crafting_panel.visible = false
	crafting_panel.panel_closed.connect(func(): _close_panels())
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
	if survival != null:
		survival.player_died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_E:
		inventory_panel.visible = not inventory_panel.visible
		crafting_panel.visible = false
		_pause_panel.visible = false
		_update_mouse_mode()
	elif event.keycode == KEY_C:
		crafting_panel.visible = not crafting_panel.visible
		inventory_panel.visible = false
		_pause_panel.visible = false
		_update_mouse_mode()
	elif event.keycode == KEY_ESCAPE:
		if inventory_panel.visible or crafting_panel.visible:
			_close_panels()
		else:
			_pause_panel.visible = not _pause_panel.visible
			_update_mouse_mode()


func open_workbench() -> void:
	crafting_panel.open_station("workbench")
	crafting_panel.visible = true
	inventory_panel.visible = false
	_update_mouse_mode()


func open_furnace() -> void:
	crafting_panel.open_station("furnace")
	crafting_panel.visible = true
	inventory_panel.visible = false
	_update_mouse_mode()


func _close_panels() -> void:
	inventory_panel.visible = false
	crafting_panel.visible = false
	_pause_panel.visible = false
	_update_mouse_mode()


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
	resume.pressed.connect(_close_panels)
	content.add_child(resume)
	var save := Button.new()
	save.text = "保存世界"
	save.pressed.connect(func(): save_requested.emit(); hud.show_message("世界已保存"))
	content.add_child(save)
	var exit := Button.new()
	exit.text = "保存并返回主菜单"
	exit.pressed.connect(func(): save_requested.emit(); return_to_menu_requested.emit())
	content.add_child(exit)


func _build_death_panel() -> void:
	_death_panel = PanelContainer.new()
	_death_panel.theme = ThemeFactory.create_theme()
	_center_control(_death_panel, Vector2(500, 270))
	add_child(_death_panel)
	_death_panel.visible = false
	var content := VBoxContainer.new()
	_death_panel.add_child(content)
	var title := Label.new()
	title.text = "你倒下了"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)
	var respawn := Button.new()
	respawn.text = "重生"
	respawn.pressed.connect(_respawn)
	content.add_child(respawn)
	var menu := Button.new()
	menu.text = "返回主菜单"
	menu.pressed.connect(func(): return_to_menu_requested.emit())
	content.add_child(menu)


func _on_player_died(cause: String) -> void:
	_death_panel.visible = true
	_death_panel.get_child(0).get_child(0).text = "你倒下了\n%s" % cause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _respawn() -> void:
	if survival != null:
		survival.respawn()
	_death_panel.visible = false
	respawn_requested.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_panel.visible or crafting_panel.visible or _pause_panel.visible else Input.MOUSE_MODE_CAPTURED


func _center_control(control: Control, desired_size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -desired_size.x * 0.5
	control.offset_right = desired_size.x * 0.5
	control.offset_top = -desired_size.y * 0.5
	control.offset_bottom = desired_size.y * 0.5
