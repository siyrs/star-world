extends SceneTree

const PlayerScene := preload("res://scenes/game/player.tscn")
const GameScene := preload("res://scenes/game/game.tscn")
const InventoryScript := preload("res://src/inventory/inventory_service.gd")
const SurvivalScript := preload("res://src/survival/survival_service.gd")
const CowScript := preload("res://src/entity/cow.gd")
const ItemPickupScript := preload("res://src/entity/item_pickup.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_live_player_interactions()
	await _test_audio_settings_and_world_lifecycle()
	if failures.is_empty():
		print("DEV-D GAMEPLAY INTEGRATION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("DEV-D TEST FAILURE: %s" % failure)
		print("DEV-D GAMEPLAY INTEGRATION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_live_player_interactions() -> void:
	var stage := Node3D.new()
	stage.name = "LiveInteractionStage"
	root.add_child(stage)
	var world := InteractionWorldStub.new()
	stage.add_child(world)
	var inventory = InventoryScript.new()
	var survival = SurvivalScript.new()
	stage.add_child(inventory)
	stage.add_child(survival)
	var player = PlayerScene.instantiate()
	stage.add_child(player)
	player.set_physics_process(false)
	player.bind_world(world)
	player.bind_inventory(inventory)
	player.bind_survival(survival)
	inventory.add_item("diamond_sword", 1)
	_check(is_equal_approx(float(player.call("_get_selected_attack_damage")), 7.0), "selected weapon uses registry damage")

	var cow = CowScript.new()
	cow.position = Vector3(0.0, 0.5, -3.0)
	stage.add_child(cow)
	cow.set_physics_process(false)
	var deaths: Array = []
	cow.died.connect(func(species_id, drops, world_position): deaths.append({"species":species_id, "drops":drops, "position":world_position}))
	await physics_frame
	await physics_frame
	player.interaction_ray.force_raycast_update()
	_check(player.interaction_ray.get_collider() == cow, "real interaction ray targets creature collider")
	var saturation_before: float = survival.saturation
	_check(player.break_target_block(), "first live attack is handled")
	_check(is_equal_approx(cow.health, 3.0), "first attack applies diamond sword damage")
	_check(player.break_target_block(), "second live attack is handled")
	_check(world.remove_calls == 0, "creature collider takes priority over block removal")
	_check(is_equal_approx(survival.saturation, saturation_before - 0.2), "attacks report survival exhaustion")
	_check(deaths.size() == 1 and deaths[0]["species"] == "cow", "fatal attack emits observable creature death")
	_check(int(deaths[0].get("drops", {}).get("raw_beef", 0)) >= 1, "fatal attack rolls guaranteed cow drop")
	var pickup_observed := false
	for child in stage.get_children():
		if child.get_script() == ItemPickupScript and str(child.get("item_id")) == "raw_beef":
			pickup_observed = true
	_check(pickup_observed, "fatal attack spawns an observable item pickup")

	inventory.clear()
	inventory.add_item("apple", 1)
	survival.hunger = 10.0
	survival.saturation = 0.0
	_check(player.place_selected_block(), "right click path consumes selected non-block food")
	_check(inventory.count_item("apple") == 0, "food use consumes exactly one inventory item")
	_check(is_equal_approx(survival.hunger, 14.0), "food use restores registry hunger points")

	await create_timer(0.35).timeout
	inventory.clear()
	inventory.add_item("dirt", 1)
	_check(is_equal_approx(float(player.call("_get_selected_attack_damage")), 1.0), "non-weapon selected item uses base attack damage")
	_add_target_wall(stage)
	await physics_frame
	await physics_frame
	_check(player.place_selected_block(), "last selected block can be placed")
	_check(inventory.count_item("dirt") == 0 and world.set_calls == 1, "placing last block consumes it and writes once")
	_check(player.get_selected_block_id() == "air", "bound empty inventory slot resolves to air")
	_check(not player.place_selected_block() and world.set_calls == 1, "empty selected slot cannot create an infinite fallback block")
	stage.queue_free()
	await process_frame


func _test_audio_settings_and_world_lifecycle() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var first_world_id := "developer-d-live-%d" % Time.get_ticks_msec()
	var state := {
		"metadata":{"id":first_world_id, "name":"Developer D", "map_id":"star_continent", "seed":443322},
		"inventory":{}, "world":{"block_overrides":{}},
		"survival":{"health":20.0, "hunger":20.0, "saturation":5.0},
		"day_night":{"time_of_day":10.0, "day":1}
	}
	game.begin_world_state(state)
	await process_frame
	var hub = game.service_hub
	var world = game.world
	var player = game.player
	var audio_events: Array[String] = []
	hub.audio_service.sound_played.connect(func(event_name): audio_events.append(str(event_name)))
	_check(world.is_started and world.get_loaded_chunk_count() > 0, "real world is active before lifecycle test")
	_check(hub.creature_spawner.active, "attach_game activates creature spawning")

	var target: Vector3i = world.world_to_block(world.get_spawn_position()) + Vector3i(2, 1, 0)
	while target.y < 63 and world.get_block(target) != "air":
		target.y += 1
	_check(world.set_block(target, "planks"), "real world placement succeeds for audio source")
	player.block_placed.emit(target, "planks")
	_check(audio_events.count("place") == 1, "world placement audio fires exactly once despite player signal")
	_check(world.remove_block(target) == "planks", "real world removal succeeds for audio source")
	player.block_broken.emit(target, "planks")
	_check(audio_events.count("break_soft") == 1, "world break audio fires exactly once despite player signal")

	var health_before: float = hub.survival.health
	player.take_damage(3.0, "focused_test")
	player.take_damage(0.0, "ignored")
	_check(is_equal_approx(hub.survival.health, health_before - 3.0), "player forwards valid damage to survival")
	_check(audio_events.count("hurt") == 1, "player valid damage emits one hurt audio event")

	var creature = hub.creature_spawner.spawn_creature("cow", player.global_position + Vector3(0.0, 2.0, -4.0))
	_check(creature != null, "active spawner creates a creature")
	if creature != null:
		creature.set_physics_process(false)
		creature.take_damage(1.0, player)
	_check(audio_events.count("creature_cow") == 1, "spawned creature damage is bridged to audio exactly once")

	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	var clamped_settings := original_settings.duplicate(true)
	clamped_settings["render_distance"] = 99
	clamped_settings["fullscreen"] = false
	hub.main_menu.settings_changed.emit(clamped_settings)
	_check(int(hub.current_settings.render_distance) == 5 and world.render_distance == 5, "hub clamps render distance to supported maximum")
	_check(world.unload_distance == 6, "world unload distance remains one chunk beyond render distance")
	var settings_panel = hub.main_menu.get("_settings_panel")
	var distance_options: OptionButton = settings_panel.get("_render_distance")
	var has_unsupported_six := false
	for index in distance_options.item_count:
		has_unsupported_six = has_unsupported_six or distance_options.get_item_id(index) == 6
	_check(not has_unsupported_six, "settings UI omits unsupported render distance 6")
	hub.main_menu.settings_changed.emit(original_settings)

	_check(hub.creature_spawner.get_child_count() > 0, "spawned creature exists before returning to menu")
	hub.return_to_menu()
	_check(not hub.creature_spawner.active and hub.creature_spawner.get_child_count() == 0, "return to menu deactivates and clears creatures")
	_check(hub.creature_spawner.spawn_creature("cow", Vector3.ZERO) == null, "inactive spawner rejects manual and timed spawning")
	_check(not world.is_started and world.get_loaded_chunk_count() == 0 and world.pending_chunks.is_empty(), "return to menu clears world chunks and streaming state")
	_check(not player.visible and not game.world_root.visible, "return to menu hides live gameplay nodes")

	var second_world_id := "%s-restart" % first_world_id
	state["metadata"]["id"] = second_world_id
	game.begin_world_state(state)
	await process_frame
	_check(world.is_started and world.get_loaded_chunk_count() > 0, "new world restarts world generation after cleanup")
	_check(hub.creature_spawner.active, "new world attach reactivates creature spawning")
	hub.return_to_menu()
	hub.save_service.delete_world(first_world_id)
	hub.save_service.delete_world(second_world_id)
	game.queue_free()
	await process_frame
	await process_frame


func _add_target_wall(parent: Node3D) -> void:
	var wall := StaticBody3D.new()
	wall.name = "PlacementTarget"
	wall.position = Vector3(0.0, 1.5, -3.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 3.0, 0.5)
	collision.shape = shape
	wall.add_child(collision)
	parent.add_child(wall)


func _check(condition: bool, failure_message: String) -> void:
	checks += 1
	if not condition:
		failures.append(failure_message)


class InteractionWorldStub extends Node3D:
	var remove_calls := 0
	var set_calls := 0

	func get_spawn_position() -> Vector3:
		return Vector3.ZERO

	func world_to_block(_position: Vector3) -> Vector3i:
		return Vector3i(0, 1, -2)

	func remove_block(_position: Vector3i) -> String:
		remove_calls += 1
		return "stone"

	func set_block(_position: Vector3i, _block_id: String) -> bool:
		set_calls += 1
		return true

	func get_block(_position: Vector3i) -> String:
		return "air"
