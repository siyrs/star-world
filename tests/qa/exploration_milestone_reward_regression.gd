extends SceneTree

const JournalRegistryScript = preload("res://src/exploration/exploration_journal_registry.gd")
const RewardRegistryScript = preload("res://src/exploration/exploration_milestone_reward_registry.gd")
const RewardPolicyScript = preload("res://src/exploration/exploration_milestone_reward_policy.gd")
const RewardServiceScript = preload("res://src/exploration/exploration_milestone_reward_service.gd")
const RewardMigrationScript = preload("res://src/exploration/exploration_reward_state_migration.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeJournal:
	extends Node
	signal journal_changed(snapshot: Dictionary)
	var registry = JournalRegistryScript.new()
	var snapshot: Dictionary = {}

	func _init() -> void:
		set_completed([])

	func set_completed(completed_ids: Array[String]) -> void:
		var milestones: Array[Dictionary] = []
		for raw_milestone: Dictionary in registry.get_milestones():
			var milestone := raw_milestone.duplicate(true)
			var milestone_id := str(milestone.get("id", ""))
			var completed := milestone_id in completed_ids
			milestone["completed"] = completed
			milestone["progress"] = 1 if completed else 0
			milestone["target"] = 1
			milestones.append(milestone)
		snapshot = {
			"milestones": milestones,
			"milestone_count": milestones.size(),
			"completed_milestone_count": completed_ids.size(),
			"record_count": completed_ids.size(),
			"unique_chunk_count": completed_ids.size(),
		}
		journal_changed.emit(snapshot.duplicate(true))

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_policy()
	await _test_claim_lifecycle()
	_test_state_migration()
	await _test_production_composition()
	if failures.is_empty():
		print("QA EXPLORATION REWARD PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION REWARD FAILURE: %s" % failure)
		print("QA EXPLORATION REWARD FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var registry = RewardRegistryScript.new()
	_check(registry.schema_version == 1, "milestone reward schema version is stable")
	_check(registry.get_validation_errors().is_empty(), "production reward bundles have no validation errors")
	_check(registry.get_reward_ids().size() == 7, "every production exploration milestone has a reward")
	var star_reward := registry.get_reward("first_discovery", "star_continent")
	var abyss_reward := registry.get_reward("first_discovery", "abyss_world")
	_check(_item_count(star_reward.get("items", []), "torch") == 4, "first discovery always grants base torches")
	_check(_item_count(star_reward.get("items", []), "apple") == 2, "star continent receives its map-aware apple bonus")
	_check(_item_count(abyss_reward.get("items", []), "cooked_chicken") == 2, "abyss receives its map-aware food bonus")
	_check(str(star_reward.get("reward_label", "")).contains("苹果"), "reward registry exposes a player-facing map bonus label")
	var journal = FakeJournal.new()
	journal.set_completed(["first_discovery"])
	var snapshot := RewardPolicyScript.build_snapshot(
		journal.get_snapshot(),
		registry,
		[],
		"desert_ruins"
	)
	var first := RewardPolicyScript.find_reward(snapshot, "first_discovery")
	_check(str(first.get("status", "")) == "claimable", "completed unclaimed milestones become claimable")
	_check(_item_count(first.get("reward_items", []), "glass") == 4, "policy resolves the active map bonus")
	var claimed_snapshot := RewardPolicyScript.build_snapshot(
		journal.get_snapshot(),
		registry,
		["first_discovery"],
		"desert_ruins"
	)
	_check(str(RewardPolicyScript.find_reward(claimed_snapshot, "first_discovery").get("status", "")) == "claimed", "claimed state overrides derived completion")


func _test_claim_lifecycle() -> void:
	var inventory = InventoryScript.new(36, 9)
	var journal = FakeJournal.new()
	var service = RewardServiceScript.new()
	root.add_child(inventory)
	root.add_child(journal)
	root.add_child(service)
	_check(service.setup(inventory, journal), "reward service accepts production inventory and journal ports")
	service.set_profile("abyss_world")
	var locked: Dictionary = service.claim("first_discovery")
	_check(str(locked.get("reason", "")) == "milestone_locked", "locked milestone cannot grant inventory items")
	journal.set_completed(["first_discovery"])
	_check(str(service.get_reward("first_discovery").get("status", "")) == "claimable", "journal completion refreshes reward state")
	var claimed: Dictionary = service.claim("first_discovery")
	_check(bool(claimed.get("success", false)), "claimable reward commits successfully")
	_check(inventory.count_item("torch") == 4, "claim transaction grants the base reward")
	_check(inventory.count_item("cooked_chicken") == 2, "claim transaction grants the abyss map bonus")
	_check(service.is_claimed("first_discovery"), "successful transaction marks the milestone claimed")
	var duplicate: Dictionary = service.claim("first_discovery")
	_check(str(duplicate.get("reason", "")) == "already_claimed", "duplicate claims are rejected idempotently")
	_check(inventory.count_item("torch") == 4 and inventory.count_item("cooked_chicken") == 2, "duplicate claim does not duplicate items")

	journal.set_completed(["first_discovery", "three_regions"])
	var serial := 0
	while serial < 40:
		var remaining := inventory.add_item("wooden_pickaxe", 1, {"serial":serial})
		if remaining > 0:
			break
		serial += 1
	_check(_non_empty_slots(inventory) == inventory.slot_count, "test fills every inventory slot before claiming the bundle")
	var full: Dictionary = service.claim("three_regions")
	_check(str(full.get("reason", "")) == "inventory_full", "full inventory rejects the reward atomically")
	_check(not service.is_claimed("three_regions"), "failed reward remains pending instead of being consumed")
	_check(str(service.get_reward("three_regions").get("status", "")) == "claimable", "failed reward remains visibly claimable")
	var released := _remove_first_item(inventory, "wooden_pickaxe")
	_check(released, "test releases one real inventory slot")
	var retried: Dictionary = service.claim("three_regions")
	_check(bool(retried.get("success", false)), "pending reward succeeds after space is available")
	_check(inventory.count_item("iron_ingot") == 2, "retried reward grants its complete bundle")
	_check(service.is_claimed("three_regions"), "successful retry marks the reward claimed")
	var saved := service.serialize()
	_check(int(saved.get("version", 0)) == 1, "reward state serializes with its own version")
	_check((saved.get("claimed", []) as Array).size() == 2, "reward state saves exactly two claimed milestones")

	var restored = RewardServiceScript.new()
	root.add_child(restored)
	_check(restored.setup(inventory, journal), "restored reward service accepts the same production ports")
	restored.set_profile("abyss_world")
	restored.deserialize(saved)
	_check(restored.is_claimed("first_discovery") and restored.is_claimed("three_regions"), "claimed rewards survive reload")
	_check(str(restored.get_reward("first_discovery").get("status", "")) == "claimed", "restored snapshot preserves claimed status")
	service.queue_free()
	restored.queue_free()
	journal.queue_free()
	inventory.queue_free()
	await process_frame
	await process_frame


func _test_state_migration() -> void:
	var normalized := RewardMigrationScript.normalize_reward_state({
		"version":0,
		"claimed":["first_discovery", "", "first_discovery", "unknown_reward"],
	})
	_check(int(normalized.get("version", 0)) == 1, "legacy reward state migrates to version one")
	var claimed: Array = normalized.get("claimed", [])
	_check(claimed == ["first_discovery", "unknown_reward"], "migration removes empty and duplicate claimed ids without guessing registry policy")
	var inventory = InventoryScript.new()
	var journal = FakeJournal.new()
	var service = RewardServiceScript.new()
	root.add_child(inventory)
	root.add_child(journal)
	root.add_child(service)
	service.setup(inventory, journal)
	service.deserialize(normalized)
	_check(service.is_claimed("first_discovery"), "service keeps known migrated claims")
	_check(not service.is_claimed("unknown_reward"), "service drops claims that no longer exist in the reward registry")
	service.queue_free()
	journal.queue_free()
	inventory.queue_free()


func _test_production_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var reward_service: Node = hub.get("exploration_reward_service")
	var journal_service: Node = hub.get("exploration_journal_service")
	var panel: Node = hub.game_ui.call("get_exploration_journal_panel")
	_check(reward_service != null and journal_service != null, "production service hub composes journal and reward services")
	_check(panel != null and panel.get("reward_service") == reward_service, "production journal panel receives the reward domain service")
	var state: Dictionary = hub.save_service.create_world(
		"reward-schema-%d" % Time.get_ticks_msec(),
		"star_continent",
		417239
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(state.get("exploration", {}) is Dictionary, "new worlds include the canonical exploration state")
	_check(int(state.get("exploration_rewards", {}).get("version", 0)) == 1, "new worlds include the canonical reward state")
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _item_count(raw_items: Variant, item_id: String) -> int:
	var result := 0
	if raw_items is not Array:
		return result
	for raw_item: Variant in raw_items:
		if raw_item is Dictionary and str(raw_item.get("item_id", "")) == item_id:
			result += int(raw_item.get("count", 0))
	return result


func _non_empty_slots(inventory: Node) -> int:
	var result := 0
	for index in inventory.slot_count:
		if not inventory.get_slot(index).is_empty():
			result += 1
	return result


func _remove_first_item(inventory: Node, item_id: String) -> bool:
	for index in inventory.slot_count:
		if str(inventory.get_slot(index).get("item_id", "")) == item_id:
			inventory.remove_from_slot(index, 1)
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
