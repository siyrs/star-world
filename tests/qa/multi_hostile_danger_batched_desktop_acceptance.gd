extends "res://tests/qa/multi_hostile_danger_desktop_acceptance.gd"

const ArenaBatchPolicy = preload(
	"res://tests/qa/support/multi_hostile_arena_batch_policy.gd"
)
const ARENA_BATCH_REASON := "multi_hostile_danger_desktop_arena"
const ARENA_TIME_BUDGET_MILLISECONDS := 45000


func _build_flat_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	var player_position := Vector3(
		float(origin.x) + 0.5,
		float(floor_y) + 1.05,
		float(origin.z) + 0.5
	)
	var mutations: Array[Dictionary] = ArenaBatchPolicy.build_mutations(origin, floor_y)
	_check(
		mutations.size() == ArenaBatchPolicy.expected_mutation_count(),
		"desktop danger arena stays inside one bounded mutation batch"
	)
	if not world.has_method("apply_block_mutations"):
		_check(false, "production world exposes the bounded block mutation API")
		return {
			"player_position": player_position,
			"arena_elapsed_milliseconds": -1,
		}
	if world.has_method("reset_chunk_rebuild_stats"):
		world.call("reset_chunk_rebuild_stats")
	var started_at := Time.get_ticks_msec()
	var raw_result: Variant = world.call(
		"apply_block_mutations",
		mutations,
		ARENA_BATCH_REASON
	)
	var elapsed_milliseconds := maxi(0, Time.get_ticks_msec() - started_at)
	var result: Dictionary = raw_result if raw_result is Dictionary else {}
	_check(bool(result.get("success", false)), "production world accepts the arena mutation batch")
	_check(
		int(result.get("accepted", -1)) == mutations.size(),
		"production world accepts every arena mutation"
	)
	_check(
		int(result.get("truncated", -1)) == 0
		and int(result.get("rejected", -1)) == 0,
		"arena batching never truncates or rejects a production block mutation"
	)
	_check(
		int(result.get("changed", 0))
		+ int(result.get("unchanged", 0))
		+ int(result.get("rejected", 0))
		== int(result.get("accepted", -1)),
		"arena batch accounting covers every accepted mutation exactly once"
	)
	var raw_rebuild: Variant = result.get("rebuild", {})
	var rebuild: Dictionary = raw_rebuild if raw_rebuild is Dictionary else {}
	_check(
		int(rebuild.get("batch_depth", -1)) == 0
		and int(rebuild.get("pending_chunks", -1)) == 0,
		"arena batch flushes every dirty chunk before combat starts"
	)
	_check(
		int(rebuild.get("execution_count", mutations.size())) < mutations.size(),
		"arena rebuild work remains independent of the 2205 requested cell mutations"
	)
	_check(
		elapsed_milliseconds <= ARENA_TIME_BUDGET_MILLISECONDS,
		"arena batch completes inside the 45-second real desktop budget"
	)
	print(
		"QA MULTI HOSTILE ARENA BATCH | requested=%d | changed=%d | unchanged=%d | rebuilds=%d | coalesced=%d | elapsed_ms=%d"
		% [
			mutations.size(),
			int(result.get("changed", 0)),
			int(result.get("unchanged", 0)),
			int(rebuild.get("execution_count", 0)),
			int(rebuild.get("coalesced_count", 0)),
			elapsed_milliseconds,
		]
	)
	return {
		"player_position": player_position,
		"arena_elapsed_milliseconds": elapsed_milliseconds,
		"arena_result": result.duplicate(true),
	}
