class_name PhysicsInteractionPolicy
extends RefCounted

const Layers = preload("res://src/core/physics_layers.gd")


static func configure_player(body: CharacterBody3D, interaction_ray: RayCast3D = null) -> void:
	if body == null:
		return
	body.collision_layer = Layers.PLAYER
	body.collision_mask = Layers.PLAYER_BODY_MASK
	body.add_to_group(Layers.PLAYER_GROUP)
	if interaction_ray != null:
		interaction_ray.collision_mask = Layers.PLAYER_INTERACTION_MASK


static func configure_creature(body: CharacterBody3D) -> void:
	if body == null:
		return
	body.collision_layer = Layers.ENTITIES
	body.collision_mask = Layers.ENTITY_BODY_MASK


static func disable_body_collision(body: CollisionObject3D) -> void:
	if body == null:
		return
	body.collision_layer = 0
	body.collision_mask = 0


static func configure_pickup(area: Area3D) -> void:
	if area == null:
		return
	area.collision_layer = Layers.PICKUPS
	area.collision_mask = Layers.PICKUP_BODY_MASK
	area.monitoring = true
	area.monitorable = false
	area.add_to_group(Layers.PICKUP_GROUP)


static func is_player_body(body: Node) -> bool:
	if body == null or body is not CollisionObject3D:
		return false
	var collision_body := body as CollisionObject3D
	return (
		collision_body.is_in_group(Layers.PLAYER_GROUP)
		and (collision_body.collision_layer & Layers.PLAYER) != 0
	)
