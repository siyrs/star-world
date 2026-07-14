class_name CreaturePopulationPolicy
extends RefCounted

const PERSISTENT_GROUP: StringName = &"persistent_creatures"


static func count_group(root: Node, group_name: StringName) -> int:
	if root == null:
		return 0
	var count := 0
	for child in root.get_children():
		if child is Node and child.is_in_group(group_name):
			count += 1
	return count


static func collect_out_of_range(
	root: Node, player: Node3D, maximum_distance: float
) -> Array[Node]:
	var result: Array[Node] = []
	if root == null or player == null or not is_instance_valid(player):
		return result
	var maximum_distance_squared := maximum_distance * maximum_distance
	for child in root.get_children():
		if child is not Node3D or not child.is_in_group("creatures"):
			continue
		if child.is_in_group(PERSISTENT_GROUP):
			continue
		if (
			child.global_position.distance_squared_to(player.global_position)
			> maximum_distance_squared
		):
			result.append(child)
	return result
