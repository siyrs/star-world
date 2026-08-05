extends SceneTree

const RunnerScript = preload("res://src/diagnostics/release_smoke_runner.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var runner = RunnerScript.new()
	runner.profile_id = "abyss_world"
	runner.seed = 112358
	var state: Dictionary = runner.call("_smoke_world_state")
	var metadata: Dictionary = state.get("metadata", {})
	var experience: Dictionary = state.get("experience", {})
	var onboarding: Dictionary = experience.get("onboarding", {})
	_check(str(metadata.get("map_id", "")) == "abyss_world", "smoke state retains the requested profile")
	_check(int(metadata.get("seed", 0)) == 112358, "smoke state retains the requested seed")
	_check(bool(onboarding.get("completed", false)), "release evidence starts after tutorial completion")
	_check(not bool(onboarding.get("dismissed", true)), "completed tutorial uses canonical non-dismissed state")
	_check(int(onboarding.get("current_index", -1)) == 6, "completed tutorial points beyond all six steps")
	var completed_actions: Dictionary = onboarding.get("completed_actions", {})
	for action_id: String in ["move", "look", "mine", "place", "inventory", "crafting"]:
		_check(bool(completed_actions.get(action_id, false)), "completed evidence state records %s" % action_id)
	var player_state: Dictionary = state.get("player", {})
	var saved_position: Array = player_state.get("position", [])
	_check(saved_position.is_empty(), "smoke state never encodes a post-spawn transport")
	runner.free()
	if failures.is_empty():
		print("RELEASE SMOKE EVIDENCE STATE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("RELEASE SMOKE EVIDENCE STATE FAILURE: %s" % failure)
		print("RELEASE SMOKE EVIDENCE STATE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
