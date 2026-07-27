class_name AudioEventBridge
extends Node

var audio_service


func setup(p_audio_service, world = null, inventory = null, crafting = null, survival = null) -> void:
	audio_service = p_audio_service
	if world != null:
		_connect_if_present(world, "block_broken", _on_block_broken)
		_connect_if_present(world, "block_placed", _on_block_placed)
	if inventory != null:
		_connect_if_present(inventory, "item_added", _on_item_added)
	if crafting != null:
		_connect_if_present(crafting, "craft_succeeded", _on_craft_succeeded)
	if survival != null:
		_connect_if_present(survival, "health_changed", _on_health_changed)
		_connect_if_present(survival, "food_consumed", _on_food_consumed)


func connect_creature(creature: Node) -> void:
	_connect_if_present(creature, "damaged", _on_creature_damaged.bind(str(creature.get("species_id"))))
	_connect_if_present(creature, "ambient_voice_requested", _on_creature_ambient_voice)


func connect_player(player: Node) -> void:
	_connect_if_present(player, "damage_requested", _on_player_damage_requested)
	var feel := player.get_node_or_null("CameraFeel")
	if feel != null:
		_connect_if_present(feel, "footstep_requested", _on_footstep_requested)
		_connect_if_present(feel, "land_requested", _on_land_requested)
		_connect_if_present(feel, "dig_tick_requested", _on_dig_tick_requested)


func _connect_if_present(source: Object, signal_name: String, callback: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _on_block_broken(_position = null, block_id: String = "stone") -> void:
	if audio_service != null: audio_service.play_block_break(block_id)


func _on_block_placed(_position = null, block_id: String = "") -> void:
	if audio_service != null: audio_service.play_block_place(block_id)


func _on_item_added(_item_id: String, _count: int) -> void:
	if audio_service != null: audio_service.play_pickup()


func _on_craft_succeeded(_recipe_id: String, _output: Dictionary) -> void:
	if audio_service != null: audio_service.play_craft()


func _on_health_changed(_health: float, _maximum: float) -> void:
	# Health changes are observed for external UI consumers; direct hit events use
	# damage_requested so healing and initial state do not play a hurt sound.
	return


func _on_player_damage_requested(_amount: float, _source: String) -> void:
	if audio_service != null: audio_service.play_hurt()


func _on_creature_damaged(_amount: float, _remaining: float, species_id: String) -> void:
	if audio_service != null: audio_service.play_creature(species_id)


func _on_creature_ambient_voice(species_id: String) -> void:
	if audio_service != null: audio_service.play_creature(species_id)


func _on_food_consumed(_item_id: String, _food_points: float) -> void:
	if audio_service != null and audio_service.has_method("play_eat"): audio_service.play_eat()


func _on_footstep_requested(block_id: String) -> void:
	if audio_service != null and audio_service.has_method("play_footstep"):
		audio_service.play_footstep(block_id)


func _on_land_requested(_impact_speed: float) -> void:
	if audio_service != null and audio_service.has_method("play_land"): audio_service.play_land()


func _on_dig_tick_requested(progress: float) -> void:
	if audio_service != null and audio_service.has_method("play_dig_tick"):
		audio_service.play_dig_tick(progress)
