extends SceneTree

const AudioServiceScript = preload("res://src/audio/audio_service.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio = AudioServiceScript.new()
	root.add_child(audio)
	await process_frame
	_check(audio.get_child_count() == 3, "audio service owns exactly three playback nodes")
	_check(
		audio.get("_cache") is Dictionary and not audio.get("_cache").is_empty(),
		"procedural audio cache is initialized",
	)
	audio.start_ambient("forest")
	audio.play_ui()
	await process_frame
	audio.shutdown()
	for _frame in 4:
		await process_frame
	_check(audio.get("_cache").is_empty(), "shutdown releases every generated stream cache entry")
	for player_name in ["Effects", "Creatures", "Ambient"]:
		var player := audio.get_node_or_null(player_name) as AudioStreamPlayer
		_check(player != null and player.stream == null, "%s stream reference is cleared" % player_name)
	audio.dispose()
	await process_frame
	_check(audio.is_disposed(), "explicit disposal marks the audio service terminal")
	_check(audio.get_child_count() == 0, "explicit disposal frees all playback nodes")
	_check(
		audio.get_node_or_null("Ambient") == null,
		"disposed audio service no longer exposes stale playback nodes",
	)
	var event_count := 0
	audio.sound_played.connect(func(_event_name: String) -> void: event_count += 1)
	audio.play_ui()
	audio.start_ambient("forest")
	await process_frame
	_check(event_count == 0, "disposed audio service ignores future playback requests")
	audio.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("QA AUDIO LIFECYCLE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA AUDIO LIFECYCLE FAILURE: %s" % failure)
		print("QA AUDIO LIFECYCLE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
