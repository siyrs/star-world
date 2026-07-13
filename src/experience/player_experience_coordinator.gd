class_name PlayerExperienceCoordinator
extends Node

signal experience_ready

const FeedbackScript = preload("res://src/experience/gameplay_feedback_service.gd")
const OnboardingScript = preload("res://src/experience/onboarding_service.gd")
const PromptResolverScript = preload("res://src/experience/interaction_prompt_resolver.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const SERIAL_VERSION := 1

var feedback: Node
var onboarding: Node
var inventory: Node
var game_ui: Node
var interaction_service: Node
var player: Node
var prompts_enabled := true

var _prompt_resolver = PromptResolverScript.new()
var _current_focus: Dictionary = {}
var _gameplay_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	feedback = FeedbackScript.new()
	feedback.name = "Feedback"
	add_child(feedback)
	onboarding = OnboardingScript.new()
	onboarding.name = "Onboarding"
	add_child(onboarding)
	onboarding.tutorial_completed.connect(_on_tutorial_completed)
	experience_ready.emit()


func setup(p_inventory: Node, p_game_ui: Node, p_interaction_service: Node) -> void:
	_disconnect_static_dependencies()
	inventory = p_inventory
	game_ui = p_game_ui
	interaction_service = p_interaction_service
	if inventory != null and inventory.has_signal("selected_slot_changed"):
		inventory.connect("selected_slot_changed", Callable(self, "_on_selected_slot_changed"))
	if game_ui != null and game_ui.has_signal("overlay_changed"):
		game_ui.connect("overlay_changed", Callable(self, "_on_overlay_changed"))
	_refresh_prompt()


func attach_player(p_player: Node) -> void:
	if player == p_player:
		return
	_disconnect_player()
	player = p_player
	_current_focus.clear()
	if player != null and player.has_signal("interaction_focus_changed"):
		player.connect("interaction_focus_changed", Callable(self, "_on_interaction_focus_changed"))
	if player != null and player.has_signal("gameplay_action_reported"):
		player.connect("gameplay_action_reported", Callable(self, "_on_gameplay_action_reported"))
	_refresh_prompt()


func detach_player() -> void:
	_disconnect_player()
	player = null
	_current_focus.clear()
	if feedback != null:
		feedback.clear_prompt()


func prepare_world(state: Dictionary) -> void:
	_current_focus.clear()
	_gameplay_active = false
	if feedback != null:
		feedback.clear()
	if onboarding != null:
		var onboarding_state: Dictionary = state.get("onboarding", {})
		onboarding.deserialize(onboarding_state)


func begin_gameplay() -> void:
	_gameplay_active = true
	_refresh_prompt()
	if onboarding != null:
		onboarding.state_changed.emit(onboarding.get_state())


func end_gameplay() -> void:
	_gameplay_active = false
	_current_focus.clear()
	if feedback != null:
		feedback.clear()


func apply_settings(settings: Dictionary) -> void:
	prompts_enabled = bool(settings.get("show_interaction_prompts", true))
	if onboarding != null:
		onboarding.set_enabled(bool(settings.get("show_tutorial", true)))
	_refresh_prompt()


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"onboarding": onboarding.serialize() if onboarding != null else {},
	}


func publish_message(
	message: String, severity: String = "info", duration: float = 2.4, dedupe_key: String = ""
) -> void:
	if feedback != null:
		feedback.publish(message, severity, duration, dedupe_key)


func get_feedback() -> Node:
	return feedback


func get_onboarding() -> Node:
	return onboarding


func get_status() -> Dictionary:
	return {
		"gameplay_active": _gameplay_active,
		"prompts_enabled": prompts_enabled,
		"player_attached": is_instance_valid(player),
		"focus": _current_focus.duplicate(true),
		"onboarding": onboarding.get_state() if onboarding != null else {},
		"prompt": feedback.get_prompt() if feedback != null else {},
	}


func _on_interaction_focus_changed(focus: Dictionary) -> void:
	_current_focus = focus.duplicate(true)
	_refresh_prompt()


func _on_gameplay_action_reported(action: StringName, payload: Dictionary) -> void:
	if onboarding != null:
		onboarding.report_action(action)
	match str(action):
		"mine":
			_publish_block_action("已采集", payload, "success")
		"place":
			_publish_block_action("已放置", payload, "success")
		"eat":
			var item_name := str(payload.get("display_name", "食物"))
			publish_message("已食用 %s" % item_name, "success", 1.8, "eat:%s" % item_name)


func _on_selected_slot_changed(_index: int, _slot: Dictionary) -> void:
	_refresh_prompt()


func _on_overlay_changed(_overlay: int, context: StringName) -> void:
	if context == InputContextScript.CONTEXT_INVENTORY and onboarding != null:
		onboarding.report_action(&"inventory")
	elif context == InputContextScript.CONTEXT_CRAFTING and onboarding != null:
		onboarding.report_action(&"crafting")
	if context == InputContextScript.CONTEXT_GAMEPLAY:
		_refresh_prompt()
	elif feedback != null:
		feedback.clear_prompt()


func _on_tutorial_completed() -> void:
	publish_message(
		"基础引导完成，开始创造属于你的星世界吧！",
		"success",
		4.0,
		"tutorial_complete"
	)


func _refresh_prompt() -> void:
	if feedback == null:
		return
	if not _gameplay_active or not prompts_enabled:
		feedback.clear_prompt()
		return
	var prompt: Dictionary = _prompt_resolver.resolve(
		_current_focus, inventory, interaction_service
	)
	feedback.set_prompt(prompt)


func _publish_block_action(prefix: String, payload: Dictionary, severity: String) -> void:
	var block_id := str(payload.get("block_id", ""))
	var display_name := str(payload.get("display_name", ""))
	if display_name.is_empty() and not block_id.is_empty():
		display_name = str(BlockRegistryScript.get_definition(block_id).get("name", block_id))
	if display_name.is_empty():
		display_name = "方块"
	publish_message(
		"%s %s" % [prefix, display_name],
		severity,
		1.6,
		"%s:%s" % [prefix, block_id if not block_id.is_empty() else display_name]
	)


func _disconnect_player() -> void:
	if player == null:
		return
	var focus_callback := Callable(self, "_on_interaction_focus_changed")
	if player.has_signal("interaction_focus_changed") and player.is_connected(
		"interaction_focus_changed", focus_callback
	):
		player.disconnect("interaction_focus_changed", focus_callback)
	var action_callback := Callable(self, "_on_gameplay_action_reported")
	if player.has_signal("gameplay_action_reported") and player.is_connected(
		"gameplay_action_reported", action_callback
	):
		player.disconnect("gameplay_action_reported", action_callback)


func _disconnect_static_dependencies() -> void:
	if inventory != null:
		var inventory_callback := Callable(self, "_on_selected_slot_changed")
		if inventory.has_signal("selected_slot_changed") and inventory.is_connected(
			"selected_slot_changed", inventory_callback
		):
			inventory.disconnect("selected_slot_changed", inventory_callback)
	if game_ui != null:
		var overlay_callback := Callable(self, "_on_overlay_changed")
		if game_ui.has_signal("overlay_changed") and game_ui.is_connected(
			"overlay_changed", overlay_callback
		):
			game_ui.disconnect("overlay_changed", overlay_callback)
