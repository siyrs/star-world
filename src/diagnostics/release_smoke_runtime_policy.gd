class_name ReleaseSmokeRuntimePolicy
extends RefCounted

# Release route soak is a runtime-performance gate. Global health may be
# critical because an intentionally bounded ecology/operations pool is at
# capacity, which must remain observable but must not be misreported as a
# frame-time or streaming failure. Prefer runtime_status so repeated peak-frame
# failures retain the original gate sensitivity; use sustained status only for
# older/partial snapshots that do not expose the full runtime status.
static func normalized_status(value: Variant, fallback: String = "healthy") -> String:
	var status := str(value).strip_edges().to_lower()
	return fallback if status.is_empty() else status


static func runtime_health_status(health: Dictionary) -> String:
	var runtime := str(health.get("runtime_status", "")).strip_edges()
	if not runtime.is_empty():
		return normalized_status(runtime)
	var sustained := str(health.get("sustained_runtime_status", "")).strip_edges()
	if not sustained.is_empty():
		return normalized_status(sustained)
	return normalized_status(health.get("status", "healthy"))


static func is_runtime_critical(health: Dictionary) -> bool:
	return runtime_health_status(health) == "critical"
