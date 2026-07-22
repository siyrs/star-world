class_name ItemPickup
extends Area3D

signal collected(item_id: String, count: int)
signal stack_changed(item_id: String, count: int)
signal expired(item_id: String, count: int)

const PhysicsPolicy = preload("res://src/core/physics_interaction_policy.gd")
const VisualResources = preload("res://src/entity/pickup_visual_resource_cache.gd")
const DEFAULT_LIFETIME_SECONDS := 180.0
const MAX_ITEMS_PER_PICKUP := 65535
const MAX_RUNTIME_DELTA_SECONDS := 0.25
const ROTATION_SPEED := 2.2
const BOB_FREQUENCY := 4.0
const BOB_AMPLITUDE := 0.12

var item_id: String = ""
var item_count: int = 1
var inventory_service
var life_seconds: float = DEFAULT_LIFETIME_SECONDS
var _collection_locked := false
var _merge_count := 0
var _count_label: Label3D
var _visual_root: Node3D
var _mesh_instance: MeshInstance3D
var _collision_shape_node: CollisionShape3D
var _shared_runtime_managed := false
var _runtime_phase := 0.0
var _runtime_advance_count := 0
var _visual_offset_y := 0.0
var _expired := false


func setup(p_item_id: String, p_count: int, p_inventory = null) -> void:
	item_id = p_item_id.strip_edges()
	item_count = clampi(p_count, 1, MAX_ITEMS_PER_PICKUP)
	inventory_service = p_inventory
	life_seconds = DEFAULT_LIFETIME_SECONDS
	_expired = false
	_update_count_label()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("pickups")
	PhysicsPolicy.configure_pickup(self)
	_collision_shape_node = CollisionShape3D.new()
	_collision_shape_node.name = "PickupCollision"
	_collision_shape_node.shape = VisualResources.get_collision_shape()
	add_child(_collision_shape_node)
	_visual_root = Node3D.new()
	_visual_root.name = "PickupVisual"
	add_child(_visual_root)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "PickupMesh"
	_mesh_instance.mesh = VisualResources.get_box_mesh()
	_mesh_instance.position.y = 0.2
	_mesh_instance.material_override = VisualResources.get_material(_item_color())
	_visual_root.add_child(_mesh_instance)
	_count_label = Label3D.new()
	_count_label.name = "StackCount"
	_count_label.position = Vector3(0.0, 0.62, 0.0)
	_count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_count_label.fixed_size = true
	_count_label.no_depth_test = true
	_count_label.font_size = 30
	_count_label.outline_size = 8
	_count_label.modulate = Color.WHITE
	_count_label.outline_modulate = Color(0.04, 0.04, 0.05, 0.95)
	_visual_root.add_child(_count_label)
	if _runtime_phase <= 0.0:
		_runtime_phase = float(int(get_instance_id()) % 6283) / 1000.0
	_update_count_label()
	body_entered.connect(_on_body_entered)
	set_process(not _shared_runtime_managed)


func _process(delta: float) -> void:
	if _shared_runtime_managed:
		return
	advance_runtime(delta, float(Time.get_ticks_msec()) / 1000.0)


func configure_shared_runtime(phase: float = 0.0) -> void:
	_shared_runtime_managed = true
	_runtime_phase = fmod(maxf(0.0, phase), TAU)
	set_process(false)


func release_shared_runtime() -> void:
	_shared_runtime_managed = false
	set_process(is_inside_tree() and not _expired and not _collection_locked)


func advance_runtime(delta: float, elapsed_seconds: float) -> bool:
	if _expired or _collection_locked or is_queued_for_deletion():
		return false
	var safe_delta := clampf(delta, 0.0, MAX_RUNTIME_DELTA_SECONDS) if is_finite(delta) else 0.0
	if safe_delta <= 0.0:
		return false
	_runtime_advance_count += 1
	life_seconds = maxf(0.0, life_seconds - safe_delta)
	var safe_elapsed := maxf(0.0, elapsed_seconds) if is_finite(elapsed_seconds) else 0.0
	_visual_offset_y = sin(_runtime_phase + safe_elapsed * BOB_FREQUENCY) * BOB_AMPLITUDE
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.position = Vector3(0.0, _visual_offset_y, 0.0)
		_visual_root.rotation.y = fmod(_runtime_phase + safe_elapsed * ROTATION_SPEED, TAU)
	if life_seconds <= 0.0:
		_expire()
		return true
	return false


func can_merge(p_item_id: String) -> bool:
	return (
		not _collection_locked
		and not _expired
		and not is_queued_for_deletion()
		and not item_id.is_empty()
		and item_id == p_item_id
		and item_count < MAX_ITEMS_PER_PICKUP
	)


func merge_items(p_count: int, refresh_lifetime: bool = true) -> int:
	if _collection_locked or _expired or p_count <= 0 or item_id.is_empty():
		return maxi(0, p_count)
	var accepted := mini(p_count, MAX_ITEMS_PER_PICKUP - item_count)
	if accepted <= 0:
		return p_count
	item_count += accepted
	_merge_count += 1
	if refresh_lifetime:
		life_seconds = maxf(life_seconds, DEFAULT_LIFETIME_SECONDS)
	_update_count_label()
	stack_changed.emit(item_id, item_count)
	return p_count - accepted


func get_pickup_snapshot() -> Dictionary:
	return {
		"item_id": item_id,
		"item_count": item_count,
		"life_seconds": maxf(0.0, life_seconds),
		"collection_locked": _collection_locked,
		"merge_count": _merge_count,
		"max_items_per_pickup": MAX_ITEMS_PER_PICKUP,
		"count_label_visible": _count_label != null and _count_label.visible,
		"shared_runtime_managed": _shared_runtime_managed,
		"process_enabled": is_processing(),
		"runtime_advance_count": _runtime_advance_count,
		"visual_offset_y": _visual_offset_y,
		"collision_anchor": [position.x, position.y, position.z],
		"expired": _expired,
	}


func get_count_label() -> Label3D:
	return _count_label


func get_visual_root() -> Node3D:
	return _visual_root


func get_visual_offset() -> Vector3:
	return Vector3(0.0, _visual_offset_y, 0.0)


func get_visual_resource_ids() -> Dictionary:
	return {
		"mesh_id": (
			_mesh_instance.mesh.get_instance_id()
			if _mesh_instance != null and _mesh_instance.mesh != null
			else 0
		),
		"material_id": (
			_mesh_instance.material_override.get_instance_id()
			if _mesh_instance != null and _mesh_instance.material_override != null
			else 0
		),
		"collision_shape_id": (
			_collision_shape_node.shape.get_instance_id()
			if _collision_shape_node != null and _collision_shape_node.shape != null
			else 0
		),
	}


func _on_body_entered(body: Node3D) -> void:
	if _collection_locked or _expired or not PhysicsPolicy.is_player_body(body):
		return
	var leftover := item_count
	if body.has_method("collect_item"):
		leftover = int(body.call("collect_item", item_id, item_count))
	elif inventory_service != null and inventory_service.has_method("add_item"):
		leftover = int(inventory_service.call("add_item", item_id, item_count))
	else:
		return
	_finish_collection(clampi(leftover, 0, item_count))


func _finish_collection(leftover: int) -> void:
	var accepted := item_count - leftover
	if accepted > 0:
		collected.emit(item_id, accepted)
	item_count = leftover
	_update_count_label()
	if item_count <= 0:
		_collection_locked = true
		# Area3D cannot change monitoring during body_entered signal dispatch.
		# Defer both physics shutdown and disposal to keep collection error-free.
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		call_deferred("queue_free")


func _expire() -> void:
	if _expired or _collection_locked:
		return
	_expired = true
	_collection_locked = true
	expired.emit(item_id, item_count)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	call_deferred("queue_free")


func _update_count_label() -> void:
	if _count_label == null or not is_instance_valid(_count_label):
		return
	_count_label.visible = item_count > 1
	_count_label.text = "×%d" % item_count if item_count > 1 else ""


func _item_color() -> Color:
	if inventory_service != null and inventory_service.registry != null:
		var item: Dictionary = inventory_service.registry.get_item(item_id)
		return Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	return Color("#FFE06A")
