extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const OUTPUT_PATH := "res://tests/qa/artifacts/world-gameplay.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var state := {
		"metadata": {
			"id":"visual-qa",
			"name":"可视化验收",
			"map_id":"star_continent",
			"seed":734521,
			"map_profile":{"ambient":"forest"}
		},
		"inventory":{},
		"world":{"block_overrides":{}},
		"survival":{"health":20.0, "hunger":20.0},
		"day_night":{"time_of_day":9.0, "day":1}
	}
	game.begin_world_state(state)
	for _frame in 180:
		await process_frame
	await RenderingServer.frame_post_draw
	var camera: Camera3D = game.player.get_view_camera()
	var camera_block: Vector3i = game.world.world_to_block(camera.global_position)
	print("QA VISUAL STATE | spawn=%s player=%s camera=%s block=%s block_id=%s chunks=%d" % [game.world.get_spawn_position(), game.player.global_position, camera.global_position, camera_block, game.world.get_block(camera_block), game.world.get_loaded_chunk_count()])
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error == OK:
		print("QA VISUAL CAPTURE PASS | %s" % OUTPUT_PATH)
		quit(0)
	else:
		push_error("Unable to save visual capture: %s" % error_string(error))
		quit(1)
