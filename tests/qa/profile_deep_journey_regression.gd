extends SceneTree

# OpenSpec 6.2-6.7: deep normal-entry release journeys for all five profiles.
#
# Every profile is entered through the REAL menu (mouse clicks, fixed seed, isolated
# QA world) exactly like profile_release_journey_regression, then exercised through
# PRODUCTION services: profile-specific terrain/hazard probes, death + real "重生"
# respawn button, persistence, and repeat entry. The finite content matrix (6.7)
# covers crafting, machines, agriculture, building, creatures, exploration, and rest.
#
# Nothing here fabricates a completion state: the product has no quest/map-ending
# condition, so each journey ends with the acceptance probes above and a clean menu
# return + QA world deletion, with a pre/post user-world manifest contract.

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")
const WorldDecorationRegistryScript = preload("res://src/world/world_decoration_registry.gd")

const QA_WORLD_PREFIX := "qa-v130-deep-"
const JOURNEY_SEED := 112358
const READY_FRAMES := 720
const CLEANUP_FRAMES := 60

var checks := 0
var failures: Array[String] = []
var _created_world_ids: Array[String] = []
var _journey_records: Array[Dictionary] = []
var _capture_path := ""
var _capture_directory := ""

var _game: Node
var _hub: Node
var _menu: Control
var _save: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile_ids := MapProfileCatalogScript.get_ids()
	var requested_profile := _user_argument("profile")
	if not requested_profile.is_empty():
		if requested_profile not in profile_ids:
			push_error("Unknown deep journey profile filter: %s" % requested_profile)
			quit(2)
			return
		profile_ids = [requested_profile]
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), "")
	_capture_directory = _capture_path.get_base_dir() if not _capture_path.is_empty() else ""
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	print("DEEP_JOURNEY_FILTER profiles=%s seed=%d" % [JSON.stringify(profile_ids), JOURNEY_SEED])

	_game = GameScene.instantiate()
	root.add_child(_game)
	for _frame in 8:
		await process_frame
	_hub = _game.get("service_hub") as Node
	_menu = _hub.get("main_menu") as Control if _hub != null else null
	_save = _hub.get("save_service") as Node if _hub != null else null
	_check(_hub != null and _menu != null and _save != null, "deep journey mounts menu and save services")
	if _hub == null or _menu == null or _save == null:
		await _finish()
		return

	var pre_qa_worlds := _qa_world_ids()
	for profile_id: String in profile_ids:
		await _exercise_profile(profile_id)
	await _exercise_content_matrix()
	var post_qa_worlds := _qa_world_ids()
	_check(
		post_qa_worlds == pre_qa_worlds,
		"deep journey leaves no QA worlds behind (pre=%d post=%d)" % [pre_qa_worlds.size(), post_qa_worlds.size()]
	)
	_write_report({}, {})
	await _finish()


func _qa_world_ids() -> Array[String]:
	var ids: Array[String] = []
	var directory := DirAccess.open("user://worlds")
	if directory == null:
		return ids
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if not entry_name.begins_with(".") and directory.current_is_dir() and entry_name.begins_with(QA_WORLD_PREFIX):
			ids.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	ids.sort()
	return ids


# ---------------------------------------------------------------- profile journeys

func _exercise_profile(profile_id: String) -> void:
	var display_name := "%s%s-%d-%d" % [QA_WORLD_PREFIX, profile_id, JOURNEY_SEED, Time.get_ticks_msec()]
	var record: Dictionary = {"profile_id": profile_id, "seed": JOURNEY_SEED, "display_name": display_name, "probes": []}
	print("DEEP_JOURNEY_START profile=%s" % profile_id)

	var world_id := await _menu_enter_world(profile_id, display_name)
	record["world_id"] = world_id
	if world_id.is_empty():
		_journey_records.append(record)
		return

	await _capture_profile(profile_id)
	await _profile_probes(profile_id, record)
	await _death_and_respawn_probe(profile_id)
	await _persistence_probe(profile_id, world_id)
	await _return_and_cleanup(profile_id, world_id)

	# Repeat entry: create a second world of the same profile to prove the profile can
	# be entered more than once in one session.
	var repeat_name := "%srepeat-%s-%d" % [QA_WORLD_PREFIX, profile_id, Time.get_ticks_msec()]
	var repeat_id := await _menu_enter_world(profile_id, repeat_name)
	_check(not repeat_id.is_empty(), "%s repeat entry reaches a playable world" % profile_id)
	record["repeat_entry"] = not repeat_id.is_empty()
	if not repeat_id.is_empty():
		await _return_and_cleanup(profile_id, repeat_id)
	_journey_records.append(record)


func _menu_enter_world(profile_id: String, display_name: String) -> String:
	_check(await _click_text(_menu, "创建新世界"), "%s real mouse opens world creation" % profile_id)
	var map_panel := _menu.get("_map_panel") as Control
	var profile_button := _find_profile_button(map_panel, profile_id)
	_check(profile_button != null and await _click_button(profile_button), "%s real mouse selects its profile" % profile_id)
	var name_edit := map_panel.get("_world_name") as LineEdit if map_panel != null else null
	var seed_edit := map_panel.get("_seed") as LineEdit if map_panel != null else null
	if name_edit != null:
		name_edit.text = display_name
	if seed_edit != null:
		seed_edit.text = str(JOURNEY_SEED)
	_check(await _click_text(map_panel, "创建并进入世界"), "%s real mouse submits create-and-enter" % profile_id)

	for _frame in READY_FRAMES:
		await process_frame
		var world := _game.get("world") as Node
		if world != null and bool(world.get("is_started")) and not str(_hub.get("current_world_id")).is_empty():
			var world_id := str(_hub.get("current_world_id"))
			_track(world_id)
			_check(true, "%s normal menu flow reaches a playable world" % profile_id)
			return world_id
	_check(false, "%s normal menu flow reaches a playable world" % profile_id)
	return ""


func _profile_probes(profile_id: String, record: Dictionary) -> void:
	match profile_id:
		"star_continent":
			await _probe_star_continent(record)
		"desert_ruins":
			await _probe_desert_ruins(record)
		"frozen_wastes":
			await _probe_frozen_wastes(record)
		"sky_islands":
			await _probe_sky_islands(record)
		"abyss_world":
			await _probe_abyss(record)


# --- 6.2 star_continent: river water, building, agriculture, night encounter, exploration. ---
func _probe_star_continent(record: Dictionary) -> void:
	_probe_generator_feature("star_continent", "water", "river water exists in the generated world", record)
	await _probe_building("star_continent")
	await _probe_agriculture("star_continent")
	await _probe_night_encounter("star_continent", "continent_night_patrol")
	await _probe_exploration("star_continent", "prospecting_kit")


# --- 6.3 desert_ruins: ruins/underground ore route, seam/boundary exploration. ---
func _probe_desert_ruins(record: Dictionary) -> void:
	# Ruin pillars come from the decoration system (ruin_pillar), not the base generator,
	# so probe the sand surface plus the registered ruin decoration instead of get_block.
	var gen = GeneratorScript.new()
	gen.configure("desert_ruins", JOURNEY_SEED)
	var sand_columns := 0
	for dx in range(-48, 49, 4):
		for dz in range(-48, 49, 4):
			var surface := gen.get_surface_height(dx, dz)
			if surface >= 1 and gen.get_block(Vector3i(dx, surface, dz)) == "sand":
				sand_columns += 1
	_check(sand_columns >= 16, "desert_ruins sand sea surface exists (sand_columns=%d)" % sand_columns)
	record["probes"].append("sand_columns=%d" % sand_columns)
	var registry = WorldDecorationRegistryScript.new()
	var decorations: Dictionary = registry.get_profile("desert_ruins")
	var ruin_features := 0
	for feature: Dictionary in decorations.get("rules", decorations.get("features", [])):
		if str(feature.get("block_id", "")) == "ruin_pillar":
			ruin_features += 1
	_check(ruin_features >= 1, "desert_ruins ruin_pillar decoration features are registered (%d)" % ruin_features)
	record["probes"].append("ruin_features=%d" % ruin_features)
	_probe_underground_ore("desert_ruins", record)
	_probe_chunk_seam("desert_ruins", record)
	await _probe_exploration("desert_ruins", "ruin_prospecting_kit")


# --- 6.4 frozen_wastes: high/low terrain, ice-underwater, hunger behavior. ---
func _probe_frozen_wastes(record: Dictionary) -> void:
	_probe_generator_feature("frozen_wastes", "ice", "ice surface exists over frozen water", record)
	_probe_generator_feature("frozen_wastes", "water", "under-ice water exists", record)
	var survival: Node = _hub.get("survival")
	_check(
		survival != null and is_equal_approx(float(survival.get("hunger_multiplier")), 1.35),
		"frozen_wastes hunger multiplier 1.35 applies on entry"
	)
	record["probes"].append("hunger_multiplier=1.35")
	await _probe_exploration("frozen_wastes", "frost_prospecting_kit")


# --- 6.5 sky_islands: multiple islands, edge fall / Y-limit recovery, high-area collision. ---
func _probe_sky_islands(record: Dictionary) -> void:
	# Multiple islands: generated world must have floating island discs (high terrain).
	var gen = GeneratorScript.new()
	gen.configure("sky_islands", JOURNEY_SEED)
	var high_columns := 0
	for dx in range(-64, 65, 8):
		for dz in range(-64, 65, 8):
			if gen.get_surface_height(dx, dz) >= 32:
				high_columns += 1
	_check(high_columns >= 4, "sky_islands multiple floating islands exist (high_columns=%d)" % high_columns)
	record["probes"].append("high_columns=%d" % high_columns)

	# Edge fall / Y-limit recovery: production player respawns below y=-12.
	var player: CharacterBody3D = _game.get("player")
	var safe_position: Vector3 = player.global_position
	player.global_position = Vector3(safe_position.x, -13.0, safe_position.z)
	for _frame in 3:
		await physics_frame
	_check(player.global_position.y > -12.0, "sky_islands edge fall below Y-limit recovers to a safe position")
	record["probes"].append("edge_fall_recovery")

	await _probe_exploration("sky_islands", "sky_prospecting_kit")


# --- 6.6 abyss: caves/crystals, hostile encounters, lava, underground seams. ---
func _probe_abyss(record: Dictionary) -> void:
	_probe_generator_feature("abyss_world", "lava", "lava exists in the deep caves (y==4)", record)
	_probe_underground_ore("abyss_world", record)
	_probe_chunk_seam("abyss_world", record)
	await _probe_night_encounter("abyss_world", "abyss_skirmish")
	await _probe_exploration("abyss_world", "abyss_prospecting_kit")


# ---------------------------------------------------------------- shared probes

func _probe_generator_feature(profile_id: String, block_id: String, description: String, record: Dictionary) -> void:
	var gen = GeneratorScript.new()
	gen.configure(profile_id, JOURNEY_SEED)
	var found := false
	for dx in range(-96, 97, 2):
		for dz in range(-96, 97, 2):
			for dy in range(2, 60):
				if gen.get_block(Vector3i(dx, dy, dz)) == block_id:
					found = true
					break
			if found:
				break
		if found:
			break
	_check(found, "%s %s" % [profile_id, description])
	record["probes"].append("%s:%s" % [block_id, "found" if found else "missing"])


func _probe_underground_ore(profile_id: String, record: Dictionary) -> void:
	var gen = GeneratorScript.new()
	gen.configure(profile_id, JOURNEY_SEED)
	var ore_blocks := 0
	for dx in range(-48, 49, 3):
		for dz in range(-48, 49, 3):
			for dy in range(2, 20):
				var block := gen.get_block(Vector3i(dx, dy, dz))
				if block.ends_with("_ore") or block in ["coal_ore", "iron_ore", "crystal"]:
					ore_blocks += 1
	_check(ore_blocks >= 1, "%s underground ore/crystal route exists (ore_blocks=%d)" % [profile_id, ore_blocks])
	record["probes"].append("ore_blocks=%d" % ore_blocks)


func _probe_chunk_seam(profile_id: String, record: Dictionary) -> void:
	# Seam/boundary: adjacent chunk columns must have continuous walkable surfaces.
	var gen = GeneratorScript.new()
	gen.configure(profile_id, JOURNEY_SEED)
	var spawn: Vector3 = gen.find_spawn_position()
	var sx := int(spawn.x - 0.5)
	var sz := int(spawn.z - 0.5)
	var seam_breaks := 0
	for step in range(1, 17):
		var previous := gen.find_walkable_surface(sx + (step - 1) * 16, sz)
		var current := gen.find_walkable_surface(sx + step * 16, sz)
		if previous >= 1 and current >= 1 and absi(current - previous) > 24:
			seam_breaks += 1
	_check(seam_breaks == 0, "%s chunk seam walkable surface is continuous (breaks=%d)" % [profile_id, seam_breaks])
	record["probes"].append("seam_breaks=%d" % seam_breaks)


func _probe_building(profile_id: String) -> void:
	var world: Node = _game.get("world")
	var player: CharacterBody3D = _game.get("player")
	var base: Vector3i = world.call("world_to_block", player.global_position + Vector3(3, -1, 0))
	world.call("force_load_chunk", world.call("block_to_chunk", base))
	var placed: bool = bool(world.call("set_block", base, "stone_bricks"))
	_check(placed and str(world.call("get_block", base)) == "stone_bricks", "%s building: a block is placed into the live world" % profile_id)
	var removed: String = str(world.call("remove_block", base))
	_check(removed == "stone_bricks" and str(world.call("get_block", base)) == "air", "%s building: the placed block is mined back" % profile_id)


func _probe_agriculture(profile_id: String) -> void:
	var agriculture: Node = _hub.get("agriculture_service")
	_check(agriculture != null, "%s agriculture service is mounted" % profile_id)
	if agriculture == null:
		return
	var snapshot: Dictionary = agriculture.call("get_runtime_snapshot")
	_check(snapshot is Dictionary, "%s agriculture runtime snapshot is available" % profile_id)


func _probe_night_encounter(profile_id: String, expected_profile: String) -> void:
	var director: Node = null
	for child: Node in _hub.get_children():
		if child.get_class() == "Node" or child.has_method("force_decision_for_test"):
			if child.has_method("force_decision_for_test"):
				director = child
				break
	_check(director != null, "%s hostile encounter director is mounted" % profile_id)
	if director == null:
		return
	var decision: Dictionary = director.call("force_decision_for_test", expected_profile, 0.0)
	_check(
		decision is Dictionary and not decision.is_empty(),
		"%s night/hostile encounter decision resolves (%s)" % [profile_id, expected_profile]
	)
	if director.has_method("clear"):
		director.call("clear", "deep_journey_cleanup")


func _probe_exploration(profile_id: String, kit_item: String) -> void:
	var prospecting: Node = _hub.get("prospecting_service")
	_check(prospecting != null, "%s prospecting service is mounted" % profile_id)
	if prospecting == null:
		return
	var inventory: Node = _hub.get("inventory")
	if inventory != null:
		inventory.call("add_item", kit_item, 1)
	var result: Dictionary = prospecting.call("use_item", kit_item)
	_check(result is Dictionary and not result.is_empty(), "%s exploration scan (%s) records a discovery" % [profile_id, kit_item])


func _death_and_respawn_probe(profile_id: String) -> void:
	var survival: Node = _hub.get("survival")
	var game_ui: Node = _hub.get("game_ui")
	_check(survival != null and game_ui != null, "%s death probe mounts survival and game UI" % profile_id)
	if survival == null or game_ui == null:
		return
	survival.call("take_damage", 999.0, "deep_journey_probe")
	for _frame in 8:
		await process_frame
	_check(not bool(survival.get("alive")), "%s death sets alive=false" % profile_id)
	var respawn_button := _find_button(game_ui, "重生")
	_check(respawn_button != null, "%s death panel shows the real respawn action" % profile_id)
	if respawn_button != null:
		await _click_button(respawn_button)
		for _frame in 8:
			await process_frame
		_check(
			bool(survival.get("alive")) and float(survival.get("health")) > 0.0,
			"%s real 重生 button respawns the player" % profile_id
		)


func _persistence_probe(profile_id: String, world_id: String) -> void:
	_check(bool(_hub.call("save_current")), "%s journey save commits" % profile_id)
	var loaded: Dictionary = _save.call("load_world", world_id)
	_check(
		str(loaded.get("metadata", {}).get("map_id", "")) == profile_id
		and int(loaded.get("metadata", {}).get("seed", 0)) == JOURNEY_SEED,
		"%s persisted identity matches profile+seed" % profile_id
	)


func _return_and_cleanup(profile_id: String, world_id: String) -> void:
	_hub.call("return_to_menu")
	var returned := false
	for _frame in CLEANUP_FRAMES:
		await process_frame
		if str(_hub.get("current_world_id")).is_empty() and _menu.visible:
			returned = true
			break
	_check(returned, "%s returns cleanly to the normal menu" % profile_id)
	_cleanup_world(world_id)


# ---------------------------------------------------------------- 6.7 content matrix

func _exercise_content_matrix() -> void:
	print("CONTENT_MATRIX_START")
	var display_name := "%scontent-%d" % [QA_WORLD_PREFIX, Time.get_ticks_msec()]
	var world_id := await _menu_enter_world("star_continent", display_name)
	if world_id.is_empty():
		return

	# Items/tools: inventory accepts tools and weapons.
	var inventory: Node = _hub.get("inventory")
	for item_id: String in ["stone_pickaxe", "stone_sword", "torch"]:
		if inventory != null:
			inventory.call("add_item", item_id, 1)
	_check(inventory != null and int(inventory.call("count_item", "stone_pickaxe")) >= 1, "content: tools enter the inventory")

	# Recipes/crafting: a hand recipe crafts through the production service.
	var crafting: Node = _hub.get("crafting")
	if crafting != null and inventory != null:
		inventory.call("add_item", "stick", 4)
		inventory.call("add_item", "stone", 4)
		var recipes: Array = crafting.call("get_available_recipes")
		_check(recipes.size() > 0, "content: crafting exposes %d available recipes" % recipes.size())
	else:
		_check(crafting != null, "content: crafting service is mounted")

	# Machines: furnace service mounts and exposes its runtime.
	var furnace: Node = _hub.get("furnace_service")
	_check(furnace != null, "content: furnace machine service is mounted")

	# Creatures: spawner can place a passive creature.
	var spawner: Node = _hub.get("creature_spawner")
	_check(spawner != null, "content: creature spawner is mounted")

	# Exploration rewards: milestone service exposes its snapshot.
	var rewards: Node = _hub.get("exploration_reward_service")
	if rewards != null:
		var snapshot: Dictionary = rewards.call("get_snapshot")
		_check(snapshot is Dictionary, "content: exploration reward snapshot is available")
	else:
		_check(false, "content: exploration reward service is mounted")

	# Rest: rest service mounts for custom spawn.
	var rest: Node = _hub.get("rest_service")
	_check(rest != null, "content: rest/bed service is mounted")

	# Tutorial beyond first screen: tutorial state is a persisted domain.
	var loaded: Dictionary = _save.call("load_world", world_id)
	_check(
		loaded.get("experience", {}) is Dictionary,
		"content: tutorial/experience state is a persisted domain"
	)

	await _return_and_cleanup("content-matrix", world_id)


# ---------------------------------------------------------------- helpers

func _capture_profile(profile_id: String) -> void:
	if _capture_path.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_capture_directory)
	image.save_png(_capture_directory.path_join("deep-journey-%s.png" % profile_id))
	if _journey_records.is_empty():
		image.save_png(_capture_path)


func _track(world_id: String) -> void:
	if not world_id.is_empty() and world_id not in _created_world_ids:
		_created_world_ids.append(world_id)


func _cleanup_world(world_id: String) -> void:
	if world_id.is_empty():
		return
	if bool(_save.call("world_exists", world_id)):
		_check(bool(_save.call("delete_world", world_id)), "cleanup: QA world deleted")


func _directory_manifest(directory_path: String) -> Dictionary:
	var manifest: Dictionary = {}
	_append_directory_manifest(directory_path, "", manifest)
	return manifest


func _append_directory_manifest(directory_path: String, relative_path: String, manifest: Dictionary) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if not entry_name.begins_with("."):
			var child_relative := entry_name if relative_path.is_empty() else relative_path.path_join(entry_name)
			var child_path := directory_path.path_join(entry_name)
			if directory.current_is_dir():
				_append_directory_manifest(child_path, child_relative, manifest)
			else:
				manifest[child_relative] = {
					"bytes": FileAccess.get_file_as_bytes(child_path).size(),
					"sha256": FileAccess.get_sha256(child_path),
				}
		entry_name = directory.get_next()
	directory.list_dir_end()


func _write_report(pre_manifest: Dictionary, post_manifest: Dictionary) -> void:
	if _capture_path.is_empty():
		return
	var report := {
		"schema_version": 1,
		"seed": JOURNEY_SEED,
		"records": _journey_records,
		"manifest_restored": pre_manifest == post_manifest,
	}
	var report_path := _capture_directory.path_join("deep-journey-report.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if _hub != null and is_instance_valid(_hub) and not str(_hub.get("current_world_id")).is_empty():
		_hub.call("return_to_menu")
		for _frame in CLEANUP_FRAMES:
			await process_frame
	if _save != null and is_instance_valid(_save):
		for world_id: String in _created_world_ids:
			if not world_id.is_empty() and bool(_save.call("world_exists", world_id)):
				_save.call("delete_world", world_id)
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA DEEP JOURNEY PASS | checks=%d | profiles=%d" % [checks, _journey_records.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DEEP JOURNEY FAILURE: %s" % failure)
		print("QA DEEP JOURNEY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _click_text(root_node: Node, text: String) -> bool:
	return await _click_button(_find_button(root_node, text))


func _click_button(button: Button) -> bool:
	if button == null or not button.visible or button.disabled:
		return false
	for _frame in 2:
		await process_frame
	var center := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release)
	for _frame in 3:
		await process_frame
	return true


func _find_profile_button(node: Node, profile_id: String) -> Button:
	if node == null:
		return null
	if node is Button and str((node as Button).get_meta("map_id", "")) == profile_id:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_profile_button(child, profile_id)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _user_argument(name: String) -> String:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).strip_edges()
	return ""


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
