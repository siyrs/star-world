extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const AtomicJsonStoreScript = preload("res://src/save/atomic_json_store.gd")
const READY_FRAMES := 720
const MENU_FRAMES := 240
const CLEANUP_FRAMES := 32

var checks := 0
var failures: Array[String] = []
var world_id := ""
var report_path := "user://diagnostics/qa-release-lifecycle-%d-%d.json" % [
	int(Time.get_unix_time_from_system()), Time.get_ticks_msec()
]
var sentinel_path := "user://qa-release-lifecycle-%d/world.json" % Time.get_ticks_msec()
var sentinel_text := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_file_family(report_path)
	_write_sentinel()
	var game = GameScene.instantiate()
	game.application_exit_enabled = false
	game.force_release_lifecycle_reporting = true
	game.release_lifecycle_report_path_override = report_path
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	var save := hub.get("save_service") as Node if hub != null else null
	var reporter := game.get("release_lifecycle_report") as Node
	_check(
		hub != null and save != null and reporter != null,
		"production composition mounts the release lifecycle reporter"
	)
	if hub == null or save == null or reporter == null:
		await _finish(game, save)
		return
	var initial: Dictionary = game.call("get_release_lifecycle_snapshot")
	_check(
		bool(initial.get("enabled", false))
		and float(initial.get("timings", {}).get("scene_ready_milliseconds", -1.0)) >= 0.0,
		"forced QA mode records the real production scene-ready boundary"
	)
	var state: Dictionary = save.call(
		"create_world",
		"Release Lifecycle %d" % Time.get_ticks_msec(),
		"star_continent",
		620729
	)
	world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "release lifecycle fixture creates one authoritative world")
	if world_id.is_empty():
		await _finish(game, save)
		return
	game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(game, hub),
		"release lifecycle fixture reaches the first playable world through production startup"
	)
	game.call("request_save")
	await process_frame
	var after_save: Dictionary = game.call("get_release_lifecycle_snapshot")
	_check(
		bool(after_save.get("first_save", {}).get("success", false))
		and str(after_save.get("first_save", {}).get("reason", "")) == "manual"
		and int(after_save.get("first_save", {}).get("bytes", 0)) > 0,
		"first successful production save records reason, bytes and elapsed time"
	)
	_check(
		bool(game.call("request_application_quit", &"release_lifecycle_qa")),
		"real application quit path prepares the final save and release boundary"
	)
	_check(
		await _wait_for_menu(hub),
		"prepared quit releases the active world before report persistence"
	)
	var store = AtomicJsonStoreScript.new()
	var read_result: Dictionary = store.read_dictionary(report_path)
	var report: Dictionary = read_result.get("data", {})
	_check(bool(read_result.get("ok", false)), "release lifecycle report is atomically readable")
	var timings: Dictionary = report.get("timings", {})
	var scene_ms := float(timings.get("scene_ready_milliseconds", -1.0))
	var world_ms := float(timings.get("first_world_playable_milliseconds", -1.0))
	var save_ms := float(timings.get("first_save_milliseconds", -1.0))
	var quit_start_ms := float(timings.get("quit_requested_milliseconds", -1.0))
	var quit_end_ms := float(timings.get("quit_completed_milliseconds", -1.0))
	_check(
		int(report.get("schema_version", 0)) == 1
		and scene_ms >= 0.0
		and world_ms >= scene_ms
		and save_ms >= world_ms
		and quit_start_ms >= save_ms
		and quit_end_ms >= quit_start_ms,
		"release timings retain monotonic scene, playable, save and quit ordering"
	)
	_check(
		str(report.get("first_world", {}).get("world_id", "")) == world_id
		and str(report.get("first_world", {}).get("profile_id", "")) == "star_continent",
		"first playable report identifies the production profile without gameplay payload"
	)
	var quit: Dictionary = report.get("quit", {})
	var before: Dictionary = quit.get("before_resources", {})
	var after: Dictionary = quit.get("after_resources", {})
	var delta: Dictionary = quit.get("resource_delta", {})
	_check(
		bool(quit.get("prepared", false))
		and str(quit.get("source", "")) == "release_lifecycle_qa"
		and before.has("node_count")
		and after.has("node_count")
		and int(delta.get("node_count", 0))
		== int(after.get("node_count", 0)) - int(before.get("node_count", 0)),
		"quit report captures bounded before/after resources and exact deltas"
	)
	var report_text := _read_text(report_path)
	_check(
		not report_text.contains('"inventory"')
		and not report_text.contains('"block_overrides"')
		and not report_text.contains('"position"'),
		"diagnostic report excludes inventory, block and transform payloads"
	)
	_check(
		_read_text(sentinel_path) == sentinel_text,
		"independent lifecycle reporting never mutates a world.json sentinel"
	)
	_check(
		not FileAccess.file_exists("%s.tmp" % report_path),
		"atomic report persistence leaves no temporary file after success"
	)
	await _finish(game, save)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		var world := game.get("world") as Node
		if (
			world != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == world_id
		):
			return true
	return false


func _wait_for_menu(hub: Node) -> bool:
	for _frame in MENU_FRAMES:
		await process_frame
		var menu := hub.get("main_menu") as Control
		if str(hub.get("current_world_id")).is_empty() and menu != null and menu.visible:
			return true
	return false


func _write_sentinel() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(sentinel_path.get_base_dir())
	)
	sentinel_text = JSON.stringify({
		"save_version":2,
		"metadata":{"id":"sentinel"},
		"player":{"position":[1,2,3]},
		"inventory":{"stone":64},
		"world":{"block_overrides":{"1,2,3":"stone"}},
	}, "\t")
	var file := FileAccess.open(sentinel_path, FileAccess.WRITE)
	if file != null:
		file.store_string(sentinel_text)
		file.close()


func _finish(game: Node, save: Node) -> void:
	if save != null and is_instance_valid(save) and not world_id.is_empty():
		if bool(save.call("world_exists", world_id)):
			save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	_remove_file_family(report_path)
	_remove_file_family(sentinel_path)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(sentinel_path.get_base_dir())
	)
	if failures.is_empty():
		print("QA RELEASE LIFECYCLE REPORT PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA RELEASE LIFECYCLE REPORT FAILURE: %s" % failure)
	print(
		"QA RELEASE LIFECYCLE REPORT FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _remove_file_family(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".recover", ".corrupt"]:
		var candidate := "%s%s" % [path, suffix]
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
