extends "res://tests/qa/tutorial_placement_desktop_acceptance.gd"

# Stabilize the production player's body-yaw / CameraPivot-pitch hierarchy after
# a full menu reload. The base journey and every assertion remain unchanged.
# Held mining uses the same production PRIMARY_ACTION consumed by
# GameplayInputService and ControllerExplorationPlayer.

const HARVEST_TIMEOUT_MILLISECONDS := 15000
const AIM_REFRESH_MILLISECONDS := 250


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
	var target_world: Vector3 = world.call("block_to_world", target)
	if player != null:
		await _aim_at(player, target_world)

	# The production controller bridge maps this action into the same held state,
	# target resolution, harvest service, progress UI and completion path as a
	# physical primary button. No player or service method is invoked directly.
	Input.action_press(InputActions.PRIMARY_ACTION)
	await process_frame
	var deadline := Time.get_ticks_msec() + HARVEST_TIMEOUT_MILLISECONDS
	var next_aim_refresh := Time.get_ticks_msec() + AIM_REFRESH_MILLISECONDS
	while (
		str(world.call("get_block", target)) != "air"
		and Time.get_ticks_msec() < deadline
	):
		await process_frame
		if player != null and Time.get_ticks_msec() >= next_aim_refresh:
			await _aim_at(player, target_world)
			next_aim_refresh = Time.get_ticks_msec() + AIM_REFRESH_MILLISECONDS
	Input.action_release(InputActions.PRIMARY_ACTION)
	await process_frame
	await process_frame
