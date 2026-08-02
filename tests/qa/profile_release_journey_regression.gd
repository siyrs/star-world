extends SceneTree

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const SaveServiceScript = preload("res://src/save/save_service.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const QA_WORLD_PREFIX := "qa-v130-journey-"
const JOURNEY_SEED := 112358

var checks := 0
var failures: Array[String] = []
var _created_world_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile_ids := MapProfileCatalogScript.get_ids()
	var requested_profile := _user_argument("profile")
	if not requested_profile.is_empty():
		if requested_profile not in profile_ids:
			push_error("Unknown journey profile filter: %s" % requested_profile)
			quit(2)
			return
		profile_ids = [requested_profile]
	print("JOURNEY_FILTER profiles=%s" % JSON.stringify(profile_ids))

	# 1. Pre-flight: snapshot user data for integrity check.
	var save := SaveServiceScript.new()
	root.add_child(save)
	await process_frame
	var pre_world_count := _count_qa_worlds(save)

	# 2. For each profile: create a world via the normal menu path, enter
	#    gameplay, verify spawn quality, and clean up.
	for profile_id: String in profile_ids:
		var world_id := _unique_qa_world_id(profile_id)
		print("JOURNEY_START profile=%s world=%s" % [profile_id, world_id])

		# --- Normal menu entry ---
		var menu = MainMenuScene.instantiate()
		root.add_child(menu)
		for _frame in 4:
			await process_frame
		var map_panel: Control = menu.get("_map_panel")
		_check(map_panel != null, "%s map panel exists" % profile_id)
		var main_panel: Control = menu.get("_main_panel")
		var create_button := _find_button(menu, "创建新世界")
		if create_button != null:
			create_button.pressed.emit()
			await process_frame
		_check(
			map_panel != null and map_panel.visible,
			"%s map panel opens for world creation" % profile_id
		)
		# Select the profile card and set a QA-tagged world name.
		var profile_selected := false
		if map_panel != null:
			map_panel.call("_select_profile", profile_id)
			await process_frame
			# Inject QA-prefixed world name so the save is traceable.
			var name_edit: LineEdit = _find_line_edit(map_panel)
			if name_edit != null:
				name_edit.text = world_id
			var create_world_button := _find_button(map_panel, "创建并进入世界")
			if create_world_button != null:
				create_world_button.pressed.emit()
				await process_frame
				profile_selected = true
		_check(profile_selected, "%s world creation initiated via normal menu" % profile_id)

		# --- Verify world state ---
		for _frame in 2:
			await process_frame
		var worlds: Array = save.list_worlds()
		var newest_world_id := ""
		for w: Dictionary in worlds:
			var name: String = str(w.get("name", ""))
			if name.begins_with(QA_WORLD_PREFIX):
				newest_world_id = str(w.get("id", ""))
				break
		var found := not newest_world_id.is_empty()
		if found:
			_created_world_ids.append(newest_world_id)
		_check(found, "%s world persisted after creation" % profile_id)

		# --- Verify spawn quality ---
		var gen = GeneratorScript.new()
		gen.configure(profile_id, JOURNEY_SEED)
		var spawn_pos: Vector3 = gen.find_spawn_position()
		var snapshot: Dictionary = gen.get_last_spawn_quality_snapshot()
		_check(
			bool(snapshot.get("hard_safe", false)),
			"%s journey seed %d produces a hard-safe spawn at %s"
			% [profile_id, JOURNEY_SEED, spawn_pos]
		)
		_check(
			spawn_pos.y > 1.0 and spawn_pos.y < 64.0,
			"%s journey spawn is within world bounds" % profile_id
		)
		gen = null
		menu.queue_free()
		for _frame in 3:
			await process_frame

	# 3. Cleanup: delete all QA worlds created during this run.
	for world_id: String in _created_world_ids:
		save.delete_world(world_id)
	for _frame in 3:
		await process_frame

	# 4. Post-flight: verify no QA worlds leaked.
	var post_world_count := _count_qa_worlds(save)
	_check(
		post_world_count == pre_world_count,
		"all QA journey worlds cleaned up (pre=%d post=%d)" % [pre_world_count, post_world_count]
	)
	save.queue_free()
	await process_frame

	if failures.is_empty():
		print("QA PROFILE JOURNEY PASS | checks=%d | profiles=%d" % [checks, profile_ids.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PROFILE JOURNEY FAILURE: %s" % failure)
		print("QA PROFILE JOURNEY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _unique_qa_world_id(profile_id: String) -> String:
	return "%s%s-%d-%d" % [QA_WORLD_PREFIX, profile_id, JOURNEY_SEED, Time.get_ticks_msec()]


func _count_qa_worlds(save) -> int:
	var count := 0
	for w: Dictionary in save.list_worlds():
		if str(w.get("name", "")).begins_with(QA_WORLD_PREFIX):
			count += 1
	return count


func _find_line_edit(node: Node) -> LineEdit:
	for child: Node in node.get_children():
		if child is LineEdit:
			return child as LineEdit
		var nested := _find_line_edit(child)
		if nested != null:
			return nested
	return null


func _find_button(node: Node, text: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text == text:
			return child as Button
		var nested := _find_button(child, text)
		if nested != null:
			return nested
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
