class_name ItemPickup
extends Area3D

signal collected(item_id: String, count: int)
signal stack_changed(item_id: String, count: int)

const PhysicsPolicy = preload("res://src/core/physics_interaction_policy.gd")
const DEFAULT_LIFETIME_SECONDS := 180.0
const MAX_ITEMS_PER_PICKUP := 65535

var item_id: String = ""
var item_count: int = 1
var inventory_service
var life_seconds: float = DEFAULT_LIFETIME_SECONDS
var _collection_locked := false
var _merge_count := 0
var _count_label: Label3D


func setup(p_item_id: String, p_count: int, p_inventory = null) -> void:
	item_id = p_item_id.strip_edges()
	item_count = clampi(p_count, 1, MAX_ITEMS_PER_PICKUP)
	inventory_service = p_inventory
	_update_count_label()


func _ready() -> void:
	add_to_group("pickups")
	PhysicsPolicy.configure_pickup(self)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.32
	collision.shape = shape
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mesh_instance.mesh = box
	mesh_instance.position.y = 0.2
	var material := StandardMaterial3D.new()
	material.albedo_color = _item_color()
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.25
	mesh_instance.material_override = material
	add_child(mesh_instance)
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
	add_child(_count_label)
	_update_count_label()
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	rotation.y += delta * 2.2
	position.y += sin(Time.get_ticks_msec() * 0.004) * delta * 0.12
	life_seconds -= delta
	if life_seconds <= 0.0:
		queue_free()


func can_merge(p_item_id: String) -> bool:
	return (
		not _collection_locked
		and not is_queued_for_deletion()
		and not item_id.is_empty()
		and item_id == p_item_id
		and item_count < MAX_ITEMS_PER_PICKUP
	)


func merge_items(p_count: int, refresh_lifetime: bool = true) -> int:
	if _collection_locked or p_count <= 0 or item_id.is_empty():
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
	}


func get_count_label() -> Label3D:
	return _count_label


func _on_body_entered(body: Node3D) -> void:
	if _collection_locked or not PhysicsPolicy.is_player_body(body):
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
