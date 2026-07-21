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


func _init() -> void:
	soil_moisture = CachedSoilMoistureServiceScript.new()


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


func advance_time(seconds: float) -> void:
	if world == null or seconds <= 0.0:
		return
	var batch_started := _begin_world_batch("agriculture_advance")
	super.advance_time(seconds)
	_finish_world_batch(batch_started, "agriculture_advance")


func clear() -> void:
	super.clear()
	_reset_world_batch_runtime()


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
