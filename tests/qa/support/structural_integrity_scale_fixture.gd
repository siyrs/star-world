class_name StructuralIntegrityScaleFixture
extends RefCounted

const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const LadderPolicyScript = preload("res://src/block/block_ladder_policy.gd")

const TARGET_DOOR_COUNT := 128
const TARGET_LADDER_COUNT := 256
const FALLBACK_DOOR_COUNT := 6
const FALLBACK_LADDER_COUNT := 10


static func build_main(center_chunk: Vector2i, floor_y: int) -> Dictionary:
	var mutation_map: Dictionary = {}
	var support_positions: Array[Vector3i] = []
	var support_seen: Dictionary = {}
	var target_positions: Dictionary = {}
	var target_collision_count := 0
	var target_door_cells: Array[Vector3i] = []
	var target_ladder_cells: Array[Vector3i] = []
	var control_doors: Array[Dictionary] = []
	var control_ladders: Array[Dictionary] = []
	var base_chunk := center_chunk - Vector2i(2, 2)

	for door_index in TARGET_DOOR_COUNT:
		var chunk_index := int(door_index / 8)
		var within := door_index % 8
		var chunk_coord := base_chunk + Vector2i(chunk_index % 4, int(chunk_index / 4))
		var local_x := 0 if within % 2 == 0 else 15
		var local_z := 1 + int(within / 2) * 4
		var lower := Vector3i(
			chunk_coord.x * 16 + local_x,
			floor_y + 1,
			chunk_coord.y * 16 + local_z,
		)
		var support := lower + Vector3i.DOWN
		var upper := lower + Vector3i.UP
		var lower_id := DoorPolicyScript.variant(
			door_index % 4,
			false,
			door_index % 3 == 0,
		)
		target_collision_count += _record_target_position(
			target_positions,
			support,
			"door_support",
		)
		target_collision_count += _record_target_position(
			target_positions,
			lower,
			"door_lower",
		)
		target_collision_count += _record_target_position(
			target_positions,
			upper,
			"door_upper",
		)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(
			mutation_map,
			upper,
			DoorPolicyScript.upper_variant(lower_id),
		)
		_append_unique_position(support_positions, support_seen, support)
		target_door_cells.append(lower)
		target_door_cells.append(upper)

	for ladder_index in TARGET_LADDER_COUNT:
		var chunk_index := int(ladder_index / 16)
		var within := ladder_index % 16
		var layer := int(within / 8)
		var slot := within % 8
		var chunk_coord := base_chunk + Vector2i(chunk_index % 4, int(chunk_index / 4))
		var x_edge_positions := (
			[2, 6]
			if posmod(chunk_coord.x, 2) == 0
			else [10, 14]
		)
		var z_edge_positions := (
			[2, 6]
			if posmod(chunk_coord.y, 2) == 0
			else [10, 14]
		)
		var local_x := 0
		var local_z := 0
		var block_id := "ladder"
		if slot < 4:
			local_x = 0 if slot < 2 else 15
			local_z = int(x_edge_positions[slot % 2])
			block_id = "ladder_west" if local_x == 0 else "ladder_east"
		else:
			var side_slot := slot - 4
			local_z = 0 if side_slot < 2 else 15
			local_x = int(z_edge_positions[side_slot % 2])
			block_id = "ladder_north" if local_z == 0 else "ladder"
		var ladder_position := Vector3i(
			chunk_coord.x * 16 + local_x,
			floor_y + 4 + layer,
			chunk_coord.y * 16 + local_z,
		)
		var support := ladder_position + LadderPolicyScript.support_offset(block_id)
		target_collision_count += _record_target_position(
			target_positions,
			support,
			"ladder_support",
		)
		target_collision_count += _record_target_position(
			target_positions,
			ladder_position,
			"ladder",
		)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, ladder_position, block_id)
		_append_unique_position(support_positions, support_seen, support)
		target_ladder_cells.append(ladder_position)

	var gallery_origin := Vector3i(
		center_chunk.x * 16 + 8,
		floor_y + 1,
		(center_chunk.y - 3) * 16 + 8,
	)
	for x_offset in range(-7, 8):
		for z_offset in range(-5, 7):
			_set_mutation(
				mutation_map,
				Vector3i(
					gallery_origin.x + x_offset,
					floor_y,
					gallery_origin.z + z_offset,
				),
				"stone",
			)
			for y_offset in range(1, 8):
				_set_mutation(
					mutation_map,
					Vector3i(
						gallery_origin.x + x_offset,
						floor_y + y_offset,
						gallery_origin.z + z_offset,
					),
					"air",
				)
	for index in 4:
		var lower := Vector3i(
			gallery_origin.x - 5 + index * 3,
			floor_y + 1,
			gallery_origin.z + 2,
		)
		var lower_id := DoorPolicyScript.variant(index, false, index % 2 == 1)
		_set_mutation(mutation_map, lower + Vector3i.DOWN, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(
			mutation_map,
			lower + Vector3i.UP,
			DoorPolicyScript.upper_variant(lower_id),
		)
		control_doors.append({"lower": lower, "lower_id": lower_id})
	var ladder_ids := ["ladder", "ladder_east", "ladder_north", "ladder_west"]
	for index in 4:
		var ladder_id := str(ladder_ids[index])
		var ladder_position := Vector3i(
			gallery_origin.x - 5 + index * 3,
			floor_y + 4,
			gallery_origin.z + 3,
		)
		var support := ladder_position + LadderPolicyScript.support_offset(ladder_id)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, ladder_position, ladder_id)
		control_ladders.append({"position": ladder_position, "block_id": ladder_id})

	return {
		"mutations": _mutation_array(mutation_map),
		"support_positions": support_positions,
		"target_door_cells": target_door_cells,
		"target_ladder_cells": target_ladder_cells,
		"control_doors": control_doors,
		"control_ladders": control_ladders,
		"gallery_origin": gallery_origin,
		"target_position_count": target_positions.size(),
		"target_collision_count": target_collision_count,
	}


static func build_fallback(gallery_origin: Vector3i, floor_y: int) -> Dictionary:
	var mutation_map: Dictionary = {}
	var support_positions: Array[Vector3i] = []
	var support_seen: Dictionary = {}
	var fixture_positions: Dictionary = {}
	var collision_count := 0
	var structure_cells: Array[Vector3i] = []
	for index in FALLBACK_DOOR_COUNT:
		var lower := Vector3i(
			gallery_origin.x - 6 + index * 2,
			floor_y + 1,
			gallery_origin.z - 2,
		)
		var support := lower + Vector3i.DOWN
		var upper := lower + Vector3i.UP
		var lower_id := DoorPolicyScript.variant(index % 4, false, index % 2 == 0)
		collision_count += _record_target_position(fixture_positions, support, "door_support")
		collision_count += _record_target_position(fixture_positions, lower, "door_lower")
		collision_count += _record_target_position(fixture_positions, upper, "door_upper")
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(
			mutation_map,
			upper,
			DoorPolicyScript.upper_variant(lower_id),
		)
		_append_unique_position(support_positions, support_seen, support)
		structure_cells.append(lower)
		structure_cells.append(upper)
	for index in FALLBACK_LADDER_COUNT:
		var ladder_ids := ["ladder", "ladder_east", "ladder_north", "ladder_west"]
		var ladder_id := str(ladder_ids[index % ladder_ids.size()])
		var ladder_position := Vector3i(
			gallery_origin.x - 6 + (index % 5) * 3,
			floor_y + 5 + int(index / 5),
			gallery_origin.z - 1,
		)
		var support := ladder_position + LadderPolicyScript.support_offset(ladder_id)
		collision_count += _record_target_position(fixture_positions, support, "ladder_support")
		collision_count += _record_target_position(fixture_positions, ladder_position, "ladder")
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, ladder_position, ladder_id)
		_append_unique_position(support_positions, support_seen, support)
		structure_cells.append(ladder_position)
	return {
		"mutations": _mutation_array(mutation_map),
		"support_positions": support_positions,
		"structure_cells": structure_cells,
		"fixture_position_count": fixture_positions.size(),
		"collision_count": collision_count,
	}


static func _record_target_position(
	positions: Dictionary,
	position: Vector3i,
	role: String
) -> int:
	var key := _position_key(position)
	if positions.has(key):
		return 1
	positions[key] = role
	return 0


static func _set_mutation(
	mutation_map: Dictionary,
	position: Vector3i,
	block_id: String
) -> void:
	mutation_map[_position_key(position)] = {
		"position": position,
		"block_id": block_id,
	}


static func _mutation_array(mutation_map: Dictionary) -> Array:
	var keys: Array[String] = []
	for raw_key: Variant in mutation_map.keys():
		keys.append(str(raw_key))
	keys.sort()
	var result: Array = []
	for key: String in keys:
		var raw_change: Variant = mutation_map.get(key, {})
		if raw_change is Dictionary:
			result.append((raw_change as Dictionary).duplicate(true))
	return result


static func _append_unique_position(
	positions: Array[Vector3i],
	seen: Dictionary,
	position: Vector3i
) -> void:
	var key := _position_key(position)
	if seen.has(key):
		return
	seen[key] = true
	positions.append(position)


static func _position_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]
