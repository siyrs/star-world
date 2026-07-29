class_name RangedCombatService
extends Node3D

signal charge_changed(snapshot: Dictionary)
signal shot_fired(result: Dictionary)
signal shot_rejected(result: Dictionary)
signal projectile_hit(result: Dictionary)

const RegistryScript = preload("res://src/combat/ranged_weapon_registry.gd")
const ShotPolicyScript = preload("res://src/combat/ranged_shot_policy.gd")
const ProjectileRuntimeScript = preload("res://src/combat/projectile_runtime_service.gd")
const MAIN_HAND_SLOT := "main_hand"
const STATUS_SIGNAL_INTERVAL := 0.05

var inventory: Node
var equipment_service: Node
var combat_service: Node
var registry = RegistryScript.new()
var shot_policy = ShotPolicyScript.new()
var projectile_runtime: Node3D

var _charging := false
var _charge_seconds := 0.0
var _charge_profile: Dictionary = {}
var _cooldown_remaining := 0.0
var _cooldown_total := 0.0
var _signal_accumulator := 0.0
var _shot_count := 0
var _rejection_count := 0
var _cancel_count := 0
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	registry.ensure_loaded()
	projectile_runtime = ProjectileRuntimeScript.new()
	projectile_runtime.name = "ProjectileRuntime"
	add_child(projectile_runtime)
	projectile_runtime.call("setup", combat_service)
	projectile_runtime.connect("projectile_hit", Callable(self, "_on_projectile_hit"))


func _process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	if _charging:
		_charge_seconds += safe_delta
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - safe_delta)
	_signal_accumulator += safe_delta
	if (_charging or _cooldown_remaining > 0.0) and _signal_accumulator >= STATUS_SIGNAL_INTERVAL:
		_emit_status()


func setup(p_inventory: Node, p_equipment: Node, p_combat: Node) -> void:
	inventory = p_inventory
	equipment_service = p_equipment
	combat_service = p_combat
	registry.ensure_loaded()
	if projectile_runtime != null:
		projectile_runtime.call("setup", combat_service)


func has_ranged_weapon() -> bool:
	return not get_active_profile().is_empty()


func get_equipped_weapon_id() -> String:
	if equipment_service == null or not equipment_service.has_method("get_slot"):
		return ""
	var raw_slot: Variant = equipment_service.call("get_slot", MAIN_HAND_SLOT)
	return str(raw_slot.get("item_id", "")) if raw_slot is Dictionary else ""


func get_active_profile() -> Dictionary:
	return registry.get_profile(get_equipped_weapon_id())


func begin_charge() -> Dictionary:
	var profile := get_active_profile()
	if profile.is_empty():
		return {"handled": false, "accepted": false, "reason": "not_ranged_weapon"}
	if _charging:
		return _reject("already_charging")
	if _cooldown_remaining > 0.0:
		return _reject("cooldown")
	if not _has_ammo(profile):
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


func advance_charge(_delta: float) -> Dictionary:
	# RangedCombatService._process() is the single pause-aware charge clock.
	# Player input only declares that the button remains held; it must never
	# accumulate the same frame delta a second time.
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
	if not _has_ammo(profile):
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
	var durability := {"consumed": false, "broken": false}
	if equipment_service != null and equipment_service.has_method("consume_durability"):
		durability = equipment_service.call(
			"consume_durability",
			MAIN_HAND_SLOT,
			maxi(1, int(profile.get("durability_cost", 1))),
			"ranged_attack"
		)
	_cooldown_total = maxf(0.05, float(profile.get("cooldown_seconds", 0.55)))
	_cooldown_remaining = _cooldown_total
	_shot_count += 1
	_last_result = {
		"handled": true,
		"accepted": true,
		"status": "fired",
		"reason": "ok",
		"projectile_id": int(spawn_result.get("projectile_id", 0)),
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
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


func clear(reason: String = "clear") -> void:
	if _charging:
		cancel_charge(reason)
	_charging = false
	_charge_seconds = 0.0
	_charge_profile.clear()
	_cooldown_remaining = 0.0
	_cooldown_total = 0.0
	_last_result.clear()
	if projectile_runtime != null:
		projectile_runtime.call("clear", reason)
	_emit_status(true)


func get_snapshot() -> Dictionary:
	var profile := get_active_profile()
	var active_profile := _charge_profile if _charging else profile
	var ammo_item_id := str(profile.get("ammo_item_id", ""))
	return {
		"equipped": not profile.is_empty(),
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
		"ammo_item_id": ammo_item_id,
		"ammo_count": _ammo_count(ammo_item_id),
		"charging": _charging,
		"charge_seconds": _charge_seconds,
		"charge_ratio": shot_policy.charge_ratio(_charge_seconds, active_profile) if _charging else 0.0,
		"minimum_draw_ratio": float(active_profile.get("minimum_draw_ratio", 0.0)),
		"cooldown_ready": _cooldown_remaining <= 0.0,
		"cooldown_remaining_seconds": _cooldown_remaining,
		"cooldown_total_seconds": _cooldown_total,
		"cooldown_ready_ratio": 1.0 if _cooldown_total <= 0.0 else clampf(1.0 - _cooldown_remaining / _cooldown_total, 0.0, 1.0),
		"shot_count": _shot_count,
		"rejection_count": _rejection_count,
		"cancel_count": _cancel_count,
		"last_result": _last_result.duplicate(true),
		"projectiles": projectile_runtime.call("get_snapshot") if projectile_runtime != null else {},
	}


func _has_ammo(profile: Dictionary) -> bool:
	return _ammo_count(str(profile.get("ammo_item_id", ""))) > 0


func _ammo_count(item_id: String) -> int:
	if item_id.is_empty() or inventory == null or not inventory.has_method("count_item"):
		return 0
	return maxi(0, int(inventory.call("count_item", item_id)))


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
