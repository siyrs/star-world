extends SceneTree

const BASE_DESKTOP_PATH := "res://tests/qa/structural_integrity_desktop_acceptance.gd"
const BATCHED_DESKTOP_PATH := "res://tests/qa/structural_integrity_batched_desktop_acceptance.gd"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var base_script: Script = load(BASE_DESKTOP_PATH)
	_check(base_script != null, "base structural desktop journey loads as a valid script")
	var batched_script: Script = load(BATCHED_DESKTOP_PATH)
	_check(batched_script != null, "collision-free structural desktop journey loads as a valid script")
	if failures.is_empty():
		print("QA STRUCTURAL DESKTOP IMPORT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA STRUCTURAL DESKTOP IMPORT FAILURE: %s" % failure)
		print(
			"QA STRUCTURAL DESKTOP IMPORT FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
