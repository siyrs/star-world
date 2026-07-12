extends SceneTree

const BlockRegistryScript := preload("res://src/block/block_registry.gd")
const GeneratorScript := preload("res://src/world/world_generator.gd")
const WorldScript := preload("res://src/world/voxel_world.gd")
const PlayerScene := preload("res://scenes/game/player.tscn")
const GameScene := preload("res://scenes/game/game.tscn")
const MapPanelScript := preload("res://src/ui/map_selection_panel.gd")
const SaveBrowserScript := preload("res://src/ui/save_browser_panel.gd")
const SaveScript := preload("res://src/save/save_service.gd")
const ItemRegistryScript := preload("res://src/inventory/item_registry.gd")
const InventoryScript := preload("res://src/inventory/inventory_service.gd")
const CraftingScript := preload("res://src/crafting/crafting_service.gd")
const SurvivalScript := preload("res://src/survival/survival_service.gd")
const DayNightScript := preload("res://src/survival/day_night_service.gd")
const CreatureFactoryScript := preload("res://src/entity/creature_factory.gd")
const CreatureSpawnerScript := preload("res://src/entity/creature_spawner.gd")
const ItemPickupScript := preload("res://src/entity/item_pickup.gd")
const AudioScript := preload("res://src/audio/audio_service.gd")

const PROFILE_IDS := ["star_continent", "desert_ruins", "frozen_wastes", "sky_islands", "abyss_world"]
const PROFILE_NAMES := ["星辰大陆", "荒漠遗迹", "极寒冰原", "天空群岛", "深渊世界"]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_delivery_contract()
	await _test_menu_and_dynamic_button_contracts()
	await _test_five_maps_seed_and_chunks()
	await _test_player_world_interaction()
	_test_inventory_and_crafting()
	await _test_survival_entities_and_audio()
	await _test_integrated_save_resume()
	if failures.is_empty():
		print("QA ACCEPTANCE PASS | checks=%d | profiles=5" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA ACCEPTANCE FAILURE: %s" % failure)
		print("QA ACCEPTANCE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_delivery_contract() -> void:
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	_expect("run/main_scene=\"res://scenes/game/game.tscn\"" in project_text, "AC-001 integrated main scene configured")
	_expect("config/name=\"星的世界\"" in project_text, "AC-001 product name configured")
	for path in ["res://README.md", "res://BUILD.md", "res://ARCHITECTURE.md"]:
		_expect(FileAccess.file_exists(path), "AC-007 delivery document exists: %s" % path)
	var readme := FileAccess.get_file_as_string("res://README.md")
	for required_text in ["星辰大陆", "荒漠遗迹", "极寒冰原", "天空群岛", "深渊世界", "左键破坏", "右键放置", "世界存档"]:
		_expect(required_text in readme, "AC-007 README documents %s" % required_text)
	var build_text := FileAccess.get_file_as_string("res://BUILD.md")
	_expect("--export-release \"Windows Desktop\"" in build_text, "AC-007 Windows export command documented")
	var architecture_text := FileAccess.get_file_as_string("res://ARCHITECTURE.md")
	for module_name in ["Core", "World / Chunk", "Player", "Inventory", "Crafting", "Save", "Survival", "Entity", "UI", "Audio"]:
		_expect(module_name in architecture_text, "AC-007 architecture documents %s" % module_name)
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect("platform=\"Windows Desktop\"" in preset, "AC-007 Windows preset exists")
	_expect("application/modify_resources=false" in preset, "AC-007 deterministic resource modification setting")
	_expect(FileAccess.file_exists("res://build/StarWorld.exe") and FileAccess.file_exists("res://build/StarWorld.pck"), "AC-007 Windows EXE and PCK present")


func _test_menu_and_dynamic_button_contracts() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var hub: Node = game.get_node("GameplayServiceHub")
	var menu: Control = hub.get("main_menu")
	var game_ui: CanvasLayer = hub.get("game_ui")
	_expect(menu != null and menu.visible, "AC-001 main menu is visible at startup")
	_expect(game_ui != null and not game_ui.visible, "AC-001 game HUD is hidden before world start")
	_expect(not game.world_root.visible and not game.player.visible, "AC-001 3D gameplay is hidden behind menu")
	var map_panel: Control = menu.get("_map_panel")
	var save_panel: Control = menu.get("_save_panel")
	var settings_panel: Control = menu.get("_settings_panel")
	var main_panel: Control = menu.get("_main_panel")
	for label in ["开始游戏", "地图选择"]:
		var button = _find_button(menu, label)
		_expect(button != null, "AC-001 menu button exists: %s" % label)
		if button != null:
			button.pressed.emit()
			await process_frame
			_expect(map_panel.visible and not main_panel.visible, "AC-001 %s routes to map selection" % label)
			map_panel.back_requested.emit()
			await process_frame
			_expect(main_panel.visible and not map_panel.visible, "AC-001 map back returns to main menu")
	var save_button = _find_button(menu, "存档 / 继续")
	_expect(save_button != null, "AC-001 save/continue button exists")
	if save_button != null:
		save_button.pressed.emit()
		await process_frame
		_expect(save_panel.visible and not main_panel.visible, "AC-001 save/continue routes to save browser")
		save_panel.back_requested.emit()
		await process_frame
		_expect(main_panel.visible, "AC-001 save browser back returns to main menu")
	var settings_button = _find_button(menu, "设置")
	_expect(settings_button != null, "AC-001 settings button exists")
	if settings_button != null:
		settings_button.pressed.emit()
		await process_frame
		_expect(settings_panel.visible and not main_panel.visible, "AC-001 settings routes to settings panel")
		settings_panel.back_requested.emit()
		await process_frame
		_expect(main_panel.visible, "AC-001 settings back returns to main menu")
	_expect(_find_button(menu, "退出") != null, "AC-001 exit button exists")
	_stop_audio(hub)
	game.queue_free()
	await process_frame

	var direct_map_panel = MapPanelScript.new()
	root.add_child(direct_map_panel)
	await process_frame
	var profiles: Array = direct_map_panel.get("_profiles")
	_expect(profiles.size() == 5, "AC-002 map panel loads exactly five profiles")
	var map_buttons: VBoxContainer = direct_map_panel.get("_map_buttons")
	_expect(map_buttons.get_child_count() == 5, "AC-002 map panel renders five buttons")
	for index in mini(5, map_buttons.get_child_count()):
		var profile: Dictionary = profiles[index]
		var map_button: Button = map_buttons.get_child(index)
		map_button.pressed.emit()
		_expect(str(direct_map_panel.get("_selected_map_id")) == str(profile.get("id", "")), "AC-002 map button closure selects %s" % profile.get("id", ""))
		_expect(PROFILE_NAMES[index] in map_button.text, "AC-002 map button names %s" % PROFILE_NAMES[index])
	direct_map_panel.queue_free()
	await process_frame

	var save_service = SaveScript.new()
	root.add_child(save_service)
	var token := str(Time.get_ticks_msec())
	var state_a: Dictionary = save_service.create_world("QA Menu A %s" % token, "star_continent", 111001)
	var state_b: Dictionary = save_service.create_world("QA Menu B %s" % token, "desert_ruins", 222002)
	var id_a := str(state_a.get("metadata", {}).get("id", ""))
	var id_b := str(state_b.get("metadata", {}).get("id", ""))
	_expect(not id_a.is_empty() and not id_b.is_empty() and id_a != id_b, "AC-006 two temporary menu saves created")
	var browser = SaveBrowserScript.new()
	root.add_child(browser)
	await process_frame
	browser.setup(save_service)
	await process_frame
	var emitted_ids: Array[String] = []
	browser.load_requested.connect(func(world_id: String): emitted_ids.append(world_id))
	var verified_ids: Dictionary = {}
	var list: VBoxContainer = browser.get("_list")
	for row in list.get_children():
		if row.get_child_count() < 2:
			continue
		var select_button: Button = row.get_child(0)
		var continue_button: Button = row.get_child(1)
		var expected_id := ""
		if ("QA Menu A %s" % token) in select_button.text:
			expected_id = id_a
		elif ("QA Menu B %s" % token) in select_button.text:
			expected_id = id_b
		if expected_id.is_empty():
			continue
		select_button.pressed.emit()
		_expect(str(browser.get("_selected_world_id")) == expected_id, "AC-006 save select closure uses correct world id")
		continue_button.pressed.emit()
		_expect(not emitted_ids.is_empty() and emitted_ids.back() == expected_id, "AC-006 continue closure emits correct world id")
		var loaded: Dictionary = save_service.load_world(expected_id)
		_expect(str(loaded.get("metadata", {}).get("id", "")) == expected_id, "AC-006 emitted save id resolves correct metadata")
		verified_ids[expected_id] = true
	_expect(verified_ids.has(id_a) and verified_ids.has(id_b), "AC-006 both save rows independently verified")
	if not id_a.is_empty(): save_service.delete_world(id_a)
	if not id_b.is_empty(): save_service.delete_world(id_b)
	browser.queue_free()
	save_service.queue_free()
	await process_frame


func _test_five_maps_seed_and_chunks() -> void:
	var profile_signatures: Dictionary = {}
	var environment_colors: Dictionary = {}
	for profile_id in PROFILE_IDS:
		var first = GeneratorScript.new()
		var same = GeneratorScript.new()
		var other = GeneratorScript.new()
		first.configure(profile_id, 1357911)
		same.configure(profile_id, 1357911)
		other.configure(profile_id, 2468022)
		var first_signature := _generator_signature(first)
		var same_signature := _generator_signature(same)
		var other_signature := _generator_signature(other)
		_expect(first_signature == same_signature, "AC-002 %s repeats the same seed exactly" % profile_id)
		_expect(first_signature != other_signature, "AC-002 %s changes with another seed" % profile_id)
		_expect(not profile_signatures.has(first_signature), "AC-002 %s terrain differs from earlier profiles" % profile_id)
		profile_signatures[first_signature] = profile_id
		var found_surface := false
		var found_expected_surface := false
		for x in range(-32, 33, 4):
			for z in range(-32, 33, 4):
				var height: int = first.get_surface_height(x, z)
				var top_id: String = first.get_block(Vector3i(x, height, z))
				if top_id != BlockRegistryScript.AIR:
					found_surface = true
				if profile_id == "star_continent" and top_id == "grass": found_expected_surface = true
				elif profile_id == "desert_ruins" and top_id == "sand": found_expected_surface = true
				elif profile_id == "frozen_wastes" and top_id == "snow": found_expected_surface = true
				elif profile_id == "sky_islands" and top_id == "grass": found_expected_surface = true
				elif profile_id == "abyss_world" and top_id == "stone_bricks": found_expected_surface = true
		_expect(found_surface and found_expected_surface, "AC-002 %s exposes its map-specific surface" % profile_id)
		var spawn: Vector3 = first.find_spawn_position()
		_expect(spawn.y > 2.0 and spawn.y < 64.0, "AC-002 %s provides a safe spawn" % profile_id)

		var world = WorldScript.new()
		world.render_distance = 1
		root.add_child(world)
		world.start_world(profile_id, 1357911, "qa-profile-%s" % profile_id, {})
		_expect(world.get_loaded_chunk_count() == 1, "AC-002 %s synchronously loads spawn chunk" % profile_id)
		var coords: Array = world.get_loaded_chunk_coords()
		var chunk: Node = world.chunks[Vector2i(coords[0])]
		var collision: CollisionShape3D = chunk.get_node("Collision")
		_expect(chunk.surface_face_count > 0 and collision.shape != null, "AC-002/003 %s creates rendered collision terrain" % profile_id)
		world.queue_free()
		await process_frame

		var day = DayNightScript.new()
		var sun := DirectionalLight3D.new()
		var world_environment := WorldEnvironment.new()
		world_environment.environment = Environment.new()
		root.add_child(sun)
		root.add_child(world_environment)
		root.add_child(day)
		day.attach_lighting(sun, world_environment)
		day.set_map_profile(profile_id)
		day.set_time(12.0)
		environment_colors[profile_id] = world_environment.environment.background_color.to_html()
		day.queue_free()
		sun.queue_free()
		world_environment.queue_free()
		await process_frame
	_expect(profile_signatures.size() == 5, "AC-002 all five terrain profiles are distinct")
	var unique_colors: Dictionary = {}
	for color_value in environment_colors.values(): unique_colors[color_value] = true
	_expect(unique_colors.size() == 5, "AC-002 all five environments have distinct day colors")

	var stream_world = WorldScript.new()
	stream_world.render_distance = 1
	stream_world.unload_distance = 2
	stream_world.chunks_per_frame = 2
	root.add_child(stream_world)
	stream_world.start_world("star_continent", 998877, "qa-stream", {})
	var origin_coord := Vector2i(stream_world.get_loaded_chunk_coords()[0])
	for _index in 4:
		stream_world._process(0.5)
	_expect(stream_world.get_loaded_chunk_count() > 1, "AC-002 dynamic streaming loads neighboring chunks")
	stream_world.set_focus(Vector3(16.0 * 20.0, 40.0, 0.0))
	_expect(not stream_world.chunks.has(origin_coord), "AC-002 dynamic streaming unloads distant chunks")
	var negative := Vector3i(-1, 50, -1)
	_expect(stream_world.block_to_chunk(negative) == Vector2i(-1, -1), "AC-002 negative coordinates map to correct chunk")
	_expect(stream_world.to_local_block(negative) == Vector3i(15, 50, 15), "AC-002 negative coordinates map to local voxel")
	_expect(stream_world.set_block(negative, "glass"), "AC-003 block can be added at negative coordinates")
	_expect(stream_world.get_block(negative) == "glass", "AC-003 added block is queryable")
	_expect(stream_world.remove_block(negative) == "glass", "AC-003 added block can be removed")
	stream_world.queue_free()
	await process_frame


func _test_player_world_interaction() -> void:
	var world = WorldScript.new()
	world.render_distance = 1
	world.unload_distance = 2
	root.add_child(world)
	world.start_world("star_continent", 431245, "qa-player", {})
	var target := Vector3i(0, 50, -3)
	var support := Vector3i(0, 50, -4)
	world.set_block(target, "stone")
	world.set_block(support, "stone")
	world.force_load_chunk(Vector2i(0, -1))
	var inventory = InventoryScript.new()
	var survival = SurvivalScript.new()
	var player = PlayerScene.instantiate()
	root.add_child(inventory)
	root.add_child(survival)
	root.add_child(player)
	player.bind_world(world)
	player.bind_inventory(inventory)
	player.bind_survival(survival)
	inventory.add_item("oak_planks", 3)
	inventory.select_slot(0)
	player.global_position = Vector3(0.5, 49.0, 0.5)
	player.set_input_enabled(false)
	for _index in 3: await physics_frame
	player.interaction_ray.force_raycast_update()
	_expect(player.interaction_ray.is_colliding(), "AC-003 first-person ray reaches voxel collision")
	var stone_before := inventory.count_item("stone")
	_expect(player.break_target_block(), "AC-003 left-click mining path breaks targeted block")
	_expect(world.get_block(target) == BlockRegistryScript.AIR, "AC-003 mined voxel becomes air")
	_expect(inventory.count_item("stone") == stone_before + 1, "AC-003 mining collects the block drop")
	for _index in 2: await physics_frame
	var planks_before := inventory.count_item("oak_planks")
	_expect(player.place_selected_block(), "AC-003 right-click placement path places selected block")
	_expect(world.get_block(target) == "planks", "AC-003 placed voxel has selected block type")
	_expect(inventory.count_item("oak_planks") == planks_before - 1, "AC-003 placement consumes one selected item")
	_expect(world.serialize_sparse_overrides().has(world.block_key(target)), "AC-006 placement enters sparse override save")
	for action in ["move_forward", "move_backward", "move_left", "move_right", "jump", "sprint", "quick_save", "hotbar_1", "hotbar_9"]:
		_expect(InputMap.has_action(action), "AC-003 input action registered: %s" % action)
	player.global_position = world.get_spawn_position()
	player.velocity = Vector3.ZERO
	player.set_input_enabled(true)
	world.set_focus(player)
	for _index in 90: await physics_frame
	_expect(player.is_on_floor(), "AC-003 gravity settles player on voxel collision")
	var start_position: Vector3 = player.global_position
	Input.action_press("move_forward")
	for _index in 30: await physics_frame
	Input.action_release("move_forward")
	_expect(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(start_position.x, start_position.z)) > 0.2, "AC-003 WASD movement changes horizontal position")
	for _index in 6: await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	_expect(player.velocity.y > 0.0, "AC-003 jump applies upward velocity")
	for action in ["move_forward", "jump"]: Input.action_release(action)
	player.queue_free()
	inventory.queue_free()
	survival.queue_free()
	world.queue_free()
	await process_frame


func _test_inventory_and_crafting() -> void:
	var registry = ItemRegistryScript.new()
	_expect(registry.load_from_file() and registry.item_count() == 62, "AC-004 62 item definitions load")
	var inventory = InventoryScript.new()
	root.add_child(inventory)
	_expect(inventory.slot_count == 36 and inventory.hotbar_size == 9, "AC-004 inventory exposes 36 slots and 9-slot hotbar")
	_expect(inventory.add_item("dirt", 130) == 0, "AC-004 inventory accepts multi-stack quantity")
	_expect(inventory.get_slot(0).get("count", 0) == 64 and inventory.get_slot(1).get("count", 0) == 64 and inventory.get_slot(2).get("count", 0) == 2, "AC-004 max stack boundaries are enforced")
	var snapshot: Dictionary = inventory.serialize()
	var restored = InventoryScript.new()
	root.add_child(restored)
	_expect(restored.deserialize(snapshot) and restored.count_item("dirt") == 130, "AC-004 inventory round trip preserves stacks")
	var crafting = CraftingScript.new()
	root.add_child(crafting)
	crafting.setup(restored)
	_expect(crafting.recipe_count() == 42, "AC-004 42 recipes load")
	restored.clear()
	restored.add_item("oak_planks", 8)
	restored.add_item("stick", 4)
	crafting.set_station("hand")
	_expect(not crafting.can_craft("wooden_pickaxe"), "AC-004 workbench recipe is station-gated")
	crafting.set_station("workbench")
	_expect(crafting.can_craft("wooden_pickaxe") and crafting.craft("wooden_pickaxe"), "AC-004 real workbench craft succeeds")
	_expect(restored.count_item("wooden_pickaxe") == 1 and restored.count_item("oak_planks") == 5 and restored.count_item("stick") == 2, "AC-004 crafting consumes inputs and adds output")
	inventory.queue_free()
	restored.queue_free()
	crafting.queue_free()


func _test_survival_entities_and_audio() -> void:
	var survival = SurvivalScript.new()
	root.add_child(survival)
	survival.saturation = 0.0
	survival.hunger = 1.0
	survival.passive_hunger_interval = 0.1
	survival._process(0.2)
	_expect(survival.hunger == 0.0, "AC-005 passive hunger changes survival state")
	var health_before := survival.health
	survival.starvation_damage_interval = 0.1
	survival._process(0.2)
	_expect(survival.health < health_before, "AC-005 starvation damages player")
	survival.take_damage(999.0, "qa")
	_expect(not survival.alive and survival.health == 0.0, "AC-005 fatal damage causes death")
	survival.respawn()
	_expect(survival.alive and survival.health == survival.max_health, "AC-005 respawn restores life")

	var day = DayNightScript.new()
	var sun := DirectionalLight3D.new()
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	root.add_child(sun)
	root.add_child(world_environment)
	root.add_child(day)
	day.attach_lighting(sun, world_environment)
	day.set_time(12.0)
	var day_energy := sun.light_energy
	day.set_time(23.0)
	_expect(day.is_night() and day.get_phase() == "night", "AC-005 night phase activates")
	_expect(sun.light_energy < day_energy, "AC-005 day/night changes real light energy")

	var factory = CreatureFactoryScript.new()
	_expect(factory.profiles.size() == 4, "AC-005 four creature profiles load")
	for species in ["chicken", "cow", "pig", "zombie"]:
		var creature = factory.create(species, Vector3.ZERO)
		root.add_child(creature)
		await process_frame
		_expect(creature.get_node_or_null("CollisionShape3D") != null, "AC-005 %s has collision" % species)
		_expect(creature.get_child_count() >= 4 and creature.max_health > 0.0, "AC-005 %s has model and health" % species)
		_expect(not creature.drops.is_empty(), "AC-005 %s has death drops" % species)
		creature.queue_free()
	await process_frame

	var target_player := DamageTarget.new()
	root.add_child(target_player)
	target_player.global_position = Vector3(0.0, 0.0, 5.0)
	var zombie = factory.create("zombie", Vector3.ZERO, target_player)
	root.add_child(zombie)
	await process_frame
	var chase_direction: Vector3 = zombie._choose_direction()
	_expect(chase_direction.z > 0.5, "AC-005 zombie AI chases its target")
	target_player.global_position = Vector3(0.0, 0.0, 1.0)
	zombie._choose_direction()
	_expect(target_player.health == 17.0, "AC-005 zombie AI attacks and damages player target")
	zombie.queue_free()
	target_player.queue_free()
	await process_frame

	var death_record: Dictionary = {}
	var chicken = factory.create("chicken", Vector3.ZERO)
	root.add_child(chicken)
	await process_frame
	chicken.died.connect(func(species_id: String, drops: Dictionary, _position: Vector3): death_record["species"] = species_id; death_record["drops"] = drops)
	chicken.take_damage(999.0)
	_expect(death_record.get("species", "") == "chicken", "AC-005 creature death signal fires")
	_expect(int(death_record.get("drops", {}).get("raw_chicken", 0)) >= 1, "AC-005 creature death rolls guaranteed drop")
	var pickup_found := false
	for child in root.get_children():
		if child.get_script() == ItemPickupScript and str(child.get("item_id")) == "raw_chicken":
			pickup_found = true
			child.queue_free()
	_expect(pickup_found, "AC-005 creature death spawns collectable pickup")
	chicken.queue_free()

	var spawner = CreatureSpawnerScript.new()
	var spawn_target := DamageTarget.new()
	root.add_child(spawn_target)
	root.add_child(spawner)
	spawner.setup(spawn_target, null, day)
	var spawned = spawner.spawn_creature("zombie", Vector3(3.0, 4.0, 5.0))
	_expect(spawned != null and spawned.species_id == "zombie", "AC-005 creature spawner creates requested hostile entity")
	if spawned != null: spawned.queue_free()
	spawner.queue_free()
	spawn_target.queue_free()

	var audio = AudioScript.new()
	root.add_child(audio)
	await process_frame
	var sounds: Array[String] = []
	audio.sound_played.connect(func(event_name: String): sounds.append(event_name))
	audio.play_block_break("stone")
	audio.play_block_place("planks")
	audio.play_creature("cow")
	audio.start_ambient("forest")
	_expect("break_hard" in sounds and "place" in sounds, "AC-007 break and place audio events play")
	_expect("creature_cow" in sounds and "ambient_forest" in sounds, "AC-007 creature and ambient audio events play")
	_stop_audio_service(audio)
	audio.queue_free()
	survival.queue_free()
	day.queue_free()
	sun.queue_free()
	world_environment.queue_free()
	await process_frame


func _test_integrated_save_resume() -> void:
	var world_id := "qa-integrated-%d" % Time.get_ticks_msec()
	var initial_state := {
		"metadata": {"id":world_id, "name":"QA Integrated", "map_id":"frozen_wastes", "seed":556677, "map_profile":{"ambient":"wind"}},
		"inventory": {},
		"world": {"block_overrides":{}},
		"player": {},
		"survival": {"health":20.0, "hunger":20.0},
		"day_night": {"time_of_day":8.0, "day":1}
	}
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	game.service_hub.current_settings["render_distance"] = 1
	game.begin_world_state(initial_state)
	await process_frame
	await process_frame
	var hub: Node = game.service_hub
	_expect(game.world.is_started and game.world.profile_id == "frozen_wastes", "AC-002 integrated menu state starts selected map")
	_expect(game.player.visible and game.world_root.visible and hub.game_ui.visible and not hub.main_menu.visible, "AC-001 integrated world reveals gameplay and HUD")
	_expect(hub.game_ui.hud.get("_slot_buttons").size() == 9, "AC-004 integrated HUD renders nine hotbar slots")
	var build_position: Vector3i = game.world.world_to_block(game.world.get_spawn_position()) + Vector3i(2, 0, 0)
	_expect(game.world.set_block(build_position, "stone_bricks"), "AC-003 integrated building places persistent block")
	hub.inventory.add_item("diamond", 3)
	game.player.global_position = game.world.get_spawn_position() + Vector3(2.0, 3.0, 2.0)
	hub.survival.take_damage(4.0, "qa")
	hub.day_night.set_time(23.5)
	var expected_position: Vector3 = game.player.global_position
	var saved_state: Dictionary = game.request_save()
	_expect(hub.save_service.world_exists(world_id), "AC-006 integrated save writes world directory")
	_expect(saved_state.get("world", {}).get("block_overrides", {}).has(game.world.block_key(build_position)), "AC-006 integrated state contains sparse building override")
	var disk_state: Dictionary = hub.save_service.load_world(world_id)
	_expect(disk_state.get("inventory", {}).get("slots", []).size() == 36, "AC-006 disk save includes full inventory")
	_expect(is_equal_approx(float(disk_state.get("survival", {}).get("health", 0.0)), 16.0), "AC-006 disk save includes survival health")
	_stop_audio(hub)
	game.queue_free()
	await process_frame
	await process_frame

	var resumed = GameScene.instantiate()
	root.add_child(resumed)
	await process_frame
	resumed.service_hub.current_settings["render_distance"] = 1
	resumed.begin_world_state(disk_state)
	await process_frame
	await process_frame
	_expect(resumed.world.get_block(build_position) == "stone_bricks", "AC-006 relaunch restores built block")
	_expect(resumed.service_hub.inventory.count_item("diamond") == 3, "AC-006 relaunch restores inventory")
	_expect(resumed.player.global_position.distance_to(expected_position) < 0.01, "AC-006 relaunch restores player position")
	_expect(is_equal_approx(resumed.service_hub.survival.health, 16.0), "AC-006 relaunch restores health")
	_expect(is_equal_approx(resumed.service_hub.day_night.time_of_day, 23.5), "AC-006 relaunch restores day/night time")
	resumed.service_hub.return_to_menu()
	_expect(resumed.service_hub.main_menu.visible and not resumed.service_hub.game_ui.visible and not resumed.world_root.visible, "AC-001 save and return restores menu state")
	_expect(resumed.service_hub.save_service.delete_world(world_id), "AC-006 QA temporary integrated save cleaned")
	_stop_audio(resumed.service_hub)
	resumed.queue_free()
	await process_frame


func _generator_signature(generator) -> String:
	var values: Array = []
	for x in range(-24, 25, 6):
		for z in range(-24, 25, 6):
			var height: int = generator.get_surface_height(x, z)
			values.append([height, generator.get_block(Vector3i(x, height, z)), generator.get_block(Vector3i(x, maxi(1, height - 6), z))])
	return JSON.stringify(values)


func _find_button(node: Node, exact_text: String):
	if node is Button and node.text == exact_text:
		return node
	for child in node.get_children():
		var found = _find_button(child, exact_text)
		if found != null:
			return found
	return null


func _stop_audio(hub: Node) -> void:
	var audio = hub.get("audio_service")
	if audio != null:
		_stop_audio_service(audio)


func _stop_audio_service(audio: Node) -> void:
	if audio.has_method("stop_ambient"):
		audio.call("stop_ambient")
	for player_name in ["Effects", "Creatures", "Ambient"]:
		var player: AudioStreamPlayer = audio.get_node_or_null(player_name)
		if player != null:
			player.stop()
			player.stream = null


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


class DamageTarget extends Node3D:
	var health := 20.0

	func take_damage(amount: float, _source: String = "") -> void:
		health -= amount
