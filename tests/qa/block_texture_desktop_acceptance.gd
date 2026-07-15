extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const TextureAtlasScript = preload("res://src/block/block_texture_atlas.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const OUTPUT_PATH := "user://block-texture-gallery.png"
const CLEANUP_FRAMES := 6
const GALLERY_BLOCKS := [
	"dirt", "stone", "cobblestone", "planks", "stone_bricks", "glass",
	"coal_ore", "iron_ore", "gold_ore", "diamond_ore", "leaves", "wool",
	"grass", "wood", "crafting_table", "chest", "furnace", "repair_station",
]

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _atlas_path := ""
var _created_world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_atlas_path = _capture_path.get_base_dir().path_join("block-texture-atlas.png")
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "game exposes the production service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Block-Texture-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 19604531
	)
	_check(not state.is_empty(), "desktop texture journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	var world: Node = game.world
	var player: Node3D = game.player
	_check(world != null and bool(world.get("is_started")), "real voxel world starts before visual acceptance")
	_check(player != null and bool(player.get("input_enabled")), "real player keeps gameplay input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "texture rendering does not change mouse capture")
	if world == null or player == null:
		await _finish(game, hub)
		return
	if hub.get("creature_spawner") != null and hub.creature_spawner.has_method("set_active"):
		hub.creature_spawner.set_active(false)
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var chunk_coord: Vector2i = world.call("block_to_chunk", player_block)
	var chunk: Node = world.call("force_load_chunk", chunk_coord)
	_check(chunk != null, "gallery uses a real loaded production chunk")
	if chunk == null:
		await _finish(game, hub)
		return
	var chunk_origin := Vector3i(chunk_coord.x * 16, 0, chunk_coord.y * 16)
	var floor_y := clampi(player_block.y - 1, 4, 57)
	_build_gallery(chunk, floor_y)
	chunk.call("rebuild_mesh")
	await physics_frame
	await process_frame
	await process_frame
	var camera := player.call("get_view_camera") as Camera3D
	player.set_physics_process(false)
	player.global_position = Vector3(chunk_origin.x + 8.0, floor_y + 4.9, chunk_origin.z + 14.1)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	var gallery_center := Vector3(chunk_origin.x + 8.0, floor_y + 2.45, chunk_origin.z + 5.55)
	if camera != null:
		camera.look_at(gallery_center, Vector3.UP)
	await physics_frame
	await process_frame
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	_check(mesh_instance != null and mesh_instance.mesh != null, "gallery chunk produces a rendered mesh")
	if mesh_instance != null and mesh_instance.mesh != null:
		var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
		_check(material != null and material.albedo_texture != null, "real chunk material binds the runtime atlas")
		if material != null:
			_check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "real chunk uses nearest-neighbor pixel filtering")
			_check(material.vertex_color_use_as_albedo, "directional face shading still multiplies the pixel atlas")
	var atlas: Image = TextureAtlasScript.get_image()
	_check(atlas != null and not atlas.is_empty(), "desktop runtime exposes the generated pixel atlas")
	_check(_quantized_unique_colors(atlas, Rect2i(Vector2i.ZERO, atlas.get_size()), 1) >= 70, "atlas contains broad visual variation instead of flat swatches")
	if atlas != null and not atlas.is_empty():
		DirAccess.make_dir_recursive_absolute(_atlas_path.get_base_dir())
		_check(atlas.save_png(_atlas_path) == OK and FileAccess.file_exists(_atlas_path), "generated atlas is saved as reviewable evidence")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "texture gallery produces a rendered desktop frame")
	if image != null and not image.is_empty():
		var gameplay_rect := Rect2i(120, 70, 784, 400)
		_check(_quantized_unique_colors(image, gameplay_rect, 16) >= 30, "rendered world region contains varied textured color buckets")
		_save_image(image)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "visual gallery leaves the gameplay mouse captured")
	_check(bool(player.get("input_enabled")), "visual gallery never locks WASD input")
	await _finish(game, hub)


func _build_gallery(chunk: Node, floor_y: int) -> void:
	for local_x in range(0, 16):
		for local_z in range(2, 16):
			chunk.call("set_local_block", Vector3i(local_x, floor_y, local_z), "stone", false)
			for local_y in range(floor_y + 1, mini(64, floor_y + 8)):
				chunk.call("set_local_block", Vector3i(local_x, local_y, local_z), "air", false)
	var index := 0
	for row in range(3):
		for column in range(6):
			var block_id: String = GALLERY_BLOCKS[index]
			chunk.call(
				"set_local_block",
				Vector3i(3 + column * 2, floor_y + 1 + row, 5 + (row % 2)),
				block_id,
				false
			)
			index += 1
	# A foreground strip demonstrates cutout crops and animated-looking fluid patterns.
	for column in range(4):
		chunk.call("set_local_block", Vector3i(4 + column * 2, floor_y + 1, 9), "farmland_wet", false)
		chunk.call("set_local_block", Vector3i(4 + column * 2, floor_y + 2, 9), "wheat_stage_%d" % column, false)
	chunk.call("set_local_block", Vector3i(12, floor_y + 1, 9), "water", false)
	chunk.call("set_local_block", Vector3i(13, floor_y + 1, 9), "lava", false)


func _quantized_unique_colors(image: Image, rect: Rect2i, stride: int) -> int:
	var unique: Dictionary = {}
	var safe_rect := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(safe_rect.position.y, safe_rect.end.y, maxi(1, stride)):
		for x in range(safe_rect.position.x, safe_rect.end.x, maxi(1, stride)):
			var color := image.get_pixel(x, y)
			if color.a < 0.2:
				continue
			var bucket := Vector3i(
				int(round(color.r * 15.0)),
				int(round(color.g * 15.0)),
				int(round(color.b * 15.0))
			)
			unique[bucket] = true
	return unique.size()


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "textured world screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _created_world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_created_world_id)
		if hub.get("audio_service") != null:
			if hub.audio_service.has_method("shutdown"):
				hub.audio_service.shutdown()
			else:
				hub.audio_service.stop_ambient()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA BLOCK TEXTURE DESKTOP PASS | checks=%d | capture=%s | atlas=%s" % [checks, _capture_path, _atlas_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BLOCK TEXTURE DESKTOP FAILURE: %s" % failure)
		print("QA BLOCK TEXTURE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
