class_name BatchedBlockStructureIntegrityService
extends "res://src/interaction/block_structure_integrity_service.gd"

const PRE_FLUSH_SIGNAL := "block_mutation_batch_pre_flush"

var _pre_flush_signal_count := 0
var _pre_flush_cleanup_count := 0
var _last_pre_flush_summary: Dictionary = {}
var _last_pre_flush_result: Dictionary = {}


func bind_world(p_world: Node) -> bool:
	var bound := super.bind_world(p_world)
	if not bound:
		return false
	_connect_pre_flush()
	return true


func clear(reset_counters: bool = true) -> void:
	super.clear(reset_counters)
	if reset_counters:
		_pre_flush_signal_count = 0
		_pre_flush_cleanup_count = 0
		_last_pre_flush_summary.clear()
		_last_pre_flush_result.clear()


func get_snapshot() -> Dictionary:
	var result: Dictionary = super.get_snapshot()
	result["pre_flush_supported"] = (
		world != null
		and is_instance_valid(world)
		and world.has_signal(PRE_FLUSH_SIGNAL)
	)
	result["pre_flush_signal_count"] = _pre_flush_signal_count
	result["pre_flush_cleanup_count"] = _pre_flush_cleanup_count
	result["last_pre_flush_summary"] = _last_pre_flush_summary.duplicate(true)
	result["last_pre_flush_result"] = _last_pre_flush_result.duplicate(true)
	return result


func _disconnect_world() -> void:
	_disconnect_pre_flush()
	super._disconnect_world()


func _connect_pre_flush() -> void:
	if (
		world == null
		or not is_instance_valid(world)
		or not world.has_signal(PRE_FLUSH_SIGNAL)
	):
		return
	var callback := Callable(self, "_on_block_mutation_batch_pre_flush")
	if not world.is_connected(PRE_FLUSH_SIGNAL, callback):
		world.connect(PRE_FLUSH_SIGNAL, callback)


func _disconnect_pre_flush() -> void:
	if (
		world == null
		or not is_instance_valid(world)
		or not world.has_signal(PRE_FLUSH_SIGNAL)
	):
		return
	var callback := Callable(self, "_on_block_mutation_batch_pre_flush")
	if world.is_connected(PRE_FLUSH_SIGNAL, callback):
		world.disconnect(PRE_FLUSH_SIGNAL, callback)


func _on_block_mutation_batch_pre_flush(
	_reason: String,
	summary: Dictionary
) -> void:
	_pre_flush_signal_count += 1
	_last_pre_flush_summary = summary.duplicate(true)
	if _shutdown or _applying_cleanup or _pending_candidates.is_empty():
		return
	_pre_flush_cleanup_count += 1
	_last_pre_flush_result = flush_pending()
