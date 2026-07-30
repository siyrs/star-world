class_name HostileMeleeCreature
extends "res://src/entity/base_creature.gd"


func _commit_attack() -> void:
	var attack_target := target
	_attack_windup_remaining = 0.0
	_attack_timer = maxf(0.1, attack_cooldown_seconds)
	_last_attack_cancel_reason = ""
	_set_attack_state(HostileAttackPolicyScript.STATE_COOLDOWN)
	var applied := false
	if attack_target != null and is_instance_valid(attack_target):
		if attack_target.has_method("take_hostile_damage"):
			var raw_result: Variant = attack_target.call(
				"take_hostile_damage",
				attack_damage,
				attack_source_id,
				get_instance_id()
			)
			if raw_result is Dictionary:
				applied = bool(raw_result.get("applied", raw_result.get("accepted", false)))
			else:
				applied = bool(raw_result)
		elif attack_target.has_method("take_damage"):
			attack_target.call("take_damage", attack_damage, attack_source_id)
			applied = true
		elif attack_target.has_method("get_survival_service"):
			var survival: Variant = attack_target.call("get_survival_service")
			if survival != null and survival.has_method("take_damage"):
				survival.call("take_damage", attack_damage, attack_source_id)
				applied = true
	if applied:
		attack_landed.emit(attack_target, attack_damage)
