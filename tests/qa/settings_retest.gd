extends SceneTree

const ServiceHubScene := preload("res://scenes/ui/service_hub.tscn")
const PlayerScene := preload("res://scenes/game/player.tscn")
const WorldScript := preload("res://src/world/voxel_world.gd")
const SettingsPolicy := preload("res://src/settings/game_settings_policy.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var original: Dictionary = hub.current_settings.duplicate(true)
	var player = PlayerScene.instantiate()
	var world = WorldScript.new()
	root.add_child(player)
	root.add_child(world)
	hub.attach_game(world, player)
	var requested := {
		"mouse_sensitivity": 0.42,
		"render_distance": 5,
		"master_volume": 0.37,
		"fullscreen": false,
		"cycle_minutes": 13,
		# Direct signal callers are normalized to the nearest allowed interval.
		"autosave_minutes": 9,
		"show_tutorial": false,
		"show_interaction_prompts": true,
	}
	hub.main_menu.settings_changed.emit(requested)
	_expect(is_equal_approx(player.mouse_sensitivity, 0.0042), "live actual player sensitivity")
	_expect(world.render_distance == 5, "live actual world render distance")
	_expect(is_equal_approx(hub.day_night.cycle_duration_seconds, 780.0), "live day/night duration")
	_expect(
		int(hub.current_settings.get("autosave_minutes", -1)) == 10,
		"production settings policy normalizes autosave to an allowed interval"
	)
	var autosave: Node = hub.get("autosave_runtime_participant") as Node
	var autosave_snapshot: Dictionary = autosave.call("get_snapshot") if autosave != null else {}
	_expect(
		autosave != null
		and bool(autosave_snapshot.get("enabled", false))
		and is_equal_approx(float(autosave_snapshot.get("interval_minutes", 0.0)), 10.0),
		"live autosave runtime receives the normalized interval"
	)
	var persisted: Dictionary = hub.save_service.load_settings({})
	_expect(is_equal_approx(float(persisted.get("mouse_sensitivity", 0.0)), 0.42), "sensitivity persisted")
	_expect(int(persisted.get("render_distance", 0)) == 5, "render distance persisted")
	_expect(int(persisted.get("cycle_minutes", 0)) == 13, "cycle duration persisted")
	_expect(int(persisted.get("autosave_minutes", -1)) == 10, "autosave interval persisted")
	_expect(
		persisted.keys().all(func(key: Variant) -> bool: return key in SettingsPolicy.DEFAULTS),
		"persisted settings retain only the canonical whitelist"
	)

	var reloaded_hub = ServiceHubScene.instantiate()
	root.add_child(reloaded_hub)
	await process_frame
	await process_frame
	var reloaded_player = PlayerScene.instantiate()
	var reloaded_world = WorldScript.new()
	root.add_child(reloaded_player)
	root.add_child(reloaded_world)
	reloaded_hub.attach_game(reloaded_world, reloaded_player)
	_expect(is_equal_approx(reloaded_player.mouse_sensitivity, 0.0042), "reloaded actual player sensitivity")
	_expect(reloaded_world.render_distance == 5, "reloaded actual world render distance")
	_expect(is_equal_approx(reloaded_hub.day_night.cycle_duration_seconds, 780.0), "reloaded day/night duration")
	var reloaded_autosave: Node = reloaded_hub.get("autosave_runtime_participant") as Node
	var reloaded_snapshot: Dictionary = (
		reloaded_autosave.call("get_snapshot") if reloaded_autosave != null else {}
	)
	_expect(
		is_equal_approx(float(reloaded_snapshot.get("interval_minutes", 0.0)), 10.0),
		"reloaded autosave runtime uses the persisted interval"
	)

	hub.main_menu.settings_changed.emit({"autosave_minutes": 0})
	autosave_snapshot = autosave.call("get_snapshot") if autosave != null else {}
	_expect(
		not bool(autosave_snapshot.get("enabled", true)),
		"zero-minute setting disables autosave without removing manual save"
	)
	hub.main_menu.settings_changed.emit(original)
	for node in [reloaded_hub, reloaded_player, reloaded_world, hub, player, world]:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame
	if failures.is_empty():
		print("QA SETTINGS RETEST PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA SETTINGS RETEST FAILURE: %s" % failure)
		print("QA SETTINGS RETEST FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
