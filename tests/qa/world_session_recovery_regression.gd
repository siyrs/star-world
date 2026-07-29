extends SceneTree

const SaveServiceScript = preload("res://src/save/save_service.gd")
const RecoveryServiceScript = preload(
	"res://src/save/world_session_recovery_service.gd"
)
const RecoveryPolicy = preload("res://src/save/world_session_recovery_policy.gd")
const MARKER_PATH := "user://session_recovery.json"
const MARKER_SUFFIXES := ["", ".tmp", ".bak", ".recover", ".corrupt"]
const CLEANUP_FRAMES := 16

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clear_marker_files()
	var host := Node.new()
	root.add_child(host)
	var save := SaveServiceScript.new()
	save.name = "RecoveryRegressionSave"
	host.add_child(save)
	await process_frame
	var recovery := RecoveryServiceScript.new()
	recovery.name = "RecoveryServiceA"
	host.add_child(recovery)
	_check(recovery.setup(save), "recovery service installs against the authoritative save service")

	var state: Dictionary = save.create_world(
		"Recovery Regression %d" % Time.get_ticks_msec(),
		"star_continent",
		510729
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "recovery regression creates a real authoritative world")
	if world_id.is_empty():
		await _finish(host, save, world_id)
		return

	_check(recovery.begin_world(state), "world entry writes one strict recovery marker")
	var candidate: Dictionary = recovery.get_recovery_candidate()
	_check(
		str(candidate.get("world_id", "")) == world_id
		and str(candidate.get("state", "")) == RecoveryPolicy.STATE_LOADING
		and int(candidate.get("checkpoint_count", -1)) == 0,
		"new recovery marker starts in loading state without a synthetic checkpoint"
	)
	_check(recovery.mark_active(world_id), "playable world promotes the marker to active")
	candidate = recovery.get_recovery_candidate()
	_check(
		str(candidate.get("state", "")) == RecoveryPolicy.STATE_ACTIVE,
		"active marker retains the current authoritative world identity"
	)

	state["inventory"] = {
		"version":1,
		"slots":[{"item_id":"apple", "count":3}],
	}
	_check(save.save_world(world_id, state), "real world save succeeds while the marker is active")
	candidate = recovery.get_recovery_candidate()
	_check(
		int(candidate.get("checkpoint_count", 0)) == 1
		and int(candidate.get("last_checkpoint_at_unix", 0)) > 0,
		"authoritative world_saved fact updates the recovery checkpoint evidence"
	)

	recovery.shutdown()
	recovery.queue_free()
	await process_frame
	var restarted := RecoveryServiceScript.new()
	restarted.name = "RecoveryServiceRestarted"
	host.add_child(restarted)
	_check(restarted.setup(save), "second service instance simulates a fresh application start")
	var restarted_candidate: Dictionary = restarted.get_recovery_candidate()
	_check(
		str(restarted_candidate.get("world_id", "")) == world_id
		and int(restarted_candidate.get("checkpoint_count", 0)) == 1,
		"fresh application instance discovers the interrupted world session"
	)
	var loaded: Dictionary = save.load_world(world_id)
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("session_recovery")
		and not serialized.contains("checkpoint_count")
		and not serialized.contains("last_checkpoint_at_unix"),
		"session recovery diagnostics remain completely outside world.json"
	)
	_check(restarted.dismiss_candidate(), "player can dismiss only the recovery hint")
	_check(
		restarted.get_recovery_candidate().is_empty()
		and save.world_exists(world_id)
		and not _marker_files_exist(),
		"dismissing recovery preserves the world and removes every marker candidate"
	)

	_check(restarted.begin_world(state), "second recovery marker can be created")
	_check(restarted.mark_active(world_id), "second marker reaches active state")
	_check(save.save_world(world_id, state), "second marker receives a real checkpoint")
	restarted.shutdown()
	restarted.queue_free()
	await process_frame
	var primary := FileAccess.open(
		ProjectSettings.globalize_path(MARKER_PATH), FileAccess.WRITE
	)
	_check(primary != null, "recovery primary opens for corruption fixture")
	if primary != null:
		primary.store_string("{ invalid session marker")
		primary.close()
	var fail_closed := RecoveryServiceScript.new()
	fail_closed.name = "RecoveryServiceFailClosed"
	host.add_child(fail_closed)
	_check(fail_closed.setup(save), "fail-closed recovery service starts after marker corruption")
	var fail_closed_snapshot: Dictionary = fail_closed.get_snapshot()
	_check(
		fail_closed.get_recovery_candidate().is_empty()
		and int(fail_closed_snapshot.get("non_primary_rejection_count", 0)) == 1
		and not _marker_files_exist(),
		"corrupt primary never promotes an older backup into a false recovery prompt"
	)

	_check(fail_closed.begin_world(state), "marker can be recreated after fail-closed cleanup")
	_check(fail_closed.mark_active(world_id), "recreated marker becomes active")
	_check(save.delete_world(world_id), "authoritative world deletion succeeds")
	_check(
		fail_closed.get_recovery_candidate().is_empty()
		and not _marker_files_exist(),
		"deleting the authoritative world clears its stale recovery entry"
	)

	await _finish(host, save, world_id)


func _finish(host: Node, save: Node, world_id: String) -> void:
	_clear_marker_files()
	if (
		save != null
		and is_instance_valid(save)
		and not world_id.is_empty()
		and bool(save.call("world_exists", world_id))
	):
		save.call("delete_world", world_id)
	if host != null and is_instance_valid(host):
		host.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA WORLD SESSION RECOVERY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD SESSION RECOVERY FAILURE: %s" % failure)
		print(
			"QA WORLD SESSION RECOVERY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _clear_marker_files() -> void:
	var absolute_path := ProjectSettings.globalize_path(MARKER_PATH)
	for suffix: String in MARKER_SUFFIXES:
		var path := "%s%s" % [absolute_path, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _marker_files_exist() -> bool:
	var absolute_path := ProjectSettings.globalize_path(MARKER_PATH)
	for suffix: String in MARKER_SUFFIXES:
		if FileAccess.file_exists("%s%s" % [absolute_path, suffix]):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
