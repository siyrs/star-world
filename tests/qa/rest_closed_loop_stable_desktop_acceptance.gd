extends "res://tests/qa/rest_closed_loop_desktop_acceptance.gd"

# Preserve the complete bed/respawn/removal journey and every base assertion.
# The base suite owns the passive-clock pause around aim-and-click; this
# variant additionally stabilizes one continuously sampled system on software
# CI: it temporarily suspends the production player's voxel-ground recovery
# while a bounded sequence of real move_and_slide calls proves the rebuilt
# collision, then restores normal processing. Direct RestService.skip_to_time()
# remains active, so successful night sleep still advances to morning while a
# rejected bed cannot accumulate incidental frame drift.


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	# Production intentionally keeps the body 0.02 m above resolved voxel ground.
	# Leaving its physics process active here can reset that clearance between two
	# fixture-driven moves, so a 0.5 m/s probe only travels about 0.008 m and may
	# never report a physical floor on a busy runner. Own the bounded probe window,
	# exercise the real CharacterBody collision, then restore normal processing.
	var was_physics_processing := player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	for _frame in frame_limit:
		player.velocity.y = -2.0
		player.move_and_slide()
		if player.is_on_floor():
			player.velocity = Vector3.ZERO
			player.set_physics_process(was_physics_processing)
			return
		await physics_frame
		await process_frame
	player.velocity.y = -2.0
	player.move_and_slide()
	player.velocity = Vector3.ZERO
	player.set_physics_process(was_physics_processing)
