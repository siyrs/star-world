extends SceneTree

const ResolverScript = preload("res://src/player/player_spawn_resolver.gd")
const WorldScript = preload("res://src/world/voxel_world.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class FlatWorld:
	extends Node

	func get_block(position: Vector3i) -> String:
		return "stone" if position.y <= 0 else "air"

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, 1.05, candidate.z)


func _initialize() -> void:
	var world := FlatWorld.new()
	var resolver = ResolverScript.new()
	var seam_position := Vector3(-0.32804477, 1.05, -0.32514107)
	var resolved: Vector3 = resolver.resolve(
		world, seam_position, Vector3(4.5, 1.05, 4.5)
	)
	_check(is_equal_approx(resolved.x, -0.56), "negative X seam uses a safe interior offset")
	_check(is_equal_approx(resolved.z, -0.56), "negative Z seam uses a safe interior offset")
	_check(is_equal_approx(resolved.y, 1.05), "seam recovery resolves a stable ground height")
	var centered: Vector3 = resolver.resolve(
		world, Vector3(2.5, 1.05, 3.5), Vector3(4.5, 1.05, 4.5)
	)
	_check(centered == Vector3(2.5, 1.05, 3.5), "already centered saves stay unchanged")
	var generated_world = WorldScript.new()
	root.add_child(generated_world)
	generated_world.start_world(
		"star_continent",
		1088352404,
		"spawn-seam-real-world",
		{
			"world": {
				"block_overrides": {
					"-2,21,-5": "planks",
					"-2,21,-4": "planks",
					"-1,21,-3": "planks",
				}
			}
		}
	)
	var saved_position := Vector3(-0.32804477, 21.6444416, -0.32514107)
	var real_resolved: Vector3 = resolver.resolve(
		generated_world, saved_position, generated_world.get_spawn_position()
	)
	print("QA SPAWN REAL RESOLVE | saved=%s resolved=%s" % [saved_position, real_resolved])
	_check(
		not real_resolved.is_equal_approx(saved_position),
		"the affected completed save is moved away from its wedged position"
	)
	_check(
		real_resolved.x <= -1.5 and real_resolved.z <= -1.5,
		"the affected completed save moves away from the obstructed terrain corner"
	)
	_check(
		resolver.is_position_clear(generated_world, real_resolved),
		"the recovered completed-save position has body clearance"
	)
	_check(
		resolver.is_position_supported(generated_world, real_resolved),
		"the recovered completed-save position has terrain support"
	)
	var player := PlayerScene.instantiate()
	root.add_child(player)
	var player_collision := player.get_node("CollisionShape3D") as CollisionShape3D
	_check(
		player_collision != null and player_collision.shape is CylinderShape3D,
		"the player uses a flat-bottomed collider that does not catch voxel triangle seams"
	)
	_check(
		is_zero_approx(player.floor_snap_length),
		"the player avoids engine floor snap against voxel triangle and step edges"
	)
	player.queue_free()
	generated_world.queue_free()
	if failures.is_empty():
		print("QA SPAWN SEAM PASS | checks=%d" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("QA SPAWN SEAM FAILURE: %s" % failure)
	print("QA SPAWN SEAM FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
