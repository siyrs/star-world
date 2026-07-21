extends SceneTree

const BatchedWorldScript = preload("res://src/world/batched_voxel_world.gd")
const ScalableServiceScript = preload(
	"res://src/agriculture/scalable_agriculture_service.gd"
)
const ScalableParticipantScript = preload(
	"res://src/agriculture/scalable_agriculture_runtime_participant.gd"
)

const TEST_CROP_COUNT := 128
const TEST_Y := 30

var checks := 0
var failures: Array[String] = []


class FakeChunk:
	extends Node
	var blocks: Dictionary = {}
	var rebuild_count := 0

	func get_local_block(local_position: Vector3i) -> String:
		return str(blocks.get(_key(local_position), "air"))

	func set_local_block(
		local_position: Vector3i,
		block_id: String,
		_rebuild: bool = true
	) -> bool:
		var key := _key(local_position)
		if str(blocks.get(key, "air")) == block_id:
			return false
		blocks[key] = block_id
		return true

	func rebuild_mesh() -> void:
		rebuild_count += 1

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


class FakeAudio:
	extends Node
	var pickup_count := 0

	func play_pickup() -> void:
		pickup_count += 1


class FakeHub:
	extends Node
	var audio_service: Node
	var messages: Array[Dictionary] = []

	func _publish_character_message(
		message: String,
		severity: String,
		dedupe_key: String,
		duration: float
	) -> void:
		messages.append({
			"message": message,
			"severity": severity,
			"dedupe_key": dedupe_key,
			"duration": duration,
		})


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_growth_and_hydration_batching()
	await _test_exact_large_maturity_aggregation()
	if failures.is_empty():
		print("QA AGRICULTURE SCALE BATCH PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AGRICULTURE SCALE BATCH FAILURE: %s" % failure)
		print(
			"QA AGRICULTURE SCALE BATCH FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_growth_and_hydration_batching() -> void:
	var world = BatchedWorldScript.new()
	root.add_child(world)
	var chunk := _install_chunk(world, Vector2i.ZERO)
	var state := _farm_state(TEST_CROP_COUNT)
	_check(world.begin_chunk_rebuild_batch("agriculture_scale_fixture"), "fixture batch opens")
	for index in TEST_CROP_COUNT:
		var crop_position := _crop_position(index)
		world.set_block(crop_position + Vector3i.DOWN, "farmland_wet")
		world.set_block(crop_position, "wheat_stage_0")
	world.end_chunk_rebuild_batch(true)

	var service = ScalableServiceScript.new()
	root.add_child(service)
	await process_frame
	_check(service.deserialize(state), "scalable agriculture accepts the production state schema")
	world.reset_chunk_rebuild_stats()
	service.attach_world(world, null)
	var attached: Dictionary = service.get_runtime_snapshot()
	var moisture: Dictionary = attached.get("soil_refresh_cache", {})
	var last_refresh: Dictionary = moisture.get("last_refresh", {})
	_check(
		int(moisture.get("refresh_batch_count", 0)) == 1,
		"attach performs one authoritative soil refresh instead of the previous duplicate pass",
	)
	_check(
		int(last_refresh.get("cache_hits", 0)) > 0
		and int(last_refresh.get("sample_reads", 0)) < TEST_CROP_COUNT * 242,
		"overlapping soil refreshes reuse cached world samples",
	)

	var event_counter := {"count": 0}
	service.crop_stage_changed.connect(
		func(_position: Vector3i, _crop_id: String, _stage: int) -> void:
			event_counter["count"] = int(event_counter.get("count", 0)) + 1
	)
	chunk.rebuild_count = 0
	world.reset_chunk_rebuild_stats()
	service.advance_time(200.0)
	var mature_count := 0
	for index in TEST_CROP_COUNT:
		if int(service.get_crop_state(_crop_position(index)).get("stage", -1)) == 3:
			mature_count += 1
	var rebuild: Dictionary = world.get_chunk_rebuild_stats()
	_check(mature_count == TEST_CROP_COUNT, "all bounded test crops reach their final stage")
	_check(
		int(event_counter.get("count", 0)) == TEST_CROP_COUNT * 3,
		"canonical crop-stage signals remain visible for every real transition",
	)
	_check(
		chunk.rebuild_count == 1 and int(rebuild.get("execution_count", 0)) == 1,
		"one hundred twenty-eight crops mature through one loaded-chunk rebuild",
	)
	_check(
		int(rebuild.get("request_count", 0)) >= TEST_CROP_COUNT * 3
		and int(rebuild.get("coalesced_count", 0)) >= TEST_CROP_COUNT * 3 - 1,
		"growth diagnostics retain raw and coalesced rebuild evidence",
	)
	var runtime: Dictionary = service.get_runtime_snapshot()
	var batch: Dictionary = runtime.get("world_mutation_batch", {})
	_check(
		int(batch.get("started_count", 0)) >= 2
		and int(batch.get("flush_count", 0)) >= 1,
		"attach and growth expose bounded world-batch diagnostics",
	)
	var serialized := JSON.stringify(service.serialize())
	_check(
		not serialized.contains("world_mutation_batch")
		and not serialized.contains("soil_refresh_cache")
		and not serialized.contains("sample_cache"),
		"agriculture batching diagnostics remain transient",
	)
	service.clear()
	service.queue_free()
	world.clear_world()
	world.queue_free()
	await process_frame


func _test_exact_large_maturity_aggregation() -> void:
	var service = ScalableServiceScript.new()
	root.add_child(service)
	var hub := FakeHub.new()
	var audio := FakeAudio.new()
	hub.audio_service = audio
	root.add_child(hub)
	hub.add_child(audio)
	var participant = ScalableParticipantScript.new()
	root.add_child(participant)
	participant.set("hub", hub)
	participant.set("agriculture_service", service)
	participant.set("_active", true)
	for index in 2048:
		var crop_id := ["wheat", "carrot", "potato"][index % 3]
		participant.call(
			"_on_crop_stage_changed",
			Vector3i(index % 64, TEST_Y + 1, int(index / 64)),
			crop_id,
			3
		)
	var pending: Dictionary = participant.get_lifecycle_snapshot()
	_check(
		int(pending.get("pending_maturity_events", 0)) == 2048
		and int(pending.get("pending_maturity_samples", 0)) == 64,
		"large maturity aggregation retains exact totals with sixty-four bounded positions",
	)
	var summary: Dictionary = participant.call("flush_pending_maturity_batch")
	var counts: Dictionary = summary.get("counts", {})
	_check(
		int(summary.get("matured_count", 0)) == 2048
		and int(counts.get("wheat", 0))
		+ int(counts.get("carrot", 0))
		+ int(counts.get("potato", 0)) == 2048,
		"two thousand forty-eight maturity events remain fully counted",
	)
	_check(
		int(summary.get("sampled_position_count", 0)) == 64
		and int(summary.get("dropped_position_samples", 0)) == 1984,
		"only diagnostic positions are sampled while crop counts remain lossless",
	)
	_check(
		hub.messages.size() == 1 and audio.pickup_count == 1,
		"large maturity completion produces one player message and one audio cue",
	)
	var lifecycle: Dictionary = participant.get_lifecycle_snapshot()
	_check(
		int(lifecycle.get("matured_crop_total", 0)) == 2048
		and int(lifecycle.get("dropped_maturity_events", -1)) == 0,
		"lifecycle diagnostics distinguish exact events from dropped position samples",
	)
	participant.queue_free()
	hub.queue_free()
	service.queue_free()
	await process_frame


func _farm_state(crop_count: int) -> Dictionary:
	var crops: Dictionary = {}
	var soils: Dictionary = {}
	for index in crop_count:
		var crop_position := _crop_position(index)
		var soil_position := crop_position + Vector3i.DOWN
		crops["crop@%d,%d,%d" % [crop_position.x, crop_position.y, crop_position.z]] = {
			"crop_id": "wheat",
			"position": [crop_position.x, crop_position.y, crop_position.z],
			"stage": 0,
			"elapsed_seconds": 0.0,
		}
		soils["soil@%d,%d,%d" % [soil_position.x, soil_position.y, soil_position.z]] = {
			"position": [soil_position.x, soil_position.y, soil_position.z],
			"manual_remaining_seconds": 600.0,
			"hydrated": true,
		}
	return {
		"version": 2,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"crops": crops,
		"soil_moisture": {"version": 1, "soils": soils},
	}


func _crop_position(index: int) -> Vector3i:
	return Vector3i(index % 16, TEST_Y + 1, int(index / 16))


func _install_chunk(world: Node, coord: Vector2i) -> FakeChunk:
	var chunk := FakeChunk.new()
	chunk.name = "AgricultureScaleChunk_%d_%d" % [coord.x, coord.y]
	world.add_child(chunk)
	world.chunks[coord] = chunk
	return chunk


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
