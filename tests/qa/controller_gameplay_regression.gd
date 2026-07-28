extends SceneTree

const ProfileScript = preload("res://src/input/gameplay_controller_profile.gd")
const Actions = preload("res://src/input/gameplay_input_actions.gd")
const InputServiceScript = preload("res://src/input/gameplay_input_service.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_contract()
	_test_invalid_profile_rejection()
	_test_input_map_contract()
	await _test_input_service()
	await _test_production_player_composition()
	_release_actions()
	if failures.is_empty():
		print("QA CONTROLLER GAMEPLAY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA CONTROLLER GAMEPLAY FAILURE: %s" % failure)
	print("QA CONTROLLER GAMEPLAY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_profile_contract() -> void:
	var profile = ProfileScript.new()
	var snapshot: Dictionary = profile.get_snapshot()
	_check(profile.get_validation_errors().is_empty(), "production controller profile has no validation errors")
	_check(bool(snapshot.get("loaded_from_file", false)), "production controller profile is loaded from data")
	_check(int(snapshot.get("schema_version", 0)) == 1, "controller schema version remains stable")
	_check(int(snapshot.get("binding_count", 0)) == 21, "controller profile owns exactly twenty-one logical bindings")
	_check(int(snapshot.get("binding_budget", 0)) == 32, "controller binding budget remains bounded at thirty-two")
	_check(is_equal_approx(float(snapshot.get("movement_deadzone", 0.0)), 0.22), "movement deadzone is explicit")
	_check(is_equal_approx(float(snapshot.get("look_deadzone", 0.0)), 0.18), "look deadzone is explicit")
	_check(profile.apply_look_curve(Vector2(0.1, 0.0)) == Vector2.ZERO, "small right-stick drift is rejected")
	var shaped := profile.apply_look_curve(Vector2(0.8, 0.0))
	_check(shaped.x > 0.5 and shaped.x < 1.0, "right-stick response curve is bounded and progressive")
	var actions: Dictionary = {}
	var physical: Dictionary = {}
	for binding: Dictionary in profile.get_bindings():
		var action := str(binding.get("action", ""))
		actions[action] = int(actions.get(action, 0)) + 1
		var key := _physical_key(binding)
		physical[key] = int(physical.get(key, 0)) + 1
	_check(actions.size() == 21, "every controller command has one logical action owner")
	_check(physical.size() == 21, "every controller command has one unique physical control")
	for action_count: Variant in actions.values():
		_check(int(action_count) == 1, "controller actions cannot have duplicate profile entries")
	for physical_count: Variant in physical.values():
		_check(int(physical_count) == 1, "controller physical controls cannot conflict")


func _test_invalid_profile_rejection() -> void:
	var path := "user://invalid-controller-profile.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "invalid controller fixture opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"profile_id": "bad",
		"name": "bad",
		"bindings": [
			{"action":"jump", "kind":"button", "button":0},
			{"action":"sprint", "kind":"button", "button":0},
		],
	}))
	file.close()
	var profile = ProfileScript.new()
	_check(not profile.load_from_file(path), "conflicting and incomplete controller data is rejected")
	_check(not profile.get_validation_errors().is_empty(), "invalid controller data exposes validation evidence")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_input_map_contract() -> void:
	var repaired := Actions.ensure_default_bindings()
	_check(Actions.has_required_bindings(), "keyboard and controller bindings are installed together")
	_check(repaired.size() <= 32, "binding repair result remains bounded")
	var profile = ProfileScript.new()
	for binding: Dictionary in profile.get_bindings():
		var action := StringName(binding.get("action", ""))
		_check(InputMap.has_action(action), "%s action exists" % action)
		_check(_has_binding(action, binding), "%s owns its production joypad binding" % action)
		_check(
			is_equal_approx(InputMap.action_get_deadzone(action), profile.deadzone_for_action(action)),
			"%s uses the profile deadzone" % action
		)


func _test_input_service() -> void:
	var service = InputServiceScript.new()
	root.add_child(service)
	await process_frame
	service.set_active(true)
	Input.action_press(Actions.MOVE_RIGHT, 0.8)
	Input.action_press(Actions.MOVE_FORWARD, 0.6)
	var movement: Vector2 = service.get_movement_vector()
	_check(movement.x > 0.5 and movement.y < -0.3, "left stick resolves through the authoritative movement vector")
	Input.action_release(Actions.MOVE_RIGHT)
	Input.action_release(Actions.MOVE_FORWARD)
	Input.action_press(Actions.LOOK_RIGHT, 0.8)
	Input.action_press(Actions.LOOK_DOWN, 0.65)
	var look: Vector2 = service.get_look_vector()
	_check(look.x > 0.0 and look.y > 0.0 and look.length() <= 1.0, "right stick resolves through the bounded response curve")
	Input.action_release(Actions.LOOK_RIGHT)
	Input.action_release(Actions.LOOK_DOWN)
	Input.action_press(Actions.PRIMARY_ACTION, 1.0)
	_check(service.is_primary_action_pressed(), "right trigger exposes a held primary action")
	Input.action_release(Actions.PRIMARY_ACTION)
	Input.action_press(Actions.SECONDARY_ACTION, 1.0)
	_check(service.is_secondary_action_just_pressed(), "left trigger exposes a just-pressed secondary action")
	Input.action_release(Actions.SECONDARY_ACTION)
	await process_frame
	Input.action_press(Actions.HOTBAR_NEXT)
	_check(service.get_hotbar_cycle_just_pressed() == 1, "D-Pad right cycles the hotbar forward")
	Input.action_release(Actions.HOTBAR_NEXT)
	await process_frame
	Input.action_press(Actions.HOTBAR_PREVIOUS)
	_check(service.get_hotbar_cycle_just_pressed() == -1, "D-Pad left cycles the hotbar backward")
	Input.action_release(Actions.HOTBAR_PREVIOUS)
	var status: Dictionary = service.get_binding_status()
	_check(bool(status.get("valid", false)), "input service reports the combined binding contract as valid")
	_check(int(status.get("controller_profile", {}).get("binding_count", 0)) == 21, "input diagnostics expose the bounded controller profile")
	service.set_active(false)
	_check(service.get_movement_vector() == Vector2.ZERO and service.get_look_vector() == Vector2.ZERO, "inactive gameplay releases continuous controller state")
	service.queue_free()
	await process_frame


func _test_production_player_composition() -> void:
	var service = InputServiceScript.new()
	root.add_child(service)
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.bind_input_service(service)
	service.set_active(true)
	player.set_input_enabled(true)
	var yaw_before: float = float(player.rotation.y)
	Input.action_press(Actions.LOOK_RIGHT, 0.9)
	player.call("_process", 0.25)
	Input.action_release(Actions.LOOK_RIGHT)
	var snapshot: Dictionary = player.call("get_controller_gameplay_snapshot")
	_check(player.rotation.y < yaw_before, "production player applies right-stick yaw")
	_check(int(snapshot.get("look_frame_count", 0)) == 1, "production player exposes exact controller look evidence")
	Input.action_press(Actions.PRIMARY_ACTION, 1.0)
	player.call("_process", 0.016)
	Input.action_release(Actions.PRIMARY_ACTION)
	player.call("_process", 0.016)
	snapshot = player.call("get_controller_gameplay_snapshot")
	_check(int(snapshot.get("primary_press_count", 0)) == 1, "production player reuses the primary-action press path")
	_check(int(snapshot.get("primary_release_count", 0)) == 1, "production player releases the shared harvest hold exactly once")
	Input.action_press(Actions.SECONDARY_ACTION, 1.0)
	player.call("_process", 0.016)
	Input.action_release(Actions.SECONDARY_ACTION)
	await process_frame
	snapshot = player.call("get_controller_gameplay_snapshot")
	_check(int(snapshot.get("secondary_count", 0)) == 1, "production player routes secondary action through interact/use")
	var hotbar_before := int(snapshot.get("selected_hotbar_index", 0))
	Input.action_press(Actions.HOTBAR_NEXT)
	player.call("_process", 0.016)
	Input.action_release(Actions.HOTBAR_NEXT)
	await process_frame
	snapshot = player.call("get_controller_gameplay_snapshot")
	_check(int(snapshot.get("selected_hotbar_index", 0)) == posmod(hotbar_before + 1, 9), "production player cycles the existing hotbar selection")
	_check(int(snapshot.get("hotbar_cycle_count", 0)) == 1, "production player records one bounded hotbar command")
	player.set_input_enabled(false)
	service.set_active(false)
	player.queue_free()
	service.queue_free()
	for _frame in 6:
		await process_frame


func _has_binding(action: StringName, binding: Dictionary) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if str(binding.get("kind", "")) == "button" and event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).button_index == int(binding.get("button", -1)):
				return true
		if str(binding.get("kind", "")) == "axis" and event is InputEventJoypadMotion:
			var axis_event := event as InputEventJoypadMotion
			if axis_event.axis == int(binding.get("axis", -1)) and is_equal_approx(axis_event.axis_value, float(binding.get("value", 0.0))):
				return true
	return false


func _physical_key(binding: Dictionary) -> String:
	if str(binding.get("kind", "")) == "button":
		return "button:%d" % int(binding.get("button", -1))
	return "axis:%d:%d" % [int(binding.get("axis", -1)), int(signf(float(binding.get("value", 0.0))))]


func _release_actions() -> void:
	for action: StringName in [
		Actions.MOVE_RIGHT, Actions.MOVE_FORWARD, Actions.LOOK_RIGHT, Actions.LOOK_DOWN,
		Actions.PRIMARY_ACTION, Actions.SECONDARY_ACTION, Actions.HOTBAR_NEXT,
		Actions.HOTBAR_PREVIOUS,
	]:
		Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
