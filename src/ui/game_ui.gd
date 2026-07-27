class_name GameUI
extends CanvasLayer

signal save_requested
signal return_to_menu_requested
signal respawn_requested
signal input_context_requested(context: StringName)
signal simulation_pause_requested(paused: bool)
signal overlay_changed(overlay: int, context: StringName)

enum Overlay {
	NONE,
	INVENTORY,
	CRAFTING,
	FURNACE,
	CONTAINER,
	PAUSE,
	DEATH,
}

const HudScript = preload("res://src/ui/hud.gd")
const GuidanceOverlayScript = preload("res://src/ui/guidance_overlay.gd")
const InventoryPanelScript = preload("res://src/ui/inventory_panel.gd")
const CraftingPanelScript = preload("res://src/ui/crafting_panel.gd")
const FurnacePanelScript = preload("res://src/ui/furnace_panel.gd")
const ContainerPanelScript = preload("res://src/ui/container_panel.gd")
const ExplorationJournalPanelScript = preload("res://src/ui/responsive_exploration_journal_panel.gd")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const PanelAnimator = preload("res://src/ui/ui_panel_animator.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const InputActionsScript = preload("res://src/input/gameplay_input_actions.gd")
const EXPLORATION_JOURNAL_OVERLAY := ExtensionOverlayIds.EXPLORATION_JOURNAL

var inventory
var crafting
var survival
var day_night
var audio_service
var gameplay_input
var container_storage
var furnace_service
var experience_coordinator
var exploration_journal_service: Node
var exploration_reward_service: Node
var hud
var guidance_overlay
var inventory_panel
var crafting_panel
var furnace_panel
var container_panel
var exploration_journal_panel: Control
var _overlay_scrim: ColorRect
var _pause_panel: PanelContainer
var _death_panel: PanelContainer
var _death_title: Label
var _pause_status: Label
var _overlay: int = Overlay.NONE
var _gameplay_active := false
var _desired_sizes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputActionsScript.ensure_default_bindings()
	layer = 10

	hud = HudScript.new()
	add_child(hud)
	guidance_overlay = GuidanceOverlayScript.new()
	add_child(guidance_overlay)
	_build_overlay_scrim()

	inventory_panel = InventoryPanelScript.new()
	_center_control(inventory_panel, Vector2(760, 520))
	add_child(inventory_panel)
	inventory_panel.visible = false
	inventory_panel.panel_closed.connect(_close_overlay)

	crafting_panel = CraftingPanelScript.new()
	_center_control(crafting_panel, Vector2(820, 540))
	add_child(crafting_panel)
	crafting_panel.visible = false
	crafting_panel.panel_closed.connect(_close_overlay)

	furnace_panel = FurnacePanelScript.new()
	_center_control(furnace_panel, Vector2(940, 540))
	add_child(furnace_panel)
	furnace_panel.visible = false
	furnace_panel.panel_closed.connect(_close_overlay)

	container_panel = ContainerPanelScript.new()
	_center_control(container_panel, Vector2(840, 560))
	add_child(container_panel)
	container_panel.visible = false
	container_panel.panel_closed.connect(_close_overlay)

	exploration_journal_panel = ExplorationJournalPanelScript.new()
	exploration_journal_panel.name = "ExplorationJournalPanel"
	_center_control(exploration_journal_panel, Vector2(920, 550))
	add_child(exploration_journal_panel)
	exploration_journal_panel.visible = false
	exploration_journal_panel.panel_closed.connect(_close_overlay)

	_build_pause_panel()
	_build_death_panel()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func setup(
	p_inventory,
	p_crafting,
	p_survival,
	p_day_night,
	p_audio = null,
	p_gameplay_input = null,
	p_container_storage = null,
	p_furnace_service = null,
	p_experience_coordinator = null
) -> void:
	inventory = p_inventory
	crafting = p_crafting
	survival = p_survival
	day_night = p_day_night
	audio_service = p_audio
	gameplay_input = p_gameplay_input
	container_storage = p_container_storage
	furnace_service = p_furnace_service
	experience_coordinator = p_experience_coordinator
	hud.setup(inventory, survival, day_night)
	guidance_overlay.setup(experience_coordinator)
	if guidance_overlay.has_method("attach_crosshair") and hud.has_method("get_crosshair"):
		guidance_overlay.call("attach_crosshair", hud.call("get_crosshair"))
	inventory_panel.setup(inventory)
	crafting_panel.setup(crafting, inventory)
	furnace_panel.setup(inventory, furnace_service)
	container_panel.setup(inventory, container_storage)
	if survival != null and survival.has_signal("player_died"):
		var callback := Callable(self, "_on_player_died")
		if not survival.is_connected("player_died", callback):
			survival.connect("player_died", callback)


func setup_exploration_journal(
	p_journal_service: Node,
	p_reward_service: Node = null
) -> void:
	exploration_journal_service = p_journal_service
	exploration_reward_service = p_reward_service
	if exploration_journal_panel != null and exploration_journal_panel.has_method("setup"):
		exploration_journal_panel.call(
			"setup",
			exploration_journal_service,
			exploration_reward_service
		)


func begin_gameplay() -> void:
	_gameplay_active = true
	visible = true
	guidance_overlay.begin_gameplay()
	_apply_responsive_layout()
	if survival != null and not bool(survival.get("alive")):
		_death_title.text = "你倒下了"
		_set_overlay(Overlay.DEATH, true)
	else:
		_set_overlay(Overlay.NONE, true)


func end_gameplay() -> void:
	_gameplay_active = false
	if crafting != null:
		crafting.set_station("hand")
	_overlay = Overlay.NONE
	if container_panel != null:
		container_panel.close_container()
	if furnace_panel != null:
		furnace_panel.close_machine()
	_hide_all_overlays()
	if _overlay_scrim != null:
		_overlay_scrim.visible = false
	if inventory_panel != null and inventory_panel.has_method("cancel_swap_selection"):
		inventory_panel.call("cancel_swap_selection")
	if guidance_overlay != null:
		guidance_overlay.end_gameplay()
	visible = false
	simulation_pause_requested.emit(false)


func open_inventory() -> void:
	if not _can_change_overlay():
		return
	_set_overlay(Overlay.NONE if _overlay == Overlay.INVENTORY else Overlay.INVENTORY)


func open_crafting(station: String = "hand") -> void:
	if not _can_change_overlay():
		return
	var resolved_station := station if station in ["hand", "workbench"] else "hand"
	crafting_panel.open_station(resolved_station)
	_set_overlay(Overlay.CRAFTING)


func toggle_crafting(station: String = "hand") -> void:
	if _overlay == Overlay.CRAFTING:
		_set_overlay(Overlay.NONE)
	else:
		open_crafting(station)


func open_workbench() -> void:
	open_crafting("workbench")


func open_furnace(machine_id: String, title: String = "熔炉") -> bool:
	if not _can_change_overlay() or furnace_panel == null:
		return false
	if not furnace_panel.open_machine(machine_id, title):
		show_message("无法打开该熔炉", 2.5, "error", "furnace_open_failed")
		return false
	_set_overlay(Overlay.FURNACE)
	return true


func open_container(container_id: String, title: String = "箱子") -> bool:
	if not _can_change_overlay() or container_panel == null:
		return false
	if not container_panel.open_container(container_id, title):
		show_message("无法打开该容器", 2.5, "error", "container_open_failed")
		return false
	_set_overlay(Overlay.CONTAINER)
	return true


func open_exploration_journal() -> bool:
	if not _can_change_overlay() or exploration_journal_panel == null:
		return false
	if exploration_journal_panel.has_method("refresh"):
		exploration_journal_panel.call("refresh")
	_set_overlay(EXPLORATION_JOURNAL_OVERLAY)
	return true


func toggle_exploration_journal() -> void:
	if _overlay == EXPLORATION_JOURNAL_OVERLAY:
		_set_overlay(Overlay.NONE)
	else:
		open_exploration_journal()


func toggle_pause() -> void:
	if not _can_change_overlay():
		return
	_set_overlay(Overlay.NONE if _overlay == Overlay.PAUSE else Overlay.PAUSE)


func close_overlay() -> void:
	_close_overlay()


func get_active_overlay() -> int:
	return _overlay


func get_guidance_overlay() -> Node:
	return guidance_overlay


func get_furnace_panel() -> Node:
	return furnace_panel


func get_exploration_journal_panel() -> Node:
	return exploration_journal_panel


func is_gameplay_input_blocked() -> bool:
	return not _gameplay_active or _overlay != Overlay.NONE


func get_visual_snapshot() -> Dictionary:
	return {
		"overlay": _overlay,
		"scrim_visible": _overlay_scrim != null and _overlay_scrim.visible,
		"inventory_rect": inventory_panel.get_global_rect() if inventory_panel != null else Rect2(),
		"crafting_rect": crafting_panel.get_global_rect() if crafting_panel != null else Rect2(),
		"furnace_rect": furnace_panel.get_global_rect() if furnace_panel != null else Rect2(),
		"container_rect": container_panel.get_global_rect() if container_panel != null else Rect2(),
		"journal_rect": (
			exploration_journal_panel.get_global_rect()
			if exploration_journal_panel != null
			else Rect2()
		),
		"pause_rect": _pause_panel.get_global_rect() if _pause_panel != null else Rect2(),
		"death_rect": _death_panel.get_global_rect() if _death_panel != null else Rect2(),
	}


func show_message(
	message: String, seconds: float = 2.0, severity: String = "info", dedupe_key: String = ""
) -> void:
	if experience_coordinator != null and experience_coordinator.has_method("publish_message"):
		experience_coordinator.call("publish_message", message, severity, seconds, dedupe_key)
	elif hud != null:
		hud.show_message(message, seconds)


func show_save_result(saved: bool) -> void:
	var message := "世界已保存" if saved else "保存失败，请检查磁盘空间或写入权限"
	if _pause_status != null:
		_pause_status.text = message
		_pause_status.theme_type_variation = "SuccessLabel" if saved else "DangerLabel"
	show_message(message, 3.0, "success" if saved else "error", "save_result")


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
	if _event_toggles_inventory(event):
		open_inventory()
		get_viewport().set_input_as_handled()
	elif _event_toggles_crafting(event):
		toggle_crafting("hand")
		get_viewport().set_input_as_handled()
	elif _event_toggles_exploration_journal(event):
		toggle_exploration_journal()
		get_viewport().set_input_as_handled()


func _event_toggles_inventory(event: InputEvent) -> bool:
	if gameplay_input != null and gameplay_input.has_method("event_toggles_inventory"):
		return bool(gameplay_input.call("event_toggles_inventory", event))
	return event.is_action_pressed(InputActionsScript.TOGGLE_INVENTORY)


func _event_toggles_crafting(event: InputEvent) -> bool:
	if gameplay_input != null and gameplay_input.has_method("event_toggles_crafting"):
		return bool(gameplay_input.call("event_toggles_crafting", event))
	return event.is_action_pressed(InputActionsScript.TOGGLE_CRAFTING)


func _event_toggles_exploration_journal(event: InputEvent) -> bool:
	if gameplay_input != null and gameplay_input.has_method("event_toggles_exploration_journal"):
		return bool(gameplay_input.call("event_toggles_exploration_journal", event))
	return event.is_action_pressed(InputActionsScript.TOGGLE_EXPLORATION_JOURNAL)


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
	if _overlay == Overlay.CRAFTING and next_overlay != Overlay.CRAFTING:
		if crafting != null:
			crafting.set_station("hand")
	if _overlay == Overlay.FURNACE and next_overlay != Overlay.FURNACE:
		if furnace_panel != null:
			furnace_panel.close_machine()
	if _overlay == Overlay.CONTAINER and next_overlay != Overlay.CONTAINER:
		if container_panel != null:
			container_panel.close_container()
	_overlay = next_overlay
	_hide_all_overlays()
	if _overlay_scrim != null:
		_overlay_scrim.visible = _overlay != Overlay.NONE
	match _overlay:
		Overlay.INVENTORY:
			PanelAnimator.open(inventory_panel)
		Overlay.CRAFTING:
			PanelAnimator.open(crafting_panel)
		Overlay.FURNACE:
			PanelAnimator.open(furnace_panel)
		Overlay.CONTAINER:
			PanelAnimator.open(container_panel)
		Overlay.PAUSE:
			PanelAnimator.open(_pause_panel)
			_pause_status.text = ""
			_pause_status.theme_type_variation = "CaptionLabel"
		Overlay.DEATH:
			PanelAnimator.open(_death_panel)
	if _overlay == EXPLORATION_JOURNAL_OVERLAY and exploration_journal_panel != null:
		PanelAnimator.open(exploration_journal_panel)
	var context := _context_for_overlay()
	if guidance_overlay != null:
		guidance_overlay.set_overlay_blocked(_overlay != Overlay.NONE)
	input_context_requested.emit(context)
	simulation_pause_requested.emit(_overlay in [Overlay.PAUSE, Overlay.DEATH])
	overlay_changed.emit(_overlay, context)


func _hide_all_overlays() -> void:
	if inventory_panel != null:
		inventory_panel.visible = false
	if crafting_panel != null:
		crafting_panel.visible = false
	if furnace_panel != null:
		furnace_panel.visible = false
	if container_panel != null:
		container_panel.visible = false
	if exploration_journal_panel != null:
		exploration_journal_panel.visible = false
	if _pause_panel != null:
		_pause_panel.visible = false
	if _death_panel != null:
		_death_panel.visible = false


func _context_for_overlay() -> StringName:
	if _overlay == EXPLORATION_JOURNAL_OVERLAY:
		return InputContextScript.CONTEXT_JOURNAL
	match _overlay:
		Overlay.INVENTORY:
			return InputContextScript.CONTEXT_INVENTORY
		Overlay.CRAFTING:
			return InputContextScript.CONTEXT_CRAFTING
		Overlay.FURNACE:
			return InputContextScript.CONTEXT_MACHINE
		Overlay.CONTAINER:
			return InputContextScript.CONTEXT_CONTAINER
		Overlay.PAUSE:
			return InputContextScript.CONTEXT_PAUSE
		Overlay.DEATH:
			return InputContextScript.CONTEXT_DEATH
		_:
			return InputContextScript.CONTEXT_GAMEPLAY


func _build_overlay_scrim() -> void:
	_overlay_scrim = ColorRect.new()
	_overlay_scrim.name = "OverlayScrim"
	_overlay_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_scrim.color = Color("#02070DB8")
	_overlay_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_scrim.visible = false
	add_child(_overlay_scrim)


func _build_pause_panel() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.name = "PausePanel"
	_pause_panel.theme = ThemeFactory.create_theme()
	_pause_panel.theme_type_variation = "ModalPanel"
	_center_control(_pause_panel, Vector2(500, 480))
	add_child(_pause_panel)
	_pause_panel.visible = false
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_MD)
	_pause_panel.add_child(content)
	var eyebrow := UiKit.make_eyebrow("EXPEDITION PAUSED")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(eyebrow)
	var title := UiKit.make_title("游戏已暂停")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle := UiKit.make_subtitle("世界模拟、机器、作物与自动保存活动时间均已停止。")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	content.add_child(UiKit.make_divider())
	_pause_status = Label.new()
	_pause_status.name = "PauseStatus"
	_pause_status.theme_type_variation = "CaptionLabel"
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_status.custom_minimum_size.y = 28
	content.add_child(_pause_status)
	var resume := UiKit.style_button(
		Button.new(), "PrimaryButton", Vector2(0, Tokens.CONTROL_HEIGHT_LG)
	)
	resume.text = "继续游戏"
	resume.pressed.connect(_close_overlay)
	content.add_child(resume)
	var save := UiKit.style_button(
		Button.new(), "SecondaryButton", Vector2(0, Tokens.CONTROL_HEIGHT_MD)
	)
	save.text = "保存世界"
	save.pressed.connect(_save_from_pause)
	content.add_child(save)
	var exit := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(0, Tokens.CONTROL_HEIGHT_MD)
	)
	exit.text = "保存并返回主菜单"
	exit.pressed.connect(_save_and_return_to_menu)
	content.add_child(exit)
	var hint := Label.new()
	hint.text = "ESC 继续 · F5 快速保存"
	hint.theme_type_variation = "SubduedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)


func _build_death_panel() -> void:
	_death_panel = PanelContainer.new()
	_death_panel.name = "DeathPanel"
	_death_panel.theme = ThemeFactory.create_theme()
	_death_panel.theme_type_variation = "ModalPanel"
	_death_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#2A0F0AFA", Tokens.COLOR_DANGER, 2, Tokens.SPACE_XL)
	)
	_center_control(_death_panel, Vector2(540, 350))
	add_child(_death_panel)
	_death_panel.visible = false
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_MD)
	_death_panel.add_child(content)
	var eyebrow := UiKit.make_eyebrow("EXPEDITION INTERRUPTED")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color", Tokens.color(Tokens.COLOR_DANGER))
	content.add_child(eyebrow)
	_death_title = UiKit.make_title("你倒下了")
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_death_title)
	var hint := UiKit.make_subtitle("重生会恢复生命，并返回当前地图的安全出生点。")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)
	content.add_child(UiKit.make_divider())
	var respawn := UiKit.style_button(
		Button.new(), "PrimaryButton", Vector2(0, Tokens.CONTROL_HEIGHT_LG)
	)
	respawn.text = "重生"
	respawn.pressed.connect(_respawn)
	content.add_child(respawn)
	var menu := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(0, Tokens.CONTROL_HEIGHT_MD)
	)
	menu.text = "返回主菜单"
	menu.pressed.connect(func() -> void: return_to_menu_requested.emit())
	content.add_child(menu)


func _save_from_pause() -> void:
	_pause_status.text = "正在保存世界…"
	_pause_status.theme_type_variation = "CaptionLabel"
	show_message("正在保存…", 1.0, "info", "save_progress")
	save_requested.emit()


func _save_and_return_to_menu() -> void:
	_pause_status.text = "正在保存并返回主菜单…"
	_pause_status.theme_type_variation = "CaptionLabel"
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
	control.set_meta("star_desired_size", desired_size)
	_desired_sizes[control.get_instance_id()] = desired_size
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	_fit_control(control, desired_size)


func _fit_control(control: Control, desired_size: Vector2) -> void:
	if control == null or not is_instance_valid(control):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = Vector2(1280, 720)
	var safe_size := Vector2(
		minf(desired_size.x, maxf(320.0, viewport_size.x - Tokens.PANEL_SAFE_MARGIN * 2.0)),
		minf(desired_size.y, maxf(260.0, viewport_size.y - Tokens.PANEL_SAFE_MARGIN * 2.0))
	)
	control.offset_left = -safe_size.x * 0.5
	control.offset_right = safe_size.x * 0.5
	control.offset_top = -safe_size.y * 0.5
	control.offset_bottom = safe_size.y * 0.5


func _apply_responsive_layout() -> void:
	for control in [
		inventory_panel,
		crafting_panel,
		furnace_panel,
		container_panel,
		exploration_journal_panel,
		_pause_panel,
		_death_panel,
	]:
		if control == null or not is_instance_valid(control):
			continue
		var desired: Variant = control.get_meta("star_desired_size", control.custom_minimum_size)
		_fit_control(control, desired if desired is Vector2 else control.custom_minimum_size)
