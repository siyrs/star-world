extends "res://tests/qa/husbandry_closed_loop_desktop_acceptance.gd"

# Preserve the complete production journey and every base assertion. The fixture
# only makes the initial collision contact deterministic on software-rendered CI:
# CharacterBody3D receives a real downward move_and_slide before the base test
# samples is_on_floor(). No animal, inventory, world or husbandry state is changed.


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		player.velocity.y = minf(player.velocity.y, -0.5)
		player.move_and_slide()
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame
	# Leave the final floor flag sourced from a real collision query immediately
	# before the inherited assertion rather than from a stale previous frame.
	player.velocity.y = -0.5
	player.move_and_slide()
