class_name RangedCombatService
extends Node3D

signal charge_changed(snapshot: Dictionary)
signal shot_fired(result: Dictionary)
signal shot_rejected(result: Dictionary)
signal projectile_hit(result: Dictionary)
signal reload_started(result: Dictionary)
signal reload_completed(result: Dictionary)
signal reload_cancelled(result: Dictionary)

const RegistryScript = preload("res://src/combat/ranged_weapon_registry.gd")
const ShotPolicyScript = preload("res://src/combat/ranged_shot_policy.gd")
const ProjectileRuntimeScript = preload("res://src/combat/projectile_runtime_service.gd")
const HitscanRuntimeScript = preload("res://src/combat/hitscan_runtime_service.gd")
const MAIN_HAND_SLOT := "main_hand"
const MAGAZINE_METADATA_KEY := "magazine_rounds"
const STATUS_SIGNAL_INTERVAL := 0.05
const ACTION_CHARGE := "charge"
const ACTION_FIREARM := "firearm"

var inventory: Node
var equipment_service: Node
var combat_service: Node
var registry = RegistryScript.new()
var shot_policy = ShotPolicyScript.new()
var projectile_runtime: Node3D
var hitscan_runtime: Node3D

var _charging := false
var _charge_seconds := 0.0
var _charge_profile: Dictionary = {}
var _trigger_active := false
var _trigger_profile: Dictionary = {}
var _trigger_origin := Vector3.ZERO
var _trigger_direction := Vector3.FORWARD
var _trigger_attacker: Node3D
var _cooldown_remaining := 0.0
var _cooldown_total := 0.0
var _reload_remaining := 0.0
var _reload_total := 0.0
var _reload_weapon_id := ""
var _signal_accumulator := 0.0
var _shot_count := 0
var _rejection_count := 0
var _cancel_count := 0
var _reload_count := 0
var _last_result: Dictionary = {}
var _profile_cache_initialized := false
var _cached_weapon_id := ""
var _cached_profile: Dictionary = {}
var _profile_refresh_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	registry.ensure_loaded()
	projectile_runtime = ProjectileRuntimeScript.new()
	projectile_runtime.name = "ProjectileRuntime"
	add_child(projectile_runtime)
	projectile_runtime.call("setup", combat_service)
	projectile_runtime.connect("projectile_hit", Callable(self, "_on_projectile_hit"))
	hitscan_runtime = HitscanRuntimeScript.new()
	hitscan_runtime.name = "HitscanRuntime"
	add_child(hitscan_runtime)
	hitscan_runtime.call("setup", combat_service)


func _process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	if _charging:
		_charge_seconds += safe_delta
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - safe_delta)
	if _reload_remaining > 0.0:
		if get_equipped_weapon_id() != _reload_weapon_id:
			_cancel_reload("weapon_changed")
		else:
			_reload_remaining = maxf(0.0, _reload_remaining - safe_delta)
			if _reload_remaining <= 0.0:
				_complete_reload()
	_signal_accumulator += safe_delta
	if (
		_charging
		or _trigger_active
		or _reload_remaining > 0.0
		or _cooldown_remaining > 0.0
	) and _signal_accumulator >= STATUS_SIGNAL_INTERVAL:
		_emit_status()


func setup(p_inventory: Node, p_equipment: Node, p_combat: Node) -> void:
	inventory = p_inventory
	equipment_service = p_equipment
	combat_service = p_combat
	registry.ensure_loaded()
	_profile_cache_initialized = false
	_cached_weapon_id = ""
	_cached_profile.clear()
	if projectile_runtime != null:
		projectile_runtime.call("setup", combat_service)
	if hitscan_runtime != null:
		hitscan_runtime.call("setup", combat_service)


func has_ranged_weapon() -> bool:
	return not _active_profile_ref().is_empty()


func get_equipped_weapon_id() -> String:
	if equipment_service == null or not equipment_service.has_method("get_slot"):
		return ""
	var raw_slot: Variant = equipment_service.call("get_slot", MAIN_HAND_SLOT)
	return str(raw_slot.get("item_id", "")) if raw_slot is Dictionary else ""


func get_active_profile() -> Dictionary:
	return _active_profile_ref().duplicate(true)


func begin_primary(
	origin: Vector3 = Vector3.ZERO,
	direction: Vector3 = Vector3.FORWARD,
	attacker: Node3D = null
) -> Dictionary:
	var profile := _active_profile_ref()
	if profile.is_empty():
		return {"handled": false, "accepted": false, "reason": "not_ranged_weapon"}
	if str(profile.get("action_kind", ACTION_CHARGE)) == ACTION_FIREARM:
		return _begin_firearm_trigger(profile, origin, direction, attacker)
	return _begin_charge_with_profile(profile)


func advance_primary(
	_delta: float,
	origin: Vector3 = Vector3.ZERO,
	direction: Vector3 = Vector3.FORWARD,
	attacker: Node3D = null
) -> Dictionary:
	if _charging:
		return advance_charge(_delta)
	if not _trigger_active:
		return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_active"}
	if get_equipped_weapon_id() != str(_trigger_profile.get("weapon_item_id", "")):
		_clear_trigger()
		return _reject("weapon_changed")
	_trigger_origin = origin
	_trigger_direction = _normalized_direction(direction)
	_trigger_attacker = attacker
	if (
		str(_trigger_profile.get("fire_mode", "semi")) == "auto"
		and _cooldown_remaining <= 0.0
		and _reload_remaining <= 0.0
	):
		var fired := _fire_firearm(
			_trigger_profile,
			_trigger_origin,
			_trigger_direction,
			_trigger_attacker
		)
		if str(fired.get("reason", "")) == "empty_magazine":
			_clear_trigger()
		return fired
	return {
		"handled": true,
		"accepted": false,
		"status": "holding",
		"reason": "ok",
	}


func release_primary(
	origin: Vector3 = Vector3.ZERO,
	direction: Vector3 = Vector3.FORWARD,
	attacker: Node3D = null
) -> Dictionary:
	if _charging:
		return release_charge(origin, direction, attacker)
	if _trigger_active:
		_clear_trigger()
		_emit_status(true)
		return {
			"handled": true,
			"accepted": false,
			"status": "released",
			"reason": "ok",
		}
	return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_active"}


func cancel_primary(reason: String = "cancelled") -> Dictionary:
	if _charging:
		return cancel_charge(reason)
	if _trigger_active:
		_clear_trigger()
		_cancel_count += 1
		_last_result = {
			"handled": true,
			"accepted": false,
			"status": "cancelled",
			"reason": reason,
		}
		_emit_status(true)
		return _last_result.duplicate(true)
	return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_active"}


func begin_charge() -> Dictionary:
	var profile := _active_profile_ref()
	if profile.is_empty() or str(profile.get("action_kind", ACTION_CHARGE)) != ACTION_CHARGE:
		return {"handled": false, "accepted": false, "reason": "not_charge_weapon"}
	return _begin_charge_with_profile(profile)


func advance_charge(_delta: float) -> Dictionary:
	# RangedCombatService._process() is the single pause-aware charge clock.
	if not _charging:
		return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_charging"}
	_emit_status()
	return get_snapshot()


func release_charge(origin: Vector3, direction: Vector3, attacker: Node3D = null) -> Dictionary:
	if not _charging:
		return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_charging"}
	var profile := _charge_profile.duplicate(true)
	var evaluation := shot_policy.evaluate_release(profile, _charge_seconds, direction)
	_charging = false
	_charge_seconds = 0.0
	_charge_profile.clear()
	if not bool(evaluation.get("accepted", false)):
		return _reject(str(evaluation.get("reason", "release_rejected")), evaluation)
	if str(profile.get("weapon_item_id", "")) != get_equipped_weapon_id():
		return _reject("weapon_changed", evaluation)
	if not _has_reserve_ammo(profile):
		return _reject("no_ammo", evaluation)
	if projectile_runtime == null or not bool(projectile_runtime.call("can_spawn")):
		return _reject("projectile_capacity", evaluation)
	var ammo_item_id := str(profile.get("ammo_item_id", ""))
	var transaction: Dictionary = inventory.call("transact_items", {ammo_item_id: 1}, [])
	if not bool(transaction.get("success", false)):
		return _reject("ammo_transaction_failed", evaluation)
	var normalized_direction: Vector3 = evaluation.get("direction", Vector3.FORWARD)
	var spawn_result: Dictionary = projectile_runtime.call(
		"spawn_projectile",
		{
			"origin": origin,
			"velocity": normalized_direction * float(evaluation.get("speed", 0.0)),
			"gravity": float(profile.get("gravity", 0.0)),
			"max_distance": float(profile.get("max_distance", 64.0)),
			"max_lifetime_seconds": float(profile.get("max_lifetime_seconds", 5.0)),
			"collision_mask": int(profile.get("collision_mask", 5)),
			"attacker": attacker,
			"shot": shot_policy.build_shot(profile, evaluation),
		}
	)
	if not bool(spawn_result.get("success", false)):
		inventory.call("add_item", ammo_item_id, 1)
		return _reject(str(spawn_result.get("reason", "projectile_spawn_failed")), evaluation)
	var durability := _consume_weapon_durability(profile, "ranged_attack")
	_cooldown_total = maxf(0.05, float(profile.get("cooldown_seconds", 0.55)))
	_cooldown_remaining = _cooldown_total
	_shot_count += 1
	_last_result = {
		"handled": true,
		"accepted": true,
		"status": "fired",
		"reason": "ok",
		"attack_kind": "ranged",
		"projectile_id": int(spawn_result.get("projectile_id", 0)),
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
		"weapon_display_name": _weapon_display_name(str(profile.get("weapon_item_id", ""))),
		"ammo_item_id": ammo_item_id,
		"charge_ratio": float(evaluation.get("charge_ratio", 0.0)),
		"damage": float(evaluation.get("damage", 0.0)),
		"speed": float(evaluation.get("speed", 0.0)),
		"durability": durability.duplicate(true),
	}
	shot_fired.emit(_last_result.duplicate(true))
	_emit_status(true)
	return _last_result.duplicate(true)


func cancel_charge(reason: String = "cancelled") -> Dictionary:
	if not _charging:
		return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_charging"}
	var ratio := shot_policy.charge_ratio(_charge_seconds, _charge_profile)
	_charging = false
	_charge_seconds = 0.0
	_charge_profile.clear()
	_cancel_count += 1
	_last_result = {
		"handled": true,
		"accepted": false,
		"status": "cancelled",
		"reason": reason,
		"charge_ratio": ratio,
	}
	_emit_status(true)
	return _last_result.duplicate(true)


func request_reload() -> Dictionary:
	var profile := _active_profile_ref()
	if profile.is_empty() or str(profile.get("action_kind", "")) != ACTION_FIREARM:
		return {"handled": false, "accepted": false, "reason": "not_firearm"}
	if _reload_remaining > 0.0:
		return _reject("already_reloading")
	var capacity := maxi(1, int(profile.get("magazine_capacity", 1)))
	var loaded := _magazine_rounds(profile)
	if loaded >= capacity:
		return _reject("magazine_full")
	var reserve := _reserve_ammo_count(profile)
	if reserve <= 0:
		return _reject("no_reserve_ammo")
	_clear_trigger()
	_reload_total = maxf(0.2, float(profile.get("reload_seconds", 1.0)))
	_reload_remaining = _reload_total
	_reload_weapon_id = str(profile.get("weapon_item_id", ""))
	_last_result = {
		"handled": true,
		"accepted": true,
		"status": "reloading",
		"reason": "ok",
		"weapon_item_id": _reload_weapon_id,
		"weapon_display_name": _weapon_display_name(_reload_weapon_id),
		"magazine_rounds": loaded,
		"magazine_capacity": capacity,
		"reserve_ammo_count": reserve,
		"reload_seconds": _reload_total,
	}
	reload_started.emit(_last_result.duplicate(true))
	_emit_status(true)
	return _last_result.duplicate(true)


func cancel_reload(reason: String = "cancelled") -> Dictionary:
	return _cancel_reload(reason)


func clear(reason: String = "clear") -> void:
	if _charging:
		cancel_charge(reason)
	if _reload_remaining > 0.0:
		_cancel_reload(reason)
	_clear_trigger()
	_charging = false
	_charge_seconds = 0.0
	_charge_profile.clear()
	_cooldown_remaining = 0.0
	_cooldown_total = 0.0
	_reload_remaining = 0.0
	_reload_total = 0.0
	_reload_weapon_id = ""
	_last_result.clear()
	if projectile_runtime != null:
		projectile_runtime.call("clear", reason)
	if hitscan_runtime != null:
		hitscan_runtime.call("clear", reason)
	_emit_status(true)


func get_snapshot() -> Dictionary:
	var profile := _active_profile_ref()
	var active_profile := _charge_profile if _charging else profile
	var ammo_item_id := str(profile.get("ammo_item_id", ""))
	var action_kind := str(profile.get("action_kind", ""))
	var capacity := int(profile.get("magazine_capacity", 0)) if action_kind == ACTION_FIREARM else 0
	var loaded := _magazine_rounds(profile) if action_kind == ACTION_FIREARM else 0
	return {
		"equipped": not profile.is_empty(),
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
		"weapon_display_name": _weapon_display_name(str(profile.get("weapon_item_id", ""))),
		"ammo_item_id": ammo_item_id,
		"ammo_count": _reserve_ammo_count(profile),
		"reserve_ammo_count": _reserve_ammo_count(profile),
		"action_kind": action_kind,
		"delivery_kind": str(profile.get("delivery_kind", "")),
		"fire_mode": str(profile.get("fire_mode", "")),
		"magazine_rounds": loaded,
		"magazine_capacity": capacity,
		"trigger_active": _trigger_active,
		"charging": _charging,
		"charge_seconds": _charge_seconds,
		"charge_ratio": shot_policy.charge_ratio(_charge_seconds, active_profile) if _charging else 0.0,
		"minimum_draw_ratio": float(active_profile.get("minimum_draw_ratio", 0.0)),
		"reloading": _reload_remaining > 0.0,
		"reload_remaining_seconds": _reload_remaining,
		"reload_total_seconds": _reload_total,
		"reload_ratio": 0.0 if _reload_total <= 0.0 else clampf(1.0 - _reload_remaining / _reload_total, 0.0, 1.0),
		"cooldown_ready": _cooldown_remaining <= 0.0,
		"cooldown_remaining_seconds": _cooldown_remaining,
		"cooldown_total_seconds": _cooldown_total,
		"cooldown_ready_ratio": 1.0 if _cooldown_total <= 0.0 else clampf(1.0 - _cooldown_remaining / _cooldown_total, 0.0, 1.0),
		"shot_count": _shot_count,
		"rejection_count": _rejection_count,
		"cancel_count": _cancel_count,
		"reload_count": _reload_count,
		"profile_refresh_count": _profile_refresh_count,
		"last_result": _last_result.duplicate(true),
		"projectiles": projectile_runtime.call("get_snapshot") if projectile_runtime != null else {},
		"hitscan": hitscan_runtime.call("get_snapshot") if hitscan_runtime != null else {},
	}


func _begin_charge_with_profile(profile: Dictionary) -> Dictionary:
	if _charging:
		return _reject("already_charging")
	if _reload_remaining > 0.0:
		return _reject("reloading")
	if _cooldown_remaining > 0.0:
		return _reject("cooldown")
	if not _has_reserve_ammo(profile):
		return _reject("no_ammo")
	if projectile_runtime == null or not bool(projectile_runtime.call("can_spawn")):
		return _reject("projectile_capacity")
	_charging = true
	_charge_seconds = 0.0
	_charge_profile = profile.duplicate(true)
	_last_result = {
		"handled": true,
		"accepted": true,
		"status": "charging",
		"reason": "ok",
	}
	_emit_status(true)
	return _last_result.duplicate(true)


func _begin_firearm_trigger(
	profile: Dictionary,
	origin: Vector3,
	direction: Vector3,
	attacker: Node3D
) -> Dictionary:
	if _reload_remaining > 0.0:
		return _reject("reloading")
	if _cooldown_remaining > 0.0:
		return _reject("cooldown")
	if _magazine_rounds(profile) <= 0:
		return _reject("empty_magazine")
	_trigger_active = true
	_trigger_profile = profile.duplicate(true)
	_trigger_origin = origin
	_trigger_direction = _normalized_direction(direction)
	_trigger_attacker = attacker
	var result := _fire_firearm(
		_trigger_profile,
		_trigger_origin,
		_trigger_direction,
		_trigger_attacker
	)
	if not bool(result.get("accepted", false)):
		_clear_trigger()
	return result


func _fire_firearm(
	profile: Dictionary,
	origin: Vector3,
	direction: Vector3,
	attacker: Node3D
) -> Dictionary:
	if str(profile.get("action_kind", "")) != ACTION_FIREARM:
		return _reject("not_firearm")
	if _reload_remaining > 0.0:
		return _reject("reloading")
	if _cooldown_remaining > 0.0:
		return _reject("cooldown")
	if str(profile.get("weapon_item_id", "")) != get_equipped_weapon_id():
		return _reject("weapon_changed")
	var loaded_before := _magazine_rounds(profile)
	if loaded_before <= 0:
		return _reject("empty_magazine")
	if hitscan_runtime == null:
		return _reject("hitscan_unavailable")
	if not _set_magazine_rounds(profile, loaded_before - 1):
		return _reject("magazine_update_failed")
	var normalized_direction := _normalized_direction(direction)
	var shot := {
		"attack_kind": "firearm",
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
		"ammo_item_id": str(profile.get("ammo_item_id", "")),
		"raw_damage": float(profile.get("damage_per_pellet", 0.0)),
		"shot_direction": [normalized_direction.x, normalized_direction.y, normalized_direction.z],
		"knockback_horizontal": float(profile.get("knockback_horizontal", 0.0)),
		"knockback_vertical": float(profile.get("knockback_vertical", 0.0)),
		"hit_stun_seconds": float(profile.get("hit_stun_seconds", 0.0)),
	}
	var hitscan_result: Dictionary = hitscan_runtime.call(
		"resolve_shot",
		{
			"origin": origin,
			"direction": normalized_direction,
			"max_distance": float(profile.get("max_distance", 64.0)),
			"pellet_count": int(profile.get("pellet_count", 1)),
			"spread_degrees": float(profile.get("spread_degrees", 0.0)),
			"collision_mask": int(profile.get("collision_mask", 5)),
			"attacker": attacker,
			"shot": shot,
		}
	)
	if not bool(hitscan_result.get("success", false)):
		_set_magazine_rounds(profile, loaded_before)
		return _reject(str(hitscan_result.get("reason", "hitscan_failed")))
	var durability := _consume_weapon_durability(profile, "firearm_attack")
	_cooldown_total = maxf(0.05, float(profile.get("fire_interval_seconds", 0.25)))
	_cooldown_remaining = _cooldown_total
	_shot_count += 1
	var loaded_after := loaded_before - 1
	_last_result = {
		"handled": true,
		"accepted": true,
		"status": "fired",
		"reason": "ok",
		"attack_kind": "firearm",
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
		"weapon_display_name": _weapon_display_name(str(profile.get("weapon_item_id", ""))),
		"ammo_item_id": str(profile.get("ammo_item_id", "")),
		"fire_mode": str(profile.get("fire_mode", "semi")),
		"magazine_before": loaded_before,
		"magazine_after": loaded_after,
		"magazine_capacity": int(profile.get("magazine_capacity", 1)),
		"reserve_ammo_count": _reserve_ammo_count(profile),
		"pellet_count": int(profile.get("pellet_count", 1)),
		"hitscan_id": int(hitscan_result.get("hitscan_id", 0)),
		"impact_count": int(hitscan_result.get("impact_count", 0)),
		"accepted_target_count": int(hitscan_result.get("accepted_target_count", 0)),
		"target_results": hitscan_result.get("target_results", []).duplicate(true),
		"recoil_pitch_degrees": float(profile.get("recoil_pitch_degrees", 0.0)),
		"recoil_yaw_degrees": float(profile.get("recoil_yaw_degrees", 0.0)),
		"durability": durability.duplicate(true),
	}
	if loaded_after <= 0:
		_last_result["magazine_empty"] = true
	shot_fired.emit(_last_result.duplicate(true))
	_emit_status(true)
	return _last_result.duplicate(true)


func _complete_reload() -> Dictionary:
	var weapon_id := _reload_weapon_id
	_reload_remaining = 0.0
	_reload_total = 0.0
	_reload_weapon_id = ""
	var profile := _active_profile_ref()
	if profile.is_empty() or str(profile.get("weapon_item_id", "")) != weapon_id:
		return _cancel_reload("weapon_changed")
	var capacity := maxi(1, int(profile.get("magazine_capacity", 1)))
	var loaded_before := _magazine_rounds(profile)
	var reserve_before := _reserve_ammo_count(profile)
	var rounds_to_load := mini(capacity - loaded_before, reserve_before)
	if rounds_to_load <= 0:
		return _cancel_reload("no_reserve_ammo")
	var ammo_item_id := str(profile.get("ammo_item_id", ""))
	var transaction: Dictionary = inventory.call(
		"transact_items",
		{ammo_item_id: rounds_to_load},
		[]
	)
	if not bool(transaction.get("success", false)):
		return _cancel_reload("ammo_transaction_failed")
	if not _set_magazine_rounds(profile, loaded_before + rounds_to_load):
		var refund_leftover := int(inventory.call("add_item", ammo_item_id, rounds_to_load))
		var result := _cancel_reload("magazine_update_failed")
		result["refund_leftover"] = refund_leftover
		return result
	_reload_count += 1
	_last_result = {
		"handled": true,
		"accepted": true,
		"status": "reloaded",
		"reason": "ok",
		"weapon_item_id": weapon_id,
		"weapon_display_name": _weapon_display_name(weapon_id),
		"ammo_item_id": ammo_item_id,
		"rounds_loaded": rounds_to_load,
		"magazine_before": loaded_before,
		"magazine_after": loaded_before + rounds_to_load,
		"magazine_capacity": capacity,
		"reserve_before": reserve_before,
		"reserve_after": _reserve_ammo_count(profile),
	}
	reload_completed.emit(_last_result.duplicate(true))
	_emit_status(true)
	return _last_result.duplicate(true)


func _cancel_reload(reason: String) -> Dictionary:
	if _reload_remaining <= 0.0 and _reload_weapon_id.is_empty():
		return {"handled": has_ranged_weapon(), "accepted": false, "reason": "not_reloading"}
	var weapon_id := _reload_weapon_id
	_reload_remaining = 0.0
	_reload_total = 0.0
	_reload_weapon_id = ""
	_cancel_count += 1
	_last_result = {
		"handled": true,
		"accepted": false,
		"status": "reload_cancelled",
		"reason": reason,
		"weapon_item_id": weapon_id,
	}
	reload_cancelled.emit(_last_result.duplicate(true))
	_emit_status(true)
	return _last_result.duplicate(true)


func _clear_trigger() -> void:
	_trigger_active = false
	_trigger_profile.clear()
	_trigger_origin = Vector3.ZERO
	_trigger_direction = Vector3.FORWARD
	_trigger_attacker = null


func _active_profile_ref() -> Dictionary:
	var weapon_id := get_equipped_weapon_id()
	if not _profile_cache_initialized or weapon_id != _cached_weapon_id:
		_cached_weapon_id = weapon_id
		_cached_profile = registry.get_profile(weapon_id)
		_profile_cache_initialized = true
		_profile_refresh_count += 1
	return _cached_profile


func _has_reserve_ammo(profile: Dictionary) -> bool:
	return _reserve_ammo_count(profile) > 0


func _reserve_ammo_count(profile: Dictionary) -> int:
	var item_id := str(profile.get("ammo_item_id", ""))
	if item_id.is_empty() or inventory == null or not inventory.has_method("count_item"):
		return 0
	return maxi(0, int(inventory.call("count_item", item_id)))


func _magazine_rounds(profile: Dictionary) -> int:
	if profile.is_empty() or equipment_service == null or not equipment_service.has_method("get_slot"):
		return 0
	var item: Dictionary = equipment_service.call("get_slot", MAIN_HAND_SLOT)
	if str(item.get("item_id", "")) != str(profile.get("weapon_item_id", "")):
		return 0
	var capacity := maxi(0, int(profile.get("magazine_capacity", 0)))
	return clampi(int(item.get("metadata", {}).get(MAGAZINE_METADATA_KEY, 0)), 0, capacity)


func _set_magazine_rounds(profile: Dictionary, value: int) -> bool:
	if equipment_service == null or not equipment_service.has_method("update_slot_metadata"):
		return false
	var item: Dictionary = equipment_service.call("get_slot", MAIN_HAND_SLOT)
	if str(item.get("item_id", "")) != str(profile.get("weapon_item_id", "")):
		return false
	var capacity := maxi(0, int(profile.get("magazine_capacity", 0)))
	return bool(equipment_service.call(
		"update_slot_metadata",
		MAIN_HAND_SLOT,
		{MAGAZINE_METADATA_KEY: clampi(value, 0, capacity)}
	))


func _consume_weapon_durability(profile: Dictionary, reason: String) -> Dictionary:
	if equipment_service == null or not equipment_service.has_method("consume_durability"):
		return {"consumed": false, "broken": false}
	return equipment_service.call(
		"consume_durability",
		MAIN_HAND_SLOT,
		maxi(1, int(profile.get("durability_cost", 1))),
		reason
	)


func _weapon_display_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	if inventory != null:
		var item_registry: Variant = inventory.get("registry")
		if item_registry != null and item_registry.has_method("get_display_name"):
			return str(item_registry.call("get_display_name", item_id))
	return item_id


func _normalized_direction(direction: Vector3) -> Vector3:
	if (
		is_finite(direction.x)
		and is_finite(direction.y)
		and is_finite(direction.z)
		and direction.length_squared() > 0.0001
	):
		return direction.normalized()
	return Vector3.FORWARD


func _reject(reason: String, extra: Dictionary = {}) -> Dictionary:
	_rejection_count += 1
	var result := {
		"handled": true,
		"accepted": false,
		"status": "rejected",
		"reason": reason,
	}
	result.merge(extra, true)
	result["accepted"] = false
	result["status"] = "rejected"
	result["reason"] = reason
	_last_result = result.duplicate(true)
	shot_rejected.emit(result.duplicate(true))
	_emit_status(true)
	return result


func _emit_status(force: bool = false) -> void:
	if not force and _signal_accumulator < STATUS_SIGNAL_INTERVAL:
		return
	_signal_accumulator = 0.0
	charge_changed.emit(get_snapshot())


func _on_projectile_hit(_projectile_id: int, result: Dictionary) -> void:
	projectile_hit.emit(result.duplicate(true))
