class_name ItemPickup
extends Area3D

signal collected(item_id: String, count: int)

const PhysicsPolicy = preload("res://src/core/physics_interaction_policy.gd")

var item_id: String = ""
var item_count: int = 1
var inventory_service
var life_seconds: float = 180.0
var _collection_locked := false


func setup(p_item_id: String, p_count: int, p_inventory = null) -> void:
	item_id = p_item_id
	item_count = maxi(1, p_count)
	inventory_service = p_inventory


func _ready() -> void:
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
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	rotation.y += delta * 2.2
	position.y += sin(Time.get_ticks_msec() * 0.004) * delta * 0.12
	life_seconds -= delta
	if life_seconds <= 0.0:
		queue_free()


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
	if item_count <= 0:
		_collection_locked = true
		monitoring = false
		queue_free()


func _item_color() -> Color:
	if inventory_service != null and inventory_service.registry != null:
		var item: Dictionary = inventory_service.registry.get_item(item_id)
		return Color.from_string(str(item.get("color", "#FFFFFF")), Color.WHITE)
	return Color("#FFE06A")
