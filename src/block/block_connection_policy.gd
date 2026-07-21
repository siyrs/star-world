class_name BlockConnectionPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const EAST := 1
const WEST := 2
const SOUTH := 4
const NORTH := 8
const ALL := EAST | WEST | SOUTH | NORTH
const GLASS_PANE_FAMILY := "glass_pane"
const OAK_FENCE_FAMILY := "oak_fence"

const DIRECTION_SPECS: Array[Dictionary] = [
	{"name":"east", "offset":Vector3i.RIGHT, "bit":EAST, "face_index":0},
	{"name":"west", "offset":Vector3i.LEFT, "bit":WEST, "face_index":1},
	{"name":"south", "offset":Vector3i.BACK, "bit":SOUTH, "face_index":4},
	{"name":"north", "offset":Vector3i.FORWARD, "bit":NORTH, "face_index":5},
]


static func supports(block_id: String) -> bool:
	return not family_id(block_id).is_empty()


static func family_id(block_id: String) -> String:
	return str(
		BlockRegistryScript.get_definition(block_id).get("connection_family", "")
	).strip_edges()


static func can_connect(block_id: String, neighbor_id: String) -> bool:
	var family := family_id(block_id)
	if family.is_empty() or neighbor_id == BlockRegistryScript.AIR:
		return false
	if family_id(neighbor_id) == family:
		return true
	var neighbor := BlockRegistryScript.get_definition(neighbor_id)
	if neighbor.is_empty():
		return false
	if bool(neighbor.get("connection_anchor", false)):
		return true
	if not bool(neighbor.get("solid", false)):
		return false
	return str(neighbor.get("shape", "cube")) == "cube"


static func resolve_mask(block_id: String, neighbor_ids: Dictionary = {}) -> int:
	if not supports(block_id):
		return 0
	var result := 0
	for spec: Dictionary in DIRECTION_SPECS:
		var direction_name := str(spec.get("name", ""))
		var neighbor_id := str(
			neighbor_ids.get(direction_name, BlockRegistryScript.AIR)
		)
		if can_connect(block_id, neighbor_id):
			result |= int(spec.get("bit", 0))
	return result if result != 0 else fallback_mask(block_id)


static func fallback_mask(block_id: String) -> int:
	if family_id(block_id) != GLASS_PANE_FAMILY:
		return 0
	var quarters := posmod(
		int(BlockRegistryScript.get_definition(block_id).get("rotation_quarters", 0)),
		4
	)
	return EAST | WEST if quarters % 2 == 0 else NORTH | SOUTH


static func display_mask(block_id: String) -> int:
	return ALL if family_id(block_id) == OAK_FENCE_FAMILY else fallback_mask(block_id)


static func read_neighbors(world: Node, block_position: Vector3i) -> Dictionary:
	var result := empty_neighbors()
	if world == null or not is_instance_valid(world) or not world.has_method("get_block"):
		return result
	for spec: Dictionary in DIRECTION_SPECS:
		var direction_name := str(spec.get("name", ""))
		var offset: Vector3i = spec.get("offset", Vector3i.ZERO)
		result[direction_name] = str(
			world.call("get_block", block_position + offset)
		)
	return result


static func empty_neighbors() -> Dictionary:
	return {
		"east":BlockRegistryScript.AIR,
		"west":BlockRegistryScript.AIR,
		"south":BlockRegistryScript.AIR,
		"north":BlockRegistryScript.AIR,
	}


static func bit_for_face(face_index: int) -> int:
	match face_index:
		0:
			return EAST
		1:
			return WEST
		4:
			return SOUTH
		5:
			return NORTH
		_:
			return 0


static func has_direction(mask: int, direction_bit: int) -> bool:
	return direction_bit != 0 and (mask & direction_bit) != 0


static func connected_face(
	block_id: String,
	connection_mask: int,
	face_index: int,
	neighbor_id: String
) -> bool:
	var direction_bit := bit_for_face(face_index)
	return (
		has_direction(connection_mask, direction_bit)
		and can_connect(block_id, neighbor_id)
	)


static func mask_names(mask: int) -> Array[String]:
	var result: Array[String] = []
	for spec: Dictionary in DIRECTION_SPECS:
		if has_direction(mask, int(spec.get("bit", 0))):
			result.append(str(spec.get("name", "")))
	return result
