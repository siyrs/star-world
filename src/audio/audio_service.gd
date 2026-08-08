class_name AudioService
extends Node

signal sound_played(event_name: String)

var _effects_player: AudioStreamPlayer
var _creature_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _effect_pool: Array[AudioStreamPlayer] = []
var _pool_cursor := 0
var _pool_enabled := true
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _disposed := false


func _ready() -> void:
	_rng.seed = 7355608
	_pool_enabled = not bool(get_meta("disable_effect_pool", false))
	_effects_player = _create_player("Effects")
	_effect_pool.append(_effects_player)
	if _pool_enabled:
		for index in range(2, 5):
			_effect_pool.append(_create_player("Effects%d" % index))
	_creature_player = _create_player("Creatures")
	_ambient_player = _create_player("Ambient")
	_build_cache()


func _exit_tree() -> void:
	if not _disposed:
		dispose()


func shutdown() -> void:
	# Shutdown is non-destructive: it releases every stream/cache reference while
	# preserving the fixed playback-node topology for diagnostics and terminal dispose.
	_stop_and_clear_players()
	_cache.clear()
	_pool_cursor = 0


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_stop_and_clear_players()
	_cache.clear()
	for pooled_player: AudioStreamPlayer in _effect_pool.duplicate():
		_dispose_player(pooled_player)
	_effect_pool.clear()
	# The main effects player is part of the pool and has already been released.
	_effects_player = null
	_dispose_player(_creature_player)
	_dispose_player(_ambient_player)
	_creature_player = null
	_ambient_player = null
	_pool_cursor = 0


func is_disposed() -> bool:
	return _disposed


func get_lifecycle_snapshot() -> Dictionary:
	var valid_pool_players := 0
	for player: AudioStreamPlayer in _effect_pool:
		if player != null and is_instance_valid(player):
			valid_pool_players += 1
	return {
		"disposed": _disposed,
		"pool_enabled": _pool_enabled,
		"pool_size": valid_pool_players,
		"cache_size": _cache.size(),
		"child_count": get_child_count(),
		"pool_cursor": _pool_cursor,
	}


func _stop_and_clear_players() -> void:
	var seen: Dictionary = {}
	for player: AudioStreamPlayer in _effect_pool:
		_stop_and_clear_player(player, seen)
	_stop_and_clear_player(_effects_player, seen)
	_stop_and_clear_player(_creature_player, seen)
	_stop_and_clear_player(_ambient_player, seen)


func _stop_and_clear_player(player: AudioStreamPlayer, seen: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var instance_id := player.get_instance_id()
	if seen.has(instance_id):
		return
	seen[instance_id] = true
	player.stop()
	player.stream = null


func _dispose_player(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.get_parent() == self:
		remove_child(player)
	player.free()


func _create_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	add_child(player)
	return player


func _build_cache() -> void:
	if _disposed:
		return
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
	# Game-feel additions: footsteps per material family, digging ticks,
	# eating chews, a reward arpeggio and a landing thud.
	_cache["step_soft"] = _make_wave(120.0, 0.07, 0.16, "noise", 0.72)
	_cache["step_hard"] = _make_wave(230.0, 0.05, 0.14, "noise", 0.8)
	_cache["step_sand"] = _make_wave(88.0, 0.09, 0.13, "noise", 0.66)
	_cache["step_wood"] = _make_wave(150.0, 0.055, 0.15, "square", 0.7)
	_cache["dig_tick"] = _make_wave(310.0, 0.035, 0.15, "noise", 0.85)
	_cache["eat"] = _make_chew_wave()
	_cache["reward"] = _make_arpeggio_wave([523.0, 659.0, 784.0, 1046.0], 0.09, 0.2)
	_cache["land"] = _make_wave(72.0, 0.12, 0.3, "noise", 0.6)


func play_block_break(block_id: String = "stone") -> void:
	if _disposed:
		return
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
	if (
		_disposed
		or _creature_player == null
		or not is_instance_valid(_creature_player)
		or not _cache.has(species_id)
	):
		return
	_creature_player.stream = _cache[species_id]
	_creature_player.pitch_scale = _rng.randf_range(0.92, 1.08)
	if _playback_supported():
		_creature_player.play()
	sound_played.emit("creature_%s" % species_id)


func play_footstep(block_id: String = "grass") -> void:
	var key := "step_soft"
	if block_id in [
		"stone", "cobblestone", "stone_bricks", "coal_ore", "iron_ore", "gold_ore",
		"diamond_ore", "furnace", "stonecutter", "repair_station", "bedrock", "ice",
		"ruin_pillar", "stone_slab"
	]:
		key = "step_hard"
	elif block_id in ["sand", "snow"]:
		key = "step_sand"
	elif block_id in [
		"wood", "planks", "crafting_table", "chest", "oak_door", "oak_fence",
		"ladder", "oak_bed", "oak_stairs"
	]:
		key = "step_wood"
	_play_effect(key)


func play_dig_tick(progress: float = 0.0) -> void:
	if _disposed or not _cache.has("dig_tick"):
		return
	var player := _next_pool_player()
	if player == null:
		return
	player.stream = _cache["dig_tick"]
	player.pitch_scale = 0.92 + clampf(progress, 0.0, 1.0) * 0.35
	if _playback_supported():
		player.play()
	sound_played.emit("dig_tick")


func play_eat() -> void:
	_play_effect("eat")


func play_reward() -> void:
	_play_effect("reward")


func play_land() -> void:
	_play_effect("land")


func start_ambient(profile: String = "forest") -> void:
	if _disposed or _ambient_player == null or not is_instance_valid(_ambient_player):
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
	if _playback_supported():
		_ambient_player.play()
	sound_played.emit(key)


func stop_ambient() -> void:
	if _ambient_player != null and is_instance_valid(_ambient_player):
		_ambient_player.stop()
		_ambient_player.stream = null


func set_master_volume(linear_value: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(linear_value, 0.0001, 1.0)))


func _play_effect(key: String) -> void:
	if _disposed or not _cache.has(key):
		return
	var player := _next_pool_player()
	if player == null:
		return
	player.stream = _cache[key]
	player.pitch_scale = _rng.randf_range(0.94, 1.06)
	if _playback_supported():
		player.play()
	sound_played.emit(key)


# The Dummy audio driver (headless CI/QA runs) never mixes, so every started
# playback is retained forever and leaks AudioStreamPlaybackWAV instances at
# exit. Skip the playback start there while still emitting the sound_played
# contract; real drivers are unaffected.
func _playback_supported() -> bool:
	return AudioServer.get_driver_name() != "Dummy"


func _next_pool_player() -> AudioStreamPlayer:
	if not _pool_enabled:
		return _effects_player if is_instance_valid(_effects_player) else null
	if _effect_pool.is_empty():
		return null
	for attempt in _effect_pool.size():
		var index := (_pool_cursor + attempt) % _effect_pool.size()
		var candidate := _effect_pool[index]
		if candidate != null and is_instance_valid(candidate) and not candidate.playing:
			_pool_cursor = (index + 1) % _effect_pool.size()
			return candidate
	# Every voice is busy; steal the oldest one rather than dropping the event.
	var fallback := _effect_pool[_pool_cursor % _effect_pool.size()]
	_pool_cursor = (_pool_cursor + 1) % _effect_pool.size()
	return fallback if is_instance_valid(fallback) else null


func _make_chew_wave() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.52
	var sample_count := int(duration * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var chew_centers := [0.07, 0.23, 0.39]
	for sample_index in sample_count:
		var t := float(sample_index) / float(mix_rate)
		var sample_value := 0.0
		for center: float in chew_centers:
			var local := t - center
			if local < 0.0 or local > 0.12:
				continue
			var envelope := sin(PI * local / 0.12)
			sample_value += sin(TAU * 165.0 * local) * envelope
			sample_value += _rng.randf_range(-0.35, 0.35) * envelope * 0.5
		var master := clampf(sample_value * 0.24, -1.0, 1.0)
		bytes.encode_s16(sample_index * 2, int(master * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _make_arpeggio_wave(notes: Array, note_seconds: float, volume: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := note_seconds * notes.size() + 0.18
	var sample_count := int(duration * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index in sample_count:
		var t := float(sample_index) / float(mix_rate)
		var note_index := clampi(int(t / note_seconds), 0, notes.size() - 1)
		var local := t - float(note_index) * note_seconds
		var frequency := float(notes[note_index])
		var envelope := minf(1.0, local * 40.0) * maxf(0.0, 1.0 - local / (note_seconds + 0.18))
		var sample_value := sin(TAU * frequency * local) * envelope
		sample_value += sin(TAU * frequency * 2.0 * local) * envelope * 0.28
		bytes.encode_s16(
			sample_index * 2,
			int(clampf(sample_value * volume, -1.0, 1.0) * 32767.0)
		)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


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
