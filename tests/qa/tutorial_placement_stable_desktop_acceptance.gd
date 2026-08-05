extends "res://tests/qa/tutorial_placement_desktop_acceptance.gd"

# Stabilize the production player's body-yaw / CameraPivot-pitch hierarchy after
# a full menu reload. The base journey and every assertion remain unchanged.
# This adapter only prevents a transient Camera3D look_at transform from being
# overwritten while a real left-button harvest is held across physics frames.

const HARVEST_TIMEOUT_MILLISECONDS := 15000
const AIM_REFRESH_MILLISECONDS := 250
const DIAGNOSTIC_INTERVAL_MILLISECONDS := 500


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
	var inventory: Node = player.get("inventory") as Node if player != null else null
	var harvest: Node = player.get("harvest_service") as Node if player != null else null
	var selected_slot := int(inventory.get("selected_slot")) if inventory != null else -1
	var selected_item: Dictionary = (
		inventory.call("get_slot", selected_slot)
		if inventory != null and selected_slot >= 0
		else {}
	)
	print(
		"TUTORIAL HARVEST START | mouse=%d | input=%s | slot=%d | item=%s | focus=%s"
		% [
			Input.mouse_mode,
			str(player.get("input_enabled")) if player != null else "missing",
			selected_slot,
			str(selected_item.get("item_id", "")),
			str(player.call("get_interaction_focus")) if player != null else "{}",
		]
	)

	var center := root.get_visible_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	print(
		"TUTORIAL HARVEST PRESSED | held=%s | active=%s"
		% [
			str(player.get("_primary_action_held")) if player != null else "missing",
			str(harvest.call("get_active_snapshot")) if harvest != null else "{}",
		]
	)

	# Harvest progress is measured in elapsed seconds by the production service.
	# A frame-count timeout is invalid because desktop CI can run hundreds of
	# process frames per second. The policy hard-caps a block at 12 seconds, so a
	# 15-second monotonic deadline is both deterministic and strictly bounded.
	var deadline := Time.get_ticks_msec() + HARVEST_TIMEOUT_MILLISECONDS
	var next_aim_refresh := Time.get_ticks_msec() + AIM_REFRESH_MILLISECONDS
	var next_diagnostic := Time.get_ticks_msec() + DIAGNOSTIC_INTERVAL_MILLISECONDS
	while (
		str(world.call("get_block", target)) != "air"
		and Time.get_ticks_msec() < deadline
	):
		await process_frame
		if player != null and Time.get_ticks_msec() >= next_aim_refresh:
			await _aim_at(player, target_world)
			next_aim_refresh = Time.get_ticks_msec() + AIM_REFRESH_MILLISECONDS
		if Time.get_ticks_msec() >= next_diagnostic:
			print(
				"TUTORIAL HARVEST TICK | block=%s | held=%s | active=%s | focus=%s"
				% [
					str(world.call("get_block", target)),
					str(player.get("_primary_action_held")) if player != null else "missing",
					str(harvest.call("get_active_snapshot")) if harvest != null else "{}",
					str(player.call("get_interaction_focus")) if player != null else "{}",
				]
			)
			next_diagnostic = Time.get_ticks_msec() + DIAGNOSTIC_INTERVAL_MILLISECONDS

	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame
	print(
		"TUTORIAL HARVEST END | block=%s | held=%s | active=%s"
		% [
			str(world.call("get_block", target)),
			str(player.get("_primary_action_held")) if player != null else "missing",
			str(harvest.call("get_active_snapshot")) if harvest != null else "{}",
		]
	)
