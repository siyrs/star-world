class_name AudioService
extends Node

signal sound_played(event_name: String)

var _effects_player: AudioStreamPlayer
var _creature_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7355608
	_effects_player = _create_player("Effects")
	_creature_player = _create_player("Creatures")
	_ambient_player = _create_player("Ambient")
	_build_cache()


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	for player in [_effects_player, _creature_player, _ambient_player]:
		if player != null and is_instance_valid(player):
			player.stop()
			player.stream = null
	_cache.clear()


func _create_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	add_child(player)
	return player


func _build_cache() -> void:
	_cache["break_soft"] = _make_wave(135.0, 0.12, 0.34, "noise")
	_cache["break_hard"] = _make_wave(82.0, 0.16, 0.42, "noise")
	_cache["place"] = _make_wave(220.0, 0.09, 0.28, "square")
	_cache["pickup"] = _make_wave(720.0, 0.1, 0.22, "sine", 1.35)
	_cache["hurt"] = _make_wave(105.0, 0.22, 0.4, "saw")
	_cache["ui"] = _make_wave(520.0, 0.06, 0.18, "sine")
	_cache["craft"] = _make_wave(880.0, 0.16, 0.2, "sine", 1.5)
	_cache["chicken"] = _make_wave(780.0, 0.2, 0.18, "square", 1.35)
	_cache["cow"] = _make_wave(92.0, 0.45, 0.3, "saw", 0.72)
	_cache["pig"] = _make_wave(185.0, 0.25, 0.26, "square", 0.82)
	_cache["zombie"] = _make_wave(63.0, 0.5, 0.32, "saw", 0.68)


func play_block_break(block_id: String = "stone") -> void:
	var soft_blocks := ["grass", "dirt", "sand", "snow", "leaves", "wood", "planks"]
	_play_effect("break_soft" if block_id in soft_blocks else "break_hard")


func play_block_place(_block_id: String = "") -> void:
	_play_effect("place")


func play_pickup() -> void:
	_play_effect("pickup")


func play_hurt() -> void:
	_play_effect("hurt")


func play_ui() -> void:
	_play_effect("ui")


func play_craft() -> void:
	_play_effect("craft")


func play_creature(species_id: String) -> void:
	if _creature_player == null or not _cache.has(species_id):
		return
	_creature_player.stream = _cache[species_id]
	_creature_player.pitch_scale = _rng.randf_range(0.92, 1.08)
	_creature_player.play()
	sound_played.emit("creature_%s" % species_id)


func start_ambient(profile: String = "forest") -> void:
	if _ambient_player == null:
		return
	var frequency := 84.0
	var waveform := "sine"
	match profile:
		"desert":
			frequency = 64.0
			waveform = "noise"
		"wind":
			frequency = 110.0
			waveform = "noise"
		"sky":
			frequency = 160.0
			waveform = "sine"
		"cave":
			frequency = 47.0
			waveform = "saw"
	var key := "ambient_%s" % profile
	if not _cache.has(key):
		var stream := _make_wave(frequency, 2.5, 0.055, waveform, 1.015)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.mix_rate * 2.5)
		_cache[key] = stream
	_ambient_player.stream = _cache[key]
	_ambient_player.play()
	sound_played.emit(key)


func stop_ambient() -> void:
	if _ambient_player != null:
		_ambient_player.stop()


func set_master_volume(linear_value: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(linear_value, 0.0001, 1.0)))


func _play_effect(key: String) -> void:
	if _effects_player == null or not _cache.has(key):
		return
	_effects_player.stream = _cache[key]
	_effects_player.pitch_scale = _rng.randf_range(0.94, 1.06)
	_effects_player.play()
	sound_played.emit(key)


func _make_wave(
	frequency: float,
	duration: float,
	volume: float,
	waveform: String,
	end_pitch_ratio: float = 1.0
) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := maxi(1, int(duration * mix_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index in sample_count:
		var progress := float(sample_index) / float(sample_count)
		var current_frequency := lerpf(frequency, frequency * end_pitch_ratio, progress)
		var phase := TAU * current_frequency * float(sample_index) / float(mix_rate)
		var sample_value := 0.0
		match waveform:
			"square":
				sample_value = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw":
				sample_value = fmod(phase / PI, 2.0) - 1.0
			"noise":
				sample_value = _rng.randf_range(-1.0, 1.0) * 0.75 + sin(phase) * 0.25
			_:
				sample_value = sin(phase)
		var envelope := minf(1.0, progress * 18.0) * pow(1.0 - progress, 1.45)
		bytes.encode_s16(
			sample_index * 2,
			int(clampf(sample_value * volume * envelope, -1.0, 1.0) * 32767.0)
		)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream
