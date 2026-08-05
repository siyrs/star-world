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


func _active_production_player() -> Node3D:
	# This script extends SceneTree, so the root Window is the authoritative
	# viewport. Resolve the active camera from that viewport rather than calling
	# Node.get_viewport(), which is not available on SceneTree.
	var camera := root.get_camera_3d() as Camera3D
	if camera == null:
		return null
	var pivot := camera.get_parent() as Node3D
	if pivot == null:
		return null
	return pivot.get_parent() as Node3D


func _hold_left_until_removed(world: Node, target: Vector3i) -> void:
	# The active viewport camera is the authoritative player identity after a full
	# menu reload. A global name search can observe a stale queued player during
	# scene replacement and start the input action against a different instance.
	var player := _active_production_player()
	var target_world: Vector3 = world.call("block_to_world", target)
	if player != null:
		await _aim_at(player, target_world)
	var ray := (
		player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
		if player != null
		else null
	)
	if ray != null:
		ray.force_raycast_update()
	await physics_frame

	var harvest: Node = player.get("harvest_service") as Node if player != null else null
	var ranged: Node = player.get("ranged_combat_service") as Node if player != null else null
	var equipment: Node = player.get("equipment_service") as Node if player != null else null
	var rejection_log: Array[Dictionary] = []
	if harvest != null:
		harvest.harvest_rejected.connect(
			func(reason: String, snapshot: Dictionary) -> void:
				rejection_log.append({"reason": reason, "snapshot": snapshot.duplicate(true)})
		)
	var collider: Variant = ray.get_collider() if ray != null and ray.is_colliding() else null
	print(
		"TUTORIAL PRIMARY PREFLIGHT | player=%s | ray=%s | collider=%s | damage=%s | target=%s | ranged=%s | main_hand=%s"
		% [
			str(player),
			str(ray != null and ray.is_colliding()),
			str(collider),
			str(collider != null and collider.has_method("take_damage")),
			str(player.call("_resolve_harvest_target")) if player != null else "{}",
			str(ranged.call("get_active_profile")) if ranged != null else "{}",
			str(equipment.call("get_slot", "main_hand")) if equipment != null else "{}",
		]
	)

	Input.action_press(InputActions.PRIMARY_ACTION, 1.0)
	for _frame in 3:
		await process_frame
	print(
		"TUTORIAL PRIMARY AFTER PRESS | controller=%s | held=%s | harvest=%s | rejections=%s"
		% [
			str(player.call("get_controller_gameplay_snapshot")) if player != null else "{}",
			str(player.get("_primary_action_held")) if player != null else "missing",
			str(harvest.call("get_active_snapshot")) if harvest != null else "{}",
			str(rejection_log),
		]
	)
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
	for _frame in 3:
		await process_frame
	print(
		"TUTORIAL PRIMARY END | block=%s | held=%s | harvest=%s | rejections=%s"
		% [
			str(world.call("get_block", target)),
			str(player.get("_primary_action_held")) if player != null else "missing",
			str(harvest.call("get_active_snapshot")) if harvest != null else "{}",
			str(rejection_log),
		]
	)
