extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const OrientationPolicyScript = preload("res://src/block/block_orientation_policy.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const VisualRegistryScript = preload("res://src/block/block_visual_registry.gd")
const PlacementPolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const ChunkScript = preload("res://src/chunk/voxel_chunk.gd")

var checks := 0
var failures: Array[String] = []

class FakeWorld:
	extends Node
	var block_id := "air"
	var block_position := Vector3i(2, 2, 2)

	func get_initial_block(position: Vector3i) -> String:
		return block_id if position == block_position else "air"

	func get_block(position: Vector3i) -> String:
		return get_initial_block(position)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_contract()
	_test_orientation_policy()
	_test_rotated_geometry()
	_test_visual_aliases()
	_test_preview_contract()
	await _test_chunk_variants()
	if failures.is_empty():
		print("QA DIRECTIONAL STAIRS PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DIRECTIONAL STAIRS FAILURE: %s" % failure)
		print("QA DIRECTIONAL STAIRS FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_contract() -> void:
	var variants := OrientationPolicyScript.STAIR_VARIANTS
	_check(variants.size() == 4, "oak stairs expose four cardinal variants")
	for block_id: String in variants:
		_check(BlockRegistryScript.has_block(block_id), "%s is registered" % block_id)
		_check(BlockRegistryScript.get_item_id(block_id) == "oak_stairs", "%s drops the canonical stair item" % block_id)
		_check(str(BlockRegistryScript.get_definition(block_id).get("name", "")) == "木楼梯", "%s keeps the player-facing display name" % block_id)
	_check(BlockRegistryScript.get_block_for_item("oak_stairs") == "oak_stairs", "inventory item resolves to the stable canonical stair id")
	var repair_numeric := BlockRegistryScript.get_numeric_id("repair_station")
	for block_id: String in variants.slice(1):
		_check(BlockRegistryScript.get_numeric_id(block_id) > repair_numeric, "%s is appended after legacy numeric ids" % block_id)


func _test_orientation_policy() -> void:
	_check(OrientationPolicyScript.resolve_for_forward("oak_stairs", Vector3.BACK) == "oak_stairs", "+Z facing resolves south stairs")
	_check(OrientationPolicyScript.resolve_for_forward("oak_stairs", Vector3.RIGHT) == "oak_stairs_east", "+X facing resolves east stairs")
	_check(OrientationPolicyScript.resolve_for_forward("oak_stairs", Vector3.FORWARD) == "oak_stairs_north", "-Z facing resolves north stairs")
	_check(OrientationPolicyScript.resolve_for_forward("oak_stairs", Vector3.LEFT) == "oak_stairs_west", "-X facing resolves west stairs")
	_check(OrientationPolicyScript.resolve_for_forward("stone", Vector3.RIGHT) == "stone", "non-directional blocks are unchanged")
	_check(OrientationPolicyScript.canonical_block_id("oak_stairs_west") == "oak_stairs", "variant canonicalization returns the base stair id")
	_check(OrientationPolicyScript.rise_direction("oak_stairs") == Vector3i.BACK, "south stairs rise toward +Z")
	_check(OrientationPolicyScript.rise_direction("oak_stairs_east") == Vector3i.RIGHT, "east stairs rise toward +X")
	_check(OrientationPolicyScript.rise_direction("oak_stairs_north") == Vector3i.FORWARD, "north stairs rise toward -Z")
	_check(OrientationPolicyScript.rise_direction("oak_stairs_west") == Vector3i.LEFT, "west stairs rise toward -X")


func _test_rotated_geometry() -> void:
	var expected_positions := {
		"oak_stairs": Vector3(0.0, 0.5, 0.5),
		"oak_stairs_east": Vector3(0.5, 0.5, 0.0),
		"oak_stairs_north": Vector3(0.0, 0.5, 0.0),
		"oak_stairs_west": Vector3(0.0, 0.5, 0.0),
	}
	var expected_sizes := {
		"oak_stairs": Vector3(1.0, 0.5, 0.5),
		"oak_stairs_east": Vector3(0.5, 0.5, 1.0),
		"oak_stairs_north": Vector3(1.0, 0.5, 0.5),
		"oak_stairs_west": Vector3(0.5, 0.5, 1.0),
	}
	for block_id: String in OrientationPolicyScript.STAIR_VARIANTS:
		var boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes(block_id)
		_check(boxes.size() == 2, "%s keeps lower and raised visual boxes" % block_id)
		_check(boxes[1].position.is_equal_approx(expected_positions[block_id]), "%s rotates the raised half to the expected side" % block_id)
		_check(boxes[1].size.is_equal_approx(expected_sizes[block_id]), "%s rotates the raised half dimensions" % block_id)
		_check(ShapeGeometryScript.get_bounds(block_id).size.is_equal_approx(Vector3.ONE), "%s stays inside one voxel" % block_id)
		var faces: Array[Dictionary] = ShapeGeometryScript.get_stair_ramp_collision_faces(block_id)
		_check(faces.size() == 5, "%s exposes a closed five-face ramp collision" % block_id)
		var slope_count := 0
		for face: Dictionary in faces:
			var normal: Vector3 = face.get("normal", Vector3.ZERO)
			if normal.y > 0.5 and absf(normal.y - 1.0) > 0.01:
				slope_count += 1
		_check(slope_count == 1, "%s exposes exactly one upward ramp surface" % block_id)
	_check(ShapeGeometryScript.get_local_boxes("oak_stairs_west")[1].end.x <= 0.5001, "west stairs place their raised half on -X")
	_check(ShapeGeometryScript.get_local_boxes("oak_stairs_north")[1].end.z <= 0.5001, "north stairs place their raised half on -Z")


func _test_visual_aliases() -> void:
	var registry = VisualRegistryScript.new()
	_check(registry.load_from_file(), "block visual registry loads with directional aliases")
	_check(registry.get_validation_errors().is_empty(), "directional aliases satisfy the visual registry contract")
	for block_id: String in OrientationPolicyScript.STAIR_VARIANTS:
		for face_index in 6:
			_check(registry.get_tile_id(block_id, face_index) == registry.get_tile_id("oak_stairs", face_index), "%s inherits canonical stair pixels on face %d" % [block_id, face_index])


func _test_preview_contract() -> void:
	var policy = PlacementPolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[0,0,0],
		"hit_block_id":"stone",
		"placement_position":[1,0,0],
		"placement_target_block_id":"air",
	}
	for block_id: String in OrientationPolicyScript.STAIR_VARIANTS:
		var preview: Dictionary = policy.evaluate(focus, block_id)
		_check(bool(preview.get("valid", false)), "%s preview remains placeable" % block_id)
		_check(str(preview.get("selected_block_id", "")) == block_id, "%s preview records the resolved variant" % block_id)
		var boxes: Array = preview.get("placement_boxes", [])
		_check(boxes.size() == 2, "%s preview contains both stair boxes" % block_id)
		var upper: Dictionary = boxes[1]
		var upper_position := _vector3_from(upper.get("position", []))
		var geometry_upper: AABB = ShapeGeometryScript.get_local_boxes(block_id)[1]
		_check(upper_position.is_equal_approx(geometry_upper.position), "%s preview uses production geometry orientation" % block_id)


func _test_chunk_variants() -> void:
	for block_id: String in OrientationPolicyScript.STAIR_VARIANTS:
		ChunkScript.reset_visual_cache_for_tests()
		var host := Node3D.new()
		var world := FakeWorld.new()
		world.block_id = block_id
		var chunk = ChunkScript.new()
		root.add_child(host)
		host.add_child(world)
		host.add_child(chunk)
		await process_frame
		chunk.initialize(Vector2i.ZERO, world)
		_check(chunk.surface_face_count == 11, "%s emits the complete two-box visual silhouette" % block_id)
		var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
		var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
		_check(mesh_instance != null and mesh_instance.mesh != null, "%s builds a production mesh" % block_id)
		_check(collision != null and collision.shape is ConcavePolygonShape3D, "%s builds a concave ramp collision" % block_id)
		if collision != null and collision.shape is ConcavePolygonShape3D:
			_check((collision.shape as ConcavePolygonShape3D).backface_collision, "%s keeps two-sided world collision" % block_id)
		if mesh_instance != null and mesh_instance.mesh != null:
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_check(vertices.size() == 66, "%s emits the expected triangle vertex count" % block_id)
		host.queue_free()
		await process_frame
		await process_frame


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
