extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const OrientationPolicyScript = preload("res://src/block/block_orientation_policy.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const VisualRegistryScript = preload("res://src/block/block_visual_registry.gd")
const HarvestRegistryScript = preload("res://src/harvest/block_harvest_registry.gd")
const PlacementPolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const ChunkScript = preload("res://src/chunk/voxel_chunk.gd")
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")

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
	_test_catalog_contract()
	_test_orientation_and_geometry()
	_test_visual_harvest_and_preview()
	await _test_chunk_geometry("glass_pane", Vector3(1.0, 1.0, 0.125))
	await _test_chunk_geometry("glass_pane_ns", Vector3(0.125, 1.0, 1.0))
	if failures.is_empty():
		print("QA GLASS PANE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA GLASS PANE FAILURE: %s" % failure)
		print("QA GLASS PANE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_catalog_contract() -> void:
	var item_registry = ItemRegistryScript.new()
	_check(item_registry.load_from_file(), "production item registry loads")
	_check(BlockRegistryScript.has_block("glass_pane"), "canonical glass pane block is registered")
	_check(BlockRegistryScript.has_block("glass_pane_ns"), "rotated glass pane block is registered")
	_check(BlockRegistryScript.get_block_for_item("glass_pane") == "glass_pane", "glass pane item resolves to its canonical world block")
	_check(BlockRegistryScript.get_item_id("glass_pane") == "glass_pane", "canonical pane drops the glass pane item")
	_check(BlockRegistryScript.get_item_id("glass_pane_ns") == "glass_pane", "rotated pane drops the canonical glass pane item")
	_check(str(item_registry.get_item("glass_pane").get("block_id", "")) == "glass_pane", "item data points to the registered canonical pane")
	var legacy_last := BlockRegistryScript.get_numeric_id("oak_stairs_west")
	_check(BlockRegistryScript.get_numeric_id("glass_pane") > legacy_last, "pane numeric ID is appended after all legacy blocks")
	_check(BlockRegistryScript.get_numeric_id("glass_pane_ns") > BlockRegistryScript.get_numeric_id("glass_pane"), "rotated pane variant is appended after the canonical pane")


func _test_orientation_and_geometry() -> void:
	_check(OrientationPolicyScript.supports("glass_pane"), "orientation policy supports panes")
	_check(OrientationPolicyScript.resolve_for_forward("glass_pane", Vector3.BACK) == "glass_pane", "north-south player look places an east-west pane")
	_check(OrientationPolicyScript.resolve_for_forward("glass_pane", Vector3.FORWARD) == "glass_pane", "opposite north-south look shares the same pane axis")
	_check(OrientationPolicyScript.resolve_for_forward("glass_pane", Vector3.RIGHT) == "glass_pane_ns", "east-west player look rotates the pane axis")
	_check(OrientationPolicyScript.resolve_for_forward("glass_pane", Vector3.LEFT) == "glass_pane_ns", "opposite east-west look shares the rotated pane axis")
	_check(OrientationPolicyScript.canonical_block_id("glass_pane_ns") == "glass_pane", "rotated pane canonicalizes to the inventory item block")
	var ew_boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes("glass_pane")
	var ns_boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes("glass_pane_ns")
	_check(ew_boxes.size() == 1 and ns_boxes.size() == 1, "each pane uses one compact geometry box")
	_check(ew_boxes[0].size.is_equal_approx(Vector3(1.0, 1.0, 0.125)), "canonical pane is one eighth block thick on Z")
	_check(ns_boxes[0].size.is_equal_approx(Vector3(0.125, 1.0, 1.0)), "rotated pane is one eighth block thick on X")
	_check(is_equal_approx(ew_boxes[0].position.z, 0.4375), "canonical pane is centered in its voxel")
	_check(is_equal_approx(ns_boxes[0].position.x, 0.4375), "rotated pane remains centered after rotation")
	_check(ShapeGeometryScript.uses_partial_geometry("glass_pane"), "pane enters the shared partial geometry pipeline")
	_check(not ShapeGeometryScript.is_full_cube("glass_pane_ns"), "rotated pane is not treated as a full cube")


func _test_visual_harvest_and_preview() -> void:
	var visual_registry = VisualRegistryScript.new()
	_check(visual_registry.load_from_file(), "visual registry loads pane aliases")
	_check(visual_registry.get_validation_errors().is_empty(), "pane visual aliases satisfy the production contract")
	for block_id: String in ["glass_pane", "glass_pane_ns"]:
		for face_index in 6:
			_check(visual_registry.get_tile_id(block_id, face_index) == visual_registry.get_tile_id("glass", face_index), "%s inherits glass pixels on face %d" % [block_id, face_index])
	var harvest_registry = HarvestRegistryScript.new()
	for block_id: String in ["glass_pane", "glass_pane_ns"]:
		var profile := harvest_registry.get_profile(block_id)
		_check(str(profile.get("drop_item", "")) == "glass_pane", "%s harvest returns the canonical pane item" % block_id)
		_check(bool(profile.get("breakable", false)), "%s is breakable" % block_id)
	var policy = PlacementPolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[0,0,0],
		"hit_block_id":"stone",
		"placement_position":[1,0,0],
		"placement_target_block_id":"air",
	}
	for block_id: String in ["glass_pane", "glass_pane_ns"]:
		var preview: Dictionary = policy.evaluate(focus, block_id)
		_check(bool(preview.get("valid", false)), "%s has a valid production placement preview" % block_id)
		var boxes: Array = preview.get("placement_boxes", [])
		_check(boxes.size() == 1, "%s preview contains one thin box" % block_id)
		var size_value: Variant = boxes[0].get("size", []) if not boxes.is_empty() else []
		_check(size_value is Array and size_value.size() == 3, "%s preview serializes the thin box size" % block_id)


func _test_chunk_geometry(block_id: String, expected_size: Vector3) -> void:
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
	_check(chunk.surface_face_count == 6, "%s emits six exposed pane faces" % block_id)
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	_check(mesh_instance != null and mesh_instance.mesh != null, "%s builds a production visual mesh" % block_id)
	_check(collision != null and collision.shape != null, "%s builds production collision" % block_id)
	if mesh_instance != null and mesh_instance.mesh != null:
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_check(vertices.size() == 36, "%s emits complete pane triangle vertices" % block_id)
		var bounds := mesh_instance.mesh.get_aabb().size
		_check(bounds.is_equal_approx(expected_size), "%s visual bounds match its directional thin geometry" % block_id)
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
