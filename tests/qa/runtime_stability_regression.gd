extends SceneTree

const WorldScript = preload("res://src/world/voxel_world.gd")
const SaveScript = preload("res://src/save/save_service.gd")
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")
const GameScene = preload("res://scenes/game/game.tscn")

var checks := 0
var failures: Array[String] = []
var _world_loaded_events := 0
var _recovery_source := ""
var _settings_saved_events := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_incremental_chunk_streaming()
	await _test_durable_save_recovery()
	await _test_pause_feedback_and_service_ownership()
	await _test_creature_population_culling()
	if failures.is_empty():
		print("QA RUNTIME STABILITY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA RUNTIME STABILITY FAILURE: %s" % failure)
		print("QA RUNTIME STABILITY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_incremental_chunk_streaming() -> void:
	var world = WorldScript.new()
	world.render_distance = 1
	world.unload_distance = 2
	world.chunk_build_cells_per_step = 1024
	world.max_chunk_build_steps_per_frame = 1
	root.add_child(world)
	world.start_world("star_continent", 424242, "qa-runtime-streaming", {})
	_check(world.get_loaded_chunk_count() == 1, "spawn chunk remains synchronously playable")
	_check(world.get_pending_chunk_count() == 8, "neighbor chunks enter a bounded streaming queue")
	world._process(0.016)
	_check(
		world.get_loaded_chunk_count() == 1 and world.get_building_chunk_count() == 1,
		"one frame starts incremental work without synchronously finishing a full chunk",
	)
	for _frame in 96:
		world._process(0.016)
		if world.get_loaded_chunk_count() >= 3:
			break
	_check(
		world.get_loaded_chunk_count() >= 2, "incremental streaming eventually publishes a neighbor"
	)
	var loaded_coords: Array = world.get_loaded_chunk_coords()
	if loaded_coords.size() >= 2:
		var first_chunk: Node = world.chunks[Vector2i(loaded_coords[0])]
		var second_chunk: Node = world.chunks[Vector2i(loaded_coords[1])]
		var first_mesh: Mesh = first_chunk.get_node("Mesh").mesh
		var second_mesh: Mesh = second_chunk.get_node("Mesh").mesh
		var first_material: Material = first_mesh.surface_get_material(0)
		var second_material: Material = second_mesh.surface_get_material(0)
		_check(
			first_material == second_material,
			"voxel chunks share one material resource instead of allocating per rebuild",
		)
	else:
		_check(false, "two chunks are available for shared material verification")
	var original_center := Vector2i(loaded_coords[0])
	world.set_focus(Vector3((original_center.x + 8) * 16, 40.0, original_center.y * 16))
	_check(
		not world.chunks.has(original_center), "moving far away immediately detaches stale chunks"
	)
	world.queue_free()
	await process_frame


func _test_durable_save_recovery() -> void:
	var save = SaveScript.new()
	root.add_child(save)
	await process_frame
	var state: Dictionary = save.create_world(
		"qa-runtime-save-%d" % Time.get_ticks_msec(), "star_continent", 12345
	)
	_check(not state.is_empty(), "runtime recovery test creates a world")
	if state.is_empty():
		save.queue_free()
		return
	var world_id := str(state.get("metadata", {}).get("id", ""))
	state["metadata"]["name"] = "previous-valid"
	_check(save.save_world(world_id, state), "first replacement save succeeds")
	state["metadata"]["name"] = "latest-primary"
	_check(save.save_world(world_id, state), "second replacement keeps a previous backup")
	_world_loaded_events = 0
	save.world_loaded.connect(_on_world_loaded)
	save.list_worlds()
	_check(_world_loaded_events == 0, "listing saves has no world-loaded side effects")
	var primary_path := "user://worlds/%s/world.json" % world_id
	var file := FileAccess.open(primary_path, FileAccess.WRITE)
	if file != null:
		file.store_string("{broken-json")
		file.close()
	_recovery_source = ""
	save.save_recovered.connect(_on_save_recovered)
	var recovered: Dictionary = save.load_world(world_id)
	_check(
		str(recovered.get("metadata", {}).get("name", "")) == "previous-valid",
		"a corrupt primary save falls back to the previous valid snapshot",
	)
	_check(_recovery_source == "backup", "save recovery reports the backup source")
	_check(save.delete_world(world_id), "recovery test world is cleaned up")
	save.queue_free()
	await process_frame


func _test_pause_feedback_and_service_ownership() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var hub: Node = game.service_hub
	_check(
		hub.main_menu.get_node_or_null("LocalSaveService") == null,
		"integrated main menu reuses the shared save service without a duplicate fallback",
	)
	var state: Dictionary = hub.save_service.create_world(
		"qa-runtime-session-%d" % Time.get_ticks_msec(), "star_continent", 98765
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	_check(hub.creature_spawner.active, "creature simulation activates only after world attachment")
	hub.game_ui.toggle_pause()
	_check(
		paused and hub.simulation_pause.is_paused(),
		"pause overlay pauses the actual simulation tree"
	)
	var save_button := _find_button(hub.game_ui, "保存世界")
	_check(save_button != null, "pause overlay exposes the save action")
	if save_button != null:
		save_button.pressed.emit()
	_check(
		str(hub.game_ui.get("_pause_status").text) == "世界已保存",
		"save feedback is based on the real persistence result",
	)
	hub.game_ui.close_overlay()
	_check(
		not paused and not hub.simulation_pause.is_paused(), "resuming clears the simulation pause"
	)
	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	_settings_saved_events = 0
	hub.save_service.settings_saved.connect(_on_settings_saved)
	(
		hub
		. main_menu
		. settings_changed
		. emit(
			{
				"mouse_sensitivity": 0.21,
				"render_distance": 2,
				"master_volume": 0.7,
				"fullscreen": false,
				"cycle_minutes": 9,
			}
		)
	)
	_check(
		_settings_saved_events == 1, "one settings action performs exactly one persistence write"
	)
	hub.main_menu.settings_changed.emit(original_settings)
	hub.return_to_menu()
	_check(
		hub.main_menu.visible and not game.world_root.visible,
		"successful save-and-return restores a clean menu state",
	)
	_check(hub.save_service.delete_world(world_id), "runtime session test world is cleaned up")
	hub.simulation_pause.reset()
	hub.audio_service.stop_ambient()
	game.queue_free()
	await process_frame
	await process_frame


func _test_creature_population_culling() -> void:
	var player := Node3D.new()
	var spawner = SpawnerScript.new()
	root.add_child(player)
	root.add_child(spawner)
	await process_frame
	spawner.despawn_radius = 10.0
	spawner.setup(player)
	var near_creature = spawner.spawn_creature("chicken", Vector3(4.0, 2.0, 0.0))
	var far_creature = spawner.spawn_creature("cow", Vector3(40.0, 2.0, 0.0))
	_check(
		near_creature != null and far_creature != null,
		"population test spawns near and far creatures"
	)
	var removed: int = spawner.maintain_population()
	_check(removed == 1, "population maintenance removes only out-of-range creatures")
	_check(
		near_creature.get_parent() == spawner and far_creature.get_parent() == null,
		"nearby creatures remain active while distant AI is detached",
	)
	spawner.clear_creatures()
	spawner.queue_free()
	player.queue_free()
	await process_frame


func _on_world_loaded(_world_id: String, _state: Dictionary) -> void:
	_world_loaded_events += 1


func _on_save_recovered(_world_id: String, source: String) -> void:
	_recovery_source = source


func _on_settings_saved() -> void:
	_settings_saved_events += 1


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == label:
			return child
		var nested := _find_button(child, label)
		if nested != null:
			return nested
	return null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
