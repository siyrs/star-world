extends "res://tests/qa/tutorial_placement_desktop_acceptance.gd"

# Stabilize the production player's body-yaw / CameraPivot-pitch hierarchy after
# a full menu reload. The base journey and every assertion remain unchanged.
# This adapter only prevents a transient Camera3D look_at transform from being
# overwritten while a real left-button harvest is held across physics frames.


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	var ray := player.get_node_or_null(
		"CameraPivot/Camera3D/InteractionRay"
	) as RayCast3D
	if camera == null or pivot == null or ray == null:
		return
	var direction := target - camera.global_position
	var horizontal := Vector2(direction.x, direction.z).length()
	player.rotation.y = atan2(-direction.x, -direction.z)
	pivot.rotation.x = clampf(
		atan2(direction.y, maxf(0.0001, horizontal)),
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	camera.rotation = Vector3.ZERO
	await physics_frame
	await process_frame
	ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _hold_left_until_removed(world: Node, target: Vector3i) -> void:
	var player := root.find_child("Player", true, false) as Node3D
	if player != null:
		await _aim_at(player, world.call("block_to_world", target))
	var center := root.get_visible_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	for frame_index in MAX_HARVEST_FRAMES:
		await process_frame
		if str(world.call("get_block", target)) == "air":
			break
		if player != null and (frame_index + 1) % 30 == 0:
			await _aim_at(player, world.call("block_to_world", target))
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame
