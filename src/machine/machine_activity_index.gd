class_name MachineActivityIndex
extends RefCounted

const MAX_TRACKED_IDS := 4096
const MAX_ID_LENGTH := 128

var _members: Dictionary = {}
var _order: Array[String] = []
var _dirty := false
var _add_count := 0
var _remove_count := 0
var _sort_count := 0
var _rebuild_count := 0
var _capacity_rejection_count := 0
var _max_member_count := 0


func set_active(machine_id: String, active: bool) -> bool:
	var normalized := machine_id.strip_edges()
	if normalized.is_empty() or normalized.length() > MAX_ID_LENGTH:
		return false
	if active:
		if _members.has(normalized):
			return false
		if _members.size() >= MAX_TRACKED_IDS:
			_capacity_rejection_count += 1
			return false
		_members[normalized] = true
		_order.append(normalized)
		_dirty = true
		_add_count += 1
		_max_member_count = maxi(_max_member_count, _members.size())
		return true
	if not _members.has(normalized):
		return false
	_members.erase(normalized)
	_order.erase(normalized)
	_remove_count += 1
	return true


func rebuild(active_ids: Array) -> void:
	_members.clear()
	_order.clear()
	_dirty = false
	for raw_id: Variant in active_ids:
		var machine_id := str(raw_id).strip_edges()
		if (
			machine_id.is_empty()
			or machine_id.length() > MAX_ID_LENGTH
			or _members.has(machine_id)
		):
			continue
		if _members.size() >= MAX_TRACKED_IDS:
			_capacity_rejection_count += 1
			break
		_members[machine_id] = true
		_order.append(machine_id)
	_dirty = _order.size() > 1
	_rebuild_count += 1
	_max_member_count = maxi(_max_member_count, _members.size())


func ordered_ids_view() -> Array[String]:
	_ensure_sorted()
	return _order


func contains(machine_id: String) -> bool:
	return _members.has(machine_id)


func size() -> int:
	return _members.size()


func clear() -> void:
	_members.clear()
	_order.clear()
	_dirty = false
	_add_count = 0
	_remove_count = 0
	_sort_count = 0
	_rebuild_count = 0
	_capacity_rejection_count = 0
	_max_member_count = 0


func get_snapshot() -> Dictionary:
	return {
		"member_count": _members.size(),
		"dirty": _dirty,
		"add_count": _add_count,
		"remove_count": _remove_count,
		"sort_count": _sort_count,
		"rebuild_count": _rebuild_count,
		"capacity_rejection_count": _capacity_rejection_count,
		"max_member_count": _max_member_count,
		"max_tracked_ids": MAX_TRACKED_IDS,
	}


func _ensure_sorted() -> void:
	if not _dirty:
		return
	_order.sort()
	_dirty = false
	_sort_count += 1
