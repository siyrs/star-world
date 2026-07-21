extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const Actions = preload("res://src/input/gameplay_input_actions.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1024, 576)
	# With canvas_items stretch the design viewport only follows content_scale_size;
	# resizing the window alone leaves layout running in the 1280x720 space.
	root.content_scale_size = Vector2i(1024, 576)
	Actions.ensure_default_bindings()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var hub: Node = game.get("service_hub")
	var main_menu: Node = hub.get("main_menu")
	var settings_panel := main_menu.get("_settings_panel") as Control
	main_menu.call("_show_panel", settings_panel)
	await process_frame
	_check(settings_panel != null and settings_panel.visible, "settings surface opens at compact resolution")
	_check(
		settings_panel != null and _rect_inside(viewport_rect, settings_panel.get_global_rect()),
		"settings surface remains fully inside the 576p viewport",
	)
	main_menu.call("show_main")
	var settings: Dictionary = hub.current_settings.duplicate(true)
	settings["show_tutorial"] = true
	settings["show_interaction_prompts"] = true
	hub.main_menu.settings_changed.emit(settings)
	var state: Dictionary = hub.save_service.create_world(
		"qa-ui-layout-%d" % Time.get_ticks_msec(), "star_continent", 774411
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	game.call("begin_world_state", state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	var game_ui: Node = hub.get("game_ui")
	var hud: Node = game_ui.get("hud")
	var guidance: Node = game_ui.call("get_guidance_overlay")
	var hud_rects: Dictionary = hud.call("get_layout_rects")
	var status_rect: Rect2 = hud_rects.get("status", Rect2())
	var item_rect: Rect2 = hud_rects.get("selected_item", Rect2())
	var hotbar_rect: Rect2 = hud_rects.get("hotbar", Rect2())
	var tutorial_panel := guidance.get("_tutorial_panel") as Control
	var prompt_panel := guidance.get("_prompt_panel") as Control
	var tutorial_rect := tutorial_panel.get_global_rect() if tutorial_panel != null else Rect2()
	var prompt_rect := prompt_panel.get_global_rect() if prompt_panel != null else Rect2()
	_check(tutorial_panel != null and tutorial_panel.visible, "tutorial is visible in a new world")
	_check(prompt_panel != null and prompt_panel.visible, "held starter block produces a visible prompt")
	_check(not tutorial_rect.intersects(status_rect), "tutorial does not overlap the status card")
	_check(not tutorial_rect.intersects(prompt_rect), "tutorial does not overlap contextual actions")
	_check(not tutorial_rect.intersects(item_rect), "tutorial does not overlap selected item feedback")
	_check(not tutorial_rect.intersects(hotbar_rect), "tutorial does not overlap the hotbar")
	_check(not prompt_rect.intersects(item_rect), "context prompt remains above selected item feedback")
	_check(not prompt_rect.intersects(hotbar_rect), "context prompt remains above the hotbar")
	_check(_rect_inside(viewport_rect, status_rect), "status card remains inside the compact viewport")
	_check(_rect_inside(viewport_rect, tutorial_rect), "tutorial remains inside the compact viewport")
	_check(_rect_inside(viewport_rect, prompt_rect), "context prompt remains inside the compact viewport")
	_check(_rect_inside(viewport_rect, hotbar_rect), "hotbar remains inside the compact viewport")
	game_ui.call("open_inventory")
	await process_frame
	_check(
		not tutorial_panel.visible and not prompt_panel.visible,
		"blocking overlays hide world guidance instead of stacking more UI",
	)
	game_ui.call("close_overlay")
	await process_frame
	_check(tutorial_panel.visible and prompt_panel.visible, "closing the overlay restores world guidance")
	await _press_key(KEY_F1)
	_check(not tutorial_panel.visible and prompt_panel.visible, "F1 hides only the tutorial, not context help")
	await _press_key(KEY_F1)
	_check(tutorial_panel.visible, "F1 restores the tutorial in its safe layout region")
	hub.call("return_to_menu")
	await process_frame
	_check(hub.save_service.delete_world(world_id), "UI layout test world is cleaned up")
	var audio = hub.get("audio_service")
	if audio != null and audio.has_method("shutdown"):
		audio.call("shutdown")
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("QA UI LAYOUT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA UI LAYOUT FAILURE: %s" % failure)
		print("QA UI LAYOUT FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x
		and candidate.position.y >= container_rect.position.y
		and candidate.end.x <= container_rect.end.x
		and candidate.end.y <= container_rect.end.y
	)


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


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
