extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")

const OUTPUT_PATH := "user://furnace-desktop-acceptance.png"

var checks := 0
var failures: Array[String] = []
var _created_world_id := ""
var _capture_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = ProjectSettings.globalize_path(OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var hub: Node = game.get("service_hub")
	var state: Dictionary = hub.save_service.create_world(
		"Furnace-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 97531
	)
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.call("begin_world_state", state)
	await process_frame
	await physics_frame
	await process_frame
	_check(
		game.world != null and bool(game.world.get("is_started")),
		"desktop furnace test starts a real world",
	)

	hub.inventory.clear()
	hub.inventory.add_item("raw_iron", 1)
	hub.inventory.add_item("coal", 1)
	var block_position := Vector3i(3, 22, -2)
	_check(
		hub.block_interaction.interact(game.world, block_position, "furnace"),
		"the world interaction contract opens a furnace on desktop",
	)
	await process_frame
	var game_ui: Node = hub.get("game_ui")
	var panel := game_ui.call("get_furnace_panel") as Control
	_check(
		game_ui.call("get_active_overlay") == GameUIScript.Overlay.FURNACE,
		"the dedicated furnace overlay becomes active",
	)
	_check(panel != null and panel.visible, "the furnace surface is visible")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "opening the furnace releases the mouse")
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	_check(
		panel != null and _rect_inside(viewport_rect, panel.get_global_rect()),
		"the complete furnace surface fits inside the 1024x576 product baseline",
	)

	var inventory_buttons: Array = panel.get("_inventory_buttons") if panel != null else []
	_check(inventory_buttons.size() == 36, "the machine surface exposes the complete player inventory")
	if inventory_buttons.size() >= 2:
		await _click_control(inventory_buttons[0])
		await _click_control(inventory_buttons[1])
	var machine_id := hub.block_interaction.get_machine_id(game.world, block_position, "furnace")
	_check(
		str(hub.furnace_service.get_slot(machine_id, FurnaceScript.SLOT_INPUT).get("item_id", ""))
		== "raw_iron",
		"a real pointer click moves raw iron into the input slot",
	)
	_check(
		str(hub.furnace_service.get_slot(machine_id, FurnaceScript.SLOT_FUEL).get("item_id", ""))
		== "coal",
		"a real pointer click moves coal into the fuel slot",
	)

	hub.furnace_service.advance_time(6.1, true)
	panel.call("refresh")
	await process_frame
	_check(
		str(hub.furnace_service.get_slot(machine_id, FurnaceScript.SLOT_OUTPUT).get("item_id", ""))
		== "iron_ingot",
		"elapsed machine time produces a visible iron ingot",
	)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "furnace desktop acceptance captures a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)

	var output_button := panel.get("_output_button") as Button if panel != null else null
	_check(output_button != null, "the output slot is a real clickable control")
	if output_button != null:
		await _click_control(output_button)
	_check(
		hub.inventory.count_item("iron_ingot") == 1,
		"clicking output returns the item to the player inventory",
	)
	var close_button := _find_button(panel, "关闭 [Esc]")
	_check(close_button != null, "the furnace exposes a clear close action")
	if close_button != null:
		await _click_control(close_button)
	_check(
		game_ui.call("get_active_overlay") == GameUIScript.Overlay.NONE,
		"closing the furnace restores the gameplay overlay state",
	)
	_check(
		hub.furnace_service.get_active_machine_id().is_empty(),
		"closing the surface releases the active machine reference",
	)
	_check(
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"closing the furnace recaptures the gameplay mouse",
	)
	_check(
		hub.block_interaction.can_break_block(game.world, block_position, "furnace"),
		"an empty furnace can be dismantled even when consumed fuel left residual heat",
	)
	hub.block_interaction.on_block_removed(game.world, block_position, "furnace")
	_check(
		not hub.furnace_service.has_machine(machine_id),
		"dismantling an empty furnace discards transient heat and removes its record",
	)

	_cleanup(game, hub)
	await process_frame
	await process_frame
	if failures.is_empty():
		print("FURNACE_DESKTOP_CAPTURE=%s" % _capture_path)
		print("QA FURNACE DESKTOP PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA FURNACE DESKTOP FAILURE: %s" % failure)
		print("QA FURNACE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _click_control(control: Control) -> void:
	await process_frame
	var pointer_position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer_position
	motion.global_position = pointer_position
	root.push_input(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = pointer_position
	press.global_position = pointer_position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = pointer_position
	release.global_position = pointer_position
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x
		and candidate.position.y >= container_rect.position.y
		and candidate.end.x <= container_rect.end.x
		and candidate.end.y <= container_rect.end.y
	)


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(OUTPUT_PATH)
	_check(
		error == OK and FileAccess.file_exists(OUTPUT_PATH),
		"furnace desktop screenshot is saved",
	)


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func _cleanup(game: Node, hub: Node) -> void:
	if hub != null and not hub.current_world_id.is_empty():
		hub.call("return_to_menu")
	if not _created_world_id.is_empty() and hub != null and hub.get("save_service") != null:
		hub.save_service.delete_world(_created_world_id)
	if hub != null and hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	game.queue_free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
