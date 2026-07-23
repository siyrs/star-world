extends "res://tests/qa/structural_integrity_scale_desktop_acceptance.gd"

const MAX_SINGLE_FLUSH_CLEANUP_MILLISECONDS := 12000.0
const MAX_SINGLE_FLUSH_CHUNKS := 32
const MAX_RULE_CLEANUP_MILLISECONDS := 1000.0
const LEGACY_TIME_FAILURE := (
	"384 unsupported structures clean up inside the five-second desktop budget"
)
const LEGACY_FLUSH_FAILURE := (
	"support removal and dependent cleanup use exactly two world rebuild flushes"
)


func _finish(game: Node, hub: Node) -> void:
	# The inherited journey retains all original product assertions. Replace only
	# the two superseded performance expectations after the single-flush runtime
	# has produced its complete benchmark report.
	failures.erase(LEGACY_TIME_FAILURE)
	failures.erase(LEGACY_FLUSH_FAILURE)

	var cleanup_milliseconds := float(_report.get("cleanup_milliseconds", INF))
	_check(
		cleanup_milliseconds > 0.0
		and cleanup_milliseconds <= MAX_SINGLE_FLUSH_CLEANUP_MILLISECONDS,
		"384 structures clean up inside the twelve-second software-renderer budget",
	)

	var rebuild := _dictionary_value(_report.get("world_rebuild", {}))
	_check(
		int(rebuild.get("flush_count", -1)) == 1,
		"support removal and dependent cleanup share one world rebuild flush",
	)
	_check(
		int(rebuild.get("execution_count", -1)) <= MAX_SINGLE_FLUSH_CHUNKS
		and int(rebuild.get("last_flush_chunk_count", -1)) <= MAX_SINGLE_FLUSH_CHUNKS
		and int(rebuild.get("max_dirty_chunks", -1)) <= MAX_SINGLE_FLUSH_CHUNKS,
		"single flush rebuilds at most thirty-two actual chunks",
	)
	_check(
		int(rebuild.get("pre_flush_emit_count", -1)) == 2,
		"outer support mutation and nested cleanup each emit one bounded pre-flush summary",
	)

	var integrity := _dictionary_value(_report.get("integrity", {}))
	_check(
		bool(integrity.get("pre_flush_supported", false))
		and int(integrity.get("pre_flush_cleanup_count", -1)) == 1
		and int(integrity.get("pre_flush_signal_count", -1)) == 2,
		"integrity runtime joins exactly one outer mutation batch without recursion",
	)
	var last_flush := _dictionary_value(integrity.get("last_flush", {}))
	_check(
		float(last_flush.get("elapsed_usec", INF)) / 1000.0
		<= MAX_RULE_CLEANUP_MILLISECONDS,
		"structural rule resolution completes inside one second before mesh rebuild",
	)
	var apply := _dictionary_value(last_flush.get("apply", {}))
	var nested_rebuild := _dictionary_value(apply.get("rebuild", {}))
	_check(
		bool(nested_rebuild.get("batch_active", false))
		and int(nested_rebuild.get("batch_depth", -1)) == 1
		and int(nested_rebuild.get("pending_chunks", -1))
		== int(rebuild.get("last_flush_chunk_count", -2)),
		"dependent structural mutations remain inside the outer dirty-chunk set",
	)

	await super._finish(game, hub)
