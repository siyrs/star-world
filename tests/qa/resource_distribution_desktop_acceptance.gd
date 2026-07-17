extends SceneTree

const MapSelectionPanelScript = preload("res://src/ui/map_selection_panel.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const VoxelWorldScript = preload("res://src/world/voxel_world.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://resource-distribution-desktop.png"
const TEST_SEED := 8451397
const ORE_BLOCKS: Array[String] = ["coal_ore", "iron_ore", "gold_ore", "diamond_ore"]
const DENSITY_PROFILE_IDS: Array[String] = ["sky_islands", "star_continent", "desert_ruins", "abyss_world"]
const SAMPLE_HEIGHTS: Array[int] = [5, 15, 25, 40]

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _production_ore_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var panel = MapSelectionPanelScript.new()
	root.add_child(panel)
	panel.position = Vector2(125, 13)
	panel.size = Vector2(860, 610)
	panel.scale = Vector2(0.9, 0.9)
	for _frame in 4:
		await process_frame

	var map_buttons: VBoxContainer = panel.get("_map_buttons")
	_check(map_buttons != null and map_buttons.get_child_count() == 5, "production map selection renders all five maps")
	if map_buttons != null and map_buttons.get_child_count() == 5:
		var abyss_button := map_buttons.get_child(4) as Control
		_check(abyss_button != null, "abyss map button is a real Control")
		if abyss_button != null:
			await _click_control(abyss_button)
	_check(panel.get_selected_map_id() == "abyss_world", "real pointer input selects the abyss resource profile")
	var abyss_summary := panel.get_resource_summary("abyss_world")
	_check(not abyss_summary.is_empty(), "selected map exposes a resource strategy summary")
	_check(panel.get_details_text().contains(abyss_summary), "production map details display the selected resource strategy")
	_check(panel.get_details_text().contains("资源特点"), "resource strategy is explicitly labelled for players")

	var density: Dictionary = {}
	for profile_id: String in DENSITY_PROFILE_IDS:
		density[profile_id] = _count_policy_ores(profile_id, TEST_SEED)
	_check(int(density["abyss_world"]) > int(density["desert_ruins"]), "abyss has the highest deterministic resource density")
	_check(int(density["desert_ruins"]) > int(density["star_continent"]), "desert ruins are richer than the balanced map")
	_check(int(density["star_continent"]) > int(density["sky_islands"]), "sky islands remain resource-scarce")
	print("QA RESOURCE DESKTOP DENSITY | %s" % density)

	var first_signature := _generator_signature("desert_ruins", TEST_SEED)
	var second_signature := _generator_signature("desert_ruins", TEST_SEED)
	_check(first_signature == second_signature, "fresh production generators preserve deterministic Seed output")

	var world = VoxelWorldScript.new()
	world.render_distance = 1
	world.unload_distance = 2
	root.add_child(world)
	world.start_world("abyss_world", TEST_SEED, "resource-distribution-desktop", {})
	for _frame in 5:
		await process_frame
	_check(world.is_started, "production VoxelWorld starts with the selected resource profile")
	_check(world.profile_id == "abyss_world", "production VoxelWorld keeps the selected map id")
	_check(world.get_loaded_chunk_count() >= 1, "production VoxelWorld builds its spawn chunk")
	var reference_generator = GeneratorScript.new()
	reference_generator.configure("abyss_world", TEST_SEED)
	for x in range(-16, 17):
		for z in range(-16, 17):
			var position := Vector3i(x, 8, z)
			var actual := str(world.get_initial_block(position))
			var expected := str(reference_generator.get_block(position))
			_check(actual == expected, "VoxelWorld and production generator agree at %s" % position)
			if actual in ORE_BLOCKS:
				_production_ore_count += 1
	_check(_production_ore_count > 0, "production abyss world contains generated ores in the sampled underground region")

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the map resource selection experience")
	if image != null and not image.is_empty():
		_save_image(image)

	world.clear_world()
	world.queue_free()
	panel.queue_free()
	for _frame in 6:
		await process_frame
	_finish()


func _count_policy_ores(profile_id: String, seed_value: int) -> int:
	var generator = GeneratorScript.new()
	generator.configure(profile_id, seed_value)
	var result := 0
	for x in range(-48, 49):
		for z in range(-48, 49):
			if str(generator.call("_ore_or_stone", Vector3i(x, 8, z))) in ORE_BLOCKS:
				result += 1
	return result


func _generator_signature(profile_id: String, seed_value: int) -> PackedStringArray:
	var generator = GeneratorScript.new()
	generator.configure(profile_id, seed_value)
	var result := PackedStringArray()
	for x in range(-20, 21, 4):
		for z in range(-20, 21, 4):
			for y: int in SAMPLE_HEIGHTS:
				result.append(str(generator.call("_ore_or_stone", Vector3i(x, y, z))))
	return result


func _click_control(control: Control) -> void:
	await process_frame
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = target
	press.global_position = target
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = target
	release.global_position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "desktop resource selection screenshot is saved")


func _finish() -> void:
	if failures.is_empty():
		print("QA RESOURCE DISTRIBUTION DESKTOP PASS | checks=%d | ores=%d | capture=%s" % [checks, _production_ore_count, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RESOURCE DISTRIBUTION DESKTOP FAILURE: %s" % failure)
		print("QA RESOURCE DISTRIBUTION DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
