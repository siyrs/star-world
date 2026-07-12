extends SceneTree

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const SaveServiceScript = preload("res://src/save/save_service.gd")
const SaveBrowserScript = preload("res://src/ui/save_browser_panel.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const AudioScript = preload("res://src/audio/audio_service.gd")
const AudioBridgeScript = preload("res://src/audio/audio_event_bridge.gd")
const WorldScript = preload("res://src/world/voxel_world.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")
const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")
const CreatureSpawnerScript = preload("res://src/entity/creature_spawner.gd")
const PickupScript = preload("res://src/entity/item_pickup.gd")

var checks := 0
var failures: Array[String] = []
var emitted_world_id := ""
var sound_events: Array[String] = []
var creature_died := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_menu_navigation()
	await _test_save_button_closures()
	await _test_combat_food_audio_and_lifecycle()
	if failures.is_empty():
		print("QA INTEGRATION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA INTEGRATION FAILURE: %s" % failure)
		print("QA INTEGRATION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_menu_navigation() -> void:
	var menu = MainMenuScene.instantiate()
	root.add_child(menu)
	await process_frame
	var main_panel := menu.get("_main_panel") as Control
	var map_panel := menu.get("_map_panel") as Control
	var save_panel := menu.get("_save_panel") as Control
	var start_button := _find_button(menu, "开始游戏")
	var maps_button := _find_button(menu, "地图选择")
	var saves_button := _find_button(menu, "存档 / 继续")
	_check(start_button != null and maps_button != null and saves_button != null, "main menu exposes start, map, and save actions")
	var start_rect := start_button.get_global_rect()
	var saves_rect := saves_button.get_global_rect()
	_check(not start_rect.intersects(saves_rect), "main menu button hit rectangles do not overlap")
	_check(start_rect.has_point(start_rect.get_center()) and not saves_rect.has_point(start_rect.get_center()), "start button center resolves only to start")
	start_button.pressed.emit()
	_check(map_panel.visible and not main_panel.visible, "start action opens map selection")
	map_panel.emit_signal("back_requested")
	_check(main_panel.visible and not map_panel.visible, "map selection returns to main menu")
	maps_button.pressed.emit()
	_check(map_panel.visible and not save_panel.visible, "map action opens map selection")
	map_panel.emit_signal("back_requested")
	saves_button.pressed.emit()
	_check(save_panel.visible and not map_panel.visible, "save action opens save browser")
	save_panel.emit_signal("back_requested")
	_check(main_panel.visible and not save_panel.visible, "save browser returns to main menu")
	var map_buttons_root := map_panel.get("_map_buttons") as Control
	var profiles: Array = map_panel.get("_profiles")
	var map_buttons := map_buttons_root.get_children()
	_check(map_buttons.size() == 5 and profiles.size() == 5, "map selection renders five profiles")
	for index in mini(map_buttons.size(), profiles.size()):
		var button := map_buttons[index] as Button
		button.pressed.emit()
		_check(str(map_panel.get("_selected_map_id")) == str(profiles[index].get("id", "")), "map button %d selects its own profile" % (index + 1))
	menu.queue_free()
	await process_frame


func _test_save_button_closures() -> void:
	var save = SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	var suffix := str(Time.get_ticks_msec())
	var name_a := "QA-Closure-A-%s" % suffix
	var name_b := "QA-Closure-B-%s" % suffix
	var state_a: Dictionary = save.create_world(name_a, "star_continent", 10101)
	var state_b: Dictionary = save.create_world(name_b, "frozen_wastes", 20202)
	var id_a := str(state_a.get("metadata", {}).get("id", ""))
	var id_b := str(state_b.get("metadata", {}).get("id", ""))
	_check(not id_a.is_empty() and not id_b.is_empty() and id_a != id_b, "two independent world saves are created")
	var panel = SaveBrowserScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(save)
	panel.load_requested.connect(_on_load_requested)
	var list_root := panel.get("_list") as Control
	var matched := 0
	for row_node in list_root.get_children():
		var row := row_node as HBoxContainer
		if row == null or row.get_child_count() < 2:
			continue
		var select_button := row.get_child(0) as Button
		var load_button := row.get_child(1) as Button
		var expected := ""
		if name_a in select_button.text:
			expected = id_a
		elif name_b in select_button.text:
			expected = id_b
		if expected.is_empty():
			continue
		emitted_world_id = ""
		load_button.pressed.emit()
		_check(emitted_world_id == expected, "save row emits its own world id")
		matched += 1
	_check(matched == 2, "save browser exposes both temporary worlds")
	save.delete_world(id_a)
	save.delete_world(id_b)
	panel.queue_free()
	save.queue_free()
	await process_frame


func _test_combat_food_audio_and_lifecycle() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var inventory = InventoryScript.new()
	var survival = SurvivalScript.new()
	var audio = AudioScript.new()
	var bridge = AudioBridgeScript.new()
	var world = WorldScript.new()
	world.render_distance = 1
	world.unload_distance = 2
	arena.add_child(inventory)
	arena.add_child(survival)
	arena.add_child(audio)
	arena.add_child(bridge)
	arena.add_child(world)
	await process_frame
	sound_events.clear()
	audio.sound_played.connect(_on_sound_played)
	world.start_world("star_continent", 30303, "qa-integration", {})
	bridge.setup(audio, world, inventory, null, survival)
	var target := world.world_to_block(world.get_spawn_position()) + Vector3i(1, 0, 0)
	_check(world.get_block(target) == "air", "audio interaction target starts as air")
	_check(world.set_block(target, "planks"), "world placement succeeds")
	_check(world.remove_block(target) == "planks", "world break succeeds")
	_check(sound_events.count("place") == 1 and sound_events.count("break_soft") == 1, "block placement and break each emit one sound")

	var player = PlayerScene.instantiate()
	arena.add_child(player)
	player.global_position = Vector3(0.0, 50.0, 0.0)
	player.set_physics_process(false)
	player.set_process(false)
	player.bind_inventory(inventory)
	player.bind_survival(survival)
	bridge.connect_player(player)
	inventory.clear()
	inventory.add_item("diamond_sword", 1)
	inventory.select_slot(0)
	var factory = CreatureFactoryScript.new()
	var zombie = factory.create("zombie", Vector3(0.0, 50.0, -3.0), player, inventory)
	arena.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.drops = {"rotten_flesh":[1, 1]}
	zombie.died.connect(_on_creature_died)
	bridge.connect_creature(zombie)
	await physics_frame
	await physics_frame
	creature_died = false
	_check(player.break_target_block(), "left click path attacks a creature collider")
	_check(is_equal_approx(float(zombie.health), 13.0), "selected sword damage reaches creature health")
	player.break_target_block()
	player.break_target_block()
	_check(creature_died and float(zombie.health) <= 0.0, "repeated attacks trigger creature death")
	var pickup_count := 0
	for child in arena.get_children():
		if child.get_script() == PickupScript:
			pickup_count += 1
	_check(pickup_count >= 1, "creature death creates a collectible drop")
	_check(sound_events.has("creature_zombie"), "creature damage emits its species sound")
	var health_before := float(survival.health)
	player.take_damage(2.0, "qa")
	_check(is_equal_approx(survival.health, health_before - 2.0), "player damage reaches survival health")
	_check(sound_events.has("hurt"), "player damage emits hurt sound")

	inventory.clear()
	inventory.add_item("apple", 1)
	inventory.select_slot(0)
	survival.hunger = 10.0
	_check(player.place_selected_block(), "right click path consumes selected food")
	_check(survival.hunger > 10.0 and inventory.count_item("apple") == 0, "food restores hunger and consumes one item")

	var spawner = CreatureSpawnerScript.new()
	arena.add_child(spawner)
	spawner.setup(player, inventory, null, Callable())
	var pig = spawner.spawn_creature("pig", Vector3(3.0, 50.0, -3.0))
	_check(pig != null and spawner.active, "creature spawner activates and creates a creature")
	spawner.set_active(false)
	spawner.clear_creatures()
	await process_frame
	_check(not spawner.active and spawner.get_child_count() == 0, "world exit stops and clears creature spawning")
	world.clear_world()
	_check(not world.is_started and world.get_loaded_chunk_count() == 0, "world exit clears streaming chunks")
	for player_name in ["Effects", "Creatures", "Ambient"]:
		var audio_player := audio.get_node(player_name) as AudioStreamPlayer
		audio_player.stop()
		audio_player.stream = null
	var audio_cache: Dictionary = audio.get("_cache")
	audio_cache.clear()
	await create_timer(0.35).timeout
	arena.queue_free()
	await process_frame
	await process_frame


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == label:
			return child
		var nested := _find_button(child, label)
		if nested != null:
			return nested
	return null


func _on_load_requested(world_id: String) -> void:
	emitted_world_id = world_id


func _on_sound_played(event_name: String) -> void:
	sound_events.append(event_name)


func _on_creature_died(_species_id: String, _drops: Dictionary, _world_position: Vector3) -> void:
	creature_died = true


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
