extends SceneTree

const CreatureScript = preload("res://src/entity/base_creature.gd")

var checks := 0
var failures: Array[String] = []
var requests: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creature = CreatureScript.new()
	creature.species_id = "qa_creature"
	root.add_child(creature)
	await process_frame
	creature.ambient_voice_requested.connect(
		func(species_id: String) -> void: requests.append(species_id)
	)
	var initial: Dictionary = creature.get_ambient_voice_snapshot()
	_check(
		float(initial.get("remaining_seconds", 0.0)) >= 6.0
		and float(initial.get("remaining_seconds", 0.0)) <= 18.0,
		"first ambient voice is staggered across a bounded six-to-eighteen-second window"
	)
	creature.set("_ambient_voice_timer", 0.05)
	creature.call("_update_ambient_voice", 0.04)
	_check(requests.is_empty(), "ambient voice does not fire before its exact countdown boundary")
	creature.call("_update_ambient_voice", 0.02)
	var emitted: Dictionary = creature.get_ambient_voice_snapshot()
	_check(
		requests == ["qa_creature"]
		and int(emitted.get("request_count", 0)) == 1,
		"one elapsed countdown emits one species-scoped ambient request"
	)
	_check(
		float(emitted.get("remaining_seconds", 0.0)) >= 9.0
		and float(emitted.get("remaining_seconds", 0.0)) <= 24.0,
		"subsequent ambient requests use the bounded nine-to-twenty-four-second interval"
	)
	creature.set("_dead", true)
	creature.set("_ambient_voice_timer", 0.0)
	creature.call("_update_ambient_voice", 1.0)
	_check(requests.size() == 1, "dead creatures never publish ambient voice requests")
	creature.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("QA CREATURE AMBIENT VOICE PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA CREATURE AMBIENT VOICE FAILURE: %s" % failure)
	print("QA CREATURE AMBIENT VOICE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
