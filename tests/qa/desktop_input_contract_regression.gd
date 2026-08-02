extends SceneTree

const HudScript = preload("res://src/ui/hud.gd")
const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const SaveServiceScript = preload("res://src/save/save_service.gd")
const SpawnResolverScript = preload("res://src/player/player_spawn_resolver.gd")

var checks := 0
var failures: Array[String] = []


class GroundWorld:
	extends Node

	func get_block(position: Vector3i) -> String:
		return "stone" if position.y <= 0 else "air"

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, 1.05, candidate.z)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# In headless runs the window starts at 64x64 while the design viewport is
	# 1280x720, so pushed input coordinates would land outside the window.
	# Match both the window and the canvas-items stretch target to the design
	# resolution before simulating pointer input (content_scale_size drives the
	# logical viewport under canvas_items stretch; root.size alone only resizes
	# the native window).
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	await _test_hud_pointer_passthrough()
	await _test_real_menu_pointer_click()
	await _test_safe_new_world_spawn()
	if failures.is_empty():
		print("QA DESKTOP INPUT CONTRACT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA DESKTOP INPUT CONTRACT FAILURE: %s" % failure)
		print("QA DESKTOP INPUT CONTRACT FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_hud_pointer_passthrough() -> void:
	var hud = HudScript.new()
	root.add_child(hud)
	await process_frame
	var blocking_controls: Array[String] = []
	_collect_blocking_controls(hud, blocking_controls)
	_check(
		blocking_controls.is_empty(),
		"all HUD descendants ignore pointer input so the crosshair cannot swallow mouse events",
	)
	hud.queue_free()
	await process_frame


func _test_real_menu_pointer_click() -> void:
	var menu = MainMenuScene.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var continue_button := _find_button(menu, "继续游戏")
	_check(continue_button != null, "continue button exists for pointer routing test")
	if continue_button != null:
		await _click_control(continue_button)
	var map_panel: Control = menu.get("_map_panel")
	var main_panel: Control = menu.get("_main_panel")
	var loading_panel: Control = menu.get("_loading_panel")
	var left_main_menu: bool = (
		(main_panel != null and not main_panel.visible)
		or (map_panel != null and map_panel.visible)
	)
	# The product's continue action routes by whether any world exists: with real
	# user worlds present it loads the latest one (loading panel); with no worlds
	# it falls back to the create panel. Either is the intended contract; the
	# point of this check is that the viewport mouse press+release reaches the
	# button and leaves the main command deck.
	_check(
		left_main_menu,
		"viewport mouse press and release reach continue and route away from the main menu",
	)
	menu.queue_free()
	await process_frame


func _test_safe_new_world_spawn() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	var state: Dictionary = save.create_world(
		"qa-spawn-%d" % Time.get_ticks_msec(), "star_continent", 112358
	)
	_check(not state.is_empty(), "new world state is created")
	var position = state.get("player", {}).get("position", null)
	_check(position is Array and position.is_empty(), "new worlds defer first spawn to world generation")
	var world_id := str(state.get("metadata", {}).get("id", ""))
	if not world_id.is_empty():
		save.delete_world(world_id)
	var ground_world := GroundWorld.new()
	root.add_child(ground_world)
	var resolver = SpawnResolverScript.new()
	var resolved: Vector3 = resolver.resolve(
		ground_world, Vector3(0.5, 48.0, 0.5), Vector3(0.5, 2.05, 0.5)
	)
	_check(resolved.y < 3.0, "legacy high-air placeholder is grounded")
	_check(resolver.is_position_supported(ground_world, resolved), "resolved spawn has terrain support")
	ground_world.queue_free()
	save.queue_free()
	await process_frame


func _collect_blocking_controls(node: Node, result: Array[String]) -> void:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		result.append(str(node.get_path()))
	for child in node.get_children():
		_collect_blocking_controls(child, result)


func _click_control(control: Control) -> void:
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
	release.pressed = false
	root.push_input(release)
	await process_frame


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
