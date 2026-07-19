class_name ServiceHubFeatureCoordinator
extends Node

signal participant_registered(participant_id: StringName, participant: Node)
signal lifecycle_phase_completed(phase: StringName, participant_ids: Array[String])

const REQUIRED_METHODS: Array[String] = [
	"install",
	"begin_world",
	"attach_game",
	"activate",
	"save_into",
	"snapshot_into",
	"clear",
	"shutdown",
]
const MAX_PHASE_HISTORY := 48

var hub: Node
var _participants: Array[Node] = []
var _participants_by_id: Dictionary = {}
var _dependencies_by_id: Dictionary = {}
var _phase_counts: Dictionary = {}
var _phase_history: Array[String] = []
var _shutdown := false


func setup(p_hub: Node) -> void:
	hub = p_hub
	_shutdown = false


func register_participant(participant_id: StringName, participant: Node) -> Dictionary:
	var normalized_id := str(participant_id).strip_edges()
	if normalized_id.is_empty():
		return _failure("invalid_participant_id")
	if _shutdown:
		return _failure("coordinator_shutdown", {"participant_id": normalized_id})
	if _participants_by_id.has(normalized_id):
		return _failure("duplicate_participant", {"participant_id": normalized_id})
	if participant == null or not is_instance_valid(participant):
		return _failure("participant_unavailable", {"participant_id": normalized_id})
	for method_name: String in REQUIRED_METHODS:
		if not participant.has_method(method_name):
			return _failure(
				"participant_contract",
				{"participant_id": normalized_id, "missing_method": method_name}
			)
	var dependencies := _dependency_ids(participant)
	for dependency_id: String in dependencies:
		if dependency_id == normalized_id:
			return _failure(
				"participant_dependency_cycle",
				{"participant_id": normalized_id, "dependency_id": dependency_id}
			)
		if not _participants_by_id.has(dependency_id):
			return _failure(
				"participant_dependency_missing",
				{"participant_id": normalized_id, "dependency_id": dependency_id}
			)
	participant.name = "Feature_%s" % normalized_id
	add_child(participant)
	var installed := bool(participant.call("install", hub))
	if not installed:
		remove_child(participant)
		participant.queue_free()
		return _failure("participant_install_failed", {"participant_id": normalized_id})
	_participants.append(participant)
	_participants_by_id[normalized_id] = participant
	_dependencies_by_id[normalized_id] = dependencies.duplicate()
	_record_phase("install", [normalized_id])
	participant_registered.emit(StringName(normalized_id), participant)
	return {
		"success": true,
		"participant_id": normalized_id,
		"participant": participant,
		"dependencies": dependencies.duplicate(),
	}


func has_participant(participant_id: StringName) -> bool:
	return _participants_by_id.has(str(participant_id))


func get_participant(participant_id: StringName) -> Node:
	var raw_participant: Variant = _participants_by_id.get(str(participant_id))
	return raw_participant as Node if raw_participant is Node and is_instance_valid(raw_participant) else null


func get_participant_dependencies(participant_id: StringName) -> Array[String]:
	var result: Array[String] = []
	var raw_dependencies: Variant = _dependencies_by_id.get(str(participant_id), [])
	if raw_dependencies is Array:
		for raw_id: Variant in raw_dependencies:
			var dependency_id := str(raw_id).strip_edges()
			if not dependency_id.is_empty():
				result.append(dependency_id)
	return result


func begin_world(state: Dictionary) -> void:
	var invoked := _invoke_forward("begin_world", [state.duplicate(true)])
	_record_phase("begin_world", invoked)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	var invoked := _invoke_forward(
		"attach_game", [world, player, sun, environment, ground_resolver]
	)
	_record_phase("attach_game", invoked)


func activate() -> void:
	var invoked := _invoke_forward("activate", [])
	_record_phase("activate", invoked)


func save_into(payload: Dictionary) -> void:
	var invoked := _invoke_forward("save_into", [payload])
	_record_phase("save_into", invoked)


func snapshot_into(snapshot: Dictionary) -> void:
	var invoked := _invoke_forward("snapshot_into", [snapshot])
	_record_phase("snapshot_into", invoked)


func clear(reason: StringName = &"clear") -> void:
	var invoked := _invoke_reverse("clear", [reason])
	_record_phase("clear:%s" % str(reason), invoked)


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	var invoked := _invoke_reverse("shutdown", [])
	_record_phase("shutdown", invoked)


func get_snapshot() -> Dictionary:
	var ids: Array[String] = []
	for raw_id: Variant in _participants_by_id.keys():
		ids.append(str(raw_id))
	ids.sort()
	var participant_snapshots: Dictionary = {}
	var dependency_snapshot: Dictionary = {}
	for participant_id: String in ids:
		dependency_snapshot[participant_id] = get_participant_dependencies(
			StringName(participant_id)
		)
		var participant := get_participant(StringName(participant_id))
		if participant != null and participant.has_method("get_lifecycle_snapshot"):
			var raw_snapshot: Variant = participant.call("get_lifecycle_snapshot")
			participant_snapshots[participant_id] = (
				raw_snapshot.duplicate(true) if raw_snapshot is Dictionary else {}
			)
	return {
		"participant_count": ids.size(),
		"participant_ids": ids,
		"participant_dependencies": dependency_snapshot,
		"phase_counts": _phase_counts.duplicate(true),
		"phase_history": _phase_history.duplicate(),
		"participants": participant_snapshots,
		"shutdown": _shutdown,
	}


func _dependency_ids(participant: Node) -> Array[String]:
	var result: Array[String] = []
	if participant == null or not participant.has_method("get_dependencies"):
		return result
	var raw_dependencies: Variant = participant.call("get_dependencies")
	if raw_dependencies is not Array:
		return result
	for raw_id: Variant in raw_dependencies:
		var dependency_id := str(raw_id).strip_edges()
		if dependency_id.is_empty() or dependency_id in result:
			continue
		result.append(dependency_id)
	return result


func _invoke_forward(method_name: String, arguments: Array) -> Array[String]:
	var invoked: Array[String] = []
	for participant: Node in _participants:
		if participant == null or not is_instance_valid(participant):
			continue
		participant.callv(method_name, arguments)
		invoked.append(_participant_id_for(participant))
	return invoked


func _invoke_reverse(method_name: String, arguments: Array) -> Array[String]:
	var invoked: Array[String] = []
	for index in range(_participants.size() - 1, -1, -1):
		var participant: Node = _participants[index]
		if participant == null or not is_instance_valid(participant):
			continue
		participant.callv(method_name, arguments)
		invoked.append(_participant_id_for(participant))
	return invoked


func _participant_id_for(participant: Node) -> String:
	for raw_id: Variant in _participants_by_id.keys():
		if _participants_by_id[raw_id] == participant:
			return str(raw_id)
	return participant.name


func _record_phase(phase: String, participant_ids: Array[String]) -> void:
	_phase_counts[phase] = int(_phase_counts.get(phase, 0)) + 1
	_phase_history.append("%s:%s" % [phase, ",".join(participant_ids)])
	while _phase_history.size() > MAX_PHASE_HISTORY:
		_phase_history.pop_front()
	lifecycle_phase_completed.emit(StringName(phase), participant_ids.duplicate())


func _failure(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "reason": reason}
	result.merge(extra, true)
	return result
