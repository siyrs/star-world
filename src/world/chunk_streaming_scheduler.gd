class_name ChunkStreamingScheduler
extends RefCounted

var _queue: Array[Vector2i] = []
var _queued: Dictionary = {}
var _cursor := 0


func rebuild(
	wanted: Array[Vector2i], ready_chunks: Dictionary, building_chunks: Dictionary
) -> void:
	reset()
	for coord in wanted:
		if ready_chunks.has(coord) or building_chunks.has(coord):
			continue
		_queue.append(coord)
		_queued[coord] = true


func pop_next() -> Variant:
	while _cursor < _queue.size():
		var coord := _queue[_cursor]
		_cursor += 1
		if not _queued.has(coord):
			continue
		_queued.erase(coord)
		return coord
	return null


func remove(coord: Vector2i) -> void:
	_queued.erase(coord)


func contains(coord: Vector2i) -> bool:
	return _queued.has(coord)


func pending_count() -> int:
	return _queued.size()


func snapshot() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in range(_cursor, _queue.size()):
		var coord := _queue[index]
		if _queued.has(coord):
			result.append(coord)
	return result


func reset() -> void:
	_queue.clear()
	_queued.clear()
	_cursor = 0
