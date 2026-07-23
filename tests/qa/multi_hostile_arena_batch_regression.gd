extends SceneTree

const ArenaBatchPolicy = preload(
	"res://tests/qa/support/multi_hostile_arena_batch_policy.gd"
)

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_default_arena_fixture()
	_test_bounded_fixture_limits()
	if failures.is_empty():
		print("QA MULTI HOSTILE ARENA BATCH PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MULTI HOSTILE ARENA BATCH FAILURE: %s" % failure)
		print(
			"QA MULTI HOSTILE ARENA BATCH FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_default_arena_fixture() -> void:
	var origin := Vector3i(16, 24, -16)
	var floor_y := 23
	var mutations: Array[Dictionary] = ArenaBatchPolicy.build_mutations(origin, floor_y)
	_check(
		mutations.size() == ArenaBatchPolicy.expected_mutation_count(),
		"default multi-hostile arena emits the exact bounded mutation count"
	)
	_check(mutations.size() == 2205, "default arena remains below the 4096-mutation world limit")
	var seen: Dictionary = {}
	var stone_count := 0
	var air_count := 0
	for mutation: Dictionary in mutations:
		var raw_position: Variant = mutation.get("position")
		_check(raw_position is Vector3i, "every arena mutation uses an integer world position")
		if raw_position is not Vector3i:
			continue
		var position: Vector3i = raw_position
		_check(not seen.has(position), "arena mutations never write the same cell twice")
		seen[position] = true
		var block_id := str(mutation.get("block_id", ""))
		if block_id == "stone":
			stone_count += 1
		elif block_id == "air":
			air_count += 1
		else:
			_check(false, "arena mutations use only production stone and air block ids")
	_check(stone_count == 441, "default arena creates one 21x21 stone floor")
	_check(air_count == 1764, "default arena clears four cells above every floor cell")
	_check(
		seen.has(Vector3i(origin.x, floor_y, origin.z)),
		"arena includes the center floor cell"
	)
	_check(
		seen.has(Vector3i(origin.x + 10, floor_y + 4, origin.z + 10)),
		"arena includes the upper far-corner clearance cell"
	)


func _test_bounded_fixture_limits() -> void:
	var mutations: Array[Dictionary] = ArenaBatchPolicy.build_mutations(
		Vector3i.ZERO,
		12,
		999,
		999
	)
	var expected := ArenaBatchPolicy.expected_mutation_count(999, 999)
	_check(
		expected == 3750,
		"arena policy clamps oversized requests to the documented 25x25x6 fixture"
	)
	_check(mutations.size() == expected, "bounded arena construction and count policy stay identical")
	_check(
		mutations.size() <= ArenaBatchPolicy.MAX_MUTATIONS_PER_BATCH,
		"largest supported arena always fits one production world mutation batch"
	)
	var first: Dictionary = mutations.front()
	var last: Dictionary = mutations.back()
	_check(
		first.get("position") == Vector3i(-12, 12, -12)
		and first.get("block_id") == "stone",
		"bounded arena starts at the clamped floor corner"
	)
	_check(
		last.get("position") == Vector3i(12, 17, 12)
		and last.get("block_id") == "air",
		"bounded arena ends at the clamped upper corner"
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
