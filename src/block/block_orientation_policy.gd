class_name BlockOrientationPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const STAIR_FAMILY := "oak_stairs"
const STAIR_VARIANTS: Array[String] = [
	"oak_stairs",
	"oak_stairs_east",
	"oak_stairs_north",
	"oak_stairs_west",
]


static func supports(block_id: String) -> bool:
	return family_id(block_id) == STAIR_FAMILY


static func family_id(block_id: String) -> String:
	return str(BlockRegistryScript.get_definition(block_id).get("orientation_family", ""))


static func canonical_block_id(block_id: String) -> String:
	var family := family_id(block_id)
	return family if not family.is_empty() else block_id


static func rotation_quarters(block_id: String) -> int:
	return posmod(
		int(BlockRegistryScript.get_definition(block_id).get("rotation_quarters", 0)),
		4
	)


static func resolve_for_forward(block_id: String, forward: Vector3) -> String:
	var family := family_id(block_id)
	if family.is_empty():
		return block_id
	var quarters := rotation_from_forward(forward, rotation_quarters(block_id))
	if family == STAIR_FAMILY:
		return STAIR_VARIANTS[quarters]
	return block_id


static func variant_for_quarters(block_id: String, quarters: int) -> String:
	var family := family_id(block_id)
	if family == STAIR_FAMILY:
		return STAIR_VARIANTS[posmod(quarters, 4)]
	return block_id


static func rotation_from_forward(forward: Vector3, fallback: int = 0) -> int:
	var horizontal := Vector2(forward.x, forward.z)
	if horizontal.length_squared() <= 0.0001:
		return posmod(fallback, 4)
	if absf(horizontal.x) > absf(horizontal.y):
		return 1 if horizontal.x > 0.0 else 3
	return 0 if horizontal.y > 0.0 else 2


static func rise_direction(block_id: String) -> Vector3i:
	match rotation_quarters(block_id):
		1:
			return Vector3i.RIGHT
		2:
			return Vector3i.FORWARD
		3:
			return Vector3i.LEFT
		_:
			return Vector3i.BACK


static func direction_name(block_id: String) -> String:
	match rotation_quarters(block_id):
		1:
			return "east"
		2:
			return "north"
		3:
			return "west"
		_:
			return "south"
