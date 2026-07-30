class_name EncounterRewardService
extends Node

signal reward_granted(result: Dictionary)
signal reward_pending(result: Dictionary)
signal reward_rejected(result: Dictionary)
signal economy_changed(snapshot: Dictionary)

const RegistryScript = preload("res://src/entity/encounter_reward_registry.gd")
const OverlayScript = preload("res://src/ui/encounter_reward_overlay.gd")
const BINDING_REFRESH_SECONDS := 0.25
const MAX_ACTIVE_LEDGERS := 2
const MAX_PENDING_REWARDS := 8
const MAX_CLAIM_HISTORY := 256
const AMMO_ITEM_IDS: Array[String] = ["arrow", "light_round", "shotgun_shell"]

@export var auto_bind_parent := true

var director: Node
var inventory: Node
var ranged_combat_service: Node
var creature_spawner: Node

var _registry = RegistryScript.new()
var _parent_hub: Node
var _overlay: Control
var _bound_world_id := ""
var _explicit_setup := false
var _binding_refresh_remaining := 0.0
var _retry_in_progress := false
var _retry_scheduled := false

var _ledgers: Dictionary = {}
var _pending_rewards: Dictionary = {}
var _claimed_ids: Dictionary = {}
var _claim_order: Array[String] = []
var _deferred_reward_ids: Dictionary = {}
var _encounter_start_count := 0
var _encounter_completion_count := 0
var _reward_grant_count := 0
var _reward_pending_count := 0
var _reward_rejection_count := 0
var _duplicate_completion_count := 0
var _abandoned_encounter_count := 0
var _unattributed_shot_count := 0
var _ammo_spent_total: Dictionary = {}
var _rewards_granted_total: Dictionary = {}
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	if auto_bind_parent:
		call_deferred("_refresh_parent_bindings", 0.0, true)


func setup(
	p_director: Node,
	p_inventory: Node,
	p_ranged_combat_service: Node,
	p_creature_spawner: Node
) -> void:
	_explicit_setup = true
	_bind_services(p_director, p_inventory, p_ranged_combat_service, p_creature_spawner)


func bind_parent_hub(p_parent_hub: Node) -> void:
	_parent_hub = p_parent_hub
	_explicit_setup = false
	_refresh_parent_bindings(0.0, true)


func clear(reason: String = "clear") -> void:
	var pending_forfeit: int = _pending_rewards.size()
	_ledgers.clear()
	_pending_rewards.clear()
	_claimed_ids.clear()
	_claim_order.clear()
	_deferred_reward_ids.clear()
	_encounter_start_count = 0
	_encounter_completion_count = 0
	_reward_grant_count = 0
	_reward_pending_count = 0
	_reward_rejection_count = 0
	_duplicate_completion_count = 0
	_abandoned_encounter_count = pending_forfeit
	_unattributed_shot_count = 0
	_ammo_spent_total.clear()
	_rewards_granted_total.clear()
	_last_result = {
		"status":"cleared",
		"reason":reason,
		"pending_forfeit_count":pending_forfeit,
	}
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.call("clear")
	_emit_economy_changed()


func get_snapshot() -> Dictionary:
	var ledgers: Array[Dictionary] = []
	var ledger_ids: Array = _ledgers.keys()
	ledger_ids.sort()
	for raw_id: Variant in ledger_ids:
		ledgers.append(_public_ledger(_ledgers.get(raw_id, {})))
	var pending: Array[Dictionary] = []
	var pending_ids: Array = _pending_rewards.keys()
	pending_ids.sort()
	for raw_id: Variant in pending_ids:
		var record: Dictionary = _pending_rewards.get(raw_id, {})
		pending.append({
			"encounter_id":str(raw_id),
			"profile_id":str(record.get("profile_id", "")),
			"rewards":record.get("rewards", {}).duplicate(true),
			"shot_count":int(record.get("shot_count", 0)),
			"reason":str(record.get("reason", "inventory_full")),
		})
	return {
		"world_id":_bound_world_id,
		"auto_bound":_parent_hub != null,
		"services_ready":_services_ready(),
		"active_ledger_count":ledgers.size(),
		"maximum_active_ledgers":MAX_ACTIVE_LEDGERS,
		"pending_reward_count":pending.size(),
		"maximum_pending_rewards":MAX_PENDING_REWARDS,
		"claim_history_count":_claim_order.size(),
		"maximum_claim_history":MAX_CLAIM_HISTORY,
		"deferred_reward_count":_deferred_reward_ids.size(),
		"encounter_start_count":_encounter_start_count,
		"encounter_completion_count":_encounter_completion_count,
		"reward_grant_count":_reward_grant_count,
		"reward_pending_count":_reward_pending_count,
		"reward_rejection_count":_reward_rejection_count,
		"duplicate_completion_count":_duplicate_completion_count,
		"abandoned_encounter_count":_abandoned_encounter_count,
		"unattributed_shot_count":_unattributed_shot_count,
		"ammo_spent_total":_ammo_spent_total.duplicate(true),
		"rewards_granted_total":_rewards_granted_total.duplicate(true),
		"net_ammo_total":_net_ammo(_rewards_granted_total, _ammo_spent_total),
		"ledgers":ledgers,
		"pending_rewards":pending,
		"last_result":_last_result.duplicate(true),
		"registry_schema_version":_registry.schema_version,
		"registry_profile_count":_registry.get_profile_ids().size(),
		"overlay_available":_overlay != null,
	}


func retry_pending_rewards() -> int:
	if _retry_in_progress or inventory == null or not inventory.has_method("transact_items"):
		return 0
	_retry_in_progress = true
	var granted := 0
	var ids: Array = _pending_rewards.keys()
	ids.sort()
	for raw_id: Variant in ids:
		var encounter_id := str(raw_id)
		var pending: Dictionary = _pending_rewards.get(encounter_id, {})
		var transaction: Dictionary = inventory.call(
			"transact_items", {}, _reward_additions(pending.get("rewards", {}))
		)
		if not bool(transaction.get("success", false)):
			continue
		_pending_rewards.erase(encounter_id)
		_commit_grant(encounter_id, pending, transaction, true)
		granted += 1
	_retry_in_progress = false
	_emit_economy_changed()
	return granted


func _process(delta: float) -> void:
	if auto_bind_parent and not _explicit_setup:
		_refresh_parent_bindings(maxf(0.0, delta), false)


func _refresh_parent_bindings(delta: float = 0.0, force: bool = false) -> void:
	_binding_refresh_remaining = maxf(
		0.0, _binding_refresh_remaining - maxf(0.0, delta)
	)
	if not force and _binding_refresh_remaining > 0.0:
		return
	_binding_refresh_remaining = BINDING_REFRESH_SECONDS
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		_parent_hub = get_parent()
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		return
	var next_director: Node = _parent_hub.get_node_or_null("HostileEncounterDirector")
	var next_inventory: Node = _parent_hub.get("inventory") as Node
	var next_ranged: Node = _parent_hub.get("ranged_combat_service") as Node
	var next_spawner: Node = _parent_hub.get("creature_spawner") as Node
	_bind_services(next_director, next_inventory, next_ranged, next_spawner)
	var next_world_id := str(_parent_hub.get("current_world_id"))
	if next_world_id != _bound_world_id:
		if not _bound_world_id.is_empty() or not _ledgers.is_empty() or not _pending_rewards.is_empty():
			clear("world_changed")
		_bound_world_id = next_world_id
	_ensure_overlay()


func _bind_services(
	p_director: Node,
	p_inventory: Node,
	p_ranged: Node,
	p_spawner: Node
) -> void:
	if director != p_director:
		_disconnect_director()
		director = p_director
		_connect_director()
	if ranged_combat_service != p_ranged:
		_disconnect_ranged()
		ranged_combat_service = p_ranged
		_connect_ranged()
	if inventory != p_inventory:
		_disconnect_inventory()
		inventory = p_inventory
		_connect_inventory()
	creature_spawner = p_spawner


func _connect_director() -> void:
	if director == null or not is_instance_valid(director):
		return
	var started := Callable(self, "_on_encounter_started")
	if director.has_signal("encounter_started") and not director.is_connected("encounter_started", started):
		director.connect("encounter_started", started)
	var completed := Callable(self, "_on_encounter_completed")
	if director.has_signal("encounter_completed") and not director.is_connected("encounter_completed", completed):
		director.connect("encounter_completed", completed)


func _disconnect_director() -> void:
	if director == null or not is_instance_valid(director):
		return
	var started := Callable(self, "_on_encounter_started")
	if director.has_signal("encounter_started") and director.is_connected("encounter_started", started):
		director.disconnect("encounter_started", started)
	var completed := Callable(self, "_on_encounter_completed")
	if director.has_signal("encounter_completed") and director.is_connected("encounter_completed", completed):
		director.disconnect("encounter_completed", completed)


func _connect_ranged() -> void:
	if ranged_combat_service == null or not is_instance_valid(ranged_combat_service):
		return
	var callback := Callable(self, "_on_shot_fired")
	if ranged_combat_service.has_signal("shot_fired") and not ranged_combat_service.is_connected("shot_fired", callback):
		ranged_combat_service.connect("shot_fired", callback)


func _disconnect_ranged() -> void:
	if ranged_combat_service == null or not is_instance_valid(ranged_combat_service):
		return
	var callback := Callable(self, "_on_shot_fired")
	if ranged_combat_service.has_signal("shot_fired") and ranged_combat_service.is_connected("shot_fired", callback):
		ranged_combat_service.disconnect("shot_fired", callback)


func _connect_inventory() -> void:
	if inventory == null or not is_instance_valid(inventory):
		return
	var callback := Callable(self, "_on_inventory_changed")
	if inventory.has_signal("inventory_changed") and not inventory.is_connected("inventory_changed", callback):
		inventory.connect("inventory_changed", callback)


func _disconnect_inventory() -> void:
	if inventory == null or not is_instance_valid(inventory):
		return
	var callback := Callable(self, "_on_inventory_changed")
	if inventory.has_signal("inventory_changed") and inventory.is_connected("inventory_changed", callback):
		inventory.disconnect("inventory_changed", callback)


func _on_encounter_started(snapshot: Dictionary) -> void:
	var encounter_id := str(snapshot.get("id", "")).strip_edges()
	if encounter_id.is_empty():
		_reject("invalid_encounter_id", snapshot)
		return
	if _ledgers.has(encounter_id) or _pending_rewards.has(encounter_id) or _claimed_ids.has(encounter_id):
		_reject("duplicate_encounter_start", snapshot)
		return
	if _ledgers.size() >= MAX_ACTIVE_LEDGERS:
		_reject("ledger_capacity", snapshot)
		return
	var member_ids: Array[int] = _normalized_member_ids(
		snapshot.get("living_member_ids", [])
	)
	if member_ids.is_empty():
		_reject("encounter_has_no_members", snapshot)
		return
	var ledger := {
		"encounter_id":encounter_id,
		"profile_id":str(snapshot.get("profile_id", "")),
		"display_name":str(snapshot.get("display_name", "遭遇")),
		"member_ids":member_ids,
		"defeated_ids":{},
		"ammo_spent":{},
		"shot_count":0,
		"hit_shot_count":0,
		"started_at_msec":int(snapshot.get("started_at_msec", Time.get_ticks_msec())),
		"completion_seen":false,
		"status":"active",
	}
	_ledgers[encounter_id] = ledger
	_encounter_start_count += 1
	_connect_member_death_signals(encounter_id)
	_emit_economy_changed()


func _connect_member_death_signals(encounter_id: String) -> void:
	if creature_spawner == null or not is_instance_valid(creature_spawner):
		return
	var ledger: Dictionary = _ledgers.get(encounter_id, {})
	var member_ids: Array[int] = ledger.get("member_ids", [])
	for child: Node in creature_spawner.get_children():
		if child is not Node3D:
			continue
		var member_id := int(child.get_instance_id())
		if member_id not in member_ids or not child.has_signal("died"):
			continue
		var callback := Callable(self, "_on_member_died").bind(encounter_id, member_id)
		if not child.is_connected("died", callback):
			child.connect("died", callback)


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


func _on_shot_fired(result: Dictionary) -> void:
	if not bool(result.get("accepted", false)) or str(result.get("status", "")) != "fired":
		return
	var encounter_id := _resolve_shot_encounter(result)
	if encounter_id.is_empty():
		_unattributed_shot_count += 1
		_emit_economy_changed()
		return
	var ledger: Dictionary = _ledgers.get(encounter_id, {})
	ledger["shot_count"] = int(ledger.get("shot_count", 0)) + 1
	var ammo_item_id := str(result.get("ammo_item_id", "")).strip_edges()
	if not ammo_item_id.is_empty():
		var ammo_spent: Dictionary = ledger.get("ammo_spent", {})
		ammo_spent[ammo_item_id] = int(ammo_spent.get(ammo_item_id, 0)) + 1
		ledger["ammo_spent"] = ammo_spent
		_add_total(_ammo_spent_total, ammo_item_id, 1)
	if _shot_hit_any_target(result):
		ledger["hit_shot_count"] = int(ledger.get("hit_shot_count", 0)) + 1
	_ledgers[encounter_id] = ledger
	_emit_economy_changed()


func _resolve_shot_encounter(result: Dictionary) -> String:
	var target_ids: Array[int] = _accepted_target_ids(result)
	var matches: Array[String] = []
	for raw_id: Variant in _ledgers.keys():
		var encounter_id := str(raw_id)
		var ledger: Dictionary = _ledgers.get(encounter_id, {})
		var member_ids: Array[int] = ledger.get("member_ids", [])
		for target_id: int in target_ids:
			if target_id in member_ids:
				matches.append(encounter_id)
				break
	if matches.size() == 1:
		return matches[0]
	if target_ids.is_empty() and _ledgers.size() == 1:
		return str(_ledgers.keys()[0])
	return ""


func _on_encounter_completed(snapshot: Dictionary) -> void:
	var encounter_id := str(snapshot.get("id", "")).strip_edges()
	if encounter_id.is_empty():
		return
	_encounter_completion_count += 1
	if _claimed_ids.has(encounter_id):
		if bool(_claimed_ids.get(encounter_id, false)):
			_duplicate_completion_count += 1
			_reject("duplicate_completion", snapshot)
		else:
			_claimed_ids[encounter_id] = true
		return
	if _pending_rewards.has(encounter_id):
		var pending: Dictionary = _pending_rewards.get(encounter_id, {})
		if bool(pending.get("completion_seen", false)):
			_duplicate_completion_count += 1
			_reject("duplicate_completion", snapshot)
		else:
			pending["completion_seen"] = true
			_pending_rewards[encounter_id] = pending
		return
	if not _ledgers.has(encounter_id):
		return
	var ledger: Dictionary = _ledgers.get(encounter_id, {})
	if bool(ledger.get("completion_seen", false)):
		_duplicate_completion_count += 1
		_reject("duplicate_completion", snapshot)
		return
	ledger["completion_seen"] = true
	ledger["completion_reason"] = str(snapshot.get("completion_reason", ""))
	_ledgers[encounter_id] = ledger
	var member_count := (ledger.get("member_ids", []) as Array).size()
	var defeated_count := (ledger.get("defeated_ids", {}) as Dictionary).size()
	if defeated_count >= member_count and member_count > 0:
		_schedule_reward_flush(encounter_id)
		return
	_abandoned_encounter_count += 1
	_record_claim(encounter_id, true)
	_last_result = {
		"status":"no_reward",
		"reason":"members_not_defeated",
		"encounter_id":encounter_id,
		"completion_reason":str(snapshot.get("completion_reason", "")),
		"defeated_member_count":defeated_count,
		"initial_member_count":member_count,
	}
	_ledgers.erase(encounter_id)
	_emit_economy_changed()


func _attempt_reward(encounter_id: String) -> Dictionary:
	if _claimed_ids.has(encounter_id):
		return {"success":false, "reason":"already_claimed"}
	if _pending_rewards.has(encounter_id):
		return {
			"success":false,
			"reason":str(_pending_rewards.get(encounter_id, {}).get("reason", "pending")),
			"pending":true,
		}
	if not _ledgers.has(encounter_id):
		return {"success":false, "reason":"ledger_missing"}
	var ledger: Dictionary = _ledgers.get(encounter_id, {})
	var member_count := (ledger.get("member_ids", []) as Array).size()
	var defeated_count := (ledger.get("defeated_ids", {}) as Dictionary).size()
	if member_count <= 0 or defeated_count < member_count:
		return {"success":false, "reason":"members_not_defeated"}
	var reward := _registry.build_reward(
		str(ledger.get("profile_id", "")), int(ledger.get("shot_count", 0))
	)
	if reward.is_empty():
		_record_claim(encounter_id, bool(ledger.get("completion_seen", false)))
		_ledgers.erase(encounter_id)
		return _reject("reward_profile_missing", ledger)
	var pending := {
		"encounter_id":encounter_id,
		"profile_id":str(ledger.get("profile_id", "")),
		"display_name":str(reward.get("display_name", "遭遇补给")),
		"rewards":reward.get("rewards", {}).duplicate(true),
		"efficient":bool(reward.get("efficient", false)),
		"efficient_shot_limit":int(reward.get("efficient_shot_limit", 0)),
		"shot_count":int(ledger.get("shot_count", 0)),
		"hit_shot_count":int(ledger.get("hit_shot_count", 0)),
		"ammo_spent":ledger.get("ammo_spent", {}).duplicate(true),
		"member_count":member_count,
		"completion_seen":bool(ledger.get("completion_seen", false)),
		"reason":"inventory_full",
	}
	if inventory == null or not inventory.has_method("transact_items"):
		return _queue_pending(encounter_id, pending, "inventory_unavailable")
	var transaction: Dictionary = inventory.call(
		"transact_items", {}, _reward_additions(pending.get("rewards", {}))
	)
	if bool(transaction.get("success", false)):
		return _commit_grant(encounter_id, pending, transaction, false)
	if str(transaction.get("reason", "")) == "inventory_full":
		return _queue_pending(encounter_id, pending, "inventory_full")
	_record_claim(encounter_id, bool(pending.get("completion_seen", false)))
	_ledgers.erase(encounter_id)
	return _reject(str(transaction.get("reason", "reward_transaction_failed")), pending)


func _queue_pending(encounter_id: String, pending: Dictionary, reason: String) -> Dictionary:
	if _pending_rewards.has(encounter_id):
		return {"success":false, "reason":reason, "pending":true}
	if _pending_rewards.size() >= MAX_PENDING_REWARDS:
		_record_claim(encounter_id, bool(pending.get("completion_seen", false)))
		_ledgers.erase(encounter_id)
		return _reject("pending_capacity", pending)
	pending["reason"] = reason
	_pending_rewards[encounter_id] = pending.duplicate(true)
	_ledgers.erase(encounter_id)
	_reward_pending_count += 1
	_last_result = pending.duplicate(true)
	_last_result["status"] = "pending"
	_last_result["reason"] = reason
	reward_pending.emit(_last_result.duplicate(true))
	_emit_economy_changed()
	return {"success":false, "reason":reason, "pending":true}


func _commit_grant(
	encounter_id: String,
	pending: Dictionary,
	transaction: Dictionary,
	from_pending: bool
) -> Dictionary:
	_record_claim(encounter_id, bool(pending.get("completion_seen", false)))
	_pending_rewards.erase(encounter_id)
	_ledgers.erase(encounter_id)
	_reward_grant_count += 1
	var rewards: Dictionary = pending.get("rewards", {})
	for raw_item_id: Variant in rewards.keys():
		_add_total(
			_rewards_granted_total,
			str(raw_item_id),
			int(rewards.get(raw_item_id, 0))
		)
	var result := pending.duplicate(true)
	result.merge({
		"success":true,
		"status":"granted",
		"reason":"ok",
		"from_pending":from_pending,
		"transaction":transaction.duplicate(true),
		"reward_labels":_reward_labels(rewards),
		"net_ammo":_net_ammo(rewards, pending.get("ammo_spent", {})),
	}, true)
	_last_result = result.duplicate(true)
	reward_granted.emit(result.duplicate(true))
	_emit_economy_changed()
	return result


func _record_claim(encounter_id: String, completion_seen: bool = false) -> void:
	if _claimed_ids.has(encounter_id):
		_claimed_ids[encounter_id] = bool(_claimed_ids.get(encounter_id, false)) or completion_seen
		return
	_claimed_ids[encounter_id] = completion_seen
	_claim_order.append(encounter_id)
	while _claim_order.size() > MAX_CLAIM_HISTORY:
		var expired: String = str(_claim_order.pop_front())
		_claimed_ids.erase(expired)


func _on_inventory_changed() -> void:
	if _pending_rewards.is_empty() or _retry_scheduled or _retry_in_progress:
		return
	_retry_scheduled = true
	call_deferred("_flush_pending_retry")


func _flush_pending_retry() -> void:
	_retry_scheduled = false
	retry_pending_rewards()


func _accepted_target_ids(result: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	var raw_results: Variant = result.get("target_results", [])
	if raw_results is not Array:
		return ids
	for raw_target: Variant in raw_results:
		if raw_target is not Dictionary:
			continue
		var target: Dictionary = raw_target
		if not bool(target.get("accepted", target.get("applied", false))):
			continue
		var target_id := int(target.get("target_id", 0))
		if target_id > 0 and target_id not in ids:
			ids.append(target_id)
	return ids


func _shot_hit_any_target(result: Dictionary) -> bool:
	return (
		int(result.get("accepted_target_count", 0)) > 0
		or not _accepted_target_ids(result).is_empty()
	)


func _normalized_member_ids(raw_ids: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw_ids is not Array:
		return result
	for raw_id: Variant in raw_ids:
		var member_id := int(raw_id)
		if member_id > 0 and member_id not in result:
			result.append(member_id)
	result.sort()
	return result


func _reward_additions(raw_rewards: Variant) -> Array[Dictionary]:
	var additions: Array[Dictionary] = []
	if raw_rewards is not Dictionary:
		return additions
	var ids: Array = raw_rewards.keys()
	ids.sort()
	for raw_item_id: Variant in ids:
		var quantity := int(raw_rewards.get(raw_item_id, 0))
		if quantity > 0:
			additions.append({"item_id":str(raw_item_id), "count":quantity})
	return additions


func _reward_labels(rewards: Dictionary) -> Array[String]:
	var labels: Array[String] = []
	var ids: Array = rewards.keys()
	ids.sort()
	for raw_item_id: Variant in ids:
		var item_id := str(raw_item_id)
		var display_name := item_id
		if inventory != null:
			var item_registry: Variant = inventory.get("registry")
			if item_registry != null and item_registry.has_method("get_display_name"):
				display_name = str(item_registry.call("get_display_name", item_id))
		labels.append("%s +%d" % [display_name, int(rewards.get(raw_item_id, 0))])
	return labels


func _net_ammo(rewards: Dictionary, spent: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item_id: String in AMMO_ITEM_IDS:
		var value := int(rewards.get(item_id, 0)) - int(spent.get(item_id, 0))
		if value != 0:
			result[item_id] = value
	return result


func _add_total(target: Dictionary, item_id: String, quantity: int) -> void:
	if item_id.is_empty() or quantity == 0:
		return
	target[item_id] = int(target.get(item_id, 0)) + quantity


func _public_ledger(ledger: Dictionary) -> Dictionary:
	return {
		"encounter_id":str(ledger.get("encounter_id", "")),
		"profile_id":str(ledger.get("profile_id", "")),
		"display_name":str(ledger.get("display_name", "遭遇")),
		"member_count":(ledger.get("member_ids", []) as Array).size(),
		"defeated_member_count":(ledger.get("defeated_ids", {}) as Dictionary).size(),
		"shot_count":int(ledger.get("shot_count", 0)),
		"hit_shot_count":int(ledger.get("hit_shot_count", 0)),
		"ammo_spent":ledger.get("ammo_spent", {}).duplicate(true),
		"completion_seen":bool(ledger.get("completion_seen", false)),
		"status":str(ledger.get("status", "active")),
	}


func _reject(reason: String, context: Dictionary = {}) -> Dictionary:
	_reward_rejection_count += 1
	var result := context.duplicate(true)
	result["success"] = false
	result["status"] = "rejected"
	result["reason"] = reason
	_last_result = result.duplicate(true)
	reward_rejected.emit(result.duplicate(true))
	_emit_economy_changed()
	return result


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	if _parent_hub == null or not is_instance_valid(_parent_hub):
		return
	var game_ui: Node = _parent_hub.get("game_ui") as Node
	if game_ui == null:
		return
	_overlay = OverlayScript.new()
	_overlay.name = "EncounterRewardOverlay"
	game_ui.add_child(_overlay)
	_overlay.call("setup", self)


func _services_ready() -> bool:
	return (
		director != null
		and is_instance_valid(director)
		and inventory != null
		and is_instance_valid(inventory)
		and ranged_combat_service != null
		and is_instance_valid(ranged_combat_service)
		and creature_spawner != null
		and is_instance_valid(creature_spawner)
	)


func _emit_economy_changed() -> void:
	economy_changed.emit(get_snapshot())


func _exit_tree() -> void:
	_disconnect_director()
	_disconnect_ranged()
	_disconnect_inventory()
