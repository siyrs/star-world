extends SceneTree

const ServiceHubScene := preload("res://scenes/ui/service_hub.tscn")
const PlayerScene := preload("res://scenes/game/player.tscn")
const WorldScript := preload("res://src/world/voxel_world.gd")

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
		"cycle_minutes": 13
	}
	hub.main_menu.settings_changed.emit(requested)
	_expect(is_equal_approx(player.mouse_sensitivity, 0.0042), "live actual player sensitivity")
	_expect(world.render_distance == 5, "live actual world render distance")
	_expect(is_equal_approx(hub.day_night.cycle_duration_seconds, 780.0), "live day/night duration")
	var persisted: Dictionary = hub.save_service.load_settings({})
	_expect(is_equal_approx(float(persisted.get("mouse_sensitivity", 0.0)), 0.42), "sensitivity persisted")
	_expect(int(persisted.get("render_distance", 0)) == 5, "render distance persisted")
	_expect(int(persisted.get("cycle_minutes", 0)) == 13, "cycle duration persisted")

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
