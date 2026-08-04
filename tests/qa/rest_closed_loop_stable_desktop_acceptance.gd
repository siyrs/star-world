extends "res://tests/qa/rest_closed_loop_desktop_acceptance.gd"

# Preserve the complete bed/respawn/removal journey and every base assertion.
# The fixture stabilizes two continuously sampled systems on software CI:
# - force one real downward move_and_slide before sampling is_on_floor()
# - pause only DayNightService's natural _process ticks during a mouse click
# Direct RestService.skip_to_time() remains active, so successful night sleep still
# advances to morning while rejected beds cannot accumulate incidental frame drift.


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		player.velocity.y = minf(player.velocity.y, -0.5)
		player.move_and_slide()
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame
	player.velocity.y = -0.5
	player.move_and_slide()


func _right_click_center() -> void:
	var day_night := _find_day_night(root)
	var was_processing := false
	if day_night != null:
		was_processing = day_night.is_processing()
		day_night.set_process(false)
	await super._right_click_center()
	if day_night != null and is_instance_valid(day_night):
		day_night.set_process(was_processing)


func _find_day_night(node: Node) -> Node:
	if node == null:
		return null
	for property: Dictionary in node.get_property_list():
		if str(property.get("name", "")) == "day_night":
			var candidate: Variant = node.get("day_night")
			if candidate is Node and is_instance_valid(candidate):
				return candidate
	for child: Node in node.get_children():
		var found := _find_day_night(child)
		if found != null:
			return found
	return null
