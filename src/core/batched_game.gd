class_name BatchedStarWorldGame
extends "res://src/core/game.gd"

const BATCHED_WORLD_SCRIPT_PATH := "res://src/world/batched_voxel_world.gd"
const BATCHED_PLAYER_SCENE_PATH := "res://scenes/game/player.tscn"


func _ensure_core_nodes() -> void:
	if world == null and ResourceLoader.exists(BATCHED_WORLD_SCRIPT_PATH):
		var world_script: Script = load(BATCHED_WORLD_SCRIPT_PATH)
		world = world_script.new()
		world.name = "VoxelWorld"
		world_root.add_child(world)
	if player == null and ResourceLoader.exists(BATCHED_PLAYER_SCENE_PATH):
		var player_scene: PackedScene = load(BATCHED_PLAYER_SCENE_PATH)
		player = player_scene.instantiate()
		player.name = "Player"
		add_child(player)
