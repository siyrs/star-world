extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const AttributeScript = preload("res://src/attribute/attribute_service.gd")
const CombatScript = preload("res://src/combat/combat_service.gd")
const RangedScript = preload("res://src/combat/ranged_combat_service.gd")
const HitscanScript = preload("res://src/combat/hitscan_runtime_service.gd")

var checks := 0
var failures: Array[String] = []


class FirearmTarget:
	extends CharacterBody3D
	var display_name := "枪械测试假人"
	var health := 200.0
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
	var target := _create_target(host, Vector3(0.0, 0.0, -5.0), 2.2)
	await physics_frame
	await physics_frame
	await _test_pistol_transaction(inventory, equipment, ranged, attacker, target)
	await _test_reload_transaction(inventory, equipment, ranged)
	await _test_shotgun_aggregation(inventory, equipment, ranged, attacker, target)
	await _test_auto_cadence(inventory, equipment, ranged, attacker, target)
	_test_runtime_bounds(ranged)
	target.queue_free()
	host.queue_free()
	for _frame in 6:
		await process_frame
	if failures.is_empty():
		print("QA FIREARM RUNTIME PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA FIREARM RUNTIME FAILURE: %s" % failure)
	print("QA FIREARM RUNTIME FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_pistol_transaction(
	inventory: Node,
	equipment: Node,
	ranged: Node,
	attacker: Node3D,
	target: FirearmTarget
) -> void:
	inventory.clear()
	inventory.add_item("star_pistol", 1, {"durability":420,"magazine_rounds":2})
	inventory.add_item("light_round", 10)
	_check(equipment.equip_from_inventory(inventory, _find_item_slot(inventory, "star_pistol")), "real equipment transaction equips a loaded pistol")
	var reserve_before := inventory.count_item("light_round")
	var durability_before := _durability(equipment)
	var health_before := target.health
	var fired: Dictionary = ranged.begin_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(bool(fired.get("accepted", false)) and str(fired.get("attack_kind", "")) == "firearm", "semi-auto trigger resolves one firearm shot")
	_check(int(fired.get("magazine_before", -1)) == 2 and int(fired.get("magazine_after", -1)) == 1, "accepted pistol shot decrements the magazine exactly once")
	_check(inventory.count_item("light_round") == reserve_before, "firing consumes no reserve ammunition directly")
	_check(_durability(equipment) == durability_before - 1, "accepted pistol shot consumes exactly one durability")
	_check(target.hit_count == 1 and target.health < health_before, "hitscan pistol reaches the real physics target exactly once")
	_check(str(target.last_hit.get("attack_kind", "")) == "firearm", "CombatService preserves firearm hit semantics")
	_check(int(target.last_hit.get("hitscan_id", 0)) > 0, "firearm hit includes a stable hitscan identifier")
	var second_press: Dictionary = ranged.begin_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(str(second_press.get("reason", "")) == "cooldown", "semi-auto cadence rejects presses inside the fire interval")
	ranged.call("_process", 0.30)
	ranged.release_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	var second: Dictionary = ranged.begin_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(bool(second.get("accepted", false)) and int(second.get("magazine_after", -1)) == 0, "second legal pistol shot empties the magazine")
	ranged.release_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	ranged.call("_process", 0.30)
	var empty: Dictionary = ranged.begin_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(str(empty.get("reason", "")) == "empty_magazine", "empty pistol rejects before damage durability or reserve transactions")
	_check(inventory.count_item("light_round") == reserve_before, "empty-magazine rejection preserves reserve ammunition")


func _test_reload_transaction(inventory: Node, equipment: Node, ranged: Node) -> void:
	var reserve_before := inventory.count_item("light_round")
	var started: Dictionary = ranged.request_reload()
	_check(bool(started.get("accepted", false)) and str(started.get("status", "")) == "reloading", "reload starts one bounded transient timer")
	_check(inventory.count_item("light_round") == reserve_before, "reload start does not pre-deduct reserve ammunition")
	ranged.call("_process", 0.40)
	var cancelled: Dictionary = ranged.cancel_reload("test_cancel")
	_check(str(cancelled.get("status", "")) == "reload_cancelled", "reload cancellation is explicit")
	_check(inventory.count_item("light_round") == reserve_before, "cancelled reload loses no reserve ammunition")
	_check(int(equipment.get_slot("main_hand").get("metadata", {}).get("magazine_rounds", -1)) == 0, "cancelled reload leaves the empty magazine unchanged")
	_check(bool(ranged.request_reload().get("accepted", false)), "reload can restart after cancellation")
	ranged.call("_process", 1.25)
	var snapshot: Dictionary = ranged.get_snapshot()
	_check(not bool(snapshot.get("reloading", true)), "reload completes inside the configured bounded duration")
	_check(int(snapshot.get("magazine_rounds", -1)) == 8, "completed pistol reload fills the magazine to capacity")
	_check(inventory.count_item("light_round") == reserve_before - 8, "completed reload atomically consumes exact reserve rounds")
	var saved_inventory: Dictionary = inventory.serialize()
	var saved_equipment: Dictionary = equipment.serialize()
	var restored_inventory = InventoryScript.new()
	var restored_equipment = EquipmentScript.new()
	root.add_child(restored_inventory)
	root.add_child(restored_equipment)
	await process_frame
	restored_equipment.setup(restored_inventory.registry)
	_check(restored_inventory.deserialize(saved_inventory), "reserve ammunition survives existing inventory persistence")
	_check(restored_equipment.deserialize(saved_equipment), "loaded firearm survives existing equipment persistence")
	_check(int(restored_equipment.get_slot("main_hand").get("metadata", {}).get("magazine_rounds", -1)) == 8, "magazine rounds survive save and reload")
	restored_inventory.queue_free()
	restored_equipment.queue_free()
	await process_frame


func _test_shotgun_aggregation(
	inventory: Node,
	equipment: Node,
	ranged: Node,
	attacker: Node3D,
	target: FirearmTarget
) -> void:
	ranged.clear("shotgun_fixture")
	equipment.equip("main_hand", {"item_id":"scattergun","count":1,"metadata":{"durability":560,"magazine_rounds":1}})
	inventory.add_item("shotgun_shell", 6)
	target.health = 200.0
	target.hit_count = 0
	target.last_hit.clear()
	var result: Dictionary = ranged.begin_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(bool(result.get("accepted", false)) and int(result.get("pellet_count", 0)) == 7, "pump shotgun emits seven bounded rays")
	_check(target.hit_count == 1, "shotgun pellets aggregate into one target damage transaction")
	_check(int(target.last_hit.get("pellet_hits", 0)) >= 2, "large target records multiple aggregated pellet hits")
	_check(float(target.last_hit.get("raw_damage", 0.0)) > 2.6, "aggregated shotgun damage scales with pellet hits")
	_check(int(result.get("accepted_target_count", 0)) == 1, "shotgun resolves one unique accepted target")
	ranged.release_primary(Vector3.ZERO, Vector3.FORWARD, attacker)


func _test_auto_cadence(
	inventory: Node,
	equipment: Node,
	ranged: Node,
	attacker: Node3D,
	target: FirearmTarget
) -> void:
	ranged.clear("auto_fixture")
	equipment.equip("main_hand", {"item_id":"frontier_carbine","count":1,"metadata":{"durability":720,"magazine_rounds":4}})
	inventory.add_item("light_round", 20)
	target.health = 200.0
	target.hit_count = 0
	var first: Dictionary = ranged.begin_primary(Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(bool(first.get("accepted", false)), "automatic carbine fires immediately on trigger press")
	for expected_shots in range(2, 5):
		ranged.call("_process", 0.10)
		var next: Dictionary = ranged.advance_primary(0.10, Vector3.ZERO, Vector3.FORWARD, attacker)
		_check(bool(next.get("accepted", false)), "automatic carbine emits shot %d only after cadence interval" % expected_shots)
	_check(target.hit_count == 4, "four-round automatic hold applies exactly four target transactions")
	_check(int(ranged.get_snapshot().get("magazine_rounds", -1)) == 0, "automatic hold cannot fire beyond available magazine rounds")
	ranged.call("_process", 0.10)
	var after_empty: Dictionary = ranged.advance_primary(0.10, Vector3.ZERO, Vector3.FORWARD, attacker)
	_check(str(after_empty.get("reason", "")) in ["empty_magazine", "not_active"], "automatic trigger stops deterministically on empty magazine")
	ranged.release_primary(Vector3.ZERO, Vector3.FORWARD, attacker)


func _test_runtime_bounds(ranged: Node) -> void:
	var snapshot: Dictionary = ranged.get_snapshot()
	var hitscan: Dictionary = snapshot.get("hitscan", {})
	_check(HitscanScript.MAX_RAYS_PER_SHOT == 12, "hitscan runtime exposes a hard twelve-ray budget")
	_check(float(hitscan.get("max_distance", 0.0)) == 128.0, "hitscan runtime exposes a hard distance budget")
	_check(int(hitscan.get("ray_count", 0)) <= int(hitscan.get("shot_count", 0)) * 12, "runtime ray count remains bounded by shots times twelve")
	_check(ranged.get_child_count() == 2, "ranged service owns exactly projectile and hitscan runtimes")
	for child: Node in ranged.get_children():
		_check(child is not Timer, "firearm runtime creates no per-shot Timer nodes")


func _create_target(parent: Node3D, position: Vector3, radius: float) -> FirearmTarget:
	var target := FirearmTarget.new()
	target.collision_layer = 4
	target.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape_node.shape = sphere
	target.add_child(shape_node)
	target.global_position = position
	parent.add_child(target)
	return target


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str(inventory.call("get_slot", index).get("item_id", "")) == item_id:
			return index
	return -1


func _durability(equipment: Node) -> int:
	return int(equipment.get_slot("main_hand").get("metadata", {}).get("durability", 0))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
