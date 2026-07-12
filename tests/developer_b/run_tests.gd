extends SceneTree

const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const SaveScript = preload("res://src/save/save_service.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[DEV-B] Starting gameplay service tests")
	_test_data_and_inventory()
	_test_crafting()
	_test_save_round_trip()
	_test_survival_and_time()
	await _test_entities()
	await _test_service_hub()
	if failures.is_empty():
		print("[DEV-B] PASS: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("[DEV-B] %s" % failure)
		print("[DEV-B] FAIL: %d / %d checks" % [failures.size(), checks])
		quit(1)


func _test_data_and_inventory() -> void:
	var registry = ItemRegistryScript.new()
	_expect(registry.load_from_file(), "item registry loads")
	_expect(registry.item_count() >= 30, "at least 30 registered items")
	var inventory = InventoryScript.new()
	root.add_child(inventory)
	_expect(inventory.add_item("dirt", 130) == 0, "stacked add accepts 130 blocks")
	_expect(inventory.count_item("dirt") == 130, "stacked inventory count is exact")
	_expect(inventory.get_slot(0).get("count", 0) == 64 and inventory.get_slot(1).get("count", 0) == 64, "max stack is enforced")
	_expect(inventory.remove_item("dirt", 65) == 65 and inventory.count_item("dirt") == 65, "remove spans stacks")
	var snapshot: Dictionary = inventory.serialize()
	var restored = InventoryScript.new()
	root.add_child(restored)
	_expect(restored.deserialize(snapshot) and restored.count_item("dirt") == 65, "inventory serialization round trip")
	inventory.queue_free()
	restored.queue_free()


func _test_crafting() -> void:
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	root.add_child(inventory)
	root.add_child(crafting)
	crafting.setup(inventory)
	_expect(crafting.recipe_count() >= 30, "at least 30 recipes load")
	inventory.add_item("oak_planks", 8)
	inventory.add_item("stick", 4)
	crafting.set_station("workbench")
	_expect(crafting.can_craft("wooden_pickaxe"), "wooden pickaxe requirements resolve")
	_expect(crafting.craft("wooden_pickaxe"), "wooden pickaxe crafting succeeds")
	_expect(inventory.count_item("wooden_pickaxe") == 1, "crafted output enters inventory")
	_expect(inventory.count_item("oak_planks") == 5 and inventory.count_item("stick") == 2, "craft consumes real ingredients")
	inventory.queue_free()
	crafting.queue_free()


func _test_save_round_trip() -> void:
	var save = SaveScript.new()
	root.add_child(save)
	var name := "developer-b-test-%d" % Time.get_ticks_msec()
	var state: Dictionary = save.create_world(name, "star_continent", 123456)
	_expect(not state.is_empty(), "world save is created")
	if state.is_empty():
		save.queue_free()
		return
	var world_id := str(state["metadata"]["id"])
	state["world"]["block_overrides"] = {"0,42,0":"stone_bricks"}
	state["player"]["position"] = [4.0, 52.0, -3.0]
	_expect(save.save_world(world_id, state), "world state saves atomically")
	var loaded: Dictionary = save.load_world(world_id)
	_expect(loaded.get("save_version", 0) == 2, "save schema version is retained")
	_expect(loaded.get("world", {}).get("block_overrides", {}).get("0,42,0", "") == "stone_bricks", "block override survives reload")
	_expect(loaded.get("player", {}).get("position", [])[1] == 52.0, "player position survives reload")
	_expect(save.delete_world(world_id), "temporary world can be deleted")
	save.queue_free()


func _test_survival_and_time() -> void:
	var survival = SurvivalScript.new()
	root.add_child(survival)
	survival.take_damage(5.0, "test")
	_expect(survival.health == 15.0 and survival.alive, "damage changes health")
	survival.consume_food("apple", 4.0, 2.0)
	survival.take_damage(99.0, "test")
	_expect(not survival.alive and survival.health == 0.0, "fatal damage triggers death state")
	survival.respawn()
	_expect(survival.alive and survival.health == survival.max_health, "respawn restores playable state")
	var day = DayNightScript.new()
	root.add_child(day)
	day.set_time(23.0)
	_expect(day.is_night() and day.get_phase() == "night", "night phase resolves")
	day.set_time(12.0)
	_expect(not day.is_night() and day.get_sun_strength() > 0.5, "day phase resolves")
	survival.queue_free()
	day.queue_free()


func _test_entities() -> void:
	var factory = CreatureFactoryScript.new()
	_expect(factory.profiles.size() == 4, "four creature profiles load")
	for species in ["chicken", "cow", "pig", "zombie"]:
		var creature = factory.create(species, Vector3.ZERO)
		_expect(creature != null, "%s can be created" % species)
		if creature != null:
			root.add_child(creature)
			await process_frame
			_expect(creature.get_child_count() >= 4, "%s has procedural model and collision" % species)
			_expect(creature.max_health > 0.0 and not creature.drops.is_empty(), "%s has health and drops" % species)
			creature.queue_free()
	await process_frame


func _test_service_hub() -> void:
	var scene: PackedScene = load("res://scenes/ui/service_hub.tscn")
	_expect(scene != null, "service hub scene loads")
	if scene == null:
		return
	var hub = scene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_expect(hub.get_node_or_null("Inventory") != null, "service hub instantiates inventory")
	_expect(hub.get_node_or_null("Crafting") != null, "service hub instantiates crafting")
	_expect(hub.get_node_or_null("Save") != null, "service hub instantiates save service")
	_expect(hub.get_node_or_null("Survival") != null and hub.get_node_or_null("DayNight") != null, "service hub instantiates survival and time")
	_expect(hub.get_node_or_null("AudioService") != null, "service hub instantiates audio")
	_expect(hub.get_node_or_null("CreatureSpawner") != null, "service hub instantiates creature spawner")
	_expect(hub.get_node_or_null("MainMenu") != null and hub.get_node_or_null("GameUI") != null, "service hub instantiates menu and HUD layer")
	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	_expect(is_equal_approx(hub.day_night.cycle_duration_seconds, float(original_settings.get("cycle_minutes", 10)) * 60.0), "saved cycle setting applies during service hub startup")
	var test_settings := {"mouse_sensitivity":0.31, "render_distance":6, "master_volume":0.42, "fullscreen":false, "cycle_minutes":7}
	hub.main_menu.settings_changed.emit(test_settings)
	_expect(is_equal_approx(hub.day_night.cycle_duration_seconds, 420.0), "settings signal applies day/night cycle minutes")
	var settings_player := SettingsTestPlayer.new()
	var settings_world := SettingsTestWorld.new()
	root.add_child(settings_player)
	root.add_child(settings_world)
	hub.attach_game(settings_world, settings_player)
	_expect(is_equal_approx(settings_player.mouse_sensitivity, 0.0031), "attach_game applies UI mouse sensitivity divided by 100")
	_expect(settings_world.render_distance == 5, "attach_game clamps world render distance to the supported maximum")
	_expect(settings_world.unload_distance == 6, "attach_game keeps unload distance beyond render distance")
	var persisted: Dictionary = hub.save_service.load_settings({})
	_expect(int(persisted.get("render_distance", 0)) == 5 and int(persisted.get("cycle_minutes", 0)) == 7, "settings signal persists clamped gameplay settings")
	hub.main_menu.settings_changed.emit(original_settings)
	settings_player.queue_free()
	settings_world.queue_free()
	hub.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)


class SettingsTestPlayer extends Node3D:
	var mouse_sensitivity: float = 0.0


class SettingsTestWorld extends Node3D:
	var render_distance: int = 0
	var unload_distance: int = 0
