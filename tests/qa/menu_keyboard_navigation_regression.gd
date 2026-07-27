extends SceneTree

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)
	var menu := MainMenuScene.instantiate()
	root.add_child(menu)
	for _frame in 8:
		await process_frame

	var snapshot: Dictionary = menu.call("get_navigation_snapshot")
	_check(
		bool(snapshot.get("main_visible", false))
		and str(snapshot.get("focus_text", "")) == "继续游戏",
		"startup places keyboard focus on the primary expedition action"
	)

	await _press_key(KEY_ENTER)
	snapshot = menu.call("get_navigation_snapshot")
	var focus_owner := snapshot.get("focus_owner") as Control
	var map_panel := menu.get("_map_panel") as Control
	_check(
		bool(snapshot.get("map_visible", false)) and map_panel != null,
		"Enter activates the focused primary action and opens world creation"
	)
	_check(
		focus_owner != null
		and focus_owner.is_visible_in_tree()
		and map_panel.is_ancestor_of(focus_owner),
		"world creation receives a visible keyboard focus target"
	)

	await _press_key(KEY_ESCAPE)
	for _frame in 2:
		await process_frame
	snapshot = menu.call("get_navigation_snapshot")
	_check(
		bool(snapshot.get("main_visible", false))
		and not bool(snapshot.get("map_visible", true)),
		"Escape returns from a cancellable subpage without closing the application"
	)
	_check(
		str(snapshot.get("focus_text", "")) == "继续游戏",
		"returning to the command deck restores the primary focus target"
	)

	var previous_focus := snapshot.get("focus_owner") as Control
	await _press_key(KEY_TAB)
	var next_focus := root.gui_get_focus_owner() as Control
	_check(
		next_focus != null
		and next_focus != previous_focus
		and menu.is_ancestor_of(next_focus),
		"Tab advances focus through the bounded main-menu command set"
	)

	menu.queue_free()
	for _frame in 6:
		await process_frame
	if failures.is_empty():
		print("QA MENU KEYBOARD NAVIGATION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MENU KEYBOARD NAVIGATION FAILURE: %s" % failure)
		print(
			"QA MENU KEYBOARD NAVIGATION FAIL | checks=%d | failures=%d"
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
	for _frame in 2:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
