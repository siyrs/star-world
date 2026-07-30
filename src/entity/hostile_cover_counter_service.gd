class_name HostileCoverCounterService
extends Node

signal cover_broken(snapshot: Dictionary)
signal marksman_repositioned(snapshot: Dictionary)
signal snapshot_changed(snapshot: Dictionary)

const PolicyScript = preload("res://src/entity/hostile_cover_counter_policy.gd")
const OverlayScript = preload("res://src/ui/hostile_cover_counter_overlay.gd")
const BINDING_REFRESH_SECONDS := 0.25
const MAX_INITIAL_CHILD_SCAN := 64
const MAX_BOUND_CREATURES := 32
const MAX_BREAK_DISTANCE := 3.4

@export var auto_bind_parent := true

var world: Node
var player: Node3D
var creature_spawner: Node

var _parent_hub: Node
var _overlay: Control
var _binding_refresh_remaining := 0.0
var _bound_world_id := ""
var _bound_spawner: Node
var _bound_creatures: Dictionary = {}
var _brute_break_counts: Dictionary = {}
var _last_snapshot: Dictionary = {}

var _cover_break_attack_count := 0
var _cover_break_block_count := 0
var _cover_break_rejection_count := 0
var _marksman_lane_probe_count := 0
var _marksman_reposition_count := 0
var _marksman_reposition_probe_count := 0
var _binding_overflow_count := 0
var _last_action: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)
	if auto_bind_parent:
		call_deferred("_refresh_parent_bindings", 0.0, true)


func bind_parent_hub(p_parent_hub: Node) -> void:
	_parent_hub = p_parent_hub
	_refresh_parent_bindings(0.0, true)


func clear(reason: String = "clear") -> void:
	_brute_break_counts.clear()
	_last_action = {"kind": "cleared", "reason": reason}
	_cover_break_attack_count = 0
	_cover_break_block_count = 0
	_cover_break_rejection_count = 0
	_marksman_lane_probe_count = 0
	_marksman_reposition_count = 0
	_marksman_reposition_probe_count = 0
	_publish_if_changed(true)


func resolve_brute_attack(brute: Node3D, attack_target: Node3D) -> Dictionary:
	if not _runtime_ready() or brute == null or attack_target == null:
		return {"handled": false, "reason": "runtime_unavailable"}
	if not is_instance_valid(brute) or not is_instance_valid(attack_target):
		return {"handled": false, "reason": "target_unavailable"}
	var brute_id := int(brute.get_instance_id())
	var broken_total := int(_brute_break_counts.get(brute_id, 0))
	if broken_total >= PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE:
		_cover_break_rejection_count += 1
		return {"handled": false, "reason": "brute_break_budget_exhausted"}
	var remaining_budget := PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE - broken_total
	var positions := _breakable_cover_positions(brute, attack_target, remaining_budget)
	if positions.is_empty():
		return {"handled": false, "reason": "no_breakable_cover"}
	var changes: Array = []
	for position: Vector3i in positions:
		changes.append({"position": position, "block_id": "air"})
	var apply_result: Dictionary = world.call(
		"apply_block_mutations", changes, "hostile_cover_break"
	)
	var changed := int(apply_result.get("changed", 0))
	if not bool(apply_result.get("success", false)) or changed <= 0:
		_cover_break_rejection_count += 1
		return {
			"handled": false,
			"reason": "mutation_failed",
			"apply": apply_result.duplicate(true),
		}
	_brute_break_counts[brute_id] = mini(
		PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE,
		broken_total + changed
	)
	_cover_break_attack_count += 1
	_cover_break_block_count += changed
	var result := {
		"handled": true,
		"reason": "cover_broken",
		"brute_id": brute_id,
		"target_id": int(attack_target.get_instance_id()),
		"changed_blocks": changed,
		"positions": _positions_to_arrays(positions),
		"lifetime_break_count": int(_brute_break_counts.get(brute_id, 0)),
		"lifetime_break_budget": PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE,
		"apply": apply_result.duplicate(true),
	}
	_last_action = result.duplicate(true)
	cover_broken.emit(result.duplicate(true))
	_publish_if_changed(true)
	return result


func has_projectile_lane(shooter: Node3D, attack_target: Node3D) -> bool:
	if not _runtime_ready() or shooter == null or attack_target == null:
		return false
	if not is_instance_valid(shooter) or not is_instance_valid(attack_target):
		return false
	_marksman_lane_probe_count += 1
	var start := shooter.global_position + Vector3.UP * 1.48
	var finish := attack_target.global_position + Vector3.UP * 1.05
	return _lane_clear(start, finish, true)


func find_marksman_reposition_destination(
	marksman: Node3D,
	attack_target: Node3D,
	minimum_range: float,
	maximum_range: float
) -> Dictionary:
	if not _runtime_ready() or marksman == null or attack_target == null:
		return {"success": false, "reason": "runtime_unavailable", "probes": 0}
	if not is_instance_valid(marksman) or not is_instance_valid(attack_target):
		return {"success": false, "reason": "target_unavailable", "probes": 0}
	var to_target := attack_target.global_position - marksman.global_position
	var directions := PolicyScript.reposition_directions(
		to_target, PolicyScript.MAX_REPOSITION_PROBES
	)
	var probes := 0
	for direction: Vector3 in directions:
		probes += 1
		_marksman_reposition_probe_count += 1
		var raw_candidate := marksman.global_position + direction * PolicyScript.REPOSITION_RADIUS
		var candidate: Vector3 = world.call("resolve_ground_position", raw_candidate)
		var distance_to_target := candidate.distance_to(attack_target.global_position)
		if distance_to_target < minimum_range or distance_to_target > maximum_range:
			continue
		if not _walk_lane_clear(marksman.global_position, candidate):
			continue
		if not _lane_clear(
			candidate + Vector3.UP * 1.48,
			attack_target.global_position + Vector3.UP * 1.05,
			true
		):
			continue
		return {
			"success": true,
			"reason": "lane_found",
			"destination": candidate,
			"probes": probes,
		}
	return {"success": false, "reason": "no_lane", "probes": probes}


func report_marksman_reposition(
	marksman: Node3D,
	destination: Vector3,
	probe_count: int,
	attempt_count: int
) -> void:
	_marksman_reposition_count += 1
	var result := {
		"kind": "marksman_reposition",
		"marksman_id": int(marksman.get_instance_id()) if marksman != null else 0,
		"destination": [destination.x, destination.y, destination.z],
		"probes": clampi(probe_count, 0, PolicyScript.MAX_REPOSITION_PROBES),
		"attempt_count": attempt_count,
		"attempt_budget": PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET,
	}
	_last_action = result.duplicate(true)
	marksman_repositioned.emit(result.duplicate(true))
	_publish_if_changed(true)


func get_snapshot() -> Dictionary:
	_cleanup_bound_creatures()
	return {
		"active": _runtime_ready(),
		"world_id": _bound_world_id,
		"bound_creature_count": _bound_creatures.size(),
		"maximum_bound_creatures": MAX_BOUND_CREATURES,
		"binding_overflow_count": _binding_overflow_count,
		"cover_break_attack_count": _cover_break_attack_count,
		"cover_break_block_count": _cover_break_block_count,
		"cover_break_rejection_count": _cover_break_rejection_count,
		"marksman_lane_probe_count": _marksman_lane_probe_count,
		"marksman_reposition_count": _marksman_reposition_count,
		"marksman_reposition_probe_count": _marksman_reposition_probe_count,
		"maximum_line_sample_steps": PolicyScript.MAX_LINE_SAMPLE_STEPS,
		"maximum_break_blocks_per_attack": PolicyScript.MAX_BREAK_BLOCKS_PER_ATTACK,
		"maximum_break_blocks_per_brute": PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE,
		"maximum_reposition_probes": PolicyScript.MAX_REPOSITION_PROBES,
		"maximum_reposition_attempts_per_target": PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET,
		"breakable_cover_ids": PolicyScript.BREAKABLE_COVER_IDS.duplicate(),
		"last_action": _last_action.duplicate(true),
		"overlay_available": _overlay != null and is_instance_valid(_overlay),
	}


func _process(delta: float) -> void:
	if auto_bind_parent:
		_refresh_parent_bindings(maxf(0.0, delta), false)
	_cleanup_bound_creatures()
	_publish_if_changed(false)


func _refresh_parent_bindings(delta: float = 0.0, force: bool = false) -> void:
	_binding_refresh_remaining = maxf(
		0.0, _binding_refresh_remaining - maxf(0.0, delta)
	)
	if not force and _binding_refresh_remaining > 0.0:
		return
	_binding_refresh_remaining = BINDING_REFRESH_SECONDS
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		_parent_hub = get_parent()
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		return
	var next_world: Node = _parent_hub.get("world_node") as Node
	var next_player: Node3D = _parent_hub.get("player_node") as Node3D
	var next_spawner: Node = _parent_hub.get("creature_spawner") as Node
	var next_world_id := str(_parent_hub.get("current_world_id"))
	if next_world != world or next_world_id != _bound_world_id:
		world = next_world
		player = next_player
		_bound_world_id = next_world_id
		_brute_break_counts.clear()
		_last_action = {"kind": "world_changed", "world_id": next_world_id}
	else:
		player = next_player
	_bind_spawner(next_spawner)
	_ensure_overlay()


func _bind_spawner(next_spawner: Node) -> void:
	if _bound_spawner == next_spawner:
		return
	_disconnect_spawner()
	_bound_spawner = next_spawner
	creature_spawner = next_spawner
	_bound_creatures.clear()
	if creature_spawner == null or not is_instance_valid(creature_spawner):
		return
	var callback := Callable(self, "_on_creature_spawned")
	if creature_spawner.has_signal("creature_spawned") and not creature_spawner.is_connected(
		"creature_spawned", callback
	):
		creature_spawner.connect("creature_spawned", callback)
	var scanned := 0
	for child: Node in creature_spawner.get_children():
		if scanned >= MAX_INITIAL_CHILD_SCAN:
			break
		scanned += 1
		_bind_creature(child)


func _disconnect_spawner() -> void:
	if _bound_spawner == null or not is_instance_valid(_bound_spawner):
		_bound_spawner = null
		return
	var callback := Callable(self, "_on_creature_spawned")
	if _bound_spawner.has_signal("creature_spawned") and _bound_spawner.is_connected(
		"creature_spawned", callback
	):
		_bound_spawner.disconnect("creature_spawned", callback)
	_bound_spawner = null


func _on_creature_spawned(creature: Node3D) -> void:
	_bind_creature(creature)


func _bind_creature(creature: Node) -> void:
	if creature == null or not is_instance_valid(creature):
		return
	if not creature.has_method("bind_cover_counter_service"):
		return
	var creature_id := int(creature.get_instance_id())
	if _bound_creatures.has(creature_id):
		return
	if _bound_creatures.size() >= MAX_BOUND_CREATURES:
		_binding_overflow_count += 1
		return
	creature.call("bind_cover_counter_service", self)
	_bound_creatures[creature_id] = weakref(creature)
	var callback := Callable(self, "_on_bound_creature_exiting").bind(creature_id)
	if not creature.is_connected("tree_exiting", callback):
		creature.connect("tree_exiting", callback)


func _on_bound_creature_exiting(creature_id: int) -> void:
	_bound_creatures.erase(creature_id)
	_brute_break_counts.erase(creature_id)


func _cleanup_bound_creatures() -> void:
	for raw_id: Variant in _bound_creatures.keys().duplicate():
		var creature_id := int(raw_id)
		var raw_ref: Variant = _bound_creatures.get(creature_id)
		if raw_ref is not WeakRef or raw_ref.get_ref() == null:
			_bound_creatures.erase(creature_id)
			_brute_break_counts.erase(creature_id)


func _breakable_cover_positions(
	brute: Node3D,
	attack_target: Node3D,
	remaining_budget: int
) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var limit := mini(
		PolicyScript.MAX_BREAK_BLOCKS_PER_ATTACK,
		maxi(0, remaining_budget)
	)
	if limit <= 0:
		return result
	var start := brute.global_position + Vector3.UP * 1.05
	var finish := attack_target.global_position + Vector3.UP * 1.0
	for sample: Dictionary in PolicyScript.line_samples(start, finish):
		if result.size() >= limit:
			break
		if float(sample.get("distance_from_start", INF)) > MAX_BREAK_DISTANCE:
			break
		var position: Vector3i = sample.get("position", Vector3i.ZERO)
		var block_id := str(world.call("get_block", position))
		if not PolicyScript.is_breakable_cover(block_id):
			continue
		if not _is_player_override(position, block_id):
			continue
		result.append(position)
	return result


func _is_player_override(position: Vector3i, expected_block_id: String) -> bool:
	if world == null or not world.has_method("block_key"):
		return false
	var raw_overrides: Variant = world.get("block_overrides")
	if raw_overrides is not Dictionary:
		return false
	var key := str(world.call("block_key", position))
	return str((raw_overrides as Dictionary).get(key, "")) == expected_block_id


func _lane_clear(start: Vector3, finish: Vector3, projectile_lane: bool) -> bool:
	for sample: Dictionary in PolicyScript.line_samples(start, finish):
		var position: Vector3i = sample.get("position", Vector3i.ZERO)
		var block_id := str(world.call("get_block", position))
		var local_height := float(sample.get("local_height", 0.5))
		var blocked := (
			PolicyScript.blocks_projectile_lane(block_id, local_height)
			if projectile_lane
			else PolicyScript.blocks_walk_lane(block_id, local_height)
		)
		if blocked:
			return false
	return true


func _walk_lane_clear(start: Vector3, finish: Vector3) -> bool:
	return _lane_clear(start + Vector3.UP * 0.35, finish + Vector3.UP * 0.35, false) and _lane_clear(
		start + Vector3.UP * 1.35,
		finish + Vector3.UP * 1.35,
		false
	)


func _runtime_ready() -> bool:
	return (
		world != null
		and is_instance_valid(world)
		and world.has_method("get_block")
		and world.has_method("apply_block_mutations")
		and world.has_method("resolve_ground_position")
		and not _bound_world_id.is_empty()
	)


func _positions_to_arrays(positions: Array[Vector3i]) -> Array[Array]:
	var result: Array[Array] = []
	for position: Vector3i in positions:
		result.append([position.x, position.y, position.z])
	return result


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		return
	var game_ui: Node = _parent_hub.get("game_ui") as Node
	if game_ui == null:
		return
	_overlay = OverlayScript.new()
	_overlay.name = "HostileCoverCounterOverlay"
	game_ui.add_child(_overlay)
	_overlay.call("setup", self)


func _publish_if_changed(force: bool) -> void:
	var snapshot := get_snapshot()
	if not force and snapshot == _last_snapshot:
		return
	_last_snapshot = snapshot.duplicate(true)
	snapshot_changed.emit(_last_snapshot.duplicate(true))


func _exit_tree() -> void:
	_disconnect_spawner()
