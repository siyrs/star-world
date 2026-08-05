extends SceneTree

const RuntimePolicy = preload("res://src/diagnostics/release_smoke_runtime_policy.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var operations_only_critical := {
		"status": "critical",
		"runtime_status": "healthy",
		"sustained_runtime_status": "healthy",
		"operations_status": "critical",
	}
	_check(
		RuntimePolicy.runtime_health_status(operations_only_critical) == "healthy",
		"operations-only critical health remains observable without failing runtime soak"
	)
	_check(
		not RuntimePolicy.is_runtime_critical(operations_only_critical),
		"operations capacity cannot masquerade as a runtime-performance failure"
	)
	_check(
		RuntimePolicy.is_runtime_critical({
			"status": "warning",
			"runtime_status": "healthy",
			"sustained_runtime_status": "critical",
		}),
		"sustained runtime critical status is release-blocking"
	)
	_check(
		RuntimePolicy.runtime_health_status({"runtime_status": " CRITICAL "}) == "critical",
		"runtime status is normalized when sustained status is unavailable"
	)
	_check(
		RuntimePolicy.is_runtime_critical({"status": "critical"}),
		"legacy global status remains a conservative fallback"
	)
	_check(
		RuntimePolicy.runtime_health_status({}) == "healthy",
		"missing health fields default to healthy"
	)

	if failures.is_empty():
		print("RELEASE SMOKE RUNTIME HEALTH SCOPE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("RELEASE SMOKE RUNTIME HEALTH SCOPE FAILURE: %s" % failure)
		print("RELEASE SMOKE RUNTIME HEALTH SCOPE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
