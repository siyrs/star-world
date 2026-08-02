extends SceneTree

const GeneratorScript = preload("res://src/world/world_generator.gd")
const CacheScript = preload("res://src/world/world_generator_column_cache.gd")

const SEED := 112358
const HOT_PATH_SIZE := 16
const WORLD_HEIGHT := 64
const PROFILE_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]

var checks := 0
var failures: Array[String] = []
var _benchmark: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cache_capacity_and_fields()
	_test_profile_determinism()
	_test_sky_island_hot_path()
	_test_configure_invalidation()
	_write_optional_report()
	if failures.is_empty():
		print("QA WORLD GENERATOR COLUMN CACHE PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA WORLD GENERATOR COLUMN CACHE FAILURE: %s" % failure)
	print(
		"QA WORLD GENERATOR COLUMN CACHE FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_cache_capacity_and_fields() -> void:
	var cache = CacheScript.new(256)
	var shared_column := Vector2i(4, 7)
	cache.store_height(shared_column, 42)
	cache.store_sky_strength(shared_column, 0.75)
	var shared_stats: Dictionary = cache.get_stats()
	_check(int(shared_stats.get("entry_count", 0)) == 1, "height and sky facts share one bounded column entry")
	_check(int(cache.get_height(shared_column)) == 42, "height fact round-trips")
	_check(_near(float(cache.get_sky_strength(shared_column)), 0.75), "sky-strength fact round-trips")

	cache.clear(true)
	for index in 600:
		var column := Vector2i(index, -index)
		cache.store_height(column, posmod(index, WORLD_HEIGHT))
		if index % 3 == 0:
			cache.store_sky_strength(column, float(index % 100) / 100.0)
	var stats: Dictionary = cache.get_stats()
	_check(int(stats.get("capacity", 0)) == 256, "cache capacity remains the configured hard bound")
	_check(int(stats.get("entry_count", 0)) == 256, "entry count never exceeds the hard bound")
	_check(int(stats.get("maximum_entry_count", 0)) <= 256, "observed maximum entry count is bounded")
	_check(int(stats.get("eviction_count", 0)) == 344, "oldest columns are deterministically evicted")
	_check(cache.get_height(Vector2i(0, 0)) == null, "oldest evicted column is absent")
	_check(int(cache.get_height(Vector2i(599, -599))) == posmod(599, WORLD_HEIGHT), "newest retained column remains available")
	_check(
		int(stats.get("backing_order_count", 0))
		<= 256 + CacheScript.ORDER_COMPACTION_THRESHOLD,
		"FIFO bookkeeping is bounded as well as the value dictionary"
	)

	cache.set_enabled(false)
	cache.store_height(Vector2i(900, 900), 12)
	_check(cache.get_height(Vector2i(900, 900)) == null, "disabled benchmark mode bypasses both reads and writes")
	_check(int(cache.get_stats().get("entry_count", -1)) == 0, "disabling clears retained deterministic facts")


func _test_profile_determinism() -> void:
	for profile_id: String in PROFILE_IDS:
		var uncached = GeneratorScript.new()
		uncached.configure(profile_id, SEED)
		uncached.call("set_column_cache_enabled_for_test", false)
		var expected := _sample_profile_blocks(uncached)

		var cached = GeneratorScript.new()
		cached.configure(profile_id, SEED)
		cached.call("set_column_cache_enabled_for_test", true)
		var actual := _sample_profile_blocks(cached)
		_check(actual == expected, "%s cached blocks remain byte-for-byte deterministic" % profile_id)
		var stats: Dictionary = cached.call("get_column_cache_stats")
		_check(bool(stats.get("enabled", false)), "%s production column cache is enabled" % profile_id)
		_check(int(stats.get("entry_count", 0)) > 0, "%s deterministic sampling populates the cache" % profile_id)
		_check(
			int(stats.get("entry_count", 0)) <= int(stats.get("capacity", 0)),
			"%s cache entries stay inside capacity" % profile_id
		)


func _test_sky_island_hot_path() -> void:
	var generator = GeneratorScript.new()
	generator.configure("sky_islands", SEED)
	generator.call("set_column_cache_enabled_for_test", false)
	var uncached_started := Time.get_ticks_usec()
	var uncached_blocks := _sample_hot_chunk(generator)
	var uncached_elapsed := Time.get_ticks_usec() - uncached_started
	var uncached_stats: Dictionary = generator.call("get_column_cache_stats")

	generator.call("set_column_cache_enabled_for_test", true)
	var cached_started := Time.get_ticks_usec()
	var cached_blocks := _sample_hot_chunk(generator)
	var cached_elapsed := Time.get_ticks_usec() - cached_started
	var cached_stats: Dictionary = generator.call("get_column_cache_stats")

	var uncached_height_evaluations := int(
		uncached_stats.get("surface_height_evaluation_count", 0)
	)
	var cached_height_evaluations := int(
		cached_stats.get("surface_height_evaluation_count", 0)
	)
	var uncached_sky_evaluations := int(
		uncached_stats.get("sky_strength_evaluation_count", 0)
	)
	var cached_sky_evaluations := int(
		cached_stats.get("sky_strength_evaluation_count", 0)
	)
	_benchmark = {
		"profile_id": "sky_islands",
		"seed": SEED,
		"columns": HOT_PATH_SIZE * HOT_PATH_SIZE,
		"cells": HOT_PATH_SIZE * HOT_PATH_SIZE * WORLD_HEIGHT,
		"uncached_elapsed_usec": uncached_elapsed,
		"cached_elapsed_usec": cached_elapsed,
		"elapsed_ratio": (
			float(cached_elapsed) / float(uncached_elapsed)
			if uncached_elapsed > 0
			else 0.0
		),
		"uncached_surface_height_evaluations": uncached_height_evaluations,
		"cached_surface_height_evaluations": cached_height_evaluations,
		"uncached_sky_strength_evaluations": uncached_sky_evaluations,
		"cached_sky_strength_evaluations": cached_sky_evaluations,
		"cached_stats": cached_stats.duplicate(true),
	}
	print("GENERATOR_COLUMN_CACHE_BENCHMARK %s" % JSON.stringify(_benchmark))

	_check(cached_blocks == uncached_blocks, "sky-island cache preserves every generated block in a full chunk")
	_check(
		uncached_height_evaluations >= HOT_PATH_SIZE * HOT_PATH_SIZE * (WORLD_HEIGHT - 1),
		"uncached baseline repeats surface-height work for every non-bedrock cell"
	)
	_check(
		uncached_sky_evaluations >= HOT_PATH_SIZE * HOT_PATH_SIZE * (WORLD_HEIGHT - 1),
		"uncached baseline repeats nine-island strength search for every non-bedrock cell"
	)
	_check(
		cached_height_evaluations <= HOT_PATH_SIZE * HOT_PATH_SIZE,
		"cached sky chunk evaluates surface height at most once per column"
	)
	_check(
		cached_sky_evaluations <= HOT_PATH_SIZE * HOT_PATH_SIZE,
		"cached sky chunk evaluates island strength at most once per column"
	)
	_check(
		cached_height_evaluations * 32 <= uncached_height_evaluations,
		"surface-height evaluation count falls by at least thirty-two times"
	)
	_check(
		cached_sky_evaluations * 32 <= uncached_sky_evaluations,
		"nine-island strength evaluation count falls by at least thirty-two times"
	)
	_check(int(cached_stats.get("height_hit_count", 0)) > 15000, "hot chunk records real height-cache reuse")
	_check(int(cached_stats.get("sky_strength_hit_count", 0)) > 15000, "hot chunk records real island-strength reuse")
	_check(
		int(cached_stats.get("entry_count", 0)) == HOT_PATH_SIZE * HOT_PATH_SIZE,
		"one hot chunk owns exactly one entry per X/Z column"
	)


func _test_configure_invalidation() -> void:
	var generator = GeneratorScript.new()
	generator.configure("star_continent", SEED)
	generator.get_surface_height(3, 9)
	var populated: Dictionary = generator.call("get_column_cache_stats")
	_check(int(populated.get("entry_count", 0)) == 1, "configured generator caches a sampled column")
	generator.configure("desert_ruins", SEED + 1)
	var reset: Dictionary = generator.call("get_column_cache_stats")
	_check(int(reset.get("entry_count", -1)) == 0, "profile or seed reconfiguration invalidates cached columns")
	_check(int(reset.get("surface_height_evaluation_count", -1)) == 0, "reconfiguration resets height telemetry")
	_check(int(reset.get("sky_strength_evaluation_count", -1)) == 0, "reconfiguration resets island telemetry")
	_check(str(reset.get("profile_id", "")) == "desert_ruins", "cache telemetry follows the active profile")
	_check(int(reset.get("seed", 0)) == SEED + 1, "cache telemetry follows the active seed")


func _sample_profile_blocks(generator: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for x in range(-9, 10, 3):
		for z in range(-9, 10, 3):
			for y in [0, 1, 4, 12, 18, 24, 32, 42, 52, 61]:
				result.append(str(generator.call("get_block", Vector3i(x, y, z))))
	return result


func _sample_hot_chunk(generator: RefCounted) -> Array[String]:
	var result: Array[String] = []
	result.resize(HOT_PATH_SIZE * HOT_PATH_SIZE * WORLD_HEIGHT)
	var index := 0
	for y in WORLD_HEIGHT:
		for z in HOT_PATH_SIZE:
			for x in HOT_PATH_SIZE:
				result[index] = str(generator.call("get_block", Vector3i(x, y, z)))
				index += 1
	return result


func _write_optional_report() -> void:
	var report_path := _user_argument("report")
	if report_path.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(report_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_check(false, "column-cache benchmark report opens for writing")
		return
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"benchmark": _benchmark,
	}, "\t"))
	file.close()
	_check(FileAccess.file_exists(absolute_path), "column-cache benchmark report is saved")


func _user_argument(key: String) -> String:
	var prefix := "--%s=" % key
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _near(actual: float, expected: float, tolerance: float = 0.0001) -> bool:
	return absf(actual - expected) <= tolerance


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
