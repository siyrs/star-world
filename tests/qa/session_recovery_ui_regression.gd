extends SceneTree

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const GameUiScene = preload("res://scenes/ui/game_ui.tscn")
const CLEANUP_FRAMES := 12

var checks := 0
var failures: Array[String] = []


class FakeRecoveryService:
	extends Node
	signal candidate_changed(candidate: Dictionary)

	var candidate := {
		"schema_version":1,
		"world_id":"ui-recovery-world",
		"world_name":"Compact Recovery World",
		"map_id":"frozen_wastes",
		"state":"active",
		"started_at_unix":1,
		"updated_at_unix":2,
		"last_checkpoint_at_unix":2,
		"checkpoint_count":7,
	}

	func get_recovery_candidate() -> Dictionary:
		return candidate.duplicate(true)

	func dismiss_candidate() -> bool:
		candidate = {}
		candidate_changed.emit({})
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))

	var menu = MainMenuScene.instantiate()
	root.add_child(menu)
	var recovery := FakeRecoveryService.new()
	root.add_child(recovery)
	for _frame in 5:
		await process_frame
	menu.call("setup_session_recovery", recovery)
	menu.call("show_main")
	for _frame in 5:
		await process_frame
	var menu_snapshot: Dictionary = menu.call("get_visual_snapshot")
	var recovery_snapshot: Dictionary = menu_snapshot.get("session_recovery", {})
	_check(
		bool(recovery_snapshot.get("visible", false))
		and str(recovery_snapshot.get("candidate", {}).get("world_id", ""))
		== "ui-recovery-world",
		"compact main menu presents the strict recovery candidate"
	)
	_check(
		_rect_inside(viewport_rect, menu_snapshot.get("command_panel", Rect2()))
		and _rect_inside(viewport_rect, recovery_snapshot.get("card_rect", Rect2()))
		and _rect_inside(
			viewport_rect, recovery_snapshot.get("recover_button_rect", Rect2())
		),
		"recovery command deck remains inside the 1024x576 viewport"
	)
	_check(
		int(menu_snapshot.get("button_count", 0)) == 6
		and int(recovery_snapshot.get("visible_regular_command_count", 0)) == 5
		and not bool(recovery_snapshot.get("regular_primary_visible", true)),
		"recovery replaces only the duplicate generic primary CTA without changing the bounded command contract"
	)
	var focus_owner := root.gui_get_focus_owner()
	_check(
		focus_owner is Button
		and focus_owner.name == "RecoverLastSessionButton",
		"keyboard and controller focus prioritizes recovery while the card is active"
	)
	recovery.dismiss_candidate()
	for _frame in 4:
		await process_frame
	menu_snapshot = menu.call("get_visual_snapshot")
	recovery_snapshot = menu_snapshot.get("session_recovery", {})
	_check(
		not bool(recovery_snapshot.get("visible", true))
		and bool(recovery_snapshot.get("regular_primary_visible", false))
		and int(recovery_snapshot.get("visible_regular_command_count", 0)) == 6,
		"dismissing recovery restores the normal six-command menu"
	)

	var game_ui = GameUiScene.instantiate()
	root.add_child(game_ui)
	for _frame in 4:
		await process_frame
	game_ui.call("begin_gameplay")
	game_ui.call("toggle_pause")
	await process_frame
	var game_snapshot: Dictionary = game_ui.call("get_visual_snapshot")
	var safe_quit: Dictionary = game_snapshot.get("safe_quit", {})
	_check(
		bool(safe_quit.get("available", false))
		and str(safe_quit.get("text", "")) == "保存并退出游戏",
		"compact pause overlay exposes one explicit safe desktop exit command"
	)
	_check(
		_rect_inside(viewport_rect, game_snapshot.get("pause_rect", Rect2()))
		and _rect_inside(viewport_rect, safe_quit.get("rect", Rect2())),
		"safe desktop exit remains inside the 1024x576 pause viewport"
	)
	var safe_button := _find_button(game_ui, "保存并退出游戏")
	_check(
		safe_button != null and safe_button.theme_type_variation == "DangerButton",
		"safe desktop exit uses the shared destructive-action hierarchy"
	)

	game_ui.call("end_gameplay")
	menu.queue_free()
	game_ui.queue_free()
	recovery.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA SESSION RECOVERY UI PASS | checks=%d | viewport=1024x576" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SESSION RECOVERY UI FAILURE: %s" % failure)
		print(
			"QA SESSION RECOVERY UI FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var result := _find_button(child, text)
		if result != null:
			return result
	return null


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x - 0.5
		and candidate.position.y >= container_rect.position.y - 0.5
		and candidate.end.x <= container_rect.end.x + 0.5
		and candidate.end.y <= container_rect.end.y + 0.5
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
