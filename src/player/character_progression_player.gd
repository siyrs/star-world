class_name CharacterProgressionPlayer
extends "res://src/player/harvest_enabled_player.gd"

signal combat_result_reported(result: Dictionary)

const WORLD_ENTRY_DAMAGE_GRACE_SECONDS := 90.0
const RESPAWN_DAMAGE_GRACE_SECONDS := 30.0
const REPEATED_HOSTILE_DAMAGE_COOLDOWN := 4.5

var equipment_service: Node
var attribute_service: Node
var combat_service: Node
var _base_walk_speed := 0.0
var _base_sprint_speed := 0.0
var _hostile_damage_grace_remaining := 0.0
var _hostile_damage_cooldown_remaining := 0.0


func _ready() -> void:
	_base_walk_speed = walk_speed
	_base_sprint_speed = sprint_speed
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	_hostile_damage_grace_remaining = maxf(
		0.0, _hostile_damage_grace_remaining - maxf(0.0, delta)
	)
	_hostile_damage_cooldown_remaining = maxf(
		0.0, _hostile_damage_cooldown_remaining - maxf(0.0, delta)
	)


func bind_world(p_world: Node) -> void:
	super.bind_world(p_world)
	_hostile_damage_grace_remaining = WORLD_ENTRY_DAMAGE_GRACE_SECONDS
	_hostile_damage_cooldown_remaining = 0.0


func respawn() -> void:
	super.respawn()
	_hostile_damage_grace_remaining = RESPAWN_DAMAGE_GRACE_SECONDS
	_hostile_damage_cooldown_remaining = 0.0


func setup_gameplay_services(services: Dictionary) -> void:
	super.setup_gameplay_services(services)
	if services.get("equipment") is Node:
		bind_equipment_service(services["equipment"])
	if services.get("attributes") is Node:
		bind_attribute_service(services["attributes"])
	if services.get("combat") is Node:
		bind_combat_service(services["combat"])


func bind_equipment_service(p_equipment_service: Node) -> void:
	equipment_service = p_equipment_service


func bind_attribute_service(p_attribute_service: Node) -> void:
	_disconnect_attributes()
	attribute_service = p_attribute_service
	if attribute_service != null and attribute_service.has_signal("attributes_changed"):
		attribute_service.connect("attributes_changed", Callable(self, "_on_attributes_changed"))
	_apply_movement_attributes()


func bind_combat_service(p_combat_service: Node) -> void:
	combat_service = p_combat_service


func set_respawn_position(position: Vector3) -> bool:
	if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
		return false
	spawn_position = position
	return true


func reset_respawn_position() -> void:
	if world != null and world.has_method("get_spawn_position"):
		spawn_position = world.call("get_spawn_position")


func get_respawn_position() -> Vector3:
	return spawn_position


func take_damage(amount: float, source: String = "world") -> void:
	if amount <= 0.0:
		return
	var hostile_damage := source == "zombie"
	if (
		hostile_damage
		and (
			_hostile_damage_grace_remaining > 0.0
			or _hostile_damage_cooldown_remaining > 0.0
		)
	):
		return
	if combat_service == null or not combat_service.has_method("resolve_incoming_damage"):
		super.take_damage(amount, source)
		if hostile_damage:
			_hostile_damage_cooldown_remaining = REPEATED_HOSTILE_DAMAGE_COOLDOWN
		return
	var result: Dictionary = combat_service.call("resolve_incoming_damage", amount, source, true)
	var final_damage := maxf(0.0, float(result.get("final_damage", amount)))
	if final_damage <= 0.0:
		return
	damage_requested.emit(final_damage, source)
	if survival != null and survival.has_method("take_damage"):
		survival.call("take_damage", final_damage, source)
	if hostile_damage:
		_hostile_damage_cooldown_remaining = REPEATED_HOSTILE_DAMAGE_COOLDOWN
	combat_result_reported.emit(result.duplicate(true))


func _try_attack_entity(collider: Node) -> bool:
	if combat_service != null and combat_service.has_method("try_attack_target"):
		var raw_result: Variant = combat_service.call("try_attack_target", collider, self)
		if raw_result is Dictionary:
			var result: Dictionary = raw_result
			combat_result_reported.emit(result.duplicate(true))
			if bool(result.get("handled", false)):
				if bool(result.get("accepted", false)):
					_report_player_action(
						&"attack",
						{
							"display_name": str(result.get("target_name", "生物")),
							"damage": float(result.get("final_damage", 0.0)),
							"defeated": bool(result.get("defeated", false)),
							"weapon_item_id": str(result.get("weapon_item_id", "")),
						}
					)
				return true
	return super._try_attack_entity(collider)


func _get_selected_attack_damage() -> float:
	var fallback := super._get_selected_attack_damage()
	if (
		combat_service != null
		and combat_service.has_method("has_equipped_weapon")
		and bool(combat_service.call("has_equipped_weapon"))
		and combat_service.has_method("get_attack_damage")
	):
		return maxf(0.0, float(combat_service.call("get_attack_damage", fallback)))
	return fallback


func _consume_selected_durability(reason: String) -> void:
	if (
		reason == "attack"
		and combat_service != null
		and combat_service.has_method("has_equipped_weapon")
		and bool(combat_service.call("has_equipped_weapon"))
		and combat_service.has_method("consume_attack_durability")
	):
		combat_service.call("consume_attack_durability", 1)
		return
	super._consume_selected_durability(reason)


func _on_attributes_changed(_snapshot: Dictionary) -> void:
	_apply_movement_attributes()


func _apply_movement_attributes() -> void:
	var speed_multiplier := 1.0
	if attribute_service != null and attribute_service.has_method("get_value"):
		speed_multiplier = maxf(
			0.1, float(attribute_service.call("get_value", "movement_speed", 1.0))
		)
	walk_speed = _base_walk_speed * speed_multiplier
	sprint_speed = _base_sprint_speed * speed_multiplier
	super._configure_movement_controller()


func _disconnect_attributes() -> void:
	if attribute_service == null or not attribute_service.has_signal("attributes_changed"):
		return
	var callback := Callable(self, "_on_attributes_changed")
	if attribute_service.is_connected("attributes_changed", callback):
		attribute_service.disconnect("attributes_changed", callback)
