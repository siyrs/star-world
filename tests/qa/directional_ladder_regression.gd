extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const LadderPolicyScript = preload("res://src/block/block_ladder_policy.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const PlacementPolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const TargetResolverScript = preload("res://src/interaction/voxel_target_resolver.gd")
const MovementControllerScript = preload("res://src/player/player_movement_controller.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_orientation()
	_test_wall_geometry_and_support()
	_test_placement_preview()
	_test_targeting_and_bounded_contact()
	_test_ladder_velocity_policy()
	await _test_production_player_contract()
	if failures.is_empty():
		print("QA DIRECTIONAL LADDER PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DIRECTIONAL LADDER FAILURE: %s" % failure)
		print(
			"QA DIRECTIONAL LADDER FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_catalog_and_orientation() -> void:
	_check(
		BlockRegistryScript.get_numeric_id("ladder") == 25,
		"legacy ladder numeric ID remains stable",
	)
	var expected := ["ladder", "ladder_east", "ladder_north", "ladder_west"]
	for block_id: String in expected:
		var definition: Dictionary = BlockRegistryScript.get_definition(block_id)
		_check(
			str(definition.get("shape", "")) == "ladder"
			and bool(definition.get("targetable", false))
			and bool(definition.get("climbable", false)),
			"%s exposes the directional targetable climbable contract" % block_id,
		)
		_check(
			BlockRegistryScript.get_item_id(block_id) == "ladder",
			"%s maps back to the canonical ladder item" % block_id,
		)
	var face_cases: Array[Dictionary] = [
		{"normal":Vector3.FORWARD, "block_id":"ladder", "support":Vector3i.BACK},
		{"normal":Vector3.LEFT, "block_id":"ladder_east", "support":Vector3i.RIGHT},
		{"normal":Vector3.BACK, "block_id":"ladder_north", "support":Vector3i.FORWARD},
		{"normal":Vector3.RIGHT, "block_id":"ladder_west", "support":Vector3i.LEFT},
	]
	for item: Dictionary in face_cases:
		var resolved := LadderPolicyScript.resolve_for_face_normal(
			"ladder",
			Vector3(item.get("normal", Vector3.ZERO))
		)
		_check(
			resolved == str(item.get("block_id", "")),
			"wall face resolves ladder orientation %s" % str(item.get("block_id", "")),
		)
		_check(
			LadderPolicyScript.support_offset(resolved)
			== Vector3i(item.get("support", Vector3i.ZERO)),
			"%s stores the expected backing-wall direction" % resolved,
		)
	_check(
		LadderPolicyScript.resolve_for_face_normal("ladder", Vector3.UP).is_empty(),
		"floor and ceiling faces are rejected for ladder placement",
	)


func _test_wall_geometry_and_support() -> void:
	var expected_boxes: Dictionary = {
		"ladder":AABB(Vector3(0.0, 0.0, 0.875), Vector3(1.0, 1.0, 0.125)),
		"ladder_east":AABB(Vector3(0.875, 0.0, 0.0), Vector3(0.125, 1.0, 1.0)),
		"ladder_north":AABB(Vector3.ZERO, Vector3(1.0, 1.0, 0.125)),
		"ladder_west":AABB(Vector3.ZERO, Vector3(0.125, 1.0, 1.0)),
	}
	for block_id: String in expected_boxes.keys():
		var boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes(block_id)
		var expected_box: AABB = expected_boxes[block_id]
		_check(boxes.size() == 1, "%s uses one bounded wall panel" % block_id)
		if boxes.size() == 1:
			_check(
				boxes[0].position.is_equal_approx(expected_box.position)
				and boxes[0].size.is_equal_approx(expected_box.size),
				"%s geometry is flush with its backing wall" % block_id,
			)
	_check(
		not ShapeGeometryScript.is_full_cube("ladder")
		and ShapeGeometryScript.uses_partial_geometry("ladder"),
		"ladder enters the shared partial geometry pipeline",
	)
	_check(LadderPolicyScript.is_valid_support("stone"), "full cubes support ladders")
	_check(
		not LadderPolicyScript.is_valid_support("stone_slab"),
		"partial slabs cannot silently support a wall ladder",
	)
	_check(
		not LadderPolicyScript.is_valid_support("ladder"),
		"another ladder is not treated as a structural backing wall",
	)


func _test_placement_preview() -> void:
	var policy = PlacementPolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[0, 1, 1],
		"hit_block_id":"stone",
		"placement_position":[0, 1, 0],
		"placement_target_block_id":"air",
		"placement_ladder_face_valid":true,
		"placement_ladder_support_position":[0, 1, 1],
		"placement_ladder_support_block_id":"stone",
		"placement_ladder_support_matches_target":true,
	}
	var valid: Dictionary = policy.evaluate(focus, "ladder")
	_check(bool(valid.get("valid", false)), "side-wall ladder preview is valid")
	_check(
		(valid.get("placement_boxes", []) as Array).size() == 1,
		"ladder preview uses the final thin geometry",
	)
	_check(
		valid.get("placement_support_position", []) == [0, 1, 1],
		"ladder preview exposes its backing-wall position",
	)
	var invalid_face := focus.duplicate(true)
	invalid_face["placement_ladder_face_valid"] = false
	_check(
		str(policy.evaluate(invalid_face, "ladder").get("reason", ""))
		== "ladder_face_invalid",
		"horizontal floor/ceiling placement is rejected",
	)
	var missing_support := focus.duplicate(true)
	missing_support["placement_ladder_support_block_id"] = "air"
	_check(
		str(policy.evaluate(missing_support, "ladder").get("reason", ""))
		== "ladder_support_missing",
		"preview rejects a ladder without a complete backing wall",
	)
	var mismatched_support := focus.duplicate(true)
	mismatched_support["placement_ladder_support_matches_target"] = false
	_check(
		str(policy.evaluate(mismatched_support, "ladder").get("reason", ""))
		== "ladder_support_mismatch",
		"preview rejects a support that differs from the aimed wall",
	)
	var overlapping_body := AABB(Vector3(0.2, 1.1, 0.84), Vector3(0.6, 0.7, 0.15))
	_check(
		str(policy.evaluate(focus, "ladder", overlapping_body).get("reason", ""))
		== "player_overlap",
		"thin ladder placement still protects the player body",
	)


func _test_targeting_and_bounded_contact() -> void:
	var world := FakeWorld.new()
	root.add_child(world)
	world.set_test_block(Vector3i(0, 0, 0), "ladder")
	world.set_test_block(Vector3i(0, 0, 1), "stone")
	var resolver = TargetResolverScript.new()
	var target: Dictionary = resolver.resolve_grid_from_sample(
		Vector3(0.5, 0.5, 2.5),
		Vector3.FORWARD,
		4.0,
		Callable(world, "world_to_block"),
		Callable(world, "get_block")
	)
	_check(
		str(target.get("hit_block_id", "")) == "ladder",
		"non-solid ladder remains targetable for focus and harvest",
	)
	var body_bounds := AABB(Vector3(0.2, 0.05, 0.2), Vector3(0.6, 1.8, 0.6))
	var contact: Dictionary = LadderPolicyScript.resolve_contact(world, body_bounds)
	_check(bool(contact.get("active", false)), "supported ladder creates climb contact")
	_check(
		int(contact.get("scan_count", 0)) <= LadderPolicyScript.MAX_CONTACT_CELLS,
		"ladder contact scan remains within its hard budget",
	)
	_check(
		str(contact.get("support_direction", "")) == "south",
		"contact diagnostics retain the wall orientation",
	)
	world.set_test_block(Vector3i(0, 0, 1), "air")
	var orphan: Dictionary = LadderPolicyScript.resolve_contact(world, body_bounds)
	_check(not bool(orphan.get("active", false)), "orphan ladder cannot hold the player")
	var huge_scan: Dictionary = LadderPolicyScript.resolve_contact(
		world,
		AABB(Vector3(-10.0, -10.0, -10.0), Vector3(20.0, 20.0, 20.0))
	)
	_check(
		int(huge_scan.get("scan_count", 0)) == LadderPolicyScript.MAX_CONTACT_CELLS
		and bool(huge_scan.get("budget_exhausted", false)),
		"pathological body bounds stop at the eighteen-cell contact budget",
	)
	world.queue_free()


func _test_ladder_velocity_policy() -> void:
	var controller = MovementControllerScript.new()
	controller.configure({
		"ladder_climb_speed":3.2,
		"ladder_acceleration":16.0,
		"ladder_detach_speed":2.4,
		"ladder_jump_velocity":4.2,
	})
	var contact := {
		"active":true,
		"outward_offset":Vector3i.FORWARD,
	}
	var ascent: Dictionary = controller.resolve_ladder_velocity(
		Vector3(0.0, -2.0, 0.0),
		Basis.IDENTITY,
		0.25,
		Vector2(0.0, -1.0),
		false,
		contact
	)
	var ascent_velocity: Vector3 = ascent.get("velocity", Vector3.ZERO)
	_check(
		bool(ascent.get("on_ladder", false))
		and bool(ascent.get("climbing", false))
		and ascent_velocity.y > 0.0,
		"forward input climbs and suppresses falling velocity",
	)
	var idle: Dictionary = controller.resolve_ladder_velocity(
		Vector3(0.0, 2.0, 0.0),
		Basis.IDENTITY,
		0.25,
		Vector2.ZERO,
		false,
		contact
	)
	_check(
		absf(Vector3(idle.get("velocity", Vector3.ZERO)).y) < 0.001,
		"releasing movement holds the player instead of applying gravity",
	)
	var descent: Dictionary = controller.resolve_ladder_velocity(
		Vector3.ZERO,
		Basis.IDENTITY,
		0.25,
		Vector2(0.0, 1.0),
		false,
		contact
	)
	_check(
		Vector3(descent.get("velocity", Vector3.ZERO)).y < 0.0,
		"backward input descends the ladder",
	)
	var detach: Dictionary = controller.resolve_ladder_velocity(
		Vector3.ZERO,
		Basis.IDENTITY,
		0.1,
		Vector2.ZERO,
		true,
		contact
	)
	var detach_velocity: Vector3 = detach.get("velocity", Vector3.ZERO)
	_check(
		bool(detach.get("detached_ladder", false))
		and detach_velocity.y > 0.0
		and detach_velocity.z < 0.0,
		"jump applies an upward outward detach impulse",
	)


func _test_production_player_contract() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	_check(
		player.has_method("get_ladder_movement_snapshot"),
		"production player includes ladder runtime diagnostics",
	)
	var snapshot: Dictionary = player.call("get_ladder_movement_snapshot")
	_check(
		snapshot.has("enter_count")
		and snapshot.has("exit_count")
		and snapshot.has("contact_scan_count"),
		"ladder diagnostics expose bounded entry, exit and scan evidence",
	)
	var saved: Dictionary = player.call("serialize_state")
	var serialized := JSON.stringify(saved)
	_check(
		not serialized.contains("ladder")
		and saved.has("position")
		and saved.has("rotation"),
		"transient ladder contact never enters player persistence",
	)
	player.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
