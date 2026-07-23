class_name ScalableAgricultureService
extends "res://src/agriculture/fertilizable_agriculture_service.gd"

const CachedSoilMoistureServiceScript = preload(
	"res://src/agriculture/cached_soil_moisture_service.gd"
)
const MAX_BATCH_REASON_LENGTH := 64

var _world_batch_attempt_count := 0
var _world_batch_started_count := 0
var _world_batch_flush_count := 0
var _world_batch_rejection_count := 0
var _world_batch_unsupported_count := 0
var _last_world_batch: Dictionary = {}
var _health_mature_crop_count := 0
var _health_snapshot_count := 0


func _init() -> void:
	soil_moisture = CachedSoilMoistureServiceScript.new()


func _ready() -> void:
	super._ready()
	var stage_callback := Callable(self, "_on_health_crop_stage_changed")
	if not crop_stage_changed.is_connected(stage_callback):
		crop_stage_changed.connect(stage_callback)
	var harvest_callback := Callable(self, "_on_health_crop_harvested")
	if not crop_harvested.is_connected(harvest_callback):
		crop_harvested.connect(harvest_callback)


func attach_world(p_world: Node, p_inventory: Node) -> void:
	world = p_world
	inventory = p_inventory
	if world == null:
		soil_moisture.detach_world()
		return
	var batch_started := _begin_world_batch("agriculture_attach")
	if soil_moisture.has_method("attach_world_without_refresh"):
		soil_moisture.call("attach_world_without_refresh", world)
	else:
		soil_moisture.attach_world(world)
	_sync_world_from_state()
	soil_moisture.refresh_all()
	if _offline_seconds > 0.0:
		super.advance_time(_offline_seconds)
		_offline_seconds = 0.0
	_finish_world_batch(batch_started, "agriculture_attach")
	_recount_health_mature_crops()


func deserialize(data: Dictionary) -> bool:
	var success := super.deserialize(data)
	_recount_health_mature_crops()
	return success


func advance_time(seconds: float) -> void:
	if world == null or seconds <= 0.0:
		return
	var crop_count_before := _crops.size()
	var batch_started := _begin_world_batch("agriculture_advance")
	super.advance_time(seconds)
	_finish_world_batch(batch_started, "agriculture_advance")
	if _crops.size() != crop_count_before:
		_recount_health_mature_crops()


func clear() -> void:
	super.clear()
	_reset_world_batch_runtime()
	_health_mature_crop_count = 0
	_health_snapshot_count = 0


func on_block_removed(p_world: Node, block_position: Vector3i, block_id: String) -> void:
	var crop_count_before := _crops.size()
	super.on_block_removed(p_world, block_position, block_id)
	if _crops.size() != crop_count_before:
		_recount_health_mature_crops()


func get_health_snapshot() -> Dictionary:
	_health_snapshot_count += 1
	return {
		"schema_version": 1,
		"active": _runtime_active,
		"shutdown": _shutdown,
		"world_attached": world != null and is_instance_valid(world),
		"crop_count": _crops.size(),
		"mature_crop_count": _health_mature_crop_count,
		"soil_count": soil_moisture.get_soil_count(),
		"atomic_harvest_rejection_count": _atomic_harvest_rejection_count,
		"world_mutation_batch": {
			"rejection_count": _world_batch_rejection_count,
			"unsupported_count": _world_batch_unsupported_count,
		},
		"health_snapshot_count": _health_snapshot_count,
	}


func get_runtime_snapshot() -> Dictionary:
	var result: Dictionary = super.get_runtime_snapshot()
	result["world_mutation_batch"] = get_world_mutation_batch_snapshot()
	result["soil_refresh_cache"] = (
		soil_moisture.call("get_runtime_snapshot")
		if soil_moisture != null and soil_moisture.has_method("get_runtime_snapshot")
		else {}
	)
	return result


func get_world_mutation_batch_snapshot() -> Dictionary:
	return {
		"attempt_count": _world_batch_attempt_count,
		"started_count": _world_batch_started_count,
		"flush_count": _world_batch_flush_count,
		"rejection_count": _world_batch_rejection_count,
		"unsupported_count": _world_batch_unsupported_count,
		"last_batch": _last_world_batch.duplicate(true),
	}


func _on_health_crop_stage_changed(
	_position: Vector3i, crop_id: String, stage: int
) -> void:
	var definition: Dictionary = crop_registry.get_crop(crop_id)
	var stages: Array = definition.get("stage_blocks", [])
	if not stages.is_empty() and stage >= stages.size() - 1:
		_health_mature_crop_count = mini(_crops.size(), _health_mature_crop_count + 1)


func _on_health_crop_harvested(
	_position: Vector3i, _crop_id: String, _outputs: Array
) -> void:
	_health_mature_crop_count = maxi(0, _health_mature_crop_count - 1)


func _recount_health_mature_crops() -> void:
	var mature_count := 0
	for raw_state: Variant in _crops.values():
		if raw_state is Dictionary and _is_health_mature_state(raw_state):
			mature_count += 1
	_health_mature_crop_count = mini(_crops.size(), mature_count)


func _is_health_mature_state(state: Dictionary) -> bool:
	var crop_id := str(state.get("crop_id", ""))
	var definition: Dictionary = crop_registry.get_crop(crop_id)
	var stages: Array = definition.get("stage_blocks", [])
	return (
		not stages.is_empty()
		and int(state.get("stage", 0)) >= stages.size() - 1
	)


func _begin_world_batch(reason: String) -> bool:
	_world_batch_attempt_count += 1
	if (
		world == null
		or not world.has_method("begin_chunk_rebuild_batch")
		or not world.has_method("end_chunk_rebuild_batch")
	):
		_world_batch_unsupported_count += 1
		_last_world_batch = {
			"reason": reason.left(MAX_BATCH_REASON_LENGTH),
			"supported": false,
			"started": false,
		}
		return false
	var started := bool(
		world.call("begin_chunk_rebuild_batch", reason.left(MAX_BATCH_REASON_LENGTH))
	)
	if started:
		_world_batch_started_count += 1
	else:
		_world_batch_rejection_count += 1
	_last_world_batch = {
		"reason": reason.left(MAX_BATCH_REASON_LENGTH),
		"supported": true,
		"started": started,
	}
	return started


func _finish_world_batch(started: bool, reason: String) -> void:
	if not started or world == null or not world.has_method("end_chunk_rebuild_batch"):
		return
	var raw_result: Variant = world.call("end_chunk_rebuild_batch", true)
	var result: Dictionary = raw_result if raw_result is Dictionary else {}
	if not bool(result.get("success", false)):
		_world_batch_rejection_count += 1
	if bool(result.get("flushed", false)):
		_world_batch_flush_count += 1
	_last_world_batch = {
		"reason": reason.left(MAX_BATCH_REASON_LENGTH),
		"supported": true,
		"started": true,
		"success": bool(result.get("success", false)),
		"flushed": bool(result.get("flushed", false)),
		"pending_chunks": int(result.get("pending_chunks", 0)),
		"executed_chunks": int(result.get("executed_chunks", 0)),
		"elapsed_usec": int(result.get("elapsed_usec", 0)),
		"stats": (
			(result.get("stats", {}) as Dictionary).duplicate(true)
			if result.get("stats", {}) is Dictionary
			else {}
		),
	}


func _reset_world_batch_runtime() -> void:
	_world_batch_attempt_count = 0
	_world_batch_started_count = 0
	_world_batch_flush_count = 0
	_world_batch_rejection_count = 0
	_world_batch_unsupported_count = 0
	_last_world_batch.clear()
