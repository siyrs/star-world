class_name WorldRuntimeGuard
extends RefCounted


func validate_world(world: Node) -> Dictionary:
	if world == null:
		return _failure("world_missing")
	if not bool(world.get("is_started")):
		return _failure("world_not_started")
	if not world.has_method("get_loaded_chunk_count"):
		return _failure("world_chunk_contract_missing")
	if int(world.call("get_loaded_chunk_count")) <= 0:
		return _failure("spawn_chunk_missing")
	var chunks = world.get("chunks")
	if chunks is not Dictionary or chunks.is_empty():
		return _failure("spawn_chunk_registry_empty")
	var candidate = chunks.values()[0]
	if not is_instance_valid(candidate):
		return _failure("spawn_chunk_invalid")
	if candidate.has_method("is_build_complete") and not bool(candidate.call("is_build_complete")):
		return _failure("spawn_chunk_incomplete")
	if int(candidate.get("surface_face_count")) <= 0:
		return _failure("spawn_chunk_has_no_faces")
	var mesh_instance := candidate.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return _failure("spawn_chunk_mesh_missing")
	var collision := candidate.get_node_or_null("Collision") as CollisionShape3D
	if collision == null or collision.shape == null:
		return _failure("spawn_chunk_collision_missing")
	return {"ok": true, "reason": ""}


func activate_and_validate_camera(player: Node3D) -> Dictionary:
	if player == null:
		return _failure("player_missing")
	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if camera == null:
		return _failure("camera_missing")
	camera.current = true
	camera.make_current()
	var viewport := player.get_viewport()
	if viewport == null:
		return _failure("viewport_missing")
	if viewport.get_camera_3d() != camera:
		return _failure("camera_not_current")
	return {"ok": true, "reason": "", "camera": camera}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
