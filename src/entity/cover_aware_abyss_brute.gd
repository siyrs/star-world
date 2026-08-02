class_name CoverAwareAbyssBruteCreature
extends "res://src/entity/abyss_brute.gd"

var cover_counter_service: Node
var _cover_break_attack_count := 0
var _cover_break_block_count := 0
var _cover_blocked_attack_count := 0
var _last_cover_result: Dictionary = {}


func bind_cover_counter_service(service: Node) -> void:
	cover_counter_service = service


func clear_combat_motion() -> void:
	_last_cover_result.clear()
	super.clear_combat_motion()


func get_hostile_attack_snapshot() -> Dictionary:
	var snapshot := super.get_hostile_attack_snapshot()
	snapshot.merge({
		"cover_counter_available": (
			cover_counter_service != null and is_instance_valid(cover_counter_service)
		),
		"cover_break_attack_count": _cover_break_attack_count,
		"cover_break_block_count": _cover_break_block_count,
		"cover_blocked_attack_count": _cover_blocked_attack_count,
		"last_cover_result": _last_cover_result.duplicate(true),
	}, true)
	return snapshot


func _commit_attack() -> void:
	var attack_target := target
	if (
		cover_counter_service != null
		and is_instance_valid(cover_counter_service)
		and cover_counter_service.has_method("resolve_brute_attack")
		and attack_target != null
		and is_instance_valid(attack_target)
	):
		var raw_result: Variant = cover_counter_service.call(
			"resolve_brute_attack", self, attack_target
		)
		var result: Dictionary = raw_result if raw_result is Dictionary else {}
		if bool(result.get("handled", false)) or bool(result.get("blocks_damage", false)):
			# Breaking cover and being stopped by cover both consume the committed attack.
			# This is critical for mutation failures and exhausted budgets: the brute may
			# never fall through to the base melee implementation while a wall remains.
			_attack_windup_remaining = 0.0
			_attack_timer = maxf(0.1, attack_cooldown_seconds)
			_last_attack_cancel_reason = ""
			_set_attack_state(HostileAttackPolicyScript.STATE_COOLDOWN)
			if bool(result.get("handled", false)):
				_cover_break_attack_count += 1
				_cover_break_block_count += int(result.get("changed_blocks", 0))
			else:
				_cover_blocked_attack_count += 1
			_last_cover_result = result.duplicate(true)
			return
	super._commit_attack()
