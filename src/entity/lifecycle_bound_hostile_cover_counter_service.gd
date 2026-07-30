class_name LifecycleBoundHostileCoverCounterService
extends "res://src/entity/hostile_cover_counter_service.gd"

var _lifecycle_hub: Node
var _permanent_cover_block_count := 0


func _ready() -> void:
	super._ready()
	call_deferred("_bind_parent_lifecycle")


func bind_parent_hub(p_parent_hub: Node) -> void:
	_disconnect_parent_lifecycle()
	_lifecycle_hub = p_parent_hub
	super.bind_parent_hub(p_parent_hub)
	_connect_parent_lifecycle()


func clear(reason: String = "clear") -> void:
	_permanent_cover_block_count = 0
	super.clear(reason)


func resolve_brute_attack(brute: Node3D, attack_target: Node3D) -> Dictionary:
	if _permanent_cover_blocks_lane(brute, attack_target):
		_permanent_cover_block_count += 1
		var result := {
			"handled": true,
			"reason": "permanent_cover_blocked",
			"brute_id": int(brute.get_instance_id()) if brute != null else 0,
			"target_id": int(attack_target.get_instance_id()) if attack_target != null else 0,
			"changed_blocks": 0,
			"positions": [],
		}
		_last_action = result.duplicate(true)
		_publish_if_changed(true)
		return result
	return super.resolve_brute_attack(brute, attack_target)


func get_snapshot() -> Dictionary:
	var snapshot := super.get_snapshot()
	snapshot["permanent_cover_block_count"] = _permanent_cover_block_count
	return snapshot


func _permanent_cover_blocks_lane(brute: Node3D, attack_target: Node3D) -> bool:
	if not _runtime_ready() or brute == null or attack_target == null:
		return false
	if not is_instance_valid(brute) or not is_instance_valid(attack_target):
		return false
	var start := brute.global_position + Vector3.UP * 1.05
	var finish := attack_target.global_position + Vector3.UP * 1.0
	for sample: Dictionary in PolicyScript.line_samples(start, finish):
		if float(sample.get("distance_from_start", INF)) > MAX_BREAK_DISTANCE:
			break
		var position: Vector3i = sample.get("position", Vector3i.ZERO)
		var block_id := str(world.call("get_block", position))
		var local_height := float(sample.get("local_height", 0.5))
		if not PolicyScript.blocks_walk_lane(block_id, local_height):
			continue
		if PolicyScript.is_breakable_cover(block_id) and _is_player_override(position, block_id):
			return false
		return true
	return false


func _bind_parent_lifecycle() -> void:
	var parent_hub := get_parent()
	if parent_hub == null or not is_instance_valid(parent_hub):
		return
	bind_parent_hub(parent_hub)


func _connect_parent_lifecycle() -> void:
	if _lifecycle_hub == null or not is_instance_valid(_lifecycle_hub):
		return
	var start_callback := Callable(self, "_on_world_start_requested")
	if _lifecycle_hub.has_signal("start_world_requested") and not _lifecycle_hub.is_connected(
		"start_world_requested", start_callback
	):
		_lifecycle_hub.connect("start_world_requested", start_callback)
	var return_callback := Callable(self, "_on_return_to_menu_requested")
	if _lifecycle_hub.has_signal("return_to_menu_requested") and not _lifecycle_hub.is_connected(
		"return_to_menu_requested", return_callback
	):
		_lifecycle_hub.connect("return_to_menu_requested", return_callback)


func _disconnect_parent_lifecycle() -> void:
	if _lifecycle_hub == null or not is_instance_valid(_lifecycle_hub):
		_lifecycle_hub = null
		return
	var start_callback := Callable(self, "_on_world_start_requested")
	if _lifecycle_hub.has_signal("start_world_requested") and _lifecycle_hub.is_connected(
		"start_world_requested", start_callback
	):
		_lifecycle_hub.disconnect("start_world_requested", start_callback)
	var return_callback := Callable(self, "_on_return_to_menu_requested")
	if _lifecycle_hub.has_signal("return_to_menu_requested") and _lifecycle_hub.is_connected(
		"return_to_menu_requested", return_callback
	):
		_lifecycle_hub.disconnect("return_to_menu_requested", return_callback)
	_lifecycle_hub = null


func _on_world_start_requested(_state: Dictionary) -> void:
	clear("world_start_requested")


func _on_return_to_menu_requested() -> void:
	clear("return_to_menu_requested")
	world = null
	player = null
	_bound_world_id = ""


func _exit_tree() -> void:
	_disconnect_parent_lifecycle()
	super._exit_tree()
