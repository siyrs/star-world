extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const VisualRegistryScript = preload("res://src/block/block_visual_registry.gd")
const TextureAtlasScript = preload("res://src/block/block_texture_atlas.gd")
const ChunkScript = preload("res://src/chunk/voxel_chunk.gd")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var textured_block := Vector3i(1, 1, 1)

	func get_initial_block(position: Vector3i) -> String:
		return "grass" if position == textured_block else "air"

	func get_block(position: Vector3i) -> String:
		return get_initial_block(position)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_contract()
	_test_atlas_generation()
	await _test_chunk_material_integration()
	if failures.is_empty():
		print("QA BLOCK TEXTURE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BLOCK TEXTURE FAILURE: %s" % failure)
		print("QA BLOCK TEXTURE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_contract() -> void:
	var registry = VisualRegistryScript.new()
	_check(registry.load_from_file(), "block visual registry loads its dedicated data")
	_check(registry.get_validation_errors().is_empty(), "visual registry has no unresolved block or tile references")
	_check(registry.get_tile_size() == 16, "visual contract uses deliberate 16x16 pixel tiles")
	_check(registry.get_tile_count() >= 45, "atlas exposes a broad reusable tile library")
	_check(registry.get_atlas_columns() == 8, "atlas uses a stable eight-column layout")
	for block_id: String in BlockRegistryScript.BLOCK_IDS:
		for face_index in 6:
			var tile_id := registry.get_tile_id(block_id, face_index)
			_check(not tile_id.is_empty(), "%s face %d resolves a visual tile" % [block_id, face_index])
			if block_id != BlockRegistryScript.AIR:
				_check(tile_id != "air", "%s face %d never falls back to transparent air" % [block_id, face_index])
	_check(registry.get_tile_id("grass", 2) != registry.get_tile_id("grass", 4), "grass uses a distinct top and side texture")
	_check(registry.get_tile_id("wood", 2) != registry.get_tile_id("wood", 4), "logs use end grain on top and bark on sides")
	_check(registry.get_tile_id("crafting_table", 2) != registry.get_tile_id("crafting_table", 4), "workstations can expose face-specific visual identity")


func _test_atlas_generation() -> void:
	TextureAtlasScript.reset_cache_for_tests()
	_check(TextureAtlasScript.ensure_built(), "procedural pixel atlas builds without external assets")
	var image: Image = TextureAtlasScript.get_image()
	var registry: RefCounted = TextureAtlasScript.get_registry()
	var expected_size: Vector2i = registry.call("get_atlas_pixel_size")
	_check(image != null and not image.is_empty(), "atlas exposes a non-empty runtime Image")
	_check(image.get_size() == expected_size, "atlas pixel dimensions match registry layout")
	_check(expected_size.x % 16 == 0 and expected_size.y % 16 == 0, "atlas dimensions stay aligned to whole pixel tiles")
	_check(_unique_color_count("stone", 4) >= 4, "stone contains visible pixel variation instead of a flat color")
	_check(_unique_color_count("dirt", 4) >= 4, "dirt contains visible pixel variation")
	_check(_unique_color_count("planks", 4) >= 4, "planks contain seams, knots and color variation")
	_check(_tile_checksum("grass", 2) != _tile_checksum("grass", 4), "grass top and side rasterize differently")
	_check(_tile_checksum("wood", 2) != _tile_checksum("wood", 4), "log rings and bark rasterize differently")
	var ore_checksums := {
		_tile_checksum("coal_ore", 4): true,
		_tile_checksum("iron_ore", 4): true,
		_tile_checksum("gold_ore", 4): true,
		_tile_checksum("diamond_ore", 4): true,
	}
	_check(ore_checksums.size() == 4, "each ore produces a distinct embedded mineral pattern")
	var leaves_alpha := _alpha_stats("leaves", 4)
	_check(int(leaves_alpha.get("transparent", 0)) > 0 and int(leaves_alpha.get("opaque", 0)) > 0, "leaf texture contains real cutout gaps and visible foliage")
	var glass_alpha := _alpha_stats("glass", 4)
	_check(int(glass_alpha.get("transparent", 0)) > int(glass_alpha.get("opaque", 0)), "glass keeps a transparent center with a pixel frame")
	var crop_alpha := _alpha_stats("wheat_stage_3", 4)
	_check(int(crop_alpha.get("transparent", 0)) > 0 and int(crop_alpha.get("opaque", 0)) > 0, "mature crop texture uses transparent negative space")
	var uvs: Array[Vector2] = TextureAtlasScript.get_uvs("diamond_ore", 4)
	_check(uvs.size() == 4, "each face receives four atlas UV corners")
	for uv: Vector2 in uvs:
		_check(uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0, "atlas UV remains inside texture bounds")
	var first_checksum := _image_checksum(image)
	TextureAtlasScript.reset_cache_for_tests()
	_check(TextureAtlasScript.ensure_built(), "atlas can rebuild after cache reset")
	_check(_image_checksum(TextureAtlasScript.get_image()) == first_checksum, "procedural atlas is deterministic across rebuilds")


func _test_chunk_material_integration() -> void:
	ChunkScript.reset_visual_cache_for_tests()
	var host := Node3D.new()
	var world := FakeWorld.new()
	var chunk = ChunkScript.new()
	root.add_child(host)
	host.add_child(world)
	host.add_child(chunk)
	await process_frame
	chunk.initialize(Vector2i.ZERO, world)
	_check(chunk.surface_face_count == 6, "single isolated textured block emits exactly six visual faces")
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	_check(mesh_instance != null and mesh_instance.mesh != null, "chunk builds a real textured ArrayMesh")
	if mesh_instance != null and mesh_instance.mesh != null:
		var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
		_check(material != null, "chunk surface owns a StandardMaterial3D")
		if material != null:
			_check(material.albedo_texture != null, "chunk material binds the procedural atlas")
			_check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "chunk material preserves hard nearest-neighbor pixels")
			_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "chunk material supports crisp cutout leaves, glass and crops")
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var texture_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		_check(texture_uvs.size() == 36, "six cube faces emit complete atlas UV data")
		var min_uv := Vector2.ONE
		var max_uv := Vector2.ZERO
		for uv: Vector2 in texture_uvs:
			min_uv.x = minf(min_uv.x, uv.x)
			min_uv.y = minf(min_uv.y, uv.y)
			max_uv.x = maxf(max_uv.x, uv.x)
			max_uv.y = maxf(max_uv.y, uv.y)
		_check(min_uv.x > 0.0 and max_uv.x < 1.0, "mesh UVs address atlas tiles rather than legacy full-texture UVs")
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var face_shades: Dictionary = {}
		for color: Color in colors:
			face_shades[color.to_rgba32()] = true
		_check(face_shades.size() >= 3, "top, side and bottom retain readable directional shading")
	host.queue_free()
	await process_frame
	await process_frame


func _unique_color_count(block_id: String, face_index: int) -> int:
	var image: Image = TextureAtlasScript.get_image()
	var rect := TextureAtlasScript.get_tile_rect(block_id, face_index)
	var unique: Dictionary = {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			unique[image.get_pixel(x, y).to_rgba32()] = true
	return unique.size()


func _alpha_stats(block_id: String, face_index: int) -> Dictionary:
	var image: Image = TextureAtlasScript.get_image()
	var rect := TextureAtlasScript.get_tile_rect(block_id, face_index)
	var opaque := 0
	var transparent := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				opaque += 1
			else:
				transparent += 1
	return {"opaque": opaque, "transparent": transparent}


func _tile_checksum(block_id: String, face_index: int) -> int:
	var image: Image = TextureAtlasScript.get_image()
	var rect := TextureAtlasScript.get_tile_rect(block_id, face_index)
	var checksum := 17
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			checksum = posmod(checksum * 131 + int(image.get_pixel(x, y).to_rgba32()), 2147483647)
	return checksum


func _image_checksum(image: Image) -> int:
	var checksum := 23
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			checksum = posmod(checksum * 131 + int(image.get_pixel(x, y).to_rgba32()), 2147483647)
	return checksum


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
