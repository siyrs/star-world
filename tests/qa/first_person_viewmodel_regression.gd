extends SceneTree

const PlayerScene = preload("res://scenes/game/player.tscn")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const PolicyScript = preload("res://src/player/held_item_visual_policy.gd")
const FactoryScript = preload("res://src/player/held_item_mesh_factory.gd")
const AtlasScript = preload("res://src/block/block_texture_atlas.gd")

var checks := 0
var failures: Array[String] = []


class FakeHarvestService:
	extends Node
	signal harvest_progress_changed(snapshot: Dictionary)
	signal harvest_cancelled(reason: String)
	signal harvest_completed(result: Dictionary)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_config_and_policy()
	await _test_mesh_factory()
	await _test_production_player_view()
	if failures.is_empty():
		print("QA FIRST PERSON VIEWMODEL PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA FIRST PERSON VIEWMODEL FAILURE: %s" % failure)
		print("QA FIRST PERSON VIEWMODEL FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_config_and_policy() -> void:
	_check(FileAccess.file_exists("res://data/first_person_viewmodel.json"), "viewmodel data file exists")
	var file := FileAccess.open("res://data/first_person_viewmodel.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else {}
	_check(parsed is Dictionary, "viewmodel data parses as a dictionary")
	var config: Dictionary = parsed if parsed is Dictionary else {}
	_check(int(config.get("schema_version", 0)) == 1, "viewmodel schema version is explicit")
	_check(float(config.get("swing_seconds", 0.0)) > 0.0, "swing duration is positive")
	_check(float(config.get("walk_bob_amplitude", -1.0)) >= 0.0, "walk bob amplitude is bounded")
	var policy = PolicyScript.new()
	_check(policy.classify({"category":"block"}, "grass") == "block", "block items use textured cube models")
	_check(policy.classify({"category":"tool","tool_type":"pickaxe"}, "") == "tool", "tools use procedural tool models")
	_check(policy.classify({"category":"food"}, "") == "food", "food uses the food model family")
	_check(policy.action_kind(&"attack") == PolicyScript.ACTION_SWING, "attacks map to swing animation")
	_check(policy.action_kind(&"place") == PolicyScript.ACTION_USE, "placement maps to use animation")
	var idle: Dictionary = policy.sample_transform(config, 0.0, 0.0, true)
	var walking: Dictionary = policy.sample_transform(config, 0.25, 5.4, true)
	_check(Vector3(walking.get("position_offset", Vector3.ZERO)).length() > Vector3(idle.get("position_offset", Vector3.ZERO)).length(), "walking creates visible bob offset")
	var swinging: Dictionary = policy.sample_transform(config, 0.0, 0.0, true, 0.5)
	_check(Vector3(swinging.get("rotation_degrees", Vector3.ZERO)).length() > 20.0, "mid-swing produces a strong readable rotation")
	var mining: Dictionary = policy.sample_transform(config, 0.17, 0.0, true, -1.0, -1.0, 1.0, true)
	_check(Vector3(mining.get("position_offset", Vector3.ZERO)).length() > 0.01, "active mining produces continuous motion")
	var switching: Dictionary = policy.sample_transform(config, 0.0, 0.0, true, -1.0, -1.0, 0.0)
	_check(float(Vector3(switching.get("position_offset", Vector3.ZERO)).y) < -0.2, "item switching begins below the resting pose")


func _test_mesh_factory() -> void:
	var factory = FactoryScript.new()
	var block := factory.build_model("grass_block", {"category":"block","block_id":"grass","color":"#61A84B"}, "grass")
	root.add_child(block)
	await process_frame
	_check(str(block.get_meta("model_kind", "")) == "block", "block factory reports block model kind")
	_check(int(block.get_meta("part_count", 0)) == 1, "block viewmodel uses one batched cube mesh")
	var block_mesh := _first_mesh(block)
	_check(block_mesh != null and block_mesh.mesh != null, "block viewmodel builds a real mesh")
	if block_mesh != null:
		var material := block_mesh.material_override as StandardMaterial3D
		_check(material != null and material.albedo_texture == AtlasScript.get_texture(), "block viewmodel reuses the production pixel atlas")
		_check(material != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "block viewmodel preserves nearest-neighbor pixels")
		_check(material != null and material.no_depth_test, "first-person model cannot clip behind world geometry")
	_check(not _tree_has_collision(block), "block viewmodel contains no collision objects")
	block.queue_free()
	for tool_type in ["pickaxe", "axe", "shovel", "hoe", "sword"]:
		var tool := factory.build_model("test_%s" % tool_type, {"category":"tool","tool_type":tool_type,"color":"#D4D8D9"})
		root.add_child(tool)
		await process_frame
		_check(str(tool.get_meta("model_kind", "")) == "tool", "%s uses tool model kind" % tool_type)
		_check(int(tool.get_meta("part_count", 0)) >= 3, "%s has multiple readable low-poly parts" % tool_type)
		_check(not _tree_has_collision(tool), "%s viewmodel has no collision" % tool_type)
		tool.queue_free()
	var food := factory.build_model("apple", {"category":"food","color":"#D93D38"})
	root.add_child(food)
	await process_frame
	_check(int(food.get_meta("part_count", 0)) >= 2, "food model has layered pixel-like detail")
	_check(not _tree_has_collision(food), "food viewmodel is presentation only")
	food.queue_free()
	await process_frame


func _test_production_player_view() -> void:
	var player = PlayerScene.instantiate()
	var inventory = InventoryScript.new()
	var harvest = FakeHarvestService.new()
	root.add_child(inventory)
	root.add_child(harvest)
	root.add_child(player)
	await process_frame
	player.visible = true
	player.call("bind_inventory", inventory)
	player.call("bind_harvest_service", harvest)
	player.call("set_input_enabled", true)
	var view := player.get_node_or_null("CameraPivot/Camera3D/HeldItemView")
	_check(view != null, "production player scene mounts HeldItemView under Camera3D")
	if view == null:
		player.queue_free()
		inventory.queue_free()
		harvest.queue_free()
		return
	view.call("setup", player, inventory, harvest)
	inventory.add_item("wooden_pickaxe", 1)
	inventory.add_item("grass_block", 4)
	inventory.select_slot(0)
	await process_frame
	view.call("refresh_for_test")
	var snapshot: Dictionary = view.call("get_snapshot")
	_check(str(snapshot.get("item_id", "")) == "wooden_pickaxe", "selected pickaxe appears in first person")
	_check(str(snapshot.get("model_kind", "")) == "tool", "selected pickaxe resolves tool model")
	_check(bool(snapshot.get("visible", false)), "held item is visible during gameplay")
	player.gameplay_action_reported.emit(&"attack", {})
	await process_frame
	snapshot = view.call("get_snapshot")
	_check(float(snapshot.get("swing_remaining", 0.0)) > 0.0, "real player attack event starts swing animation")
	harvest.harvest_progress_changed.emit({"status":"progress","ratio":0.25})
	await process_frame
	snapshot = view.call("get_snapshot")
	_check(bool(snapshot.get("mining_active", false)), "harvest progress enables continuous mining motion")
	harvest.harvest_cancelled.emit("released")
	await process_frame
	_check(not bool(view.call("get_snapshot").get("mining_active", true)), "harvest cancellation stops mining motion")
	inventory.select_slot(1)
	await process_frame
	view.call("refresh_for_test")
	snapshot = view.call("get_snapshot")
	_check(str(snapshot.get("item_id", "")) == "grass_block", "hotbar switch replaces the held item")
	_check(str(snapshot.get("block_id", "")) == "grass", "block item resolves its production block id")
	_check(str(snapshot.get("model_kind", "")) == "block", "block item switches to textured cube view")
	_check(float(snapshot.get("switch_remaining", 0.0)) > 0.0, "hotbar switch starts a raise animation")
	player.gameplay_action_reported.emit(&"place", {})
	await process_frame
	_check(float(view.call("get_snapshot").get("use_remaining", 0.0)) > 0.0, "placement event starts use animation")
	player.call("set_input_enabled", false)
	await process_frame
	_check(not bool(view.call("get_snapshot").get("visible", true)), "blocking gameplay input hides the held item")
	player.call("set_input_enabled", true)
	await process_frame
	_check(bool(view.call("get_snapshot").get("visible", false)), "restoring gameplay input restores the held item")
	_check(not _tree_has_collision(view), "entire first-person view tree contains no collision")
	player.queue_free()
	inventory.queue_free()
	harvest.queue_free()
	for _frame in 3:
		await process_frame


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _tree_has_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return true
	for child in node.get_children():
		if _tree_has_collision(child):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
