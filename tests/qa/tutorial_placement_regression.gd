extends SceneTree

const OnboardingScript = preload("res://src/experience/onboarding_service.gd")
const ResolverScript = preload("res://src/interaction/voxel_target_resolver.gd")
const CrosshairScript = preload("res://src/ui/world_crosshair.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends RefCounted
	var blocks: Dictionary = {}

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[_key(position)] = block_id

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_voxel_target_contract()
	await _test_tutorial_aliases_and_copy()
	await _test_crosshair_and_production_player()
	if failures.is_empty():
		print("QA TUTORIAL PLACEMENT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA TUTORIAL PLACEMENT FAILURE: %s" % failure)
		print(
			"QA TUTORIAL PLACEMENT FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_voxel_target_contract() -> void:
	var world := FakeWorld.new()
	var resolver = ResolverScript.new()
	var hit := Vector3i(2, 10, -4)
	world.set_test_block(hit, "stone")
	var side: Dictionary = resolver.resolve_from_sample(
		Vector3(2.5, 10.5, -3.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Callable(world, "world_to_block"),
		Callable(world, "get_block")
	)
	_check(side.get("hit_position", Vector3i.ZERO) == hit, "side hit resolves the voxel under the crosshair")
	_check(
		side.get("placement_position", Vector3i.ZERO) == Vector3i(2, 10, -3),
		"side hit places on the pointed face instead of one voxel above",
	)
	var edge: Dictionary = resolver.resolve_from_sample(
		Vector3(2.5, 10.9999, -3.0),
		Vector3(0.0, 0.02, 0.9998),
		Vector3(0.0, 0.0, -1.0),
		Callable(world, "world_to_block"),
		Callable(world, "get_block")
	)
	_check(
		edge.get("placement_position", Vector3i.ZERO) == Vector3i(2, 10, -3),
		"near-edge side hits preserve the dominant visible face",
	)
	var top: Dictionary = resolver.resolve_from_sample(
		Vector3(2.5, 11.0, -3.5),
		Vector3.UP,
		Vector3(0.0, -1.0, -0.1),
		Callable(world, "world_to_block"),
		Callable(world, "get_block")
	)
	_check(
		top.get("placement_position", Vector3i.ZERO) == Vector3i(2, 11, -4),
		"top-face hits intentionally place above the target voxel",
	)
	var negative_hit := Vector3i(-2, 8, -3)
	world.set_test_block(negative_hit, "dirt")
	var negative: Dictionary = resolver.resolve_from_sample(
		Vector3(-1.5, 8.5, -2.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Callable(world, "world_to_block"),
		Callable(world, "get_block")
	)
	_check(
		negative.get("hit_position", Vector3i.ZERO) == negative_hit
		and negative.get("placement_position", Vector3i.ZERO) == Vector3i(-2, 8, -2),
		"negative world coordinates keep the same hit and placement contract",
	)


func _test_tutorial_aliases_and_copy() -> void:
	var onboarding = OnboardingScript.new()
	root.add_child(onboarding)
	await process_frame
	_check(
		str(onboarding.get_state().get("step", {}).get("id", "")) == "move",
		"tutorial begins at movement",
	)
	onboarding.report_action(&"look")
	onboarding.report_action(&"move")
	_check(
		str(onboarding.get_state().get("step", {}).get("id", "")) == "mine",
		"real movement and look actions advance in prerequisite order",
	)
	_check(
		str(onboarding.get_state().get("step", {}).get("description", "")).contains("按住"),
		"mining tutorial accurately teaches hold-to-harvest",
	)
	onboarding.report_action(&"harvest_no_drop")
	_check(
		str(onboarding.get_state().get("step", {}).get("id", "")) == "place",
		"a successfully broken block completes mining even without a qualified drop",
	)
	onboarding.report_action(&"block_placed")
	onboarding.report_action(&"open_inventory")
	onboarding.report_action(&"open_crafting")
	_check(onboarding.is_completed(), "canonical gameplay aliases complete the whole tutorial")
	var serialized: Dictionary = onboarding.serialize()
	_check(int(serialized.get("version", 0)) == 2, "tutorial persistence advertises the alias-aware schema")
	onboarding.queue_free()
	await process_frame


func _test_crosshair_and_production_player() -> void:
	root.size = Vector2i(1024, 576)
	var host := Control.new()
	host.position = Vector2.ZERO
	host.size = Vector2(root.size)
	root.add_child(host)
	var crosshair = CrosshairScript.new()
	host.add_child(crosshair)
	await process_frame
	var expected := Vector2(root.size) * 0.5
	var actual: Vector2 = crosshair.call("get_aim_point")
	_check(actual.distance_to(expected) <= 0.01, "geometric crosshair is exactly at the camera viewport center")
	_check(crosshair is not Label, "crosshair no longer depends on font glyph metrics")
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	_check(
		str(player.get_script().resource_path).ends_with("precision_interaction_player.gd"),
		"production player selects the shared precision interaction contract",
	)
	player.queue_free()
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
