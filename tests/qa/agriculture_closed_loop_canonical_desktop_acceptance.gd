extends "res://tests/qa/agriculture_closed_loop_desktop_acceptance.gd"

# Keep the production journey unchanged while stabilizing two representation
# boundaries used by software-rendered CI:
# - full-inventory fixture metadata remains canonical across JSON
# - aiming writes the production player's body yaw and CameraPivot pitch rather
#   than a transient Camera3D look_at transform
# The interaction is still completed by the real centre ray, right-click input and
# production agriculture adapter; no domain result is called or forced directly.


func _fill_full_harvest_inventory(inventory: Node) -> void:
	inventory.clear()
	inventory.call("add_item", "wheat_seeds", 1)
	for index in 35:
		inventory.call(
			"add_item",
			"wooden_pickaxe",
			1,
			{"fixture_slot":"agriculture_%02d" % index},
		)


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	var ray := player.get_node_or_null(
		"CameraPivot/Camera3D/InteractionRay"
	) as RayCast3D
	if camera == null or pivot == null or ray == null:
		await super._aim_at(player, target)
		return
	# Aim at the lower half of the supporting soil. This remains visible even when
	# the crop cell contains the deliberate blocked-space fixture, and production
	# focus resolution will proxy a planted non-colliding crop from the same soil.
	var aim_target := target + Vector3(0.0, -0.32, 0.0)
	var direction := aim_target - camera.global_position
	var horizontal := Vector2(direction.x, direction.z).length()
	player.rotation.y = atan2(-direction.x, -direction.z)
	pivot.rotation.x = clampf(
		atan2(direction.y, maxf(0.0001, horizontal)),
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	camera.rotation = Vector3.ZERO
	await process_frame
	ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame
