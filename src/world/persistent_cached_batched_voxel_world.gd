class_name PersistentCachedBatchedVoxelWorld
extends "res://src/world/cached_batched_voxel_world.gd"


func serialize() -> Dictionary:
	# This production composition is the narrow persistence projection above the
	# transient rebuild and recent-snapshot layers. Runtime Chunk coordinates,
	# queues, caches and diagnostics never need to be constructed for a save.
	return {
		"version": 1,
		"profile_id": profile_id,
		"seed": seed_value,
		"world_id": world_id,
		"block_overrides": serialize_sparse_overrides(),
	}


func serialize_state() -> Dictionary:
	return serialize()
