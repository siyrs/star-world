class_name PlayerPhysicsProfile
extends Node

const PhysicsPolicy = preload("res://src/core/physics_interaction_policy.gd")


func _ready() -> void:
	var player := get_parent() as CharacterBody3D
	if player == null:
		push_error("PlayerPhysicsProfile must be a child of CharacterBody3D")
		return
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	PhysicsPolicy.configure_player(player, ray)
