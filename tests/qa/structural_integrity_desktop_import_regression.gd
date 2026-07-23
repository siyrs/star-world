extends SceneTree

const FIXTURE_PATH := "res://tests/qa/support/structural_integrity_scale_fixture.gd"
const DESKTOP_BASE_PATH := "res://tests/qa/structural_integrity_scale_desktop_acceptance.gd"
const DESKTOP_PATH := (
	"res://tests/qa/structural_integrity_single_flush_desktop_acceptance.gd"
)

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_script := load(FIXTURE_PATH) as Script
	_check(
		fixture_script != null,
		"structural scale fixture loads as a valid pure script",
	)
	var desktop_base_script := load(DESKTOP_BASE_PATH) as Script
	_check(
		desktop_base_script != null,
		"complete structural desktop journey loads as a valid script",
	)
	var desktop_script := load(DESKTOP_PATH) as Script
	_check(
		desktop_script != null,
		"single-flush structural desktop acceptance loads as a valid script",
	)
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
