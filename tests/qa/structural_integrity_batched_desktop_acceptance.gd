extends "res://tests/qa/structural_integrity_desktop_acceptance.gd"


func _build_main_fixture(center_chunk: Vector2i, floor_y: int) -> Dictionary:
	var mutation_map: Dictionary = {}
	var support_positions: Array[Vector3i] = []
	var support_seen: Dictionary = {}
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
		var lower_id := DoorPolicyScript.variant(
			door_index % 4,
			false,
			door_index % 3 == 0,
		)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(
			mutation_map,
			lower + Vector3i.UP,
			DoorPolicyScript.upper_variant(lower_id),
		)
		_append_unique_position(support_positions, support_seen, support)
		target_door_cells.append(lower)
		target_door_cells.append(lower + Vector3i.UP)

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
	}
