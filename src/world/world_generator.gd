class_name StarWorldGenerator
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ResourceDistributionRegistryScript = preload("res://src/world/resource_distribution_registry.gd")
const WORLD_HEIGHT := 64
const SEA_LEVEL := 18
const RESOURCE_ROLL_SALT := 211

var profile_id := "star_continent"
var seed_value := 734521
var height_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var resource_distribution = ResourceDistributionRegistryScript.new()


func configure(p_profile_id: String, p_seed: int) -> void:
	profile_id = normalize_profile_id(p_profile_id)
	seed_value = p_seed
	height_noise.seed = seed_value
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	height_noise.frequency = 0.012
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = 4
	detail_noise.seed = seed_value ^ 0x51F2A3
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.038
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	cave_noise.seed = seed_value ^ 0x7A31C9
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cave_noise.frequency = 0.075
	cave_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	cave_noise.fractal_octaves = 3


func normalize_profile_id(value: String) -> String:
	match value:
		"green_continent", "green", "star_continent": return "star_continent"
		"desert", "desert_ruins": return "desert_ruins"
		"ice", "snow", "frozen_wastes": return "frozen_wastes"
		"mountains", "sky", "sky_islands": return "sky_islands"
		"caves", "cave", "abyss_world": return "abyss_world"
		_: return "star_continent"


func get_block(block_position: Vector3i) -> String:
	if block_position.y < 0 or block_position.y >= WORLD_HEIGHT:
		return BlockRegistryScript.AIR
	if block_position.y == 0:
		return BlockRegistryScript.BEDROCK
	var terrain_height := get_surface_height(block_position.x, block_position.z)
	if profile_id == "sky_islands":
		return _get_sky_block(block_position, terrain_height)
	if block_position.y > terrain_height:
		if profile_id == "star_continent":
			var tree_block := _get_tree_block(block_position, terrain_height)
			if tree_block != BlockRegistryScript.AIR:
				return tree_block
		if profile_id == "star_continent" and block_position.y <= SEA_LEVEL:
			return "water"
		if profile_id == "frozen_wastes" and block_position.y <= SEA_LEVEL:
			return "ice" if block_position.y == SEA_LEVEL else "water"
		return BlockRegistryScript.AIR
	if profile_id == "abyss_world" and block_position.y > 3 and block_position.y < terrain_height - 2:
		var cave_density := cave_noise.get_noise_3d(block_position.x, block_position.y * 0.9, block_position.z)
		if cave_density > 0.51:
			return "lava" if block_position.y <= 4 and _hash_roll(block_position.x, block_position.y, block_position.z, 17) < 3600 else BlockRegistryScript.AIR
	return _layer_block(block_position, terrain_height)


func get_surface_height(x: int, z: int) -> int:
	var broad := height_noise.get_noise_2d(x, z)
	var detail := detail_noise.get_noise_2d(x, z)
	match profile_id:
		"desert_ruins":
			return clampi(18 + roundi(broad * 5.0 + detail * 2.0), 10, 31)
		"frozen_wastes":
			return clampi(22 + roundi(broad * 10.0 + detail * 3.0), 11, 43)
		"sky_islands":
			return clampi(42 + roundi(broad * 5.0 + detail * 2.0), 32, 53)
		"abyss_world":
			return clampi(35 + roundi(broad * 4.0 + detail * 2.0), 27, 44)
		_:
			var river := absf(detail_noise.get_noise_2d(x * 0.62, z * 0.62))
			if river < 0.065:
				return SEA_LEVEL - 2
			return clampi(21 + roundi(broad * 7.0 + detail * 2.0), 12, 35)


func find_spawn_position() -> Vector3:
	for radius in range(0, 65):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if radius > 0 and absi(x) != radius and absi(z) != radius:
					continue
				var top := find_walkable_surface(x, z)
				if top >= 1:
					return Vector3(x + 0.5, top + 2.05, z + 0.5)
	return Vector3(0.5, 50.0, 0.5)


func find_walkable_surface(x: int, z: int) -> int:
	for y in range(WORLD_HEIGHT - 3, 0, -1):
		var block_id := get_block(Vector3i(x, y, z))
		if not BlockRegistryScript.is_solid(block_id) or block_id in ["leaves", "ice"]:
			continue
		# The player origin starts above the surface and the first-person camera
		# occupies the third cell.  Keep all three cells clear so a nearby tree
		# canopy cannot hide the initial view even when the body itself fits.
		if get_block(Vector3i(x, y + 1, z)) == BlockRegistryScript.AIR and get_block(Vector3i(x, y + 2, z)) == BlockRegistryScript.AIR and get_block(Vector3i(x, y + 3, z)) == BlockRegistryScript.AIR:
			return y
	return -1


func _layer_block(position: Vector3i, terrain_height: int) -> String:
	var depth := terrain_height - position.y
	if depth >= 4:
		return _ore_or_stone(position)
	match profile_id:
		"desert_ruins":
			if depth <= 3: return "sand"
		"frozen_wastes":
			if depth == 0: return "snow"
			if depth <= 3: return "dirt"
		"abyss_world":
			if depth == 0: return "stone_bricks"
			return "stone"
		_:
			if depth == 0: return "grass"
			if depth <= 3: return "dirt"
	return _ore_or_stone(position)


func _ore_or_stone(position: Vector3i) -> String:
	var roll := _hash_roll(position.x, position.y, position.z, RESOURCE_ROLL_SALT)
	return resource_distribution.resolve_block(profile_id, position.y, roll)


func _get_sky_block(position: Vector3i, terrain_height: int) -> String:
	var strength := _sky_island_strength(position.x, position.z)
	if strength <= 0.0:
		return BlockRegistryScript.AIR
	var thickness := 3 + roundi(strength * 10.0)
	var bottom := terrain_height - thickness
	if position.y < bottom or position.y > terrain_height:
		return BlockRegistryScript.AIR
	var depth := terrain_height - position.y
	if depth == 0: return "grass"
	if depth <= 2: return "dirt"
	return _ore_or_stone(position)


func _sky_island_strength(x: int, z: int) -> float:
	var cell_size := 32
	var base_cell_x := floori(float(x) / cell_size)
	var base_cell_z := floori(float(z) / cell_size)
	var best := -1.0
	for cell_x in range(base_cell_x - 1, base_cell_x + 2):
		for cell_z in range(base_cell_z - 1, base_cell_z + 2):
			var offset_x := _hash_roll(cell_x, 0, cell_z, 91) % 15 - 7
			var offset_z := _hash_roll(cell_x, 0, cell_z, 131) % 15 - 7
			var center := Vector2(cell_x * cell_size + cell_size / 2 + offset_x, cell_z * cell_size + cell_size / 2 + offset_z)
			var radius := 11.0 + float(_hash_roll(cell_x, 0, cell_z, 177) % 8)
			var strength := 1.0 - Vector2(x, z).distance_to(center) / radius
			best = maxf(best, strength)
	return best


func _get_tree_block(position: Vector3i, terrain_height: int) -> String:
	if position.y <= terrain_height or position.y > terrain_height + 8:
		return BlockRegistryScript.AIR
	for tree_x in range(position.x - 2, position.x + 3):
		for tree_z in range(position.z - 2, position.z + 3):
			if not _tree_here(tree_x, tree_z):
				continue
			var ground := get_surface_height(tree_x, tree_z)
			if ground < SEA_LEVEL:
				continue
			if position.x == tree_x and position.z == tree_z and position.y >= ground + 1 and position.y <= ground + 4:
				return "wood"
			var dx := absi(position.x - tree_x)
			var dz := absi(position.z - tree_z)
			if position.y >= ground + 3 and position.y <= ground + 5 and dx <= 2 and dz <= 2:
				if position.y < ground + 5 or dx + dz <= 2:
					return "leaves"
	return BlockRegistryScript.AIR


func _tree_here(x: int, z: int) -> bool:
	return _hash_roll(x, 0, z, 701) < 185


func _hash_roll(x: int, y: int, z: int, salt: int) -> int:
	var value := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ seed_value ^ (salt * 265443576)
	value = (value ^ (value >> 13)) * 1274126177
	return int(value & 0x7FFFFFFF) % 10000
