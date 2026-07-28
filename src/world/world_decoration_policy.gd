class_name WorldDecorationPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ROLL_SCALE := 10000
const ALLOWED_RULE_TYPES: Array[String] = [
	"surface_roll",
	"column_roll",
	"ruin_grid",
	"ruin_debris",
]


static func resolve_block(
	profile: Dictionary,
	position: Vector3i,
	terrain_height: int,
	tree_present: bool,
	sky_strength: float,
	hash_roll: Callable
) -> String:
	var raw_rules: Variant = profile.get("rules", [])
	if raw_rules is not Array or not hash_roll.is_valid():
		return BlockRegistryScript.AIR
	var rules: Array = raw_rules
	for raw_rule: Variant in rules:
		if raw_rule is not Dictionary:
			continue
		var rule: Dictionary = raw_rule
		if not _common_constraints_allow(
			rule,
			position,
			terrain_height,
			tree_present,
			sky_strength
		):
			continue
		var resolved := BlockRegistryScript.AIR
		match str(rule.get("type", "")):
			"surface_roll":
				resolved = _resolve_surface_roll(rule, position, terrain_height, hash_roll)
			"column_roll":
				resolved = _resolve_column_roll(rule, position, terrain_height, hash_roll)
			"ruin_grid":
				resolved = _resolve_ruin_grid(rule, position, terrain_height, hash_roll)
			"ruin_debris":
				resolved = _resolve_ruin_debris(rule, position, terrain_height, hash_roll)
		if resolved != BlockRegistryScript.AIR:
			return resolved
	return BlockRegistryScript.AIR


static func get_poi_snapshot(
	profile: Dictionary,
	x: int,
	z: int,
	hash_roll: Callable
) -> Dictionary:
	var sites: Array[Dictionary] = []
	var raw_rules: Variant = profile.get("rules", [])
	if raw_rules is Array and hash_roll.is_valid():
		for raw_rule: Variant in raw_rules:
			if raw_rule is not Dictionary:
				continue
			var rule: Dictionary = raw_rule
			if str(rule.get("type", "")) != "ruin_grid":
				continue
			var site := _site_context(rule, x, z, hash_roll)
			site["rule_id"] = str(rule.get("id", ""))
			site["block_id"] = str(rule.get("block_id", ""))
			sites.append(site)
	return {
		"profile_id": str(profile.get("id", "")),
		"summary": str(profile.get("summary", "")),
		"rule_count": (raw_rules as Array).size() if raw_rules is Array else 0,
		"sites": sites,
	}


static func _common_constraints_allow(
	rule: Dictionary,
	position: Vector3i,
	terrain_height: int,
	tree_present: bool,
	sky_strength: float
) -> bool:
	if position.y <= terrain_height:
		return false
	if terrain_height < int(rule.get("minimum_surface_y", -1)):
		return false
	if bool(rule.get("exclude_tree", false)) and tree_present:
		return false
	if sky_strength < float(rule.get("minimum_sky_strength", -1.0)):
		return false
	return true


static func _resolve_surface_roll(
	rule: Dictionary,
	position: Vector3i,
	terrain_height: int,
	hash_roll: Callable
) -> String:
	if position.y != terrain_height + int(rule.get("surface_offset", 1)):
		return BlockRegistryScript.AIR
	var roll := _roll(hash_roll, position.x, 0, position.z, int(rule.get("roll_salt", 0)))
	var minimum_roll := int(rule.get("minimum_roll", 0))
	var maximum_roll := int(rule.get("maximum_roll", 0))
	return (
		str(rule.get("block_id", BlockRegistryScript.AIR))
		if roll >= minimum_roll and roll < maximum_roll
		else BlockRegistryScript.AIR
	)


static func _resolve_column_roll(
	rule: Dictionary,
	position: Vector3i,
	terrain_height: int,
	hash_roll: Callable
) -> String:
	var roll := _roll(hash_roll, position.x, 0, position.z, int(rule.get("roll_salt", 0)))
	if roll >= int(rule.get("maximum_roll", 0)):
		return BlockRegistryScript.AIR
	var minimum_height := int(rule.get("minimum_height", 1))
	var maximum_height := int(rule.get("maximum_height", minimum_height))
	var height_span := maxi(1, maximum_height - minimum_height + 1)
	var height := minimum_height + posmod(
		_roll(
			hash_roll,
			position.x,
			0,
			position.z,
			int(rule.get("height_roll_salt", 0))
		),
		height_span
	)
	return (
		str(rule.get("block_id", BlockRegistryScript.AIR))
		if position.y <= terrain_height + height
		else BlockRegistryScript.AIR
	)


static func _resolve_ruin_grid(
	rule: Dictionary,
	position: Vector3i,
	terrain_height: int,
	hash_roll: Callable
) -> String:
	var site := _site_context(rule, position.x, position.z, hash_roll)
	if not bool(site.get("active", false)):
		return BlockRegistryScript.AIR
	var center := site.get("center", Vector2i.ZERO) as Vector2i
	var local_x := position.x - center.x
	var local_z := position.z - center.y
	var local_radius := int(rule.get("local_radius", 0))
	var grid_spacing := maxi(1, int(rule.get("grid_spacing", 1)))
	if absi(local_x) > local_radius or absi(local_z) > local_radius:
		return BlockRegistryScript.AIR
	if posmod(local_x, grid_spacing) != 0 or posmod(local_z, grid_spacing) != 0:
		return BlockRegistryScript.AIR
	var minimum_height := int(rule.get("minimum_height", 1))
	var maximum_height := int(rule.get("maximum_height", minimum_height))
	var height_span := maxi(1, maximum_height - minimum_height + 1)
	var height := minimum_height + posmod(
		_roll(
			hash_roll,
			position.x,
			0,
			position.z,
			int(rule.get("height_roll_salt", 0))
		),
		height_span
	)
	return (
		str(rule.get("block_id", BlockRegistryScript.AIR))
		if position.y <= terrain_height + height
		else BlockRegistryScript.AIR
	)


static func _resolve_ruin_debris(
	rule: Dictionary,
	position: Vector3i,
	terrain_height: int,
	hash_roll: Callable
) -> String:
	if position.y != terrain_height + int(rule.get("surface_offset", 1)):
		return BlockRegistryScript.AIR
	var site := _site_context(rule, position.x, position.z, hash_roll)
	if not bool(site.get("active", false)):
		return BlockRegistryScript.AIR
	var center := site.get("center", Vector2i.ZERO) as Vector2i
	var local_radius := int(rule.get("local_radius", 0))
	if absi(position.x - center.x) > local_radius or absi(position.z - center.y) > local_radius:
		return BlockRegistryScript.AIR
	var roll := _roll(hash_roll, position.x, 0, position.z, int(rule.get("roll_salt", 0)))
	return (
		str(rule.get("block_id", BlockRegistryScript.AIR))
		if roll < int(rule.get("maximum_roll", 0))
		else BlockRegistryScript.AIR
	)


static func _site_context(
	rule: Dictionary,
	x: int,
	z: int,
	hash_roll: Callable
) -> Dictionary:
	var cell_size := maxi(1, int(rule.get("cell_size", 1)))
	var cell_x := floori(float(x) / float(cell_size))
	var cell_z := floori(float(z) / float(cell_size))
	var site_roll := _roll(
		hash_roll,
		cell_x,
		0,
		cell_z,
		int(rule.get("site_roll_salt", 0))
	)
	var span := maxi(1, int(rule.get("center_offset_span", 1)))
	var half_span := floori(float(span) * 0.5)
	var offset_x := posmod(
		_roll(hash_roll, cell_x, 0, cell_z, int(rule.get("center_x_salt", 0))),
		span
	) - half_span
	var offset_z := posmod(
		_roll(hash_roll, cell_x, 0, cell_z, int(rule.get("center_z_salt", 0))),
		span
	) - half_span
	var center := Vector2i(
		cell_x * cell_size + floori(float(cell_size) * 0.5) + offset_x,
		cell_z * cell_size + floori(float(cell_size) * 0.5) + offset_z
	)
	return {
		"active": site_roll >= int(rule.get("site_minimum_roll", ROLL_SCALE)),
		"site_roll": site_roll,
		"cell": Vector2i(cell_x, cell_z),
		"center": center,
	}


static func _roll(
	hash_roll: Callable,
	x: int,
	y: int,
	z: int,
	salt: int
) -> int:
	return int(hash_roll.call(x, y, z, salt))
