class_name HostileEncounterDirector
extends Node

signal encounter_started(snapshot: Dictionary)
signal encounter_completed(snapshot: Dictionary)
signal encounter_rejected(reason: String, snapshot: Dictionary)
signal snapshot_changed(snapshot: Dictionary)

const RegistryScript = preload("res://src/entity/hostile_encounter_registry.gd")
const PolicyScript = preload("res://src/entity/hostile_encounter_policy.gd")
const DECISION_INTERVAL_SECONDS := 1.0
const INITIAL_DELAY_SECONDS := 6.0
const MAX_SPAWN_ATTEMPTS_PER_DECISION := 1

var creature_spawner: Node
var player: Node3D
var day_night_service: Node
var map_id := "star_continent"
var active := false

var _registry = RegistryScript.new()
var _rng := RandomNumberGenerator.new()
var _decision_remaining := INITIAL_DELAY_SECONDS
var _cooldown_remaining := 0.0
var _active_encounters: Dictionary = {}
var _next_encounter_sequence := 1
var _start_count := 0
var _completion_count := 0
var _rollback_count := 0
var _rejection_count := 0
var _last_rejection_reason := ""
var _last_profile_id := ""
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	set_process(false)


func setup(
	p_creature_spawner: Node,
	p_player: Node3D,
	p_day_night_service: Node,
	p_map_id: String
) -> void:
	creature_spawner = p_creature_spawner
	player = p_player
	day_night_service = p_day_night_service
	map_id = p_map_id if not p_map_id.is_empty() else "star_continent"
	_publish_if_changed(true)


func set_active(value: bool) -> void:
	active = value
	set_process(active)
	if active:
		_decision_remaining = minf(_decision_remaining, INITIAL_DELAY_SECONDS)
	_publish_if_changed(true)


func set_map_profile(p_map_id: String) -> void:
	map_id = p_map_id if not p_map_id.is_empty() else "star_continent"
	_decision_remaining = minf(_decision_remaining, INITIAL_DELAY_SECONDS)
	_publish_if_changed(true)


func clear(reason: String = "clear") -> void:
	var completed: Array[Dictionary] = []
	for raw_id: Variant in _active_encounters.keys():
		var record: Dictionary = _active_encounters.get(raw_id, {})
		record["completion_reason"] = reason
		completed.append(_public_encounter_snapshot(record))
	_active_encounters.clear()
	_decision_remaining = INITIAL_DELAY_SECONDS
	_cooldown_remaining = 0.0
	_last_rejection_reason = ""
	for snapshot: Dictionary in completed:
		encounter_completed.emit(snapshot)
	_publish_if_changed(true)


func force_decision_for_test(profile_id: String = "", roll: float = 0.0) -> Dictionary:
	_cleanup_encounters()
	return _attempt_start(profile_id, roll)


func advance_for_test(delta: float, roll: float = 0.0) -> Dictionary:
	_advance(maxf(0.0, delta), roll)
	return get_snapshot()


func get_snapshot() -> Dictionary:
	var encounters: Array[Dictionary] = []
	var tracked_members := 0
	var active_pressure := 0.0
	var ids: Array = _active_encounters.keys()
	ids.sort()
	for raw_id: Variant in ids:
		var record: Dictionary = _active_encounters.get(raw_id, {})
		var snapshot := _public_encounter_snapshot(record)
		tracked_members += int(snapshot.get("living_member_count", 0))
		active_pressure += float(snapshot.get("living_pressure", 0.0))
		encounters.append(snapshot)
	return {
		"active": active,
		"map_id": map_id,
		"phase_id": _current_phase(),
		"decision_remaining_seconds": _decision_remaining,
		"cooldown_remaining_seconds": _cooldown_remaining,
		"active_encounter_count": encounters.size(),
		"maximum_active_encounters": PolicyScript.MAX_ACTIVE_ENCOUNTERS,
		"tracked_member_count": tracked_members,
		"maximum_tracked_members": PolicyScript.MAX_TRACKED_MEMBERS,
		"active_pressure": active_pressure,
		"start_count": _start_count,
		"completion_count": _completion_count,
		"rollback_count": _rollback_count,
		"rejection_count": _rejection_count,
		"last_rejection_reason": _last_rejection_reason,
		"last_profile_id": _last_profile_id,
		"health_ratio": _player_health_ratio(),
		"encounters": encounters,
		"registry_schema_version": _registry.schema_version,
		"registry_profile_count": _registry.get_profile_ids().size(),
	}


func _process(delta: float) -> void:
	_advance(maxf(0.0, delta), _rng.randf())


func _advance(delta: float, roll: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_cleanup_encounters()
	if not active or not _attachments_ready():
		_publish_if_changed(false)
		return
	_decision_remaining = maxf(0.0, _decision_remaining - delta)
	if _decision_remaining > 0.0:
		_publish_if_changed(false)
		return
	_decision_remaining = DECISION_INTERVAL_SECONDS
	for _attempt in MAX_SPAWN_ATTEMPTS_PER_DECISION:
		_attempt_start("", roll)
	_publish_if_changed(false)


func _attempt_start(profile_id: String, roll: float) -> Dictionary:
	if not _attachments_ready():
		return _reject("attachments_unavailable")
	var profiles := _registry.get_profiles()
	var context := _build_context()
	var profile := (
		_registry.get_profile(profile_id)
		if not profile_id.is_empty()
		else PolicyScript.select_profile(profiles, context, roll)
	)
	if profile.is_empty():
		return _reject(PolicyScript.rejection_reason(profiles, context))
	if not PolicyScript.is_profile_eligible(profile, context):
		return _reject("profile_not_eligible")
	var encounter_id := "%s-%06d" % [str(profile.get("id", "encounter")), _next_encounter_sequence]
	_next_encounter_sequence += 1
	var base_angle := _rng.randf_range(0.0, TAU)
	var requests := PolicyScript.formation_requests(profile, player.global_position, base_angle)
	var spawned: Array[Node3D] = []
	for request: Dictionary in requests:
		var requested_position: Vector3 = request.get("requested_position", player.global_position)
		var resolved_position: Vector3 = creature_spawner.call(
			"resolve_spawn_candidate", requested_position
		)
		var raw_creature: Variant = creature_spawner.call(
			"spawn_encounter_member",
			str(request.get("species_id", "")),
			resolved_position,
			encounter_id,
			str(request.get("role", "vanguard")),
			player,
			int(request.get("member_index", spawned.size()))
		)
		if raw_creature is not Node3D:
			_rollback_spawned(spawned)
			return _reject("spawn_transaction_failed")
		spawned.append(raw_creature)
	var refs: Array[WeakRef] = []
	var member_ids: Array[int] = []
	for member: Node3D in spawned:
		refs.append(weakref(member))
		member_ids.append(int(member.get_instance_id()))
	var record := {
		"id": encounter_id,
		"profile_id": str(profile.get("id", "")),
		"display_name": str(profile.get("display_name", "遭遇")),
		"member_refs": refs,
		"member_ids": member_ids,
		"initial_member_count": spawned.size(),
		"initial_pressure": PolicyScript.estimate_pressure(profile),
		"started_at_msec": Time.get_ticks_msec(),
		"cooldown_seconds": float(profile.get("cooldown_seconds", 30.0)),
	}
	_active_encounters[encounter_id] = record
	_cooldown_remaining = maxf(
		_cooldown_remaining, float(profile.get("cooldown_seconds", 30.0))
	)
	_start_count += 1
	_last_profile_id = str(profile.get("id", ""))
	_last_rejection_reason = ""
	var snapshot := _public_encounter_snapshot(record)
	encounter_started.emit(snapshot.duplicate(true))
	_publish_if_changed(true)
	return {"success": true, "reason": "ok", "encounter": snapshot}


func _build_context() -> Dictionary:
	var population: Dictionary = (
		creature_spawner.call("get_hostile_population_snapshot")
		if creature_spawner != null
		and creature_spawner.has_method("get_hostile_population_snapshot")
		else {}
	)
	return {
		"map_id": map_id,
		"phase_id": _current_phase(),
		"player_y": player.global_position.y if player != null else 0.0,
		"health_ratio": _player_health_ratio(),
		"existing_pressure": float(population.get("pressure", 0.0)),
		"existing_count": int(population.get("count", 0)),
		"hostile_cap": int(population.get("cap", 0)),
		"active_encounters": _active_encounters.size(),
		"tracked_members": _tracked_member_count(),
		"cooldown_remaining": _cooldown_remaining,
	}


func _cleanup_encounters() -> void:
	var completed_ids: Array[String] = []
	for raw_id: Variant in _active_encounters.keys():
		var encounter_id := str(raw_id)
		var record: Dictionary = _active_encounters.get(encounter_id, {})
		if _living_members(record).is_empty():
			completed_ids.append(encounter_id)
	for encounter_id: String in completed_ids:
		var record: Dictionary = _active_encounters.get(encounter_id, {})
		_active_encounters.erase(encounter_id)
		_completion_count += 1
		record["completion_reason"] = "members_cleared"
		encounter_completed.emit(_public_encounter_snapshot(record))
	if not completed_ids.is_empty():
		_publish_if_changed(true)


func _public_encounter_snapshot(record: Dictionary) -> Dictionary:
	var living := _living_members(record)
	var roles: Dictionary = {}
	var species: Dictionary = {}
	var living_ids: Array[int] = []
	var living_pressure := 0.0
	for member: Node3D in living:
		var role := str(member.get_meta("encounter_role", "vanguard"))
		var species_id := str(member.get("species_id"))
		roles[role] = int(roles.get(role, 0)) + 1
		species[species_id] = int(species.get(species_id, 0)) + 1
		living_ids.append(int(member.get_instance_id()))
		living_pressure += clampf(float(member.get("danger_weight")), 0.5, 6.0)
	return {
		"id": str(record.get("id", "")),
		"profile_id": str(record.get("profile_id", "")),
		"display_name": str(record.get("display_name", "遭遇")),
		"initial_member_count": int(record.get("initial_member_count", 0)),
		"living_member_count": living.size(),
		"initial_pressure": float(record.get("initial_pressure", 0.0)),
		"living_pressure": living_pressure,
		"roles": roles,
		"species": species,
		"living_member_ids": living_ids,
		"started_at_msec": int(record.get("started_at_msec", 0)),
		"completion_reason": str(record.get("completion_reason", "")),
	}


func _living_members(record: Dictionary) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var raw_refs: Variant = record.get("member_refs", [])
	if raw_refs is not Array:
		return result
	for raw_ref: Variant in raw_refs:
		if raw_ref is not WeakRef:
			continue
		var member: Variant = raw_ref.get_ref()
		if (
			member is Node3D
			and is_instance_valid(member)
			and not member.is_queued_for_deletion()
			and (
				not member.has_method("is_combat_target_available")
				or bool(member.call("is_combat_target_available"))
			)
		):
			result.append(member)
	return result


func _tracked_member_count() -> int:
	var count := 0
	for raw_id: Variant in _active_encounters.keys():
		count += _living_members(_active_encounters.get(raw_id, {})).size()
	return count


func _rollback_spawned(spawned: Array[Node3D]) -> void:
	for creature: Node3D in spawned:
		if creature_spawner != null and creature_spawner.has_method("remove_creature"):
			creature_spawner.call("remove_creature", creature, false)
		elif is_instance_valid(creature):
			creature.queue_free()
	_rollback_count += 1


func _reject(reason: String) -> Dictionary:
	_rejection_count += 1
	_last_rejection_reason = reason
	var snapshot := get_snapshot()
	encounter_rejected.emit(reason, snapshot.duplicate(true))
	_publish_if_changed(true)
	return {"success": false, "reason": reason, "snapshot": snapshot}


func _current_phase() -> String:
	if day_night_service != null and day_night_service.has_method("get_phase"):
		return str(day_night_service.call("get_phase"))
	return "day"


func _player_health_ratio() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	var survival: Node = player.get("survival") as Node
	if survival == null:
		return 1.0
	var health := float(survival.get("health"))
	var maximum := maxf(0.001, float(survival.get("max_health")))
	return clampf(health / maximum, 0.0, 1.0)


func _attachments_ready() -> bool:
	return (
		creature_spawner != null
		and is_instance_valid(creature_spawner)
		and player != null
		and is_instance_valid(player)
		and creature_spawner.has_method("spawn_encounter_member")
		and creature_spawner.has_method("resolve_spawn_candidate")
	)


func _publish_if_changed(force: bool) -> void:
	var snapshot := get_snapshot()
	if not force and snapshot == _last_snapshot:
		return
	_last_snapshot = snapshot.duplicate(true)
	snapshot_changed.emit(_last_snapshot.duplicate(true))
