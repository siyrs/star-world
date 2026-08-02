extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const AttributeScript = preload("res://src/attribute/attribute_service.gd")
const CombatScript = preload("res://src/combat/combat_service.gd")
const RangedScript = preload("res://src/combat/ranged_combat_service.gd")
const ProjectileRuntimeScript = preload("res://src/combat/projectile_runtime_service.gd")

var checks := 0
var failures: Array[String] = []


class RangedTarget:
	extends CharacterBody3D
	var display_name := "远程测试假人"
	var health := 20.0
	var hit_count := 0
	var last_hit: Dictionary = {}

	func is_combat_target_available() -> bool:
		return health > 0.0

	func get_combat_attributes() -> Dictionary:
		return {"defense": 0.0}

	func apply_combat_hit(hit: Dictionary, _attacker: Node3D = null) -> Dictionary:
		var damage := maxf(0.0, float(hit.get("final_damage", 0.0)))
		var before := health
		health = maxf(0.0, health - damage)
		hit_count += 1
		last_hit = hit.duplicate(true)
		return {
			"applied": damage > 0.0,
			"health_before": before,
			"health_after": health,
			"remaining_health": health,
			"defeated": health <= 0.0,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var attributes = AttributeScript.new()
	var combat = CombatScript.new()
	var ranged = RangedScript.new()
	var attacker := Node3D.new()
	for node: Node in [inventory, equipment, attributes, combat, ranged, attacker]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	attributes.setup(equipment)
	combat.setup(attributes, equipment)
	ranged.setup(inventory, equipment, combat)
	ranged.set_process(false)
	inventory.clear()
	inventory.add_item("bow", 1, {"durability": 384, "custom_name": "运行时验收弓"})
	inventory.add_item("arrow", 2)
	_check(equipment.equip_from_inventory(inventory, _find_item_slot(inventory, "bow")), "real equipment transaction equips the ranged weapon")
	_check(ranged.process_mode == Node.PROCESS_MODE_PAUSABLE, "ranged charge and cooldown use the shared pause contract")
	var runtime := ranged.get("projectile_runtime") as Node
	_check(runtime != null and runtime.process_mode == Node.PROCESS_MODE_PAUSABLE, "all projectiles share one pausable runtime")
	_check(ProjectileRuntimeScript.MAX_ACTIVE_PROJECTILES == 64, "projectile runtime exposes a hard active-node budget")
	var first_snapshot: Dictionary = ranged.get_snapshot()
	var refresh_count := int(first_snapshot.get("profile_refresh_count", 0))
	for _sample in 4096:
		ranged.get_snapshot()
	_check(
		int(ranged.get_snapshot().get("profile_refresh_count", -1)) == refresh_count,
		"frame hot path reuses one cached ranged profile"
	)

	var target := RangedTarget.new()
	target.name = "RangedTarget"
	target.collision_layer = 4
	target.collision_mask = 0
	var collision_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	collision_shape.shape = sphere
	target.add_child(collision_shape)
	host.add_child(target)
	target.global_position = Vector3(0.0, 0.0, -5.0)
	await physics_frame
	await physics_frame

	var ammo_before := inventory.count_item("arrow")
	var durability_before := _main_hand_durability(equipment)
	_check(bool(ranged.begin_charge().get("accepted", false)), "bow begins one bounded charge")
	ranged.call("_process", 0.8)
	var fired: Dictionary = ranged.release_charge(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(bool(fired.get("accepted", false)) and str(fired.get("status", "")) == "fired", "full draw commits one projectile")
	_check(inventory.count_item("arrow") == ammo_before - 1, "accepted shot consumes exactly one arrow")
	_check(_main_hand_durability(equipment) == durability_before - 1, "accepted shot consumes exactly one bow durability")
	_check(await _wait_for_hit(target, runtime), "real physics raycast delivers the projectile to the target")
	_check(target.hit_count == 1, "one projectile applies damage exactly once")
	_check(is_equal_approx(target.health, 13.0), "full draw applies configured maximum damage through CombatService")
	_check(str(target.last_hit.get("attack_kind", "")) == "ranged", "target receives the shared ranged combat context")
	_check(Array(target.last_hit.get("knockback", [])).size() == 3, "projectile hit reuses the combat knockback capability")
	_check(int(runtime.call("get_snapshot").get("active_count", -1)) == 0, "hit projectile is released immediately")

	ranged.call("_process", 1.0)
	var ammo_before_undercharge := inventory.count_item("arrow")
	var durability_before_undercharge := _main_hand_durability(equipment)
	_check(bool(ranged.begin_charge().get("accepted", false)), "second charge begins after cooldown")
	ranged.call("_process", 0.05)
	var undercharged: Dictionary = ranged.release_charge(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(str(undercharged.get("reason", "")) == "undercharged", "short release is rejected deterministically")
	_check(inventory.count_item("arrow") == ammo_before_undercharge, "undercharged release consumes no arrow")
	_check(_main_hand_durability(equipment) == durability_before_undercharge, "undercharged release consumes no durability")

	_check(bool(ranged.begin_charge().get("accepted", false)), "charge can start before a lifecycle cancellation")
	var cancelled: Dictionary = ranged.cancel_charge("input_disabled")
	_check(str(cancelled.get("status", "")) == "cancelled", "input disable cancels charge without firing")
	_check(inventory.count_item("arrow") == ammo_before_undercharge, "cancelled charge preserves ammunition")

	inventory.remove_item("arrow", inventory.count_item("arrow"))
	var no_ammo: Dictionary = ranged.begin_charge()
	_check(str(no_ammo.get("reason", "")) == "no_ammo", "empty ammunition is rejected before charge")
	_check(int(runtime.call("get_snapshot").get("spawn_count", 0)) == 1, "rejected shots never create hidden projectiles")

	inventory.add_item("arrow", 1)
	runtime.set_physics_process(false)
	runtime.call("clear", "capacity_fixture")
	for index in ProjectileRuntimeScript.MAX_ACTIVE_PROJECTILES:
		var spawned: Dictionary = runtime.call(
			"spawn_projectile",
			{
				"origin": Vector3(float(index) * 0.01, 20.0, 0.0),
				"velocity": Vector3.FORWARD,
				"gravity": 0.0,
				"max_distance": 64.0,
				"max_lifetime_seconds": 5.0,
				"collision_mask": 5,
				"attacker": attacker,
				"shot": {"raw_damage": 1.0},
			}
		)
		if not bool(spawned.get("success", false)):
			failures.append("capacity fixture rejected projectile %d" % index)
	_check(not bool(runtime.call("can_spawn")), "runtime stops accepting projectiles at exactly 64")
	var capacity_rejection: Dictionary = ranged.begin_charge()
	_check(str(capacity_rejection.get("reason", "")) == "projectile_capacity", "charge rejects before consuming ammo when the shared runtime is full")
	_check(inventory.count_item("arrow") == 1, "capacity rejection preserves ammunition")
	ranged.clear("world_transition")
	_check(int(runtime.call("get_snapshot").get("active_count", -1)) == 0, "world transition clears every projectile deterministically")
	_check(not bool(ranged.get_snapshot().get("charging", true)), "world transition clears transient charge state")
	_check(ranged.get_snapshot().get("projectiles", {}) is Dictionary, "runtime diagnostics remain available without entering save data")

	target.queue_free()
	host.queue_free()
	for _frame in 4:
		await process_frame
	if failures.is_empty():
		print("QA RANGED COMBAT RUNTIME PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANGED COMBAT RUNTIME FAILURE: %s" % failure)
		print(
			"QA RANGED COMBAT RUNTIME FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _wait_for_hit(target: RangedTarget, runtime: Node) -> bool:
	for _frame in 240:
		await physics_frame
		if target.hit_count > 0 and int(runtime.call("get_snapshot").get("active_count", 0)) == 0:
			return true
	return false


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) == item_id:
			return index
	return -1


func _main_hand_durability(equipment: Node) -> int:
	var item: Dictionary = equipment.call("get_slot", "main_hand")
	return int(item.get("metadata", {}).get("durability", 384))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
