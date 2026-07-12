extends SceneTree

const InputContextScript = preload("res://src/input/input_context_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const InventoryPanelScript = preload("res://src/ui/inventory_panel.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []
var hotbar_selection_events := 0


class InputProbe:
	extends Node
	var input_enabled := true

	func set_input_enabled(enabled: bool) -> void:
		input_enabled = enabled


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_input_context_ownership()
	await _test_inventory_selection_and_equip()
	await _test_selected_food_consumption()
	await _test_game_ui_state_machine()
	if failures.is_empty():
		print("QA INPUT INTERACTION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA INPUT INTERACTION FAILURE: %s" % failure)
		print("QA INPUT INTERACTION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_input_context_ownership() -> void:
	var host := Node.new()
	root.add_child(host)
	var context = InputContextScript.new()
	var probe = InputProbe.new()
	host.add_child(context)
	host.add_child(probe)
	await process_frame
	context.bind_player(probe)
	context.set_context(InputContextScript.CONTEXT_MENU)
	_check(not probe.input_enabled, "menu context disables gameplay input")
	_check(
		context.set_context(InputContextScript.CONTEXT_GAMEPLAY) and probe.input_enabled,
		"gameplay context enables the player"
	)
	_check(
		context.set_context(InputContextScript.CONTEXT_INVENTORY) and not probe.input_enabled,
		"inventory context releases player input"
	)
	var previous_context: StringName = context.get_context()
	_check(
		not context.set_context(&"unknown") and context.get_context() == previous_context,
		"unknown contexts cannot corrupt input state"
	)
	host.queue_free()
	await process_frame


func _test_inventory_selection_and_equip() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var panel = InventoryPanelScript.new()
	host.add_child(inventory)
	host.add_child(panel)
	await process_frame
	panel.setup(inventory)
	inventory.clear()
	inventory.add_item("stone", 1)
	inventory.swap_slots(0, 12)
	inventory.select_slot(3)
	_check(inventory.equip_slot(12, 4), "inventory service equips a backpack slot")
	_check(
		str(inventory.get_slot(4).get("item_id", "")) == "stone",
		"equipped item moves into the requested hotbar slot"
	)
	_check(inventory.selected_slot == 4, "equipping selects the actual target hotbar slot")
	_check(
		inventory.get_slot(12).is_empty(),
		"equipping clears the source slot when the hotbar target is empty"
	)
	_check(not inventory.equip_slot(99), "invalid equip requests are rejected")
	inventory.add_item("apple", 1)
	inventory.swap_slots(0, 12)
	var slot_buttons: Array = panel.get("_slot_buttons")
	slot_buttons[5].pressed.emit()
	_check(
		inventory.selected_slot == 5, "clicking a hotbar slot updates the actual usable selection"
	)
	_check(
		int(panel.get("_selected_source")) == -1,
		"selecting a hotbar item does not silently arm an inventory swap"
	)
	slot_buttons[12].emit_signal("slot_activated", 12)
	_check(
		str(inventory.get_slot(5).get("item_id", "")) == "apple" and inventory.selected_slot == 5,
		"activating a backpack item equips it to the active hotbar slot"
	)
	host.queue_free()
	await process_frame


func _test_selected_food_consumption() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var survival = SurvivalScript.new()
	var player = PlayerScene.instantiate()
	host.add_child(inventory)
	host.add_child(survival)
	host.add_child(player)
	await process_frame
	_check(
		not player.input_enabled, "player input starts disabled until a gameplay context owns it"
	)
	player.hotbar_selection_changed.connect(_on_hotbar_selection_changed)
	player.set_physics_process(false)
	player.set_process(false)
	player.bind_inventory(inventory)
	player.bind_survival(survival)
	inventory.clear()
	inventory.add_item("apple", 1, {"stack": "keep"})
	inventory.add_item("apple", 1, {"stack": "consume"})
	hotbar_selection_events = 0
	player.select_hotbar(1)
	_check(
		hotbar_selection_events == 1,
		"one hotbar action emits one selection change instead of being handled twice"
	)
	survival.hunger = 10.0
	survival.saturation = 0.0
	_check(player.use_selected_item(), "secondary use consumes a selected food item")
	_check(inventory.get_slot(1).is_empty(), "food consumption removes the selected stack")
	_check(
		str(inventory.get_slot(0).get("item_id", "")) == "apple",
		"food consumption leaves matching non-selected stacks untouched"
	)
	_check(survival.hunger > 10.0, "selected food restores hunger")
	host.queue_free()
	await process_frame
	await process_frame


func _test_game_ui_state_machine() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	var survival = SurvivalScript.new()
	var game_ui = GameUIScript.new()
	host.add_child(inventory)
	host.add_child(crafting)
	host.add_child(survival)
	host.add_child(game_ui)
	await process_frame
	crafting.setup(inventory)
	game_ui.setup(inventory, crafting, survival, null)
	var contexts: Array[StringName] = []
	game_ui.input_context_requested.connect(func(context: StringName): contexts.append(context))
	game_ui.begin_gameplay()
	_check(
		game_ui.visible and game_ui.get_active_overlay() == GameUIScript.Overlay.NONE,
		"starting gameplay resets transient overlays"
	)
	_check(
		not contexts.is_empty() and contexts.back() == InputContextScript.CONTEXT_GAMEPLAY,
		"starting gameplay requests the gameplay input context"
	)
	game_ui.open_inventory()
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.INVENTORY
			and contexts.back() == InputContextScript.CONTEXT_INVENTORY
		),
		"inventory overlay owns input while open"
	)
	game_ui.close_overlay()
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.NONE
			and contexts.back() == InputContextScript.CONTEXT_GAMEPLAY
		),
		"closing an overlay restores gameplay input"
	)
	game_ui.toggle_pause()
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.PAUSE
			and contexts.back() == InputContextScript.CONTEXT_PAUSE
		),
		"pause overlay requests a non-gameplay input context"
	)
	var resume_button := _find_button(game_ui, "继续游戏")
	_check(resume_button != null, "pause overlay exposes a resume action")
	if resume_button != null:
		resume_button.pressed.emit()
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.NONE
			and contexts.back() == InputContextScript.CONTEXT_GAMEPLAY
		),
		"resume button restores gameplay input"
	)
	survival.take_damage(999.0, "qa")
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.DEATH
			and contexts.back() == InputContextScript.CONTEXT_DEATH
		),
		"death state keeps the cursor available for its buttons"
	)
	game_ui.close_overlay()
	_check(
		game_ui.get_active_overlay() == GameUIScript.Overlay.DEATH,
		"death overlay cannot be dismissed into an unusable gameplay state"
	)
	var respawn_button := _find_button(game_ui, "重生")
	_check(respawn_button != null, "death overlay exposes a respawn action")
	if respawn_button != null:
		respawn_button.pressed.emit()
	_check(
		(
			survival.alive
			and game_ui.get_active_overlay() == GameUIScript.Overlay.NONE
			and contexts.back() == InputContextScript.CONTEXT_GAMEPLAY
		),
		"respawn returns to a usable gameplay context"
	)
	game_ui.end_gameplay()
	_check(
		not game_ui.visible and game_ui.is_gameplay_input_blocked(),
		"ending gameplay hides UI and keeps gameplay input blocked"
	)
	survival.alive = false
	game_ui.begin_gameplay()
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.DEATH
			and contexts.back() == InputContextScript.CONTEXT_DEATH
		),
		"loading a dead survival state reopens the death overlay instead of enabling controls"
	)
	game_ui.end_gameplay()
	host.queue_free()
	await process_frame
	await process_frame


func _on_hotbar_selection_changed(_index: int, _block_id: String) -> void:
	hotbar_selection_events += 1


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == label:
			return child
		var nested := _find_button(child, label)
		if nested != null:
			return nested
	return null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
