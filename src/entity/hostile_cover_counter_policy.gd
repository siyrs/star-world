class_name HostileCoverCounterPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const MAX_LINE_SAMPLE_STEPS := 64
const MAX_BREAK_BLOCKS_PER_ATTACK := 2
const MAX_BREAK_BLOCKS_PER_BRUTE := 12
const MAX_REPOSITION_PROBES := 6
const MAX_REPOSITION_ATTEMPTS_PER_TARGET := 4
const REPOSITION_DELAY_SECONDS := 1.8
const REPOSITION_COOLDOWN_SECONDS := 3.0
const REPOSITION_RADIUS := 4.5

# Only explicit, cheap, player-authored temporary cover is destructible. Permanent
# bases, machines, doors, fences, terrain and generated decoration remain protected.
const BREAKABLE_COVER_IDS: Array[String] = [
	"wool",
	"glass_pane",
	"glass_pane_ns",
]

const WALK_HAZARD_IDS: Array[String] = [
	"water",
	"lava",
	"cactus",
]


static func is_breakable_cover(block_id: String) -> bool:
	return block_id in BREAKABLE_COVER_IDS


static func is_walk_hazard(block_id: String) -> bool:
	return block_id in WALK_HAZARD_IDS


static func line_samples(
	start: Vector3,
	finish: Vector3,
	maximum_steps: int = MAX_LINE_SAMPLE_STEPS
) -> Array[Dictionary]:
	var distance := start.distance_to(finish)
	var bounded_maximum := clampi(maximum_steps, 1, MAX_LINE_SAMPLE_STEPS)
	var step_count := clampi(ceili(distance * 2.0), 1, bounded_maximum)
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for step_index in range(1, step_count):
		var ratio := float(step_index) / float(step_count)
		var point := start.lerp(finish, ratio)
		var position := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		var key := "%d,%d,%d" % [position.x, position.y, position.z]
		if seen.has(key):
			continue
		seen[key] = true
		result.append({
			"position": position,
			"local_height": point.y - floorf(point.y),
			"distance_from_start": start.distance_to(point),
		})
	return result


static func blocks_projectile_lane(block_id: String, local_height: float = 0.5) -> bool:
	if block_id.is_empty() or block_id in ["air", "water", "lava"]:
		return false
	if _is_open_door(block_id):
		return false
	if block_id == "stone_slab":
		return local_height <= 0.55
	return BlockRegistryScript.is_solid(block_id)


static func blocks_walk_lane(block_id: String, local_height: float = 0.5) -> bool:
	# Fluids have no solid collision, but a marksman must never select a route that
	# intentionally walks through water or lava. This differs from projectile LOS.
	if is_walk_hazard(block_id):
		return true
	if block_id.is_empty() or block_id == "air":
		return false
	if _is_open_door(block_id):
		return false
	if block_id == "stone_slab":
		return local_height <= 0.55
	return BlockRegistryScript.is_solid(block_id)


static func is_safe_reposition_support(block_id: String) -> bool:
	return (
		BlockRegistryScript.is_solid(block_id)
		and block_id not in ["leaves", "cactus", "glow_crystal"]
	)


static func can_attempt_reposition(
	blocked_seconds: float,
	cooldown_seconds: float,
	attempt_count: int
) -> bool:
	return (
		blocked_seconds >= REPOSITION_DELAY_SECONDS
		and cooldown_seconds <= 0.0
		and attempt_count < MAX_REPOSITION_ATTEMPTS_PER_TARGET
	)


static func reposition_directions(
	to_target: Vector3,
	probe_count: int = MAX_REPOSITION_PROBES
) -> Array[Vector3]:
	var forward := Vector3(to_target.x, 0.0, to_target.z)
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var candidates: Array[Vector3] = [
		side,
		-side,
		(side - forward * 0.35).normalized(),
		(-side - forward * 0.35).normalized(),
		(side + forward * 0.25).normalized(),
		(-side + forward * 0.25).normalized(),
	]
	var result: Array[Vector3] = []
	for index in mini(candidates.size(), clampi(probe_count, 0, MAX_REPOSITION_PROBES)):
		result.append(candidates[index])
	return result


static func _is_open_door(block_id: String) -> bool:
	return (
		block_id.begins_with("oak_door_open")
		or block_id.begins_with("oak_door_upper_open")
	)
