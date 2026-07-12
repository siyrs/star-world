extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const WorldScript = preload("res://src/world/voxel_world.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")
const GameScene = preload("res://scenes/game/game.tscn")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_block_registry()
	_test_seeded_profiles()
	await _test_all_profile_world_boots()
	var world = _test_world_api_and_chunks()
	_test_player_contract(world)
	world.queue_free()
	await process_frame
	await _test_game_and_service_integration()
	_test_project_delivery_files()
	if failures.is_empty():
		print("DEV-C CORE SMOKE PASS | checks=%d | blocks=%d | profiles=5" % [checks, BlockRegistryScript.BLOCK_IDS.size()])
		quit(0)
	else:
		for failure in failures:
			push_error("DEV-C TEST FAILURE: %s" % failure)
		print("DEV-C CORE SMOKE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_block_registry() -> void:
	_check(BlockRegistryScript.BLOCK_IDS.size() >= 18, "block registry has at least 18 block types")
	for required_id in ["grass", "dirt", "stone", "sand", "snow", "wood", "leaves", "water", "lava", "planks", "stone_bricks", "glass", "stone_slab", "oak_stairs", "coal_ore", "iron_ore", "gold_ore", "diamond_ore"]:
		_check(BlockRegistryScript.has_block(required_id), "missing required block %s" % required_id)
	_check(BlockRegistryScript.is_solid("stone"), "stone must be solid")
	_check(not BlockRegistryScript.is_solid("water"), "water must not create collision")


func _test_seeded_profiles() -> void:
	var profiles := ["star_continent", "desert_ruins", "frozen_wastes", "sky_islands", "abyss_world"]
	var signatures: Dictionary = {}
	for profile_id in profiles:
		var first = GeneratorScript.new()
		var second = GeneratorScript.new()
		first.configure(profile_id, 24681357)
		second.configure(profile_id, 24681357)
		var signature: Array = []
		for sample in [Vector2i(-19, 7), Vector2i(0, 0), Vector2i(13, 29), Vector2i(41, -11)]:
			var first_height: int = first.get_surface_height(sample.x, sample.y)
			var second_height: int = second.get_surface_height(sample.x, sample.y)
			_check(first_height == second_height, "%s height generation is deterministic" % profile_id)
			signature.append([first_height, first.get_block(Vector3i(sample.x, maxi(1, first_height), sample.y))])
		var encoded := JSON.stringify(signature)
		_check(not signatures.has(encoded), "%s produces a distinct terrain signature" % profile_id)
		signatures[encoded] = profile_id
		var spawn: Vector3 = first.find_spawn_position()
		_check(spawn.y > 2.0 and spawn.y < 64.0, "%s has a safe bounded spawn" % profile_id)
		var camera_cell := Vector3i(floori(spawn.x), floori(spawn.y + 1.62), floori(spawn.z))
		_check(first.get_block(camera_cell) == BlockRegistryScript.AIR, "%s keeps the first-person camera outside solid or leaf blocks" % profile_id)


func _test_all_profile_world_boots() -> void:
	var world = WorldScript.new()
	world.render_distance = 1
	root.add_child(world)
	for profile_id in ["star_continent", "desert_ruins", "frozen_wastes", "sky_islands", "abyss_world"]:
		world.start_world(profile_id, 556677, "boot-%s" % profile_id, {})
		_check(world.get_loaded_chunk_count() == 1, "%s loads its spawn chunk" % profile_id)
		var coords: Array = world.get_loaded_chunk_coords()
		var coord := Vector2i(coords[0])
		var chunk: Node = world.chunks[coord]
		_check(int(chunk.get("surface_face_count")) > 0, "%s produces renderable terrain" % profile_id)
		_check(world.get_spawn_position().y > 2.0, "%s provides a playable spawn" % profile_id)
		await process_frame
	world.queue_free()
	await process_frame


func _test_world_api_and_chunks():
	var world = WorldScript.new()
	world.render_distance = 1
	world.unload_distance = 2
	root.add_child(world)
	world.start_world("star_continent", 112233, "developer-a-world", {})
	_check(world.is_started, "world starts")
	_check(world.get_loaded_chunk_count() == 1, "spawn chunk loads synchronously")
	var loaded_coords: Array = world.get_loaded_chunk_coords()
	var center_coord := Vector2i(loaded_coords[0])
	var center_chunk: Node = world.chunks[center_coord]
	_check(int(center_chunk.get("surface_face_count")) > 0, "chunk surface mesh contains visible faces")
	var collision: CollisionShape3D = center_chunk.get_node("Collision")
	_check(collision.shape != null, "chunk builds collision shape")
	var target := world.world_to_block(world.get_spawn_position()) + Vector3i(1, 0, 0)
	_check(world.get_block(target) == BlockRegistryScript.AIR, "spawn interaction target is air")
	_check(world.set_block(target, "planks"), "set_block adds a voxel")
	_check(world.get_block(target) == "planks", "get_block observes placed voxel")
	var saved_world: Dictionary = world.serialize_state()
	_check(saved_world.get("block_overrides", {}).has(world.block_key(target)), "placed voxel is serialized sparsely")
	var restored = WorldScript.new()
	restored.render_distance = 1
	root.add_child(restored)
	restored.start_world("star_continent", 112233, "developer-a-restored", {"world": saved_world})
	_check(restored.get_block(target) == "planks", "sparse override restores in a new world instance")
	_check(restored.remove_block(target) == "planks", "remove_block returns the collected block")
	_check(restored.get_block(target) == BlockRegistryScript.AIR, "removed block becomes air")
	restored.queue_free()
	world._process(0.5)
	_check(world.get_loaded_chunk_count() >= 2, "streaming loads queued neighboring chunks")
	world.set_focus(Vector3((center_coord.x + 8) * 16, 40.0, center_coord.y * 16))
	_check(not world.chunks.has(center_coord), "streaming unloads chunks outside unload distance")
	return world


func _test_player_contract(world) -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	player.bind_world(world)
	player.select_hotbar(3)
	_check(player.get_selected_block_id() == "planks", "1-9 hotbar selection maps to placeable blocks")
	_check(player.get_view_camera() is Camera3D, "first-person camera exists")
	_check(player.has_method("break_target_block") and player.has_method("place_selected_block"), "mining and placement APIs exist")
	player.queue_free()


func _test_game_and_service_integration() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	_check(game.name == "Game", "game scene root is Game")
	var hub: Node = game.get_node("GameplayServiceHub")
	_check(hub.get("inventory") is Node and hub.get("crafting") is Node and hub.get("save_service") is Node, "real inventory/crafting/save services are mounted")
	_check(hub.get("survival") is Node and hub.get("day_night") is Node and hub.get("audio_service") is Node, "real survival/day-night/audio services are mounted")
	_check(hub.get("creature_spawner") is Node, "creature spawner service is mounted")
	var state := {
		"metadata": {"id":"developer-a-smoke", "name":"Developer A Smoke", "map_id":"desert_ruins", "seed":998877},
		"inventory": {}, "world": {"block_overrides":{}},
		"survival": {"health":20.0, "hunger":20.0},
		"day_night": {"time_of_day":8.0, "day":1}
	}
	game.begin_world_state(state)
	_check(game.world != null and bool(game.world.get("is_started")), "hub start signal launches voxel world")
	_check(str(game.world.get("profile_id")) == "desert_ruins", "map metadata selects the requested profile")
	_check(game.player.get("inventory") == hub.get("inventory"), "player is bound to the real inventory service")
	_check(game.world_root.visible and game.player.visible, "gameplay becomes visible after world start")
	var collected: Dictionary = game.request_save()
	_check(collected.get("world", {}).has("block_overrides"), "save payload includes sparse world overrides")
	var save_service = hub.get("save_service")
	_check(save_service.world_exists("developer-a-smoke"), "hub save_current persists the active world")
	save_service.delete_world("developer-a-smoke")
	var audio_service: Node = hub.get("audio_service")
	audio_service.call("stop_ambient")
	for player_name in ["Effects", "Creatures", "Ambient"]:
		var audio_player: AudioStreamPlayer = audio_service.get_node(player_name)
		audio_player.stop()
		audio_player.stream = null
	game.queue_free()
	await process_frame
	await process_frame


func _test_project_delivery_files() -> void:
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	_check("run/main_scene=\"res://scenes/game/game.tscn\"" in project_text, "project boots through integrated game/menu scene")
	_check(FileAccess.file_exists("res://export_presets.cfg"), "Windows export preset exists")
	var export_text := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("platform=\"Windows Desktop\"" in export_text, "Windows Desktop export target is configured")


func _check(condition: bool, failure_message: String) -> void:
	checks += 1
	if not condition:
		failures.append(failure_message)
