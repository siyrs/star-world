extends "res://tests/qa/rest_closed_loop_desktop_acceptance.gd"

# Preserve the complete bed/respawn/removal journey and every base assertion.
# The fixture stabilizes two continuously sampled systems on software CI:
# - force one real downward move_and_slide before sampling is_on_floor()
# - pause only DayNightService's natural _process ticks from target aim through
#   the matching mouse click
# Direct RestService.skip_to_time() remains active, so successful night sleep still
# advances to morning while a rejected bed cannot accumulate incidental frame drift.

var _paused_day_night: Node
var _paused_day_night_was_processing := false


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


func _aim_at(player: Node3D, target: Vector3) -> void:
	_pause_passive_clock()
	await super._aim_at(player, target)


func _right_click_center() -> void:
	if _paused_day_night == null:
		_pause_passive_clock()
	await super._right_click_center()
	_restore_passive_clock()


func _pause_passive_clock() -> void:
	if _paused_day_night != null and is_instance_valid(_paused_day_night):
		return
	_paused_day_night = _find_day_night(root)
	if _paused_day_night == null:
		return
	_paused_day_night_was_processing = _paused_day_night.is_processing()
	_paused_day_night.set_process(false)


func _restore_passive_clock() -> void:
	if _paused_day_night != null and is_instance_valid(_paused_day_night):
		_paused_day_night.set_process(_paused_day_night_was_processing)
	_paused_day_night = null
	_paused_day_night_was_processing = false


func _find_day_night(node: Node) -> Node:
	if node == null:
		return null
	if node is DayNightService:
		return node
	for child: Node in node.get_children():
		var found := _find_day_night(child)
		if found != null:
			return found
	return null
