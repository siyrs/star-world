extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const PlacementPolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const ChunkScript = preload("res://src/chunk/voxel_chunk.gd")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[_key(position)] = block_id

	func get_initial_block(position: Vector3i) -> String:
		return get_block(position)

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x,position.y,position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_connection_policy()
	_test_connected_geometry()
	_test_connection_aware_preview()
	await _test_live_chunk_neighbor_rebuild("glass_pane",9,Vector3(0.5625,1.0,0.125),6,Vector3(1.0,1.0,0.125))
	await _test_live_chunk_neighbor_rebuild("oak_fence",14,Vector3(0.625,1.0,0.25),6,Vector3(0.25,1.0,0.25))
	if failures.is_empty():
		print("QA CONNECTED BLOCK SHAPES PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA CONNECTED BLOCK SHAPES FAILURE: %s" % failure)
		print(
			"QA CONNECTED BLOCK SHAPES FAIL | checks=%d | failures=%d"
			% [checks,failures.size()]
		)
		quit(1)


func _test_catalog_and_connection_policy() -> void:
	_check(
		str(BlockRegistryScript.get_definition("oak_fence").get("shape","")) == "fence",
		"oak fence uses the connected partial shape contract"
	)
	_check(
		ConnectionPolicyScript.family_id("glass_pane") == "glass_pane"
		and ConnectionPolicyScript.family_id("glass_pane_ns") == "glass_pane",
		"both pane orientation variants share one connection family"
	)
	_check(
		ConnectionPolicyScript.resolve_mask("glass_pane")
		== (ConnectionPolicyScript.EAST|ConnectionPolicyScript.WEST),
		"canonical isolated panes preserve the legacy east-west silhouette"
	)
	_check(
		ConnectionPolicyScript.resolve_mask("glass_pane_ns")
		== (ConnectionPolicyScript.NORTH|ConnectionPolicyScript.SOUTH),
		"rotated isolated panes preserve the legacy north-south silhouette"
	)
	_check(
		ConnectionPolicyScript.resolve_mask("oak_fence") == 0,
		"isolated fences remain one central post"
	)
	var pane_neighbors := ConnectionPolicyScript.empty_neighbors()
	pane_neighbors["east"] = "glass_pane_ns"
	pane_neighbors["north"] = "stone"
	pane_neighbors["west"] = "stone_slab"
	var pane_mask := ConnectionPolicyScript.resolve_mask("glass_pane",pane_neighbors)
	_check(
		pane_mask == (ConnectionPolicyScript.EAST|ConnectionPolicyScript.NORTH),
		"panes connect to their family and full cubes but not partial slabs"
	)
	var fence_neighbors := ConnectionPolicyScript.empty_neighbors()
	fence_neighbors["east"] = "oak_fence"
	fence_neighbors["west"] = "stone"
	fence_neighbors["north"] = "glass_pane"
	var fence_mask := ConnectionPolicyScript.resolve_mask("oak_fence",fence_neighbors)
	_check(
		fence_mask == (ConnectionPolicyScript.EAST|ConnectionPolicyScript.WEST),
		"fences connect to fences and full cubes without crossing into pane families"
	)
	_check(
		ConnectionPolicyScript.mask_names(fence_mask) == ["east","west"],
		"connection diagnostics expose a stable direction order"
	)
	_check(
		BlockRegistryScript.get_item_id("glass_pane_ns") == "glass_pane"
		and BlockRegistryScript.get_item_id("oak_fence") == "oak_fence",
		"connected world shapes keep canonical inventory drops"
	)


func _test_connected_geometry() -> void:
	var east_pane: Array[AABB] = ShapeGeometryScript.get_local_boxes(
		"glass_pane",
		ConnectionPolicyScript.EAST
	)
	_check(east_pane.size() == 2,"one-sided pane uses a post and one arm")
	var east_pane_bounds := ShapeGeometryScript.get_bounds(
		"glass_pane",
		ConnectionPolicyScript.EAST
	)
	_check(
		east_pane_bounds.position.is_equal_approx(Vector3(0.4375,0.0,0.4375))
		and east_pane_bounds.size.is_equal_approx(Vector3(0.5625,1.0,0.125)),
		"one-sided pane reaches only its connected cell boundary"
	)
	var cross_pane: Array[AABB] = ShapeGeometryScript.get_local_boxes(
		"glass_pane",
		ConnectionPolicyScript.ALL
	)
	_check(cross_pane.size() == 5,"four-way pane uses one post and four non-overlapping arms")
	_check(
		ShapeGeometryScript.get_bounds("glass_pane",ConnectionPolicyScript.ALL).size.is_equal_approx(Vector3.ONE),
		"four-way pane spans both horizontal axes while retaining full height"
	)
	_check(
		not ShapeGeometryScript.face_enabled("glass_pane",0,0,east_pane),
		"pane post omits the internal face covered by its east arm"
	)
	_check(
		not ShapeGeometryScript.face_enabled("glass_pane",1,1,east_pane),
		"pane arm omits the internal face covered by its post"
	)
	var isolated_fence: Array[AABB] = ShapeGeometryScript.get_local_boxes("oak_fence",0)
	_check(
		isolated_fence.size() == 1
		and isolated_fence[0].size.is_equal_approx(Vector3(0.25,1.0,0.25)),
		"isolated fence is a narrow central post rather than a full cube"
	)
	var line_fence: Array[AABB] = ShapeGeometryScript.get_local_boxes(
		"oak_fence",
		ConnectionPolicyScript.EAST|ConnectionPolicyScript.WEST
	)
	_check(line_fence.size() == 5,"two-sided fence adds two rails for each connected side")
	_check(
		ShapeGeometryScript.get_bounds(
			"oak_fence",
			ConnectionPolicyScript.EAST|ConnectionPolicyScript.WEST
		).size.is_equal_approx(Vector3(1.0,1.0,0.25)),
		"east-west fence line spans the cell without becoming a full cube"
	)
	var cross_fence: Array[AABB] = ShapeGeometryScript.get_local_boxes(
		"oak_fence",
		ConnectionPolicyScript.ALL
	)
	_check(cross_fence.size() == 9,"four-way fence uses one post and eight bounded rails")
	_check(not ShapeGeometryScript.is_full_cube("oak_fence"),"fence enters the shared partial geometry pipeline")


func _test_connection_aware_preview() -> void:
	var policy = PlacementPolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[0,0,0],
		"hit_block_id":"oak_fence",
		"target_neighbor_ids":{
			"east":"stone",
			"west":"air",
			"south":"air",
			"north":"air",
		},
		"placement_position":[2,0,0],
		"placement_target_block_id":"air",
		"placement_neighbor_ids":{
			"east":"stone",
			"west":"air",
			"south":"air",
			"north":"glass_pane_ns",
		},
	}
	var preview: Dictionary = policy.evaluate(focus,"glass_pane")
	_check(bool(preview.get("valid",false)),"connected pane preview remains placeable")
	_check(
		int(preview.get("target_connection_mask",0)) == ConnectionPolicyScript.EAST,
		"target outline resolves the existing fence neighbor mask"
	)
	_check(
		int(preview.get("placement_connection_mask",0))
		== (ConnectionPolicyScript.EAST|ConnectionPolicyScript.NORTH),
		"placement preview resolves both future pane connections"
	)
	_check(
		(preview.get("placement_boxes",[]) as Array).size() == 3,
		"placement preview renders the same post and two arms as final geometry"
	)
	var overlapping_body := AABB(
		Vector3(2.72,0.1,0.45),
		Vector3(0.12,0.5,0.08)
	)
	var blocked: Dictionary = policy.evaluate(focus,"glass_pane",overlapping_body)
	_check(
		str(blocked.get("reason","")) == "player_overlap",
		"player overlap checks use connected arms rather than a stale fallback box"
	)


func _test_live_chunk_neighbor_rebuild(
	block_id: String,
	connected_faces: int,
	connected_size: Vector3,
	isolated_faces: int,
	isolated_size: Vector3
) -> void:
	ChunkScript.reset_visual_cache_for_tests()
	var host := Node3D.new()
	var world := FakeWorld.new()
	var block_position := Vector3i(15,2,2)
	var neighbor_position := Vector3i(16,2,2)
	world.set_test_block(block_position,block_id)
	world.set_test_block(neighbor_position,"stone")
	var chunk = ChunkScript.new()
	root.add_child(host)
	host.add_child(world)
	host.add_child(chunk)
	await process_frame
	chunk.initialize(Vector2i.ZERO,world)
	_check(
		chunk.surface_face_count == connected_faces,
		"%s suppresses internal and connected boundary faces" % block_id
	)
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	_check(
		mesh_instance != null and mesh_instance.mesh != null,
		"%s builds connected production mesh" % block_id
	)
	_check(
		collision != null and collision.shape != null,
		"%s builds connected production collision" % block_id
	)
	if mesh_instance != null and mesh_instance.mesh != null:
		_check(
			mesh_instance.mesh.get_aabb().size.is_equal_approx(connected_size),
			"%s mesh follows its live east connection" % block_id
		)
	world.set_test_block(neighbor_position,"air")
	chunk.rebuild_mesh()
	_check(
		chunk.surface_face_count == isolated_faces,
		"%s rebuild removes stale connected faces after neighbor removal" % block_id
	)
	if mesh_instance != null and mesh_instance.mesh != null:
		_check(
			mesh_instance.mesh.get_aabb().size.is_equal_approx(isolated_size),
			"%s rebuild restores its isolated silhouette" % block_id
		)
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
