extends SceneTree

const FeedbackScript = preload("res://src/experience/gameplay_feedback_service.gd")
const OnboardingScript = preload("res://src/experience/onboarding_service.gd")
const PromptResolverScript = preload("res://src/experience/interaction_prompt_resolver.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const Actions = preload("res://src/input/gameplay_input_actions.gd")
const GameScene = preload("res://scenes/game/game.tscn")

var checks := 0
var failures: Array[String] = []


class FakeInteractionService:
	extends Node

	func get_interaction_hint(block_id: String) -> String:
		return "右键打开箱子" if block_id == "chest" else ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_feedback_queue()
	await _test_onboarding_state_machine()
	await _test_prompt_policy()
	await _test_integrated_player_experience()
	if failures.is_empty():
		print("QA PLAYER EXPERIENCE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA PLAYER EXPERIENCE FAILURE: %s" % failure)
		print(
			"QA PLAYER EXPERIENCE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_feedback_queue() -> void:
	var feedback = FeedbackScript.new()
	root.add_child(feedback)
	await process_frame
	feedback.publish("已采集石头", "success", 1.0, "mine:stone")
	_check(
		str(feedback.get_active_toast().get("text", "")) == "已采集石头",
		"feedback immediately activates the first toast",
	)
	feedback.publish("已采集石头 ×2", "success", 1.0, "mine:stone")
	_check(
		str(feedback.get_active_toast().get("text", "")) == "已采集石头 ×2"
		and feedback.get_queue_size() == 0,
		"duplicate feedback updates the active toast instead of spamming the queue",
	)
	feedback.publish("背包已打开", "info", 1.0, "inventory")
	_check(feedback.get_queue_size() == 1, "a distinct toast waits in the bounded queue")
	feedback.call("_process", 2.0)
	_check(
		str(feedback.get_active_toast().get("text", "")) == "背包已打开",
		"feedback advances to the next queued toast",
	)
	feedback.set_prompt(
		{
			"title": "箱子",
			"primary": "[鼠标左键] 采集",
			"secondary": "[鼠标右键] 打开箱子",
		}
	)
	_check(str(feedback.get_prompt().get("title", "")) == "箱子", "prompt state is normalized")
	feedback.clear()
	_check(
		feedback.get_active_toast().is_empty() and feedback.get_prompt().is_empty(),
		"feedback clear releases transient UI state",
	)
	feedback.queue_free()
	await process_frame


func _test_onboarding_state_machine() -> void:
	var onboarding = OnboardingScript.new()
	root.add_child(onboarding)
	await process_frame
	_check(
		str(onboarding.get_state().get("step", {}).get("id", "")) == "move",
		"onboarding starts with movement",
	)
	onboarding.report_action(&"look")
	_check(
		str(onboarding.get_state().get("step", {}).get("id", "")) == "move",
		"out-of-order progress does not skip the current explanation",
	)
	onboarding.report_action(&"move")
	_check(
		str(onboarding.get_state().get("step", {}).get("id", "")) == "mine",
		"remembered out-of-order progress advances when prerequisites finish",
	)
	onboarding.toggle_visibility()
	_check(not bool(onboarding.get_state().get("visible", true)), "F1 visibility state can hide guidance")
	onboarding.toggle_visibility()
	_check(bool(onboarding.get_state().get("visible", false)), "hidden guidance can be restored")
	var saved: Dictionary = onboarding.serialize()
	var restored = OnboardingScript.new()
	root.add_child(restored)
	await process_frame
	restored.deserialize(saved)
	_check(
		str(restored.get_state().get("step", {}).get("id", "")) == "mine",
		"onboarding progress survives serialization",
	)
	for action in [&"mine", &"place", &"inventory", &"crafting"]:
		restored.report_action(action)
	_check(restored.is_completed(), "the complete first-session path finishes the tutorial")
	onboarding.queue_free()
	restored.queue_free()
	await process_frame


func _test_prompt_policy() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var interaction := FakeInteractionService.new()
	host.add_child(inventory)
	host.add_child(interaction)
	await process_frame
	inventory.grant_starter_kit()
	var resolver = PromptResolverScript.new()
	inventory.select_slot(0)
	var chest_prompt: Dictionary = resolver.resolve(
		{
			"type": "block",
			"block_id": "chest",
			"display_name": "箱子",
			"collectible": true,
		},
		inventory,
		interaction
	)
	_check(
		"采集" in str(chest_prompt.get("primary", ""))
		and "打开箱子" in str(chest_prompt.get("secondary", "")),
		"interactive blocks explain both mining and use actions",
	)
	var placement_prompt: Dictionary = resolver.resolve({}, inventory, interaction)
	_check(
		"绿色预览格" in str(placement_prompt.get("secondary", ""))
		and str(placement_prompt.get("tone", "")) == "warning",
		"held building blocks require a visible placement preview when no target is focused",
	)
	inventory.select_slot(1)
	var food_prompt: Dictionary = resolver.resolve({}, inventory, interaction)
	_check(
		"食用" in str(food_prompt.get("secondary", "")),
		"held food explains its right-click action",
	)
	var entity_prompt: Dictionary = resolver.resolve(
		{
			"type": "entity",
			"display_name": "鸡",
			"health": 4.0,
			"max_health": 4.0,
		},
		inventory,
		interaction
	)
	_check(
		"攻击" in str(entity_prompt.get("primary", ""))
		and "4 / 4" in str(entity_prompt.get("subtitle", "")),
		"entity prompts expose combat intent and readable health",
	)
	host.queue_free()
	await process_frame


func _test_integrated_player_experience() -> void:
	Actions.ensure_default_bindings()
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var hub: Node = game.get("service_hub")
	var experience: Node = hub.get("player_experience")
	var game_ui: Node = hub.get("game_ui")
	var guidance: Node = game_ui.call("get_guidance_overlay")
	_check(experience != null, "service composition mounts the player experience coordinator")
	_check(guidance != null, "game UI mounts the guidance presentation component")
	_check(_all_controls_are_passthrough(guidance), "guidance UI cannot intercept gameplay mouse input")
	var world_state: Dictionary = hub.save_service.create_world(
		"qa-player-experience-%d" % Time.get_ticks_msec(), "star_continent", 557799
	)
	var world_id := str(world_state.get("metadata", {}).get("id", ""))
	game.call("begin_world_state", world_state)
	await process_frame
	await physics_frame
	await process_frame
	var status: Dictionary = experience.call("get_status")
	_check(
		bool(status.get("gameplay_active", false)) and bool(status.get("player_attached", false)),
		"world startup activates and attaches player experience",
	)
	_check(
		bool(status.get("onboarding", {}).get("visible", false)),
		"a new world shows the first-session guide",
	)
	await _press_key(KEY_F1)
	_check(
		bool(experience.call("get_status").get("onboarding", {}).get("dismissed", false)),
		"real F1 input hides the guide without changing gameplay state",
	)
	await _press_key(KEY_F1)
	_check(
		not bool(experience.call("get_status").get("onboarding", {}).get("dismissed", true)),
		"real F1 input restores the guide",
	)
	var player: Node = game.get("player")
	player.emit_signal("gameplay_action_reported", &"look", {})
	player.emit_signal("gameplay_action_reported", &"move", {})
	player.emit_signal(
		"interaction_focus_changed",
		{
			"type": "block",
			"block_id": "chest",
			"display_name": "箱子",
			"collectible": true,
		}
	)
	await process_frame
	_check(
		"打开箱子" in str(experience.call("get_status").get("prompt", {}).get("secondary", "")),
		"live focus changes produce contextual interaction guidance",
	)
	var settings: Dictionary = hub.current_settings.duplicate(true)
	settings["show_interaction_prompts"] = false
	hub.main_menu.settings_changed.emit(settings)
	_check(
		experience.call("get_status").get("prompt", {}).is_empty(),
		"interaction prompts respect the player preference",
	)
	settings["show_interaction_prompts"] = true
	hub.main_menu.settings_changed.emit(settings)
	player.emit_signal(
		"gameplay_action_reported",
		&"place_failed",
		{
			"reason": "player_overlap",
			"message": "你离得太近了；后退一步，看到绿色预览格后再按右键",
		}
	)
	await process_frame
	_check(
		"后退一步" in str(
			experience.call("get_feedback").call("get_active_toast").get("text", "")
		),
		"failed placement gives immediate recovery guidance instead of silently ignoring right click",
	)
	player.emit_signal("gameplay_action_reported", &"mine", {"block_id": "stone", "display_name": "石头"})
	player.emit_signal("gameplay_action_reported", &"place", {"block_id": "planks", "display_name": "木板"})
	game_ui.call("open_inventory")
	await process_frame
	game_ui.call("close_overlay")
	game_ui.call("open_crafting", "hand")
	await process_frame
	game_ui.call("close_overlay")
	_check(
		bool(experience.call("get_status").get("onboarding", {}).get("completed", false)),
		"integrated gameplay actions complete the onboarding journey",
	)
	_check(hub.call("save_current"), "experience state participates in the world save transaction")
	var reloaded: Dictionary = hub.save_service.load_world(world_id)
	_check(
		bool(
			reloaded
			. get("experience", {})
			. get("onboarding", {})
			. get("completed", false)
		),
		"completed onboarding is persisted in the world save",
	)
	hub.call("return_to_menu")
	await process_frame
	status = experience.call("get_status")
	_check(
		not bool(status.get("gameplay_active", true))
		and not bool(status.get("player_attached", true))
		and status.get("prompt", {}).is_empty(),
		"returning to the menu clears transient experience references",
	)
	_check(hub.save_service.delete_world(world_id), "player experience test world is cleaned up")
	var audio = hub.get("audio_service")
	if audio != null and audio.has_method("shutdown"):
		audio.call("shutdown")
	game.queue_free()
	await process_frame
	await process_frame


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


func _all_controls_are_passthrough(node: Node) -> bool:
	if node == null:
		return false
	if node is Control:
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE:
			return false
	for child in node.get_children():
		if not _all_controls_are_passthrough(child):
			return false
	return true


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
