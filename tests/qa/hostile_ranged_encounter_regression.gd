extends SceneTree

const AttackRegistryScript = preload("res://src/entity/hostile_attack_registry.gd")
const RangedPolicyScript = preload("res://src/entity/hostile_ranged_tactics_policy.gd")
const FactoryScript = preload("res://src/entity/creature_factory.gd")
const ProjectileRuntimeScript = preload("res://src/combat/projectile_runtime_service.gd")
const CombatScript = preload("res://src/combat/combat_service.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class HostileProjectileTarget:
	extends CharacterBody3D
	var health := 100.0
	var damage_events := 0
	var last_source := ""
	var last_attacker_id := 0
	var last_result: Dictionary = {}

	func is_combat_target_available() -> bool:
		return health > 0.0

	func take_hostile_damage(
		amount: float,
		source: String = "hostile",
		attacker_id: int = 0
	) -> Dictionary:
		if amount <= 0.0:
			return {"handled": false, "accepted": false, "applied": false}
		var before := health
		health = maxf(0.0, health - amount)
		damage_events += 1
		last_source = source
		last_attacker_id = attacker_id
		last_result = {
			"handled": true,
			"accepted": true,
			"applied": true,
			"health_before": before,
			"health_after": health,
			"defeated": health <= 0.0,
		}
		return last_result.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_policy()
	await _test_player_source_scoped_cooldowns()
	await _test_real_projectile_and_line_of_sight()
	if failures.is_empty():
		print("QA HOSTILE RANGED ENCOUNTER PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE RANGED ENCOUNTER FAILURE: %s" % failure)
	print("QA HOSTILE RANGED ENCOUNTER FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_registry_and_policy() -> void:
	var registry = AttackRegistryScript.new()
	_check(registry.schema_version == 2, "ranged hostile registry loads schema version two")
	_check(registry.get_validation_errors().is_empty(), "production hostile profiles pass strict normalization")
	var marksman: Dictionary = registry.get_profile("abyss_marksman")
	_check(str(marksman.get("attack_kind", "")) == "ranged", "marksman owns ranged attack semantics")
	_check(str(marksman.get("delivery_kind", "")) == "projectile", "marksman uses dodgeable projectile delivery")
	_check(int(marksman.get("cover_probe_count", 0)) == 6, "marksman cover search owns exactly six bounded probes")
	_check(float(marksman.get("projectile_speed", 0.0)) <= 64.0, "marksman projectile speed remains inside registry hard limit")
	_check(float(marksman.get("attack_range", 0.0)) < float(marksman.get("detection_range", 0.0)), "marksman detection remains larger than attack range")

	var invalid_path := "user://invalid-hostile-ranged-profile.json"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	_check(file != null, "invalid hostile profile fixture opens for writing")
	if file != null:
		file.store_string(JSON.stringify({
			"schema_version": 2,
			"profiles": [
				marksman,
				{
					"species_id":"broken", "source_id":"broken",
					"attack_kind":"ranged", "delivery_kind":"projectile",
					"detection_range":60.0, "minimum_range":1.0,
					"preferred_range":20.0, "attack_range":40.0,
					"windup_seconds":0.01, "cooldown_seconds":0.01,
					"cancel_range_multiplier":1.0, "cancel_recovery_seconds":0.0,
					"target_leash_multiplier":1.0, "telegraph_radius_multiplier":1.0,
					"requires_line_of_sight":true, "projectile_speed":999.0,
					"projectile_gravity":0.0, "projectile_max_distance":999.0,
					"projectile_lifetime_seconds":99.0, "projectile_collision_mask":3,
					"projectile_knockback_horizontal":0.0,
					"projectile_knockback_vertical":0.0,
					"projectile_hit_stun_seconds":0.0,
					"projectile_visual_kind":"orb", "projectile_visual_color":"#FFFFFF",
					"cover_probe_count":99, "cover_probe_radius":2.0,
					"cover_refresh_seconds":0.5, "strafe_seconds":1.0,
				}
			]
		}, "  "))
		file.close()
		_check(not registry.load_from_file(invalid_path), "one unbounded hostile profile rejects the entire staged load")
		_check(registry.get_profile_ids() == ["abyss_brute", "abyss_marksman", "zombie"], "failed staged load preserves the prior complete registry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))

	_check(RangedPolicyScript.can_begin(12.0, 5.5, 24.0, true, true, 0.0, 0.0, true), "ranged attack begins at a legal visible distance")
	_check(not RangedPolicyScript.can_begin(12.0, 5.5, 24.0, false, true, 0.0, 0.0, true), "blocked line of sight prevents windup")
	_check(RangedPolicyScript.cancellation_reason(true, 12.0, 5.5, 24.0, 1.12, false, true, 0.0) == "line_of_sight_lost", "los loss cancels an active ranged windup")
	_check(RangedPolicyScript.motion_kind(3.0, 5.5, 13.0, 24.0, true, 0.0, false) == RangedPolicyScript.MOTION_RETREAT, "marksman retreats when the player breaches minimum range")
	_check(RangedPolicyScript.motion_kind(13.0, 5.5, 13.0, 24.0, true, 2.0, true) == RangedPolicyScript.MOTION_COVER, "cooldown prefers available cover")
	var probes: Array[Vector3] = RangedPolicyScript.cover_probe_directions(Vector3.FORWARD, 99)
	_check(probes.size() == RangedPolicyScript.MAX_COVER_PROBES, "cover directions clamp to the hard eight-probe budget")


func _test_player_source_scoped_cooldowns() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.set("_hostile_damage_grace_remaining", 0.0)
	var first: Dictionary = player.call("take_hostile_damage", 0.01, "zombie", 101)
	var same_attacker: Dictionary = player.call("take_hostile_damage", 0.01, "zombie", 101)
	var second_attacker: Dictionary = player.call("take_hostile_damage", 0.01, "zombie", 202)
	_check(bool(first.get("applied", false)), "first hostile attacker applies damage")
	_check(str(same_attacker.get("reason", "")) == "attacker_cooldown", "same hostile attacker is rate-limited")
	_check(bool(second_attacker.get("applied", false)), "different hostile attacker can apply pressure immediately")
	for attacker_id in range(1000, 1040):
		player.call("take_hostile_damage", 0.01, "abyss_marksman", attacker_id)
	var snapshot: Dictionary = player.call("get_hostile_damage_snapshot")
	_check(int(snapshot.get("active_source_count", 0)) == 32, "hostile attacker cooldown registry remains bounded at thirty-two")
	_check(int(snapshot.get("source_capacity", 0)) == 32, "hostile cooldown diagnostics expose the exact capacity")
	_check(int(snapshot.get("eviction_count", 0)) > 0, "new attackers deterministically evict the shortest remaining cooldown")
	player.call("_process", 4.6)
	snapshot = player.call("get_hostile_damage_snapshot")
	_check(int(snapshot.get("active_source_count", -1)) == 0, "expired hostile cooldown entries are removed deterministically")
	player.queue_free()
	for _frame in 12:
		await process_frame


func _test_real_projectile_and_line_of_sight() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var combat = CombatScript.new()
	var runtime = ProjectileRuntimeScript.new()
	host.add_child(combat)
	host.add_child(runtime)
	await process_frame
	combat.setup(null, null)
	runtime.setup(combat, 24)

	var target := HostileProjectileTarget.new()
	target.collision_layer = 2
	target.collision_mask = 0
	var target_shape := CollisionShape3D.new()
	var target_sphere := SphereShape3D.new()
	target_sphere.radius = 1.15
	target_shape.shape = target_sphere
	target_shape.position = Vector3.UP * 1.0
	target.add_child(target_shape)
	target.global_position = Vector3(0.0, 0.0, -9.0)
	host.add_child(target)

	var factory = FactoryScript.new()
	var raw_marksman: Variant = factory.create("abyss_marksman", Vector3.ZERO, target, null)
	_check(raw_marksman is Node3D, "factory creates the production abyss marksman")
	if raw_marksman is not Node3D:
		host.queue_free()
		await process_frame
		return
	var marksman: Node3D = raw_marksman
	host.add_child(marksman)
	marksman.call("bind_projectile_runtime", runtime)
	marksman.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(str(marksman.call("get_hostile_attack_snapshot").get("attack_kind", "")) == "ranged", "production marksman exposes ranged diagnostics")

	var wall := _create_wall(Vector3(0.0, 1.2, -4.5), Vector3(3.0, 3.0, 0.6))
	host.add_child(wall)
	await physics_frame
	marksman.call("_refresh_line_of_sight", true)
	var blocked_snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
	_check(not bool(blocked_snapshot.get("line_of_sight", true)), "real world collision blocks marksman line of sight")
	_check(not bool(marksman.call("_begin_attack_windup")), "marksman cannot begin windup through a solid wall")
	wall.queue_free()
	await physics_frame
	await physics_frame
	marksman.call("_refresh_line_of_sight", true)
	_check(bool(marksman.call("get_hostile_attack_snapshot").get("line_of_sight", false)), "removing the wall restores real line of sight")
	_check(bool(marksman.call("_begin_attack_windup")), "visible target starts the readable ranged windup")
	marksman.call("_advance_attack_windup", 1.2)
	var spawned := await _wait_until(
		func() -> bool: return int(runtime.get_snapshot().get("spawn_count", 0)) >= 1,
		2000
	)
	_check(spawned, "completed windup spawns one shared hostile projectile")
	var hit := await _wait_until(
		func() -> bool: return target.damage_events >= 1,
		5000
	)
	_check(hit, "shared projectile reaches the real physics target")
	_check(target.damage_events == 1, "one hostile projectile applies exactly one target transaction")
	_check(target.last_source == "abyss_marksman", "hostile projectile preserves its damage source")
	_check(target.last_attacker_id == marksman.get_instance_id(), "hostile projectile preserves exact attacker identity")
	var runtime_snapshot: Dictionary = runtime.get_snapshot()
	_check(int(runtime_snapshot.get("hit_count", 0)) == 1, "shared runtime records the authoritative hostile hit")
	_check(int(runtime_snapshot.get("active_count", -1)) == 0, "hit projectile is removed immediately")
	_check(int(runtime_snapshot.get("spawn_owner_counts", {}).get("hostile", 0)) == 1, "runtime diagnostics classify hostile ownership")

	var invalid: Dictionary = runtime.spawn_projectile({
		"origin": Vector3.ZERO,
		"velocity": Vector3.FORWARD * 200.0,
		"gravity": 0.0,
		"max_distance": 10.0,
		"max_lifetime_seconds": 1.0,
		"collision_mask": 3,
		"shot": {"raw_damage": 1.0},
	})
	_check(str(invalid.get("reason", "")) == "invalid_projectile_request", "runtime last line rejects over-speed projectiles")
	for index in 24:
		var result: Dictionary = runtime.spawn_projectile({
			"origin": Vector3(float(index) * 0.02, 20.0, 0.0),
			"velocity": Vector3.RIGHT,
			"gravity": 0.0,
			"max_distance": 64.0,
			"max_lifetime_seconds": 8.0,
			"collision_mask": 3,
			"owner_kind": "hostile",
			"visual_kind": "orb",
			"shot": {"damage_flow":"hostile", "raw_damage":1.0},
		})
		_check(bool(result.get("success", false)), "hostile projectile budget accepts slot %d" % (index + 1))
	var overflow: Dictionary = runtime.spawn_projectile({
		"origin": Vector3.ZERO,
		"velocity": Vector3.RIGHT,
		"gravity": 0.0,
		"max_distance": 64.0,
		"max_lifetime_seconds": 8.0,
		"collision_mask": 3,
		"owner_kind": "hostile",
		"shot": {"damage_flow":"hostile", "raw_damage":1.0},
	})
	_check(str(overflow.get("reason", "")) == "projectile_capacity", "twenty-fifth hostile projectile is rejected before spawning")
	runtime.clear("test_cleanup")
	_check(int(runtime.get_snapshot().get("active_count", -1)) == 0, "runtime clear removes all hostile projectiles deterministically")

	host.queue_free()
	for _frame in 12:
		await process_frame


func _create_wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.global_position = position
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	wall.add_child(shape_node)
	return wall


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(1, timeout_ms)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await physics_frame
	return bool(predicate.call())


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
