class_name HostileEncounterDirector
extends Node

signal encounter_started(snapshot: Dictionary)
signal encounter_completed(snapshot: Dictionary)
signal encounter_rejected(reason: String, snapshot: Dictionary)
signal snapshot_changed(snapshot: Dictionary)

const RegistryScript = preload("res://src/entity/hostile_encounter_registry.gd")
const PolicyScript = preload("res://src/entity/hostile_encounter_policy.gd")
const OverlayScript = preload("res://src/ui/hostile_encounter_overlay.gd")
const DECISION_INTERVAL_SECONDS := 1.0
const INITIAL_DELAY_SECONDS := 6.0
const BINDING_REFRESH_SECONDS := 0.25
const MAX_SPAWN_ATTEMPTS_PER_DECISION := 1

@export var auto_bind_parent := true

var creature_spawner: Node
var player: Node3D
var day_night_service: Node
var map_id := "star_continent"
var active := false

var _registry = RegistryScript.new()
var _rng := RandomNumberGenerator.new()
var _decision_remaining := INITIAL_DELAY_SECONDS
var _cooldown_remaining := 0.0
var _binding_refresh_remaining := 0.0
var _active_encounters: Dictionary = {}
var _next_encounter_sequence := 1
var _start_count := 0
var _completion_count := 0
var _rollback_count := 0
var _rejection_count := 0
var _last_rejection_reason := ""
var _last_profile_id := ""
var _last_snapshot: Dictionary = {}
var _parent_hub: Node
var _bound_world_id := ""
var _overlay: Control
var _explicit_setup := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	set_process(true)
	if auto_bind_parent:
		call_deferred("_refresh_parent_bindings", 0.0, true)


func setup(
	p_creature_spawner: Node,
	p_player: Node3D,
	p_day_night_service: Node,
	p_map_id: String
) -> void:
	_explicit_setup = true
	creature_spawner = p_creature_spawner
	player = p_player
	day_night_service = p_day_night_service
	map_id = p_map_id if not p_map_id.is_empty() else "star_continent"
	_publish_if_changed(true)


func bind_parent_hub(p_parent_hub: Node) -> void:
	_parent_hub = p_parent_hub
	_explicit_setup = false
	_refresh_parent_bindings(0.0, true)


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if active:
		_decision_remaining = minf(_decision_remaining, INITIAL_DELAY_SECONDS)
	if _overlay != null:
		_overlay.call("set_active", active)
	_publish_if_changed(true)


func set_map_profile(p_map_id: String) -> void:
	var next_map_id := p_map_id if not p_map_id.is_empty() else "star_continent"
	if map_id == next_map_id:
		return
	map_id = next_map_id
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
		"auto_bound": _parent_hub != null,
		"world_id": _bound_world_id,
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
		"overlay_available": _overlay != null,
	}


func _process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	if auto_bind_parent and not _explicit_setup:
		_refresh_parent_bindings(safe_delta, false)
	_advance(safe_delta, _rng.randf())


func _refresh_parent_bindings(delta: float = 0.0, force: bool = false) -> void:
	_binding_refresh_remaining = maxf(0.0, _binding_refresh_remaining - maxf(0.0, delta))
	if not force and _binding_refresh_remaining > 0.0:
		return
	_binding_refresh_remaining = BINDING_REFRESH_SECONDS
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		_parent_hub = get_parent()
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		return
	var next_spawner: Node = _parent_hub.get("creature_spawner") as Node
	var next_player: Node3D = _parent_hub.get("player_node") as Node3D
	var next_day_night: Node = _parent_hub.get("day_night") as Node
	if next_spawner != null:
		creature_spawner = next_spawner
	if next_player != null:
		player = next_player
	if next_day_night != null:
		day_night_service = next_day_night
	var current_state: Variant = _parent_hub.get("current_state")
	var metadata: Dictionary = (
		current_state.get("metadata", {})
		if current_state is Dictionary
		else {}
	)
	set_map_profile(str(metadata.get("map_id", map_id)))
	var next_world_id := str(_parent_hub.get("current_world_id"))
	if next_world_id != _bound_world_id:
		if not _bound_world_id.is_empty() or not _active_encounters.is_empty():
			clear("world_changed")
		_bound_world_id = next_world_id
	var spawner_active := bool(creature_spawner.get("active")) if creature_spawner != null else false
	set_active(not _bound_world_id.is_empty() and spawner_active and player != null)
	_ensure_overlay()


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		return
	var game_ui: Node = _parent_hub.get("game_ui") as Node
	if game_ui == null:
		return
	_overlay = OverlayScript.new()
	_overlay.name = "HostileEncounterOverlay"
	game_ui.add_child(_overlay)
	_overlay.call("setup", self)
	_overlay.call("set_active", active)


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
		var resolved_position := _resolve_spawn_candidate(requested_position)
		var creature := _spawn_encounter_member(request, resolved_position, encounter_id, spawned.size())
		if creature == null:
			_rollback_spawned(spawned)
			return _reject("spawn_transaction_failed")
		spawned.append(creature)
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


func _spawn_encounter_member(
	request: Dictionary,
	spawn_position: Vector3,
	encounter_id: String,
	fallback_index: int
) -> Node3D:
	var species_id := str(request.get("species_id", ""))
	var role := str(request.get("role", "vanguard"))
	var member_index := int(request.get("member_index", fallback_index))
	if creature_spawner.has_method("spawn_encounter_member"):
		var raw_creature: Variant = creature_spawner.call(
			"spawn_encounter_member",
			species_id,
			spawn_position,
			encounter_id,
			role,
			player,
			member_index
		)
		return raw_creature as Node3D
	if not _can_spawn_species(species_id):
		return null
	var raw_spawned: Variant = creature_spawner.call("spawn_creature", species_id, spawn_position)
	if raw_spawned is not Node3D:
		return null
	var creature: Node3D = raw_spawned
	creature.add_to_group("encounter_hostile")
	creature.set_meta("encounter_id", encounter_id)
	creature.set_meta("encounter_role", role)
	creature.set_meta("encounter_member_index", clampi(member_index, 0, 7))
	creature.set_meta("encounter_spawned", true)
	creature.set("target", player)
	return creature


func _resolve_spawn_candidate(candidate: Vector3) -> Vector3:
	if creature_spawner.has_method("resolve_spawn_candidate"):
		return creature_spawner.call("resolve_spawn_candidate", candidate)
	var resolver: Variant = creature_spawner.get("ground_resolver")
	if resolver is Callable and resolver.is_valid():
		var raw_result: Variant = resolver.call(candidate)
		if raw_result is Vector3:
			return raw_result
		if raw_result is float or raw_result is int:
			candidate.y = float(raw_result) + 1.0
	return candidate


func _can_spawn_species(species_id: String) -> bool:
	var population := _population_snapshot()
	if int(population.get("count", 0)) >= int(population.get("cap", 0)):
		return false
	var ecology_profile: Dictionary = (
		creature_spawner.call("get_ecology_profile")
		if creature_spawner.has_method("get_ecology_profile")
		else {}
	)
	var raw_species: Variant = ecology_profile.get("hostile_species", [])
	if raw_species is Array:
		for raw_entry: Variant in raw_species:
			if raw_entry is not Dictionary:
				continue
			var entry: Dictionary = raw_entry
			if str(entry.get("id", "")) != species_id:
				continue
			var cap := int(entry.get("cap", -1))
			if cap > 0 and creature_spawner.has_method("get_species_count"):
				return int(creature_spawner.call("get_species_count", species_id)) < cap
	return true


func _build_context() -> Dictionary:
	var population := _population_snapshot()
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


func _population_snapshot() -> Dictionary:
	if creature_spawner == null:
		return {}
	if creature_spawner.has_method("get_hostile_population_snapshot"):
		return creature_spawner.call("get_hostile_population_snapshot")
	var ecology: Dictionary = (
		creature_spawner.call("get_ecology_snapshot")
		if creature_spawner.has_method("get_ecology_snapshot")
		else {}
	)
	var pressure := 0.0
	if player != null and creature_spawner.has_method("get_nearby_hostile_pressure"):
		pressure = float(creature_spawner.call(
			"get_nearby_hostile_pressure", player.global_position, 64.0
		))
	return {
		"count": int(ecology.get("hostile_count", 0)),
		"cap": int(ecology.get("hostile_cap", 0)),
		"pressure": pressure,
		"species_counts": ecology.get("species_counts", {}).duplicate(true),
		"phase_id": str(ecology.get("phase", _current_phase())),
		"map_id": str(ecology.get("profile_id", map_id)),
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
		elif creature_spawner != null and creature_spawner.has_method("_dispose_child"):
			creature_spawner.call("_dispose_child", creature, false)
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
		and creature_spawner.has_method("spawn_creature")
		and player != null
		and is_instance_valid(player)
	)


func _publish_if_changed(force: bool) -> void:
	var snapshot := get_snapshot()
	if not force and snapshot == _last_snapshot:
		return
	_last_snapshot = snapshot.duplicate(true)
	snapshot_changed.emit(_last_snapshot.duplicate(true))
