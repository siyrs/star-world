extends SceneTree

const RewardRegistryScript = preload("res://src/entity/encounter_reward_registry.gd")
const RewardServiceScript = preload("res://src/entity/encounter_reward_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")

var checks := 0
var failures: Array[String] = []


class FakeDirector:
	extends Node
	signal encounter_started(snapshot: Dictionary)
	signal encounter_completed(snapshot: Dictionary)


class FakeRangedCombat:
	extends Node
	signal shot_fired(result: Dictionary)


class FakeMember:
	extends Node3D
	signal died(species_id: String, drops: Dictionary, world_position: Vector3)
	var species_id := "zombie"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_economy_policy()
	await _test_real_reward_transactions()
	await _test_pending_reward_retry()
	_test_sixty_minute_economy_simulation()
	if failures.is_empty():
		print("QA ENCOUNTER REWARD ECONOMY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA ENCOUNTER REWARD ECONOMY FAILURE: %s" % failure)
	print("QA ENCOUNTER REWARD ECONOMY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_registry_and_economy_policy() -> void:
	var registry = RewardRegistryScript.new()
	_check(registry.schema_version == 1, "reward registry loads schema version one")
	_check(registry.get_validation_errors().is_empty(), "production encounter reward profiles pass strict normalization")
	_check(
		registry.get_profile_ids() == ["abyss_assault", "abyss_skirmish", "continent_night_patrol"],
		"reward registry exposes the exact three encounter profiles"
	)
	var assault := registry.build_reward("abyss_assault", 6)
	_check(bool(assault.get("efficient", false)), "six-shot abyss assault earns the configured efficiency bonus")
	_check(
		assault.get("rewards", {}) == {"gunpowder":2, "light_round":6, "shotgun_shell":1},
		"assault reward combines base supply and efficiency bonus deterministically"
	)
	var expensive := registry.build_reward("abyss_assault", 8)
	_check(not bool(expensive.get("efficient", true)), "shots above the efficiency limit do not receive bonus ammunition")
	_check(int(expensive.get("rewards", {}).get("light_round", 0)) == 4, "expensive assault keeps only the bounded base light-round reward")

	var invalid_path := "user://invalid-encounter-rewards.json"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	_check(file != null, "invalid encounter reward fixture opens for writing")
	if file != null:
		file.store_string(JSON.stringify({
			"schema_version":1,
			"profiles":[
				registry.get_profile("abyss_assault"),
				{
					"encounter_profile_id":"broken",
					"display_name":"broken",
					"base_rewards":{"light_round":999},
					"efficient_shot_limit":99,
					"efficient_bonus":{"unknown_item":1},
				}
			]
		}, "  "))
		file.close()
		_check(not registry.load_from_file(invalid_path), "one invalid reward profile rejects the entire staged registry")
		_check(
			registry.get_profile_ids() == ["abyss_assault", "abyss_skirmish", "continent_night_patrol"],
			"failed reward reload preserves the previous complete registry"
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))


func _test_real_reward_transactions() -> void:
	var host := Node.new()
	root.add_child(host)
	var director := FakeDirector.new()
	var ranged := FakeRangedCombat.new()
	var inventory = InventoryScript.new(18, 9)
	var spawner := Node3D.new()
	var service = RewardServiceScript.new()
	service.auto_bind_parent = false
	host.add_child(director)
	host.add_child(ranged)
	host.add_child(inventory)
	host.add_child(spawner)
	host.add_child(service)
	service.setup(director, inventory, ranged, spawner)
	await process_frame

	var members := _create_members(spawner, 4)
	var member_ids := _member_ids(members)
	director.encounter_started.emit({
		"id":"abyss-assault-test-1",
		"profile_id":"abyss_assault",
		"display_name":"深渊突袭队",
		"living_member_ids":member_ids,
		"started_at_msec":Time.get_ticks_msec(),
	})
	_check(int(service.get_snapshot().get("active_ledger_count", 0)) == 1, "encounter start creates exactly one bounded economy ledger")
	for index in 6:
		var target_id := member_ids[mini(index, member_ids.size() - 1)]
		ranged.shot_fired.emit({
			"accepted":true,
			"status":"fired",
			"ammo_item_id":"light_round",
			"accepted_target_count":1,
			"target_results":[{"target_id":target_id, "accepted":true, "applied":true}],
		})
	var during: Dictionary = service.get_snapshot().get("ledgers", [])[0]
	_check(int(during.get("shot_count", 0)) == 6, "six real shot signals are attributed to the matching active squad")
	_check(int(during.get("ammo_spent", {}).get("light_round", 0)) == 6, "encounter ledger records exact light-round consumption")

	for member: FakeMember in members:
		member.died.emit(member.species_id, {}, member.global_position)
	var granted := await _wait_until(
		func() -> bool: return int(service.get_snapshot().get("reward_grant_count", 0)) == 1,
		2000
	)
	_check(granted, "last defeated member grants the squad reward before director cleanup")
	_check(inventory.count_item("light_round") == 6, "atomic reward grants six efficient light rounds")
	_check(inventory.count_item("gunpowder") == 2, "atomic reward grants two gunpowder")
	_check(inventory.count_item("shotgun_shell") == 1, "atomic reward grants one shotgun shell")
	var rewarded_snapshot := service.get_snapshot()
	_check(int(rewarded_snapshot.get("reward_grant_count", 0)) == 1, "all reward items commit as one grant")
	_check(int(rewarded_snapshot.get("net_ammo_total", {}).get("light_round", 0)) == 0, "six shots and six rewarded rounds produce neutral light-ammo net")

	director.encounter_completed.emit({
		"id":"abyss-assault-test-1",
		"profile_id":"abyss_assault",
		"completion_reason":"members_cleared",
	})
	_check(int(service.get_snapshot().get("active_ledger_count", -1)) == 0, "normal director completion closes the rewarded ledger")
	var light_rounds_after_completion := inventory.count_item("light_round")
	director.encounter_completed.emit({
		"id":"abyss-assault-test-1",
		"profile_id":"abyss_assault",
		"completion_reason":"members_cleared",
	})
	_check(inventory.count_item("light_round") == light_rounds_after_completion, "duplicate completion cannot grant the same reward twice")
	_check(int(service.get_snapshot().get("duplicate_completion_count", 0)) == 1, "duplicate completion is recorded without inventory mutation")

	var abandoned_members := _create_members(spawner, 3)
	director.encounter_started.emit({
		"id":"abyss-skirmish-abandoned",
		"profile_id":"abyss_skirmish",
		"display_name":"深渊游猎队",
		"living_member_ids":_member_ids(abandoned_members),
	})
	for member: FakeMember in abandoned_members:
		member.queue_free()
	for _frame in 4:
		await process_frame
	director.encounter_completed.emit({
		"id":"abyss-skirmish-abandoned",
		"profile_id":"abyss_skirmish",
		"completion_reason":"members_cleared",
	})
	_check(int(service.get_snapshot().get("abandoned_encounter_count", 0)) == 1, "unloaded members are not misclassified as defeated")
	_check(inventory.count_item("gunpowder") == 2, "member unload does not grant encounter rewards")

	var first_members := _create_members(spawner, 2)
	var second_members := _create_members(spawner, 2)
	director.encounter_started.emit({
		"id":"multi-ledger-a", "profile_id":"continent_night_patrol",
		"living_member_ids":_member_ids(first_members),
	})
	director.encounter_started.emit({
		"id":"multi-ledger-b", "profile_id":"continent_night_patrol",
		"living_member_ids":_member_ids(second_members),
	})
	ranged.shot_fired.emit({
		"accepted":true, "status":"fired", "ammo_item_id":"light_round",
		"accepted_target_count":0, "target_results":[],
	})
	_check(int(service.get_snapshot().get("unattributed_shot_count", 0)) == 1, "ambiguous miss across two squads is not double-counted")
	service.clear("test_cleanup")
	host.queue_free()
	for _frame in 16:
		await process_frame


func _test_pending_reward_retry() -> void:
	var host := Node.new()
	root.add_child(host)
	var director := FakeDirector.new()
	var ranged := FakeRangedCombat.new()
	var inventory = InventoryScript.new(9, 9)
	var spawner := Node3D.new()
	var service = RewardServiceScript.new()
	service.auto_bind_parent = false
	host.add_child(director)
	host.add_child(ranged)
	host.add_child(inventory)
	host.add_child(spawner)
	host.add_child(service)
	service.setup(director, inventory, ranged, spawner)
	await process_frame
	for _index in 9:
		_check(inventory.add_item("star_pistol", 1) == 0, "full-inventory fixture fills one weapon slot atomically")
	_check(inventory.get_add_capacity("light_round") == 0, "pending fixture has zero light-round capacity")

	var members := _create_members(spawner, 2)
	director.encounter_started.emit({
		"id":"pending-patrol-1",
		"profile_id":"continent_night_patrol",
		"display_name":"夜行巡猎队",
		"living_member_ids":_member_ids(members),
	})
	for member: FakeMember in members:
		member.died.emit(member.species_id, {}, member.global_position)
	var pending_ready := await _wait_until(
		func() -> bool: return int(service.get_snapshot().get("pending_reward_count", 0)) == 1,
		2000
	)
	_check(pending_ready, "full inventory queues one bounded pending reward")
	_check(inventory.count_item("light_round") == 0, "pending reward does not partially mutate a full inventory")
	inventory.remove_from_slot(0, 1)
	var retried := await _wait_until(
		func() -> bool: return int(service.get_snapshot().get("reward_grant_count", 0)) == 1,
		2000
	)
	_check(retried, "inventory change automatically retries the pending reward")
	_check(inventory.count_item("light_round") == 2, "pending patrol reward commits base and efficiency bonus together")
	_check(int(service.get_snapshot().get("pending_reward_count", -1)) == 0, "successful retry removes the pending record")

	for index in 300:
		service.call("_record_claim", "synthetic-claim-%03d" % index)
	_check(int(service.get_snapshot().get("claim_history_count", 0)) == 256, "claim history remains bounded at two hundred fifty-six ids")
	_check(int(service.get_snapshot().get("maximum_pending_rewards", 0)) == 8, "pending reward diagnostics expose the exact eight-entry cap")
	host.queue_free()
	for _frame in 16:
		await process_frame


func _test_sixty_minute_economy_simulation() -> void:
	var registry = RewardRegistryScript.new()
	var encounter_count := 0
	var total_reward_quantity := 0
	var total_light_spent := 0
	var total_light_rewarded := 0
	var maximum_single_reward := 0
	for second in range(0, 3600, 45):
		var profile_id := "abyss_assault" if encounter_count % 2 == 0 else "abyss_skirmish"
		var shot_count := 6 if profile_id == "abyss_assault" else 4
		var reward := registry.build_reward(profile_id, shot_count)
		var rewards: Dictionary = reward.get("rewards", {})
		var quantity := 0
		for raw_quantity: Variant in rewards.values():
			quantity += int(raw_quantity)
		total_reward_quantity += quantity
		maximum_single_reward = maxi(maximum_single_reward, quantity)
		total_light_spent += shot_count
		total_light_rewarded += int(rewards.get("light_round", 0))
		encounter_count += 1
	_check(encounter_count == 80, "sixty minute economy simulation resolves eighty bounded encounters")
	_check(maximum_single_reward <= 16, "every simulated reward remains inside the sixteen-item hard limit")
	_check(total_reward_quantity <= encounter_count * 16, "sixty minute reward production remains linearly bounded")
	_check(total_light_rewarded - total_light_spent <= 40, "sixty minute efficient play cannot create runaway light ammunition")
	_check(total_light_rewarded - total_light_spent >= 0, "efficient mixed encounters sustain but do not starve light ammunition")


func _create_members(parent: Node3D, count: int) -> Array[FakeMember]:
	var result: Array[FakeMember] = []
	for index in count:
		var member := FakeMember.new()
		member.name = "Member_%d" % index
		parent.add_child(member)
		result.append(member)
	return result


func _member_ids(members: Array[FakeMember]) -> Array[int]:
	var result: Array[int] = []
	for member: FakeMember in members:
		result.append(int(member.get_instance_id()))
	return result


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
