class_name CoverAwareAbyssBruteCreature
extends "res://src/entity/abyss_brute.gd"

var cover_counter_service: Node
var _cover_break_attack_count := 0
var _cover_break_block_count := 0
var _last_cover_break_result: Dictionary = {}


func bind_cover_counter_service(service: Node) -> void:
	cover_counter_service = service


func clear_combat_motion() -> void:
	_last_cover_break_result.clear()
	super.clear_combat_motion()


func get_hostile_attack_snapshot() -> Dictionary:
	var snapshot := super.get_hostile_attack_snapshot()
	snapshot.merge({
		"cover_counter_available": (
			cover_counter_service != null and is_instance_valid(cover_counter_service)
		),
		"cover_break_attack_count": _cover_break_attack_count,
		"cover_break_block_count": _cover_break_block_count,
		"last_cover_break_result": _last_cover_break_result.duplicate(true),
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
		var result: Dictionary = cover_counter_service.call(
			"resolve_brute_attack", self, attack_target
		)
		if bool(result.get("handled", false)):
			_attack_windup_remaining = 0.0
			_attack_timer = maxf(0.1, attack_cooldown_seconds)
			_last_attack_cancel_reason = ""
			_set_attack_state(HostileAttackPolicyScript.STATE_COOLDOWN)
			_cover_break_attack_count += 1
			_cover_break_block_count += int(result.get("changed_blocks", 0))
			_last_cover_break_result = result.duplicate(true)
			return
	super._commit_attack()
