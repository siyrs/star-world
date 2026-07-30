class_name DeferredEncounterRewardService
extends "res://src/entity/encounter_reward_service.gd"

var _deferred_reward_ids: Dictionary = {}


func _on_member_died(
	_species_id: String,
	_drops: Dictionary,
	_world_position: Vector3,
	encounter_id: String,
	member_id: int
) -> void:
	if not _ledgers.has(encounter_id):
		return
	var ledger: Dictionary = _ledgers.get(encounter_id, {})
	var defeated: Dictionary = ledger.get("defeated_ids", {})
	defeated[str(member_id)] = true
	ledger["defeated_ids"] = defeated
	_ledgers[encounter_id] = ledger
	if defeated.size() >= (ledger.get("member_ids", []) as Array).size():
		_schedule_reward_flush(encounter_id)
	_emit_economy_changed()


func _attempt_reward(encounter_id: String) -> Dictionary:
	if _pending_rewards.has(encounter_id):
		return {
			"success":false,
			"reason":str(_pending_rewards.get(encounter_id, {}).get("reason", "pending")),
			"pending":true,
		}
	return super._attempt_reward(encounter_id)


func clear(reason: String = "clear") -> void:
	_deferred_reward_ids.clear()
	super.clear(reason)


func _schedule_reward_flush(encounter_id: String) -> void:
	if encounter_id.is_empty() or _deferred_reward_ids.has(encounter_id):
		return
	_deferred_reward_ids[encounter_id] = true
	call_deferred("_flush_deferred_reward", encounter_id)


func _flush_deferred_reward(encounter_id: String) -> void:
	_deferred_reward_ids.erase(encounter_id)
	if not _ledgers.has(encounter_id) or _claimed_ids.has(encounter_id):
		return
	_attempt_reward(encounter_id)
