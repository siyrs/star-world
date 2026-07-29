class_name AbyssMarksmanCreature
extends "res://src/entity/base_creature.gd"

signal ranged_shot_fired(result: Dictionary)

const RangedTacticsPolicyScript = preload(
	"res://src/entity/hostile_ranged_tactics_policy.gd"
)
const LOS_REFRESH_SECONDS := 0.16
const WORLD_COLLISION_MASK := 1
const MAX_LEAD_SECONDS := 0.35

var danger_weight: float = 1.6
var attack_kind := "ranged"
var delivery_kind := "projectile"
var minimum_attack_range := 5.5
var preferred_attack_range := 13.0
var requires_line_of_sight := true
var projectile_speed := 18.0
var projectile_gravity := 0.8
var projectile_max_distance := 28.0
var projectile_lifetime_seconds := 2.2
var projectile_collision_mask := 3
var projectile_knockback_horizontal := 2.2
var projectile_knockback_vertical := 0.18
var projectile_hit_stun_seconds := 0.12
var projectile_visual_kind := "orb"
var projectile_visual_color := "#D75BFF"
var cover_probe_count := 6
var cover_probe_radius := 3.5
var cover_refresh_seconds := 0.8
var strafe_seconds := 1.2
var projectile_runtime: Node3D

var _line_of_sight := false
var _line_of_sight_refresh_remaining := 0.0
var _cover_refresh_remaining := 0.0
var _cover_destination := Vector3.ZERO
var _cover_destination_active := false
var _strafe_remaining := 0.0
var _strafe_sign := 1.0
var _current_motion_kind := RangedTacticsPolicyScript.MOTION_HOLD
var _cover_probe_ray_count := 0
var _cover_selection_count := 0
var _cover_miss_count := 0
var _ranged_shot_count := 0
var _projectile_rejection_count := 0
var _aim_telegraph_mesh: BoxMesh


func apply_profile(profile: Dictionary) -> void:
	danger_weight = clampf(float(profile.get("danger_weight", 1.6)), 0.5, 6.0)
	super.apply_profile(profile)
	var raw_attack: Variant = profile.get("hostile_attack", {})
	if raw_attack is not Dictionary:
		return
	var attack: Dictionary = raw_attack
	attack_kind = str(attack.get("attack_kind", attack_kind))
	delivery_kind = str(attack.get("delivery_kind", delivery_kind))
	minimum_attack_range = maxf(0.0, float(attack.get("minimum_range", minimum_attack_range)))
	preferred_attack_range = clampf(
		float(attack.get("preferred_range", preferred_attack_range)),
		minimum_attack_range,
		attack_range
	)
	requires_line_of_sight = bool(
		attack.get("requires_line_of_sight", requires_line_of_sight)
	)
	projectile_speed = clampf(float(attack.get("projectile_speed", projectile_speed)), 0.1, 64.0)
	projectile_gravity = clampf(float(attack.get("projectile_gravity", projectile_gravity)), 0.0, 32.0)
	projectile_max_distance = clampf(
		float(attack.get("projectile_max_distance", projectile_max_distance)),
		attack_range,
		64.0
	)
	projectile_lifetime_seconds = clampf(
		float(attack.get("projectile_lifetime_seconds", projectile_lifetime_seconds)),
		0.2,
		8.0
	)
	projectile_collision_mask = maxi(1, int(attack.get("projectile_collision_mask", projectile_collision_mask)))
	projectile_knockback_horizontal = clampf(
		float(attack.get("projectile_knockback_horizontal", projectile_knockback_horizontal)),
		0.0,
		12.0
	)
	projectile_knockback_vertical = clampf(
		float(attack.get("projectile_knockback_vertical", projectile_knockback_vertical)),
		0.0,
		4.0
	)
	projectile_hit_stun_seconds = clampf(
		float(attack.get("projectile_hit_stun_seconds", projectile_hit_stun_seconds)),
		0.0,
		2.0
	)
	projectile_visual_kind = str(attack.get("projectile_visual_kind", projectile_visual_kind))
	projectile_visual_color = str(attack.get("projectile_visual_color", projectile_visual_color))
	cover_probe_count = clampi(int(attack.get("cover_probe_count", cover_probe_count)), 0, 8)
	cover_probe_radius = clampf(float(attack.get("cover_probe_radius", cover_probe_radius)), 0.5, 6.0)
	cover_refresh_seconds = clampf(
		float(attack.get("cover_refresh_seconds", cover_refresh_seconds)), 0.25, 3.0
	)
	strafe_seconds = clampf(float(attack.get("strafe_seconds", strafe_seconds)), 0.2, 3.0)


func _ready() -> void:
	species_id = "abyss_marksman"
	display_name = "深渊射手"
	hostile = true
	collision_size = Vector3(0.78, 1.72, 0.72)
	if not _configured:
		apply_profile({
			"name":"深渊射手",
			"max_health":16,
			"speed":2.35,
			"damage":3,
			"danger_weight":1.6,
			"drops":{"gunpowder":[0,2], "abyss_cinder":[0,1]},
			"hostile_attack":{
				"species_id":"abyss_marksman", "source_id":"abyss_marksman",
				"attack_kind":"ranged", "delivery_kind":"projectile",
				"detection_range":30.0, "minimum_range":5.5,
				"preferred_range":13.0, "attack_range":24.0,
				"windup_seconds":1.1, "cooldown_seconds":4.8,
				"cancel_range_multiplier":1.12, "cancel_recovery_seconds":0.75,
				"target_leash_multiplier":1.35, "telegraph_radius_multiplier":1.0,
				"requires_line_of_sight":true, "projectile_speed":18.0,
				"projectile_gravity":0.8, "projectile_max_distance":28.0,
				"projectile_lifetime_seconds":2.2, "projectile_collision_mask":3,
				"projectile_knockback_horizontal":2.2,
				"projectile_knockback_vertical":0.18,
				"projectile_hit_stun_seconds":0.12,
				"projectile_visual_kind":"orb", "projectile_visual_color":"#D75BFF",
				"cover_probe_count":6, "cover_probe_radius":3.5,
				"cover_refresh_seconds":0.8, "strafe_seconds":1.2,
			}
		})
	super._ready()
	add_to_group("hostile")
	add_to_group("ranged_hostile")


func bind_projectile_runtime(runtime: Node3D) -> void:
	projectile_runtime = runtime


func clear_combat_motion() -> void:
	_cover_destination = Vector3.ZERO
	_cover_destination_active = false
	_current_motion_kind = RangedTacticsPolicyScript.MOTION_HOLD
	super.clear_combat_motion()


func get_hostile_attack_snapshot() -> Dictionary:
	var snapshot := super.get_hostile_attack_snapshot()
	snapshot.merge({
		"attack_kind": attack_kind,
		"delivery_kind": delivery_kind,
		"minimum_range": minimum_attack_range,
		"preferred_range": preferred_attack_range,
		"requires_line_of_sight": requires_line_of_sight,
		"line_of_sight": _line_of_sight,
		"motion_kind": _current_motion_kind,
		"cover_destination_active": _cover_destination_active,
		"cover_destination": [
			_cover_destination.x, _cover_destination.y, _cover_destination.z
		],
		"cover_probe_budget": cover_probe_count,
		"cover_probe_ray_count": _cover_probe_ray_count,
		"cover_selection_count": _cover_selection_count,
		"cover_miss_count": _cover_miss_count,
		"ranged_shot_count": _ranged_shot_count,
		"projectile_rejection_count": _projectile_rejection_count,
		"projectile_runtime_available": (
			projectile_runtime != null and is_instance_valid(projectile_runtime)
		),
	}, true)
	return snapshot


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	_line_of_sight_refresh_remaining = maxf(
		0.0, _line_of_sight_refresh_remaining - safe_delta
	)
	_cover_refresh_remaining = maxf(0.0, _cover_refresh_remaining - safe_delta)
	_strafe_remaining = maxf(0.0, _strafe_remaining - safe_delta)
	if _strafe_remaining <= 0.0:
		_strafe_remaining = strafe_seconds
		_strafe_sign *= -1.0
	super._physics_process(safe_delta)


func _choose_direction() -> Vector3:
	_acquire_target()
	if not _is_attack_target_valid():
		_current_motion_kind = RangedTacticsPolicyScript.MOTION_HOLD
		return _wander_motion()
	_refresh_line_of_sight(false)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if _begin_attack_windup():
		_current_motion_kind = RangedTacticsPolicyScript.MOTION_HOLD
		return Vector3.ZERO
	if _cover_destination_active:
		var cover_offset := _cover_destination - global_position
		cover_offset.y = 0.0
		if cover_offset.length() <= 0.45:
			_cover_destination_active = false
		else:
			_current_motion_kind = RangedTacticsPolicyScript.MOTION_COVER
			return cover_offset.normalized()
	if _attack_timer > 0.0 and _line_of_sight and _cover_refresh_remaining <= 0.0:
		_cover_refresh_remaining = cover_refresh_seconds
		_select_cover_destination()
		if _cover_destination_active:
			_current_motion_kind = RangedTacticsPolicyScript.MOTION_COVER
			return (_cover_destination - global_position).normalized()
	_current_motion_kind = RangedTacticsPolicyScript.motion_kind(
		distance,
		minimum_attack_range,
		preferred_attack_range,
		attack_range,
		_line_of_sight,
		_attack_timer,
		_cover_destination_active
	)
	match _current_motion_kind:
		RangedTacticsPolicyScript.MOTION_RETREAT:
			return (-offset.normalized() + _strafe_motion(offset) * 0.45).normalized()
		RangedTacticsPolicyScript.MOTION_APPROACH:
			return (offset.normalized() + _strafe_motion(offset) * 0.18).normalized()
		RangedTacticsPolicyScript.MOTION_STRAFE:
			return _strafe_motion(offset)
		_:
			return Vector3.ZERO


func _begin_attack_windup() -> bool:
	if not _is_attack_target_valid():
		return false
	_refresh_line_of_sight(false)
	var runtime_available := (
		projectile_runtime != null
		and is_instance_valid(projectile_runtime)
		and projectile_runtime.has_method("can_spawn")
		and bool(projectile_runtime.call("can_spawn"))
	)
	if not RangedTacticsPolicyScript.can_begin(
		_target_horizontal_distance(),
		minimum_attack_range,
		attack_range,
		_line_of_sight,
		requires_line_of_sight,
		_attack_timer,
		_attack_windup_remaining,
		runtime_available
	):
		return false
	_attack_windup_remaining = maxf(0.05, attack_windup_seconds)
	_last_attack_cancel_reason = ""
	_cover_destination_active = false
	_set_attack_state(HostileAttackPolicyScript.STATE_WINDUP)
	_update_attack_telegraph_visual()
	attack_windup_started.emit(target, get_hostile_attack_snapshot())
	return true


func _advance_attack_windup(delta: float) -> void:
	_refresh_line_of_sight(false)
	var target_valid := _is_attack_target_valid()
	var distance := _target_horizontal_distance() if target_valid else INF
	var cancel_reason := RangedTacticsPolicyScript.cancellation_reason(
		target_valid,
		distance,
		minimum_attack_range,
		attack_range,
		attack_cancel_range_multiplier,
		_line_of_sight,
		requires_line_of_sight,
		_hit_stun_remaining
	)
	if not cancel_reason.is_empty():
		_cancel_attack_windup(cancel_reason)
		return
	_face_attack_target(delta)
	_attack_windup_remaining = maxf(0.0, _attack_windup_remaining - maxf(0.0, delta))
	if _attack_windup_remaining <= 0.0:
		_commit_attack()


func _commit_attack() -> void:
	var attack_target := target
	_attack_windup_remaining = 0.0
	_attack_timer = maxf(0.1, attack_cooldown_seconds)
	_last_attack_cancel_reason = ""
	_set_attack_state(HostileAttackPolicyScript.STATE_COOLDOWN)
	if (
		attack_target == null
		or not is_instance_valid(attack_target)
		or projectile_runtime == null
		or not is_instance_valid(projectile_runtime)
		or not projectile_runtime.has_method("spawn_projectile")
	):
		_projectile_rejection_count += 1
		_last_attack_cancel_reason = "projectile_runtime_unavailable"
		return
	var origin := global_position + Vector3.UP * 1.48
	var target_position := attack_target.global_position + Vector3.UP * 1.05
	var target_velocity := Vector3.ZERO
	if attack_target is CharacterBody3D:
		target_velocity = (attack_target as CharacterBody3D).velocity
	var direction := RangedTacticsPolicyScript.lead_direction(
		origin,
		target_position,
		target_velocity,
		projectile_speed,
		MAX_LEAD_SECONDS
	)
	var spawn_result: Dictionary = projectile_runtime.call(
		"spawn_projectile",
		{
			"origin": origin + direction * 0.38,
			"velocity": direction * projectile_speed,
			"gravity": projectile_gravity,
			"max_distance": projectile_max_distance,
			"max_lifetime_seconds": projectile_lifetime_seconds,
			"collision_mask": projectile_collision_mask,
			"attacker": self,
			"owner_kind": "hostile",
			"visual_kind": projectile_visual_kind,
			"visual_color": projectile_visual_color,
			"visual_width": 0.18,
			"visual_length": 0.24,
			"shot": {
				"attack_kind": "hostile_ranged",
				"damage_flow": "hostile",
				"damage_source": attack_source_id,
				"attacker_id": get_instance_id(),
				"raw_damage": attack_damage,
				"shot_direction": [direction.x, direction.y, direction.z],
				"knockback_horizontal": projectile_knockback_horizontal,
				"knockback_vertical": projectile_knockback_vertical,
				"hit_stun_seconds": projectile_hit_stun_seconds,
			}
		}
	)
	if not bool(spawn_result.get("success", false)):
		_projectile_rejection_count += 1
		_last_attack_cancel_reason = str(
			spawn_result.get("reason", "projectile_spawn_failed")
		)
		_attack_timer = maxf(_attack_timer, attack_cancel_recovery_seconds)
		return
	_ranged_shot_count += 1
	_cover_refresh_remaining = 0.0
	var result := spawn_result.duplicate(true)
	result.merge({
		"species_id": species_id,
		"source_id": attack_source_id,
		"attack_kind": "hostile_ranged",
		"damage": attack_damage,
	}, true)
	ranged_shot_fired.emit(result)


func _create_attack_telegraph() -> void:
	_attack_telegraph = MeshInstance3D.new()
	_attack_telegraph.name = "AimTelegraph"
	_aim_telegraph_mesh = BoxMesh.new()
	_aim_telegraph_mesh.size = Vector3(0.045, 0.045, 1.0)
	_attack_telegraph.mesh = _aim_telegraph_mesh
	_attack_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_telegraph.extra_cull_margin = 32.0
	_attack_telegraph_material = StandardMaterial3D.new()
	_attack_telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_attack_telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_telegraph_material.albedo_color = Color(0.85, 0.24, 1.0, 0.38)
	_attack_telegraph_material.emission_enabled = true
	_attack_telegraph_material.emission = Color(0.72, 0.12, 1.0)
	_attack_telegraph_material.emission_energy_multiplier = 2.0
	_attack_telegraph.material_override = _attack_telegraph_material
	_attack_telegraph.visible = false
	add_child(_attack_telegraph)


func _update_attack_telegraph_visual() -> void:
	if _attack_telegraph == null or not is_instance_valid(_attack_telegraph):
		return
	var visible := (
		_attack_state == HostileAttackPolicyScript.STATE_WINDUP
		and _is_attack_target_valid()
	)
	_attack_telegraph.visible = visible
	if not visible:
		return
	var start := global_position + Vector3.UP * 1.48
	var finish := target.global_position + Vector3.UP * 1.05
	var distance := maxf(0.1, start.distance_to(finish))
	var progress := HostileAttackPolicyScript.progress_ratio(
		_attack_windup_remaining, attack_windup_seconds
	)
	var width := 0.035 + progress * 0.035
	_aim_telegraph_mesh.size = Vector3(width, width, distance)
	_attack_telegraph.global_position = start.lerp(finish, 0.5)
	_attack_telegraph.look_at(finish, Vector3.UP, true)
	if _attack_telegraph_material != null:
		_attack_telegraph_material.albedo_color = Color(
			0.85, 0.24, 1.0, lerpf(0.22, 0.62, progress)
		)


func _refresh_line_of_sight(force: bool) -> void:
	if not force and _line_of_sight_refresh_remaining > 0.0:
		return
	_line_of_sight_refresh_remaining = LOS_REFRESH_SECONDS
	_line_of_sight = _compute_line_of_sight()


func _compute_line_of_sight() -> bool:
	if not _is_attack_target_valid() or not is_inside_tree():
		return false
	var world_3d := get_world_3d()
	if world_3d == null:
		return false
	var start := global_position + Vector3.UP * 1.48
	var finish := target.global_position + Vector3.UP * 1.05
	var query := PhysicsRayQueryParameters3D.create(
		start, finish, projectile_collision_mask, [get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var impact: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if impact.is_empty():
		return true
	var collider: Variant = impact.get("collider")
	return (
		collider == target
		or (collider is Node and target.is_ancestor_of(collider as Node))
	)


func _select_cover_destination() -> void:
	_cover_destination_active = false
	if cover_probe_count <= 0 or not _is_attack_target_valid() or not is_inside_tree():
		return
	var world_3d := get_world_3d()
	if world_3d == null:
		return
	var to_target := target.global_position - global_position
	var directions := RangedTacticsPolicyScript.cover_probe_directions(
		to_target, cover_probe_count
	)
	var target_eye := target.global_position + Vector3.UP * 1.05
	for direction: Vector3 in directions:
		var candidate := global_position + direction * cover_probe_radius
		var ground_query := PhysicsRayQueryParameters3D.create(
			candidate + Vector3.UP * 2.0,
			candidate + Vector3.DOWN * 3.0,
			WORLD_COLLISION_MASK,
			[get_rid()]
		)
		var ground_hit: Dictionary = world_3d.direct_space_state.intersect_ray(ground_query)
		_cover_probe_ray_count += 1
		if ground_hit.is_empty():
			continue
		candidate.y = float((ground_hit.get("position", candidate) as Vector3).y) + 0.05
		var path_query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.8,
			candidate + Vector3.UP * 0.8,
			WORLD_COLLISION_MASK,
			[get_rid()]
		)
		var path_hit: Dictionary = world_3d.direct_space_state.intersect_ray(path_query)
		_cover_probe_ray_count += 1
		if not path_hit.is_empty():
			continue
		var cover_query := PhysicsRayQueryParameters3D.create(
			target_eye,
			candidate + Vector3.UP * 1.05,
			WORLD_COLLISION_MASK,
			[get_rid()]
		)
		var cover_hit: Dictionary = world_3d.direct_space_state.intersect_ray(cover_query)
		_cover_probe_ray_count += 1
		if cover_hit.is_empty():
			continue
		_cover_destination = candidate
		_cover_destination_active = true
		_cover_selection_count += 1
		return
	_cover_miss_count += 1


func _strafe_motion(to_target: Vector3) -> Vector3:
	return RangedTacticsPolicyScript.strafe_direction(to_target, _strafe_sign)


func _wander_motion() -> Vector3:
	if _decision_timer <= 0.0:
		_decision_timer = _rng.randf_range(1.5, 4.5)
		if _rng.randf() < 0.32:
			_wander_direction = Vector3.ZERO
		else:
			var angle := _rng.randf_range(0.0, TAU)
			_wander_direction = Vector3(sin(angle), 0.0, cos(angle))
	return _wander_direction


func _build_model() -> void:
	_make_box("Cloak", Vector3(0.72, 0.9, 0.5), Vector3(0.0, 0.92, 0.08), Color("#31263E"))
	_make_box("Torso", Vector3(0.58, 0.82, 0.42), Vector3(0.0, 1.08, 0.0), Color("#4A3659"))
	_make_box("Head", Vector3(0.5, 0.48, 0.46), Vector3(0.0, 1.72, 0.0), Color("#69506F"))
	_make_box("Hood", Vector3(0.62, 0.34, 0.55), Vector3(0.0, 1.92, 0.03), Color("#271D35"))
	_make_eyes(0.24, 1.76, 0.12, 0.07, Color("#E05CFF"))
	_make_box("LeftArm", Vector3(0.18, 0.72, 0.18), Vector3(-0.39, 1.04, 0.02), Color("#4A3659"))
	_make_box("RightArm", Vector3(0.18, 0.72, 0.18), Vector3(0.39, 1.04, 0.02), Color("#4A3659"))
	_make_box("LeftLeg", Vector3(0.22, 0.72, 0.24), Vector3(-0.18, 0.36, 0.0), Color("#251F31"))
	_make_box("RightLeg", Vector3(0.22, 0.72, 0.24), Vector3(0.18, 0.36, 0.0), Color("#251F31"))
	_make_box("FocusStaff", Vector3(0.12, 1.0, 0.12), Vector3(0.48, 1.05, 0.25), Color("#7C5B48"))
	_make_box("FocusCore", Vector3(0.24, 0.24, 0.24), Vector3(0.48, 1.62, 0.25), Color("#D75BFF"))
