extends "res://tests/qa/agriculture_closed_loop_desktop_acceptance.gd"

# Keep the production journey unchanged while stabilizing representation and
# geometry boundaries used by software-rendered CI:
# - full-inventory fixture metadata remains canonical across JSON
# - the player stands on a real lower observation floor while the target soil is
#   raised two blocks, so the centre ray can see the soil side even when the crop
#   cell intentionally contains the blocked-space stone fixture
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


func _build_farm_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var player_floor_y := clampi(origin.y - 3, 2, 56)
	var soil_y := player_floor_y + 2
	for x_offset in range(-5, 6):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(
				origin.x + x_offset,
				player_floor_y,
				origin.z + z_offset
			)
			world.call("set_block", floor_position, "stone")
			for y in range(player_floor_y + 1, mini(64, soil_y + 6)):
				world.call(
					"set_block",
					Vector3i(floor_position.x, y, floor_position.z),
					"air"
				)
	var soil_position := Vector3i(origin.x, soil_y, origin.z - 3)
	# The raised support keeps the soil authoritative in the live voxel world. Its
	# front face remains below the soil and therefore cannot intercept the ray.
	world.call("set_block", soil_position + Vector3i.DOWN, "stone")
	world.call("set_block", soil_position, "grass")
	world.call("set_block", soil_position + Vector3i.UP, "air")
	return {
		"player_position":Vector3(
			origin.x + 0.5,
			player_floor_y + 1.05,
			origin.z + 0.5
		),
		"soil_position":soil_position,
	}


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	var ray := player.get_node_or_null(
		"CameraPivot/Camera3D/InteractionRay"
	) as RayCast3D
	if camera == null or pivot == null or ray == null:
		await super._aim_at(player, target)
		return
	# The lower observation floor puts camera height inside the soil's side face.
	# A small downward bias avoids grazing the boundary with the blocked cell above.
	var aim_target := target + Vector3(0.0, -0.24, 0.0)
	var direction := aim_target - camera.global_position
	var horizontal := Vector2(direction.x, direction.z).length()
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := clampf(
		atan2(direction.y, maxf(0.0001, horizontal)),
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	player.call(
		"restore_orientation",
		{"rotation":[0.0, yaw, 0.0], "look_pitch":pitch}
	)
	camera.rotation = Vector3.ZERO
	await process_frame
	ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame
