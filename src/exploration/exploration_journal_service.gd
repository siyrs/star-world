class_name ExplorationJournalService
extends Node

signal journal_changed(snapshot: Dictionary)

const RegistryScript = preload("res://src/exploration/exploration_journal_registry.gd")
const PolicyScript = preload("res://src/exploration/exploration_journal_policy.gd")

var registry = RegistryScript.new()
var prospecting_service: Node
var _snapshot: Dictionary = {}


func setup(p_prospecting_service: Node) -> bool:
	_disconnect_prospecting()
	prospecting_service = p_prospecting_service
	if prospecting_service != null and prospecting_service.has_signal("scan_completed"):
		prospecting_service.connect(
			"scan_completed", Callable(self, "_on_scan_completed")
		)
	refresh()
	return registry.get_validation_errors().is_empty()


func refresh() -> Dictionary:
	var records: Array = []
	if prospecting_service != null and prospecting_service.has_method("get_records"):
		var raw_records: Variant = prospecting_service.call("get_records")
		if raw_records is Array:
			records = raw_records
	var next_snapshot := PolicyScript.build_snapshot(records, registry.get_config())
	if next_snapshot != _snapshot:
		_snapshot = next_snapshot.duplicate(true)
		journal_changed.emit(_snapshot.duplicate(true))
	return _snapshot.duplicate(true)


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_validation_errors() -> Array[String]:
	return registry.get_validation_errors()


func clear() -> void:
	if _snapshot.is_empty():
		return
	_snapshot.clear()
	journal_changed.emit({})


func _on_scan_completed(_result: Dictionary) -> void:
	refresh()


func _disconnect_prospecting() -> void:
	if prospecting_service == null or not prospecting_service.has_signal("scan_completed"):
		return
	var callback := Callable(self, "_on_scan_completed")
	if prospecting_service.is_connected("scan_completed", callback):
		prospecting_service.disconnect("scan_completed", callback)


func _exit_tree() -> void:
	_disconnect_prospecting()
