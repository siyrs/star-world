extends SceneTree

const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const PlacementPolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const ChunkScript = preload("res://src/chunk/voxel_chunk.gd")
const MeshFactoryScript = preload("res://src/player/held_item_mesh_factory.gd")
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []

class FakeWorld:
	extends Node
	var block_id := "air"
	var block_position := Vector3i(1, 1, 1)

	func get_initial_block(position: Vector3i) -> String:
		return block_id if position == block_position else "air"

	func get_block(position: Vector3i) -> String:
		return get_initial_block(position)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shape_contract()
	_test_shape_aware_placement()
	await _test_chunk_geometry("stone_slab", 6, 36, 0.5)
	await _test_chunk_geometry("oak_stairs", 11, 66, 1.0)
	_test_held_item_geometry()
	await _test_preview_geometry()
	if failures.is_empty():
		print("QA NON CUBE BLOCK GEOMETRY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA NON CUBE BLOCK GEOMETRY FAILURE: %s" % failure)
		print("QA NON CUBE BLOCK GEOMETRY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_shape_contract() -> void:
	var slab_boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes("stone_slab")
	_check(slab_boxes.size() == 1, "stone slab uses one compact geometry box")
	_check(is_equal_approx(slab_boxes[0].size.y, 0.5), "stone slab is exactly half a block high")
	var stair_boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes("oak_stairs")
	_check(stair_boxes.size() == 2, "oak stairs use a lower and upper geometry box")
	_check(is_equal_approx(stair_boxes[0].size.y, 0.5), "stair lower step is half height")
	_check(stair_boxes[1].position.is_equal_approx(Vector3(0.0,0.5,0.5)), "stair upper step occupies the rear half")
	_check(not ShapeGeometryScript.face_enabled("oak_stairs", 1, 3), "internal upper stair bottom face is omitted")
	_check(is_equal_approx(ShapeGeometryScript.get_bounds("oak_bed").size.y, 0.5625), "bed uses a low collision and visual silhouette")
	_check(is_equal_approx(ShapeGeometryScript.get_bounds("farmland").size.y, 0.9375), "farmland sits below a full cube")
	_check(ShapeGeometryScript.is_full_cube("stone"), "ordinary stone remains a full cube")
	_check(not ShapeGeometryScript.is_full_cube("stone_slab"), "slabs are identified as partial shapes")


func _test_shape_aware_placement() -> void:
	var policy = PlacementPolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[0,0,0],
		"hit_block_id":"stone",
		"placement_position":[1,0,0],
		"placement_target_block_id":"air",
	}
	var upper_body := AABB(Vector3(1.1,0.62,0.1), Vector3(0.3,0.25,0.3))
	var slab_valid: Dictionary = policy.evaluate(focus, "stone_slab", upper_body)
	_check(bool(slab_valid.get("valid", false)), "player above the slab volume does not block placement")
	_check((slab_valid.get("placement_boxes", []) as Array).size() == 1, "slab preview exposes one half-height box")
	var lower_body := AABB(Vector3(1.1,0.20,0.1), Vector3(0.3,0.25,0.3))
	var slab_blocked: Dictionary = policy.evaluate(focus, "stone_slab", lower_body)
	_check(str(slab_blocked.get("reason", "")) == "player_overlap", "player intersecting the lower slab volume blocks placement")
	var stair_preview: Dictionary = policy.evaluate(focus, "oak_stairs")
	_check((stair_preview.get("placement_boxes", []) as Array).size() == 2, "stair preview exposes both step boxes")
	_check((stair_preview.get("target_boxes", []) as Array).size() == 1, "full cube targets keep one outline box")


func _test_chunk_geometry(block_id: String, expected_faces: int, expected_vertices: int, expected_height: float) -> void:
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
	_check(chunk.surface_face_count == expected_faces, "%s emits its expected exposed visual faces" % block_id)
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	_check(mesh_instance != null and mesh_instance.mesh != null, "%s builds a production visual mesh" % block_id)
	_check(collision != null and collision.shape != null, "%s builds a production collision mesh" % block_id)
	if mesh_instance != null and mesh_instance.mesh != null:
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_check(vertices.size() == expected_vertices, "%s emits complete triangle vertices" % block_id)
		var minimum_y := INF
		var maximum_y := -INF
		for vertex: Vector3 in vertices:
			minimum_y = minf(minimum_y, vertex.y)
			maximum_y = maxf(maximum_y, vertex.y)
		_check(is_equal_approx(maximum_y - minimum_y, expected_height), "%s visual bounds match its intended height" % block_id)
	host.queue_free()
	await process_frame
	await process_frame


func _test_held_item_geometry() -> void:
	var registry = ItemRegistryScript.new()
	registry.load_from_file()
	var factory = MeshFactoryScript.new()
	var slab := factory.build_model("stone_slab", registry.get_item("stone_slab"), "stone_slab")
	var stair := factory.build_model("oak_stairs", registry.get_item("oak_stairs"), "oak_stairs")
	var slab_mesh := slab.get_node_or_null("Block") as MeshInstance3D
	var stair_mesh := stair.get_node_or_null("Block") as MeshInstance3D
	_check(slab_mesh != null and is_equal_approx(slab_mesh.mesh.get_aabb().size.y, 0.5), "held slab mirrors the half-height world geometry")
	_check(stair_mesh != null and stair_mesh.mesh.surface_get_array_len(0) == 66, "held stairs mirror the two-step world geometry")
	slab.free()
	stair.free()


func _test_preview_geometry() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	player.set_input_enabled(true)
	var preview: Node = player.call("get_interaction_preview")
	_check(preview != null, "production player mounts the shape-aware world preview")
	if preview != null:
		var policy = PlacementPolicyScript.new()
		var focus := {
			"type":"block",
			"hit_position":[1,2,3],
			"hit_block_id":"stone_slab",
			"placement_position":[2,2,3],
			"placement_target_block_id":"air",
		}
		focus["placement_preview"] = policy.evaluate(focus, "oak_stairs")
		player.emit_signal("interaction_focus_changed", focus)
		await process_frame
		var target := preview.get_node_or_null("TargetOutline") as MeshInstance3D
		var first_step := preview.get_node_or_null("PlacementOutline") as MeshInstance3D
		var second_step := preview.get_node_or_null("PlacementOutline_1") as MeshInstance3D
		_check(target != null and target.visible and target.scale.y < 0.6, "target outline follows the slab half-height silhouette")
		_check(first_step != null and first_step.visible and first_step.scale.y < 0.6, "stair preview renders the lower step")
		_check(second_step != null and second_step.visible and second_step.position.y > first_step.position.y, "stair preview renders a separate raised rear step")
	player.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
