class_name ExplorationMilestoneRewardService
extends Node

signal rewards_changed(snapshot: Dictionary)
signal reward_claimed(milestone_id: String, result: Dictionary)
signal reward_rejected(milestone_id: String, reason: String, context: Dictionary)

const RegistryScript = preload(
	"res://src/exploration/exploration_milestone_reward_registry.gd"
)
const PolicyScript = preload(
	"res://src/exploration/exploration_milestone_reward_policy.gd"
)
const StateMigrationScript = preload(
	"res://src/exploration/exploration_reward_state_migration.gd"
)

var registry = RegistryScript.new()
var inventory: Node
var journal_service: Node
var profile_id := "star_continent"
var _claimed: Dictionary = {}
var _snapshot: Dictionary = {}


func setup(p_inventory: Node, p_journal_service: Node) -> bool:
	_disconnect_journal()
	inventory = p_inventory
	journal_service = p_journal_service
	if journal_service != null and journal_service.has_signal("journal_changed"):
		journal_service.connect("journal_changed", Callable(self, "_on_journal_changed"))
	refresh()
	return (
		registry.get_validation_errors().is_empty()
		and inventory != null
		and inventory.has_method("transact_items")
		and journal_service != null
		and journal_service.has_method("get_snapshot")
	)


func set_profile(p_profile_id: String) -> void:
	var resolved := p_profile_id.strip_edges()
	if resolved.is_empty():
		resolved = "star_continent"
	if profile_id == resolved:
		return
	profile_id = resolved
	refresh()


func serialize() -> Dictionary:
	var claimed_ids: Array[String] = []
	for milestone_id: String in registry.get_reward_ids():
		if _claimed.has(milestone_id):
			claimed_ids.append(milestone_id)
	return {
		"version": StateMigrationScript.VERSION,
		"claimed": claimed_ids,
	}


func deserialize(raw_state: Variant) -> void:
	_claimed.clear()
	var normalized := StateMigrationScript.normalize_reward_state(raw_state)
	var raw_claimed: Variant = normalized.get("claimed", [])
	if raw_claimed is Array:
		for raw_id: Variant in raw_claimed:
			var milestone_id := str(raw_id)
			if registry.has_reward(milestone_id):
				_claimed[milestone_id] = true
	refresh()


func claim(milestone_id: String) -> Dictionary:
	var reward := PolicyScript.find_reward(refresh(), milestone_id)
	if reward.is_empty():
		return _reject(milestone_id, "unknown_reward", "没有找到该探索奖励")
	var status := str(reward.get("status", "locked"))
	if status == "claimed":
		return _reject(milestone_id, "already_claimed", "该探索奖励已经领取")
	if status != "claimable":
		return _reject(milestone_id, "milestone_locked", "尚未完成对应探索里程碑")
	if inventory == null or not inventory.has_method("transact_items"):
		return _reject(milestone_id, "inventory_unavailable", "背包服务暂时不可用")
	var raw_items: Variant = reward.get("reward_items", [])
	var items: Array = raw_items.duplicate(true) if raw_items is Array else []
	var transaction: Dictionary = inventory.call("transact_items", {}, items)
	if not bool(transaction.get("success", false)):
		var reason := str(transaction.get("reason", "transaction_failed"))
		var message := (
			"背包空间不足；奖励会保留为待领取状态"
			if reason == "inventory_full"
			else "奖励事务未完成，请稍后重试"
		)
		return _reject(
			milestone_id,
			reason,
			message,
			{
				"reward_label": str(reward.get("reward_label", "")),
				"transaction": transaction,
			}
		)
	_claimed[milestone_id] = true
	var next_snapshot := refresh()
	var result := {
		"success": true,
		"milestone_id": milestone_id,
		"reward_label": str(reward.get("reward_label", "")),
		"items": items,
		"profile_id": profile_id,
		"message": "已领取探索奖励：%s" % str(reward.get("reward_label", "")),
		"snapshot": next_snapshot,
	}
	reward_claimed.emit(milestone_id, result.duplicate(true))
	return result


func refresh() -> Dictionary:
	var journal_snapshot: Dictionary = {}
	if journal_service != null and journal_service.has_method("get_snapshot"):
		var raw_snapshot: Variant = journal_service.call("get_snapshot")
		if raw_snapshot is Dictionary:
			journal_snapshot = raw_snapshot
	var claimed_ids: Array[String] = []
	for milestone_id: String in registry.get_reward_ids():
		if _claimed.has(milestone_id):
			claimed_ids.append(milestone_id)
	var next_snapshot := PolicyScript.build_snapshot(
		journal_snapshot,
		registry,
		claimed_ids,
		profile_id
	)
	if next_snapshot != _snapshot:
		_snapshot = next_snapshot.duplicate(true)
		rewards_changed.emit(_snapshot.duplicate(true))
	return _snapshot.duplicate(true)


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_reward(milestone_id: String) -> Dictionary:
	return PolicyScript.find_reward(_snapshot, milestone_id)


func is_claimed(milestone_id: String) -> bool:
	return _claimed.has(milestone_id)


func clear() -> void:
	_claimed.clear()
	profile_id = "star_continent"
	if not _snapshot.is_empty():
		_snapshot.clear()
		rewards_changed.emit({})


func _reject(
	milestone_id: String,
	reason: String,
	message: String,
	extra: Dictionary = {}
) -> Dictionary:
	var context := extra.duplicate(true)
	context["success"] = false
	context["milestone_id"] = milestone_id
	context["reason"] = reason
	context["message"] = message
	reward_rejected.emit(milestone_id, reason, context.duplicate(true))
	return context


func _on_journal_changed(_snapshot_value: Dictionary) -> void:
	refresh()


func _disconnect_journal() -> void:
	if journal_service == null or not journal_service.has_signal("journal_changed"):
		return
	var callback := Callable(self, "_on_journal_changed")
	if journal_service.is_connected("journal_changed", callback):
		journal_service.disconnect("journal_changed", callback)


func _exit_tree() -> void:
	_disconnect_journal()
