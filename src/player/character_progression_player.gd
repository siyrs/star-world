class_name CharacterProgressionPlayer
extends "res://src/player/harvest_enabled_player.gd"

signal combat_result_reported(result: Dictionary)

const WORLD_ENTRY_DAMAGE_GRACE_SECONDS := 90.0
const RESPAWN_DAMAGE_GRACE_SECONDS := 30.0
const REPEATED_HOSTILE_DAMAGE_COOLDOWN := 4.5

var equipment_service: Node
var attribute_service: Node
var combat_service: Node
var ranged_combat_service: Node
var _base_walk_speed := 0.0
var _base_sprint_speed := 0.0
var _hostile_damage_grace_remaining := 0.0
var _hostile_damage_cooldown_remaining := 0.0
var _ranged_recoil_count := 0


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
	if services.get("ranged_combat") is Node:
		bind_ranged_combat_service(services["ranged_combat"])


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


func bind_ranged_combat_service(p_ranged_combat_service: Node) -> void:
	ranged_combat_service = p_ranged_combat_service


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


func get_ranged_combat_snapshot() -> Dictionary:
	if ranged_combat_service == null or not ranged_combat_service.has_method("get_snapshot"):
		return {}
	var snapshot: Dictionary = ranged_combat_service.call("get_snapshot")
	snapshot["player_recoil_count"] = _ranged_recoil_count
	return snapshot


func request_ranged_reload() -> Dictionary:
	if ranged_combat_service == null or not ranged_combat_service.has_method("request_reload"):
		return {"handled": false, "accepted": false, "reason": "service_unavailable"}
	var result: Dictionary = ranged_combat_service.call("request_reload")
	_handle_ranged_result(result)
	return result


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


func _start_primary_action() -> void:
	if ranged_combat_service != null and ranged_combat_service.has_method("begin_primary"):
		var firing := _ranged_origin_and_direction()
		var raw_result: Variant = ranged_combat_service.call(
			"begin_primary",
			firing.get("origin", global_position),
			firing.get("direction", -global_transform.basis.z),
			self
		)
		if raw_result is Dictionary:
			var result: Dictionary = raw_result
			if bool(result.get("handled", false)):
				if not bool(result.get("accepted", false)):
					_primary_action_held = false
				_handle_ranged_result(result)
				return
	elif ranged_combat_service != null and ranged_combat_service.has_method("begin_charge"):
		var legacy_result: Variant = ranged_combat_service.call("begin_charge")
		if legacy_result is Dictionary and bool(legacy_result.get("handled", false)):
			if not bool(legacy_result.get("accepted", false)):
				_primary_action_held = false
			_handle_ranged_result(legacy_result)
			return
	super._start_primary_action()


func _advance_harvest(delta: float) -> void:
	if ranged_combat_service != null and ranged_combat_service.has_method("get_snapshot"):
		var snapshot: Dictionary = ranged_combat_service.call("get_snapshot")
		if bool(snapshot.get("charging", false)) or bool(snapshot.get("trigger_active", false)):
			if ranged_combat_service.has_method("advance_primary"):
				var firing := _ranged_origin_and_direction()
				var result: Dictionary = ranged_combat_service.call(
					"advance_primary",
					delta,
					firing.get("origin", global_position),
					firing.get("direction", -global_transform.basis.z),
					self
				)
				if bool(result.get("accepted", false)) or str(result.get("status", "")) == "rejected":
					_handle_ranged_result(result)
			elif ranged_combat_service.has_method("advance_charge"):
				ranged_combat_service.call("advance_charge", delta)
			return
	super._advance_harvest(delta)


func _cancel_harvest(reason: String) -> void:
	if ranged_combat_service != null and ranged_combat_service.has_method("get_snapshot"):
		var snapshot: Dictionary = ranged_combat_service.call("get_snapshot")
		if bool(snapshot.get("charging", false)) or bool(snapshot.get("trigger_active", false)):
			var result: Dictionary = {}
			if reason in ["released", "controller_released"]:
				var firing := _ranged_origin_and_direction()
				if ranged_combat_service.has_method("release_primary"):
					result = ranged_combat_service.call(
						"release_primary",
						firing.get("origin", global_position),
						firing.get("direction", -global_transform.basis.z),
						self
					)
				else:
					result = ranged_combat_service.call(
						"release_charge",
						firing.get("origin", global_position),
						firing.get("direction", -global_transform.basis.z),
						self
					)
			elif ranged_combat_service.has_method("cancel_primary"):
				result = ranged_combat_service.call("cancel_primary", reason)
			else:
				result = ranged_combat_service.call("cancel_charge", reason)
			_handle_ranged_result(result)
			return
	super._cancel_harvest(reason)


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


func _handle_ranged_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	var status := str(result.get("status", ""))
	var reason := str(result.get("reason", ""))
	if status not in ["holding", "released"] and reason != "not_active":
		combat_result_reported.emit(result.duplicate(true))
	if not bool(result.get("accepted", false)):
		return
	if status == "fired":
		_report_player_action(
			&"ranged_fire",
			{
				"attack_kind": str(result.get("attack_kind", "ranged")),
				"weapon_item_id": str(result.get("weapon_item_id", "")),
				"ammo_item_id": str(result.get("ammo_item_id", "")),
				"charge_ratio": float(result.get("charge_ratio", 0.0)),
				"damage": float(result.get("damage", 0.0)),
				"pellet_count": int(result.get("pellet_count", 1)),
			}
		)
		_apply_ranged_recoil(result)
	elif status in ["reloading", "reloaded"]:
		_report_player_action(
			&"ranged_reload",
			{
				"weapon_item_id": str(result.get("weapon_item_id", "")),
				"status": status,
			}
		)


func _apply_ranged_recoil(result: Dictionary) -> void:
	var pitch := maxf(0.0, float(result.get("recoil_pitch_degrees", 0.0)))
	var yaw := maxf(0.0, float(result.get("recoil_yaw_degrees", 0.0)))
	if pitch <= 0.0 and yaw <= 0.0:
		return
	_ranged_recoil_count += 1
	if camera_pivot != null and is_instance_valid(camera_pivot):
		camera_pivot.rotate_x(-deg_to_rad(pitch))
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)
	var sequence := int(result.get("hitscan_id", _ranged_recoil_count))
	var yaw_sign := -1.0 if sequence % 2 == 0 else 1.0
	rotate_y(deg_to_rad(yaw * yaw_sign))


func _ranged_origin_and_direction() -> Dictionary:
	var direction := -global_transform.basis.z
	var origin := global_position + Vector3.UP * 1.55
	if interaction_ray != null and is_instance_valid(interaction_ray):
		direction = -interaction_ray.global_transform.basis.z
		origin = interaction_ray.global_position
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	return {
		"origin": origin + direction * 0.35,
		"direction": direction,
	}


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
