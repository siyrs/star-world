extends SceneTree

const MapSelectionPanelScript = preload("res://src/ui/map_selection_panel.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const VoxelWorldScript = preload("res://src/world/voxel_world.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://world-decoration-desktop.png"
const TEST_SEED := 734521
const VISUAL_BACKGROUND := Color("#7890A6")

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _map_capture_path := ""
var _ruin_capture_path := ""
var _report_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_map_capture_path = _capture_path.get_basename() + "-map.png"
	_ruin_capture_path = _capture_path.get_basename() + "-ruin.png"
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)

	var panel = MapSelectionPanelScript.new()
	root.add_child(panel)
	panel.position = Vector2(125, 13)
	panel.size = Vector2(860, 610)
	panel.scale = Vector2(0.9, 0.9)
	for _frame in 4:
		await process_frame
	var desert_button := _find_map_button(panel, "desert_ruins")
	_check(desert_button != null, "production map selection exposes the desert ruins card")
	if desert_button != null:
		await _click_control(desert_button)
	_check(panel.get_selected_map_id() == "desert_ruins", "real pointer input selects the desert ruins profile")
	var summary := panel.get_decoration_summary("desert_ruins")
	var summary_label := panel.get("_resource_summary_label") as Label
	var visible_summary := summary_label.text if summary_label != null else ""
	_check(not summary.is_empty(), "desert profile exposes a player-facing POI summary")
	_check(visible_summary.contains("地表地标"), "map briefing labels the world landmark identity")
	_check(visible_summary.contains(summary), "map briefing displays the authoritative POI summary")
	await _capture(_map_capture_path, "map selection POI briefing screenshot is saved")
	var primary_copy_error := DirAccess.copy_absolute(_map_capture_path, _capture_path)
	_check(
		primary_copy_error == OK
		and FileAccess.file_exists(_capture_path)
		and FileAccess.get_size(_capture_path) > 0,
		"map briefing also satisfies the reusable desktop runner primary capture contract"
	)

	var generator = GeneratorScript.new()
	generator.configure("desert_ruins", TEST_SEED)
	var active_site := _find_active_ruin_site(generator)
	_check(not active_site.is_empty(), "bounded nearby cells contain an active deterministic ruin site")
	if active_site.is_empty():
		panel.queue_free()
		await _finish()
		return
	var center: Vector2i = active_site.get("center", Vector2i.ZERO)
	var target_y := generator.get_surface_height(center.x, center.y) + 1.5
	var focus_position := Vector3(center.x + 0.5, target_y, center.y + 0.5)

	panel.visible = false
	var world = VoxelWorldScript.new()
	world.render_distance = 1
	world.unload_distance = 2
	root.add_child(world)
	world.start_world("desert_ruins", TEST_SEED, "world-decoration-desktop", {})
	_check(world.is_started, "production VoxelWorld starts with the data-driven decoration profile")
	_check(world.profile_id == "desert_ruins", "production VoxelWorld retains the desert profile id")
	world.set_streaming_focus(focus_position)
	world.update_streaming(focus_position)
	var center_chunk: Vector2i = world.block_to_chunk(Vector3i(center.x, 0, center.y))
	for offset_x in range(-1, 2):
		for offset_z in range(-1, 2):
			world.force_load_chunk(center_chunk + Vector2i(offset_x, offset_z))
	var loaded_after_force := world.get_loaded_chunk_count()
	_check(loaded_after_force >= 9, "real world synchronously loads the bounded POI viewing area")

	var pillar_count := 0
	var supporting_count := 0
	for x in range(center.x - 10, center.x + 11):
		for z in range(center.y - 10, center.y + 11):
			var surface := generator.get_surface_height(x, z)
			for offset in range(1, 5):
				var position := Vector3i(x, surface + offset, z)
				var actual := str(world.get_block(position))
				var expected := str(generator.get_block(position))
				_check(actual == expected, "loaded VoxelWorld matches the decoration generator at %s" % position)
				if actual == "ruin_pillar":
					pillar_count += 1
				elif actual in ["cactus", "dead_bush"]:
					supporting_count += 1
	_check(pillar_count > 0, "real loaded POI area contains generated ruin pillars")
	_check(supporting_count > 0, "real loaded POI area contains supporting desert decoration")

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = VISUAL_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#FFF0D0")
	environment.ambient_light_energy = 1.25
	world_environment.environment = environment
	root.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key_light.light_color = Color("#FFF0CE")
	key_light.light_energy = 2.0
	key_light.shadow_enabled = true
	root.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(30.0, 145.0, 0.0)
	fill_light.light_color = Color("#BFD8FF")
	fill_light.light_energy = 0.9
	root.add_child(fill_light)

	var camera := Camera3D.new()
	camera.fov = 58.0
	root.add_child(camera)
	camera.global_position = Vector3(center.x + 11.0, target_y + 9.0, center.y + 11.0)
	camera.look_at(focus_position, Vector3.UP)
	camera.current = true
	world.set_streaming_focus(focus_position)
	world.update_streaming(focus_position)
	for offset_x in range(-1, 2):
		for offset_z in range(-1, 2):
			world.force_load_chunk(center_chunk + Vector2i(offset_x, offset_z))
	for _frame in 5:
		await process_frame
	var loaded_at_capture := world.get_loaded_chunk_count()
	_check(loaded_at_capture >= 9, "POI chunks remain loaded while the evidence camera renders")
	await _capture(_ruin_capture_path, "real generated ruin screenshot is saved", true)

	var report := {
		"checks": checks,
		"failures": failures.duplicate(),
		"profile_id": world.profile_id,
		"seed": TEST_SEED,
		"site": active_site.duplicate(true),
		"center": [center.x, center.y],
		"loaded_chunks_after_force": loaded_after_force,
		"loaded_chunks_at_capture": loaded_at_capture,
		"pillar_count": pillar_count,
		"supporting_decoration_count": supporting_count,
		"registry_snapshot": generator.get_decoration_profile_snapshot(),
		"map_summary": summary,
		"visual_rig": "neutral_sky_ambient_key_fill",
	}
	_write_report(report)
	camera.queue_free()
	fill_light.queue_free()
	key_light.queue_free()
	world_environment.queue_free()
	panel.queue_free()
	world.clear_world()
	world.queue_free()
	await _finish()


func _find_active_ruin_site(generator) -> Dictionary:
	for cell_x in range(-5, 6):
		for cell_z in range(-5, 6):
			var snapshot: Dictionary = generator.get_poi_snapshot(cell_x * 48 + 24, cell_z * 48 + 24)
			var sites: Array = snapshot.get("sites", [])
			if sites.is_empty():
				continue
			var site: Dictionary = sites[0]
			if bool(site.get("active", false)):
				return site.duplicate(true)
	return {}


func _find_map_button(panel: Node, map_id: String) -> Control:
	var buttons: Dictionary = panel.get("_profile_buttons")
	var raw_button: Variant = buttons.get(map_id)
	return raw_button as Control if raw_button is Control else null


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


func _capture(path: String, description: String, require_readable_world: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s renders a non-empty viewport" % description)
	if image == null or image.is_empty():
		return
	if require_readable_world:
		_check(_has_readable_world_geometry(image), "real ruin evidence contains readable lit POI geometry")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), description)


func _has_readable_world_geometry(image: Image) -> bool:
	var foreground_samples := 0
	var unique_colors: Dictionary = {}
	var step_x := maxi(1, floori(float(image.get_width()) / 64.0))
	var step_y := maxi(1, floori(float(image.get_height()) / 36.0))
	for y in range(image.get_height() / 3, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var distance_from_sky := (
				absf(color.r - VISUAL_BACKGROUND.r)
				+ absf(color.g - VISUAL_BACKGROUND.g)
				+ absf(color.b - VISUAL_BACKGROUND.b)
			)
			if distance_from_sky < 0.12:
				continue
			foreground_samples += 1
			var key := "%d,%d,%d" % [
				int(color.r * 15.0),
				int(color.g * 15.0),
				int(color.b * 15.0),
			]
			unique_colors[key] = true
			if foreground_samples >= 120 and unique_colors.size() >= 16:
				return true
	return false


func _write_report(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "world decoration JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "world decoration JSON report is saved")


func _finish() -> void:
	for _frame in 16:
		await process_frame
	if failures.is_empty():
		print(
			"QA WORLD DECORATION DESKTOP PASS | checks=%d | map=%s | ruin=%s | report=%s"
			% [checks, _map_capture_path, _ruin_capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD DECORATION DESKTOP FAILURE: %s" % failure)
		print("QA WORLD DECORATION DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
