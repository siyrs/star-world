extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://equipment-desktop-acceptance.png"
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _created_world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "game exposes the progression service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Equipment-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 86421357
	)
	_check(not state.is_empty(), "desktop acceptance creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	_check(game.world != null and bool(game.world.get("is_started")), "real game world starts before equipment interaction")
	_check(hub.get_node_or_null("EquipmentService") != null, "equipment service is mounted in the desktop runtime")
	_check(hub.get_node_or_null("AttributeService") != null, "attribute service is mounted in the desktop runtime")
	_check(hub.get_node_or_null("CombatService") != null, "combat service is mounted in the desktop runtime")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures the mouse before opening character UI")

	hub.inventory.clear()
	hub.inventory.add_item("iron_sword", 1)
	hub.inventory.add_item("iron_helmet", 1)
	hub.inventory.add_item("iron_chestplate", 1)
	await process_frame
	await _press_key(KEY_E)
	_check(
		hub.game_ui.get_active_overlay() == GameUIScript.Overlay.INVENTORY,
		"E opens the integrated character inventory overlay",
	)
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "character overlay releases the desktop mouse")
	var panel: Node = hub.game_ui.call("get_character_panel")
	_check(panel != null and panel.visible, "character panel is visible")
	if panel == null:
		await _finish(game, hub)
		return
	var panel_rect: Rect2 = panel.get_global_rect()
	_check(_rect_is_inside_viewport(panel_rect), "character panel stays inside the 1024x576 viewport")
	var layout: Dictionary = panel.call("get_layout_rects")
	_check(
		Rect2(layout.get("equipment", Rect2())).size.x > 0.0
		and Rect2(layout.get("attributes", Rect2())).size.y > 0.0
		and Rect2(layout.get("inventory", Rect2())).size.x > 0.0,
		"equipment, attribute and inventory surfaces have measurable layout",
	)

	var sword_index := _find_item_slot(hub.inventory, "iron_sword")
	_check(sword_index >= 0, "iron sword is present in the player inventory")
	if sword_index >= 0:
		var sword_button: Control = panel.call("get_inventory_button", sword_index)
		_check(sword_button != null, "character panel exposes the sword slot button")
		if sword_button != null:
			await _right_click_control(sword_button)
	_check(
		str(hub.equipment_service.get_slot("main_hand").get("item_id", "")) == "iron_sword",
		"a real right click equips the sword",
	)
	_check(is_equal_approx(hub.attribute_service.get_value("attack_damage"), 6.0), "equipping the sword updates attack immediately")

	var helmet_index := _find_item_slot(hub.inventory, "iron_helmet")
	if helmet_index >= 0:
		var helmet_button: Control = panel.call("get_inventory_button", helmet_index)
		if helmet_button != null:
			await _right_click_control(helmet_button)
	var chest_index := _find_item_slot(hub.inventory, "iron_chestplate")
	if chest_index >= 0:
		var chest_button: Control = panel.call("get_inventory_button", chest_index)
		if chest_button != null:
			await _right_click_control(chest_button)
	_check(
		str(hub.equipment_service.get_slot("helmet").get("item_id", "")) == "iron_helmet",
		"a real right click equips the helmet",
	)
	_check(
		str(hub.equipment_service.get_slot("chestplate").get("item_id", ""))
		== "iron_chestplate",
		"a real right click equips the chestplate",
	)
	_check(is_equal_approx(hub.attribute_service.get_value("defense"), 8.0), "armor updates the live defense summary")
	var mitigated: Dictionary = hub.combat_service.resolve_incoming_damage(10.0, "desktop_test", false)
	_check(
		float(mitigated.get("final_damage", 10.0)) < 10.0,
		"desktop runtime combat consumes equipped defense",
	)

	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "equipment desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)

	var main_hand_button: Control = panel.call("get_equipment_button", "main_hand")
	_check(main_hand_button != null, "character panel exposes the equipped main-hand button")
	if main_hand_button != null:
		await _left_click_control(main_hand_button)
	_check(hub.equipment_service.get_slot("main_hand").is_empty(), "clicking the equipment slot unequips the sword")
	_check(hub.inventory.count_item("iron_sword") == 1, "unequipped sword returns to inventory without loss")
	_check(is_equal_approx(hub.attribute_service.get_value("attack_damage"), 1.0), "unequipping restores base attack")

	var close_button := _find_button(panel, "关闭 [E]")
	_check(close_button != null, "character panel exposes a close button")
	if close_button != null:
		await _left_click_control(close_button)
	_check(
		hub.game_ui.get_active_overlay() == GameUIScript.Overlay.NONE,
		"a real pointer click closes the character overlay",
	)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing the panel recaptures the gameplay mouse")
	await _finish(game, hub)


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _created_world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_created_world_id)
		if hub.get("audio_service") != null:
			if hub.audio_service.has_method("shutdown"):
				hub.audio_service.shutdown()
			else:
				hub.audio_service.stop_ambient()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA EQUIPMENT DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure in failures:
			push_error("QA EQUIPMENT DESKTOP FAILURE: %s" % failure)
		print(
			"QA EQUIPMENT DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _press_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release)
	await process_frame


func _right_click_control(control: Control) -> void:
	await _click_control(control, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MASK_RIGHT)


func _left_click_control(control: Control) -> void:
	await _click_control(control, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)


func _click_control(control: Control, button_index: int, button_mask: int) -> void:
	await process_frame
	var pointer_position := _canvas_to_viewport(control.get_global_rect().get_center())
	var motion := InputEventMouseMotion.new()
	motion.position = pointer_position
	motion.global_position = pointer_position
	root.push_input(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = pointer_position
	press.global_position = pointer_position
	press.button_index = button_index
	press.button_mask = button_mask
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = pointer_position
	release.global_position = pointer_position
	release.button_index = button_index
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func _rect_is_inside_viewport(rect: Rect2) -> bool:
	var transformed_start := _canvas_to_viewport(rect.position)
	var transformed_end := _canvas_to_viewport(rect.end)
	var transformed_rect := Rect2(transformed_start, transformed_end - transformed_start)
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	return (
		transformed_rect.position.x >= -0.5
		and transformed_rect.position.y >= -0.5
		and transformed_rect.end.x <= bounds.end.x + 0.5
		and transformed_rect.end.y <= bounds.end.y + 0.5
	)


func _canvas_to_viewport(position: Vector2) -> Vector2:
	return root.get_final_transform() * position


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"equipment desktop screenshot is saved",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
