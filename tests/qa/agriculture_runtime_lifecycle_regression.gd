extends SceneTree

const StateMigrationScript = preload(
	"res://src/agriculture/agriculture_state_migration.gd"
)
const NotificationPolicyScript = preload(
	"res://src/agriculture/agriculture_notification_policy.gd"
)
const CropRegistryScript = preload("res://src/agriculture/crop_registry.gd")
const AgricultureScript = preload(
	"res://src/agriculture/fertilizable_agriculture_service.gd"
)
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var profile_id := "star_continent"
	var blocks: Dictionary = {}

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[block_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(block_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var key := block_key(position)
		var previous := str(blocks.get(key, "air"))
		if previous == block_id:
			return false
		blocks[key] = block_id
		return true

	func remove_block(position: Vector3i) -> String:
		var previous := get_block(position)
		if previous == "air":
			return "air"
		blocks[block_key(position)] = "air"
		return previous

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(
			floori(float(position.x) / 16.0), floori(float(position.z) / 16.0)
		)

	func get_initial_block(position: Vector3i) -> String:
		return get_block(position)

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, maxf(1.05, candidate.y), candidate.z)

	func serialize_state() -> Dictionary:
		return {"version":1, "block_overrides":blocks.duplicate(true)}


class RacingInventory:
	extends Node
	var can_count := 0
	var transaction_count := 0

	func can_transact_items(_removals: Dictionary = {}, _additions: Array = []) -> bool:
		can_count += 1
		return true

	func transact_items(_removals: Dictionary = {}, _additions: Array = []) -> Dictionary:
		transaction_count += 1
		return {"success":false, "reason":"qa_race"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_state_migration_and_notification_policy()
	await _test_atomic_harvest_and_pause()
	await _test_production_participant_lifecycle()
	if failures.is_empty():
		print("QA AGRICULTURE RUNTIME LIFECYCLE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AGRICULTURE RUNTIME LIFECYCLE FAILURE: %s" % failure)
		print(
			"QA AGRICULTURE RUNTIME LIFECYCLE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_state_migration_and_notification_policy() -> void:
	var many_crops: Dictionary = {}
	var many_soils: Dictionary = {}
	for index in 4100:
		many_crops["legacy-%05d" % index] = {
			"crop_id":"wheat",
			"position":[index, 20, 0],
			"stage":99,
			"elapsed_seconds":INF if index == 0 else 12.0,
			"unknown":"discard",
		}
		many_soils["legacy-%05d" % index] = {
			"position":[index, 19, 0],
			"manual_remaining_seconds":999999.0,
			"hydrated":true,
			"unknown":"discard",
		}
	var normalized: Dictionary = StateMigrationScript.normalize_agriculture_state({
		"version":99,
		"saved_at_unix":-5,
		"crops":many_crops,
		"soil_moisture":{"version":99, "soils":many_soils},
		"unknown_root":"discard",
	})
	_check(int(normalized.get("version", 0)) == 2, "agriculture migration restores schema two")
	_check(int(normalized.get("saved_at_unix", -1)) == 0, "negative agriculture save time is normalized")
	_check((normalized.get("crops", {}) as Dictionary).size() == 4096, "crop records are hard-capped at 4096")
	_check(
		(normalized.get("soil_moisture", {}).get("soils", {}) as Dictionary).size() == 4096,
		"soil records are hard-capped at 4096"
	)
	var first_crop: Dictionary = normalized.get("crops", {}).get("crop@0,20,0", {})
	_check(int(first_crop.get("stage", -1)) == 3, "corrupt crop stages clamp to the registered final stage")
	_check(is_zero_approx(float(first_crop.get("elapsed_seconds", -1.0))), "non-finite crop elapsed time is removed")
	_check(not first_crop.has("unknown") and not normalized.has("unknown_root"), "agriculture migration uses a strict whitelist")
	var first_soil: Dictionary = normalized.get("soil_moisture", {}).get("soils", {}).get("soil@0,19,0", {})
	_check(
		float(first_soil.get("manual_remaining_seconds", 0.0)) <= 21600.0,
		"manual hydration is bounded to six hours"
	)
	var crop_registry = CropRegistryScript.new()
	var summary: Dictionary = NotificationPolicyScript.maturity_batch([
		{"crop_id":"wheat", "position":[0,20,0]},
		{"crop_id":"wheat", "position":[1,20,0]},
		{"crop_id":"carrot", "position":[2,20,0]},
		{"crop_id":"potato", "position":[3,20,0]},
		{"crop_id":"future_crop", "position":[4,20,0]},
	], crop_registry)
	_check(int(summary.get("matured_count", 0)) == 5, "maturity policy preserves the complete batch count")
	_check(int(summary.get("crop_type_count", 0)) == 4, "maturity policy preserves crop type count")
	_check(str(summary.get("message", "")).contains("另有 1 种作物"), "maturity message bounds visible crop types")


func _test_atomic_harvest_and_pause() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new(9, 9)
	var tools = ToolScript.new()
	var agriculture = AgricultureScript.new()
	var world = FakeWorld.new()
	for node: Node in [inventory, tools, agriculture, world]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	agriculture.setup(inventory.registry, tools)
	var soil := Vector3i(4, 18, 1)
	var crop := soil + Vector3i.UP
	world.set_test_block(soil, "farmland_wet")
	world.set_test_block(crop, "wheat_stage_3")
	agriculture.deserialize(_agriculture_state([
		{"crop_id":"wheat", "position":crop, "stage":3, "elapsed":0.0}
	], [soil]))
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("dirt", 64 * 9)
	var inventory_before: Dictionary = inventory.serialize()
	var blocked: Dictionary = agriculture.try_interact(world, inventory, crop, "wheat_stage_3")
	_check(str(blocked.get("reason", "")) == "inventory_full", "full inventory rejects atomic mature harvest")
	_check(inventory.serialize() == inventory_before, "blocked harvest performs zero inventory writes")
	_check(world.get_block(crop) == "wheat_stage_3", "blocked harvest keeps the mature crop block")
	inventory.remove_from_slot(0, 64)
	inventory.remove_from_slot(1, 64)
	var harvested: Dictionary = agriculture.try_interact(world, inventory, crop, "wheat_stage_3")
	_check(bool(harvested.get("success", false)), "mature harvest commits through one inventory transaction")
	_check(bool(harvested.get("transaction", {}).get("success", false)), "harvest exposes the committed transaction result")
	_check(inventory.count_item("wheat") == 1 and inventory.count_item("wheat_seeds") == 2, "atomic harvest grants every configured output")
	_check(world.get_block(crop) == "wheat_stage_0", "atomic harvest replants only after transaction capacity is proven")
	_check(
		int(agriculture.get_runtime_snapshot().get("atomic_harvest_count", 0)) == 1,
		"runtime diagnostics count committed atomic harvests"
	)

	var race_world = FakeWorld.new()
	var race_inventory = RacingInventory.new()
	var race_agriculture = AgricultureScript.new()
	for node: Node in [race_world, race_inventory, race_agriculture]:
		host.add_child(node)
	await process_frame
	race_agriculture.setup(inventory.registry, tools)
	var race_soil := Vector3i(8, 18, 1)
	var race_crop := race_soil + Vector3i.UP
	race_world.set_test_block(race_soil, "farmland_wet")
	race_world.set_test_block(race_crop, "wheat_stage_3")
	race_agriculture.deserialize(_agriculture_state([
		{"crop_id":"wheat", "position":race_crop, "stage":3, "elapsed":0.0}
	], [race_soil]))
	race_agriculture.attach_world(race_world, race_inventory)
	var raced: Dictionary = race_agriculture.try_interact(
		race_world, race_inventory, race_crop, "wheat_stage_3"
	)
	_check(str(raced.get("reason", "")) == "inventory_race", "commit-time inventory changes reject the harvest")
	_check(race_inventory.transaction_count == 1, "race path attempts exactly one atomic inventory commit")
	_check(race_world.get_block(race_crop) == "wheat_stage_3", "failed transaction restores the mature world block")
	_check(int(race_agriculture.get_crop_state(race_crop).get("stage", -1)) == 3, "failed transaction preserves crop domain state")

	var pause_world = FakeWorld.new()
	var pause_agriculture = AgricultureScript.new()
	host.add_child(pause_world)
	host.add_child(pause_agriculture)
	await process_frame
	pause_agriculture.setup(inventory.registry, tools)
	var pause_soil := Vector3i(12, 18, 1)
	var pause_crop := pause_soil + Vector3i.UP
	var first_duration := float(pause_agriculture.crop_registry.get_stage_duration("wheat", 0))
	pause_world.set_test_block(pause_soil, "farmland_wet")
	pause_world.set_test_block(pause_crop, "wheat_stage_0")
	pause_agriculture.deserialize(_agriculture_state([
		{
			"crop_id":"wheat",
			"position":pause_crop,
			"stage":0,
			"elapsed":maxf(0.0, first_duration - 0.05),
		}
	], [pause_soil], 1000.0))
	pause_agriculture.attach_world(pause_world, inventory)
	_check(
		pause_agriculture.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"production agriculture explicitly uses the pausable process mode"
	)
	paused = true
	await create_timer(0.75, true, false, true).timeout
	_check(pause_world.get_block(pause_crop) == "wheat_stage_0", "real SceneTree pause freezes crop growth")
	paused = false
	await create_timer(0.75, true, false, true).timeout
	_check(pause_world.get_block(pause_crop) == "wheat_stage_1", "crop growth resumes after the real pause ends")
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_participant_lifecycle() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 4:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle") as Node
	var participant: Node = hub.get("agriculture_runtime_participant") as Node
	var agriculture: Node = hub.get("agriculture_service") as Node
	var interaction: Node = hub.get("agriculture_interaction") as Node
	_check(
		coordinator != null
		and coordinator.has_participant(&"agriculture_runtime")
		and participant != null,
		"production hub installs the agriculture lifecycle participant"
	)
	_check(
		agriculture != null
		and interaction != null
		and hub.get_node_or_null("AgricultureService") == agriculture
		and hub.get_node_or_null("AgricultureInteraction") == interaction,
		"participant preserves agriculture public fields and node paths"
	)
	_check(
		agriculture != null and agriculture.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"production participant mounts pausable agriculture"
	)
	var world = FakeWorld.new()
	root.add_child(world)
	var first_soil := Vector3i(1, 20, 1)
	var second_soil := Vector3i(2, 20, 1)
	var first_crop := first_soil + Vector3i.UP
	var second_crop := second_soil + Vector3i.UP
	for soil: Vector3i in [first_soil, second_soil]:
		world.set_test_block(soil, "farmland_wet")
		world.set_test_block(soil + Vector3i(3, 0, 0), "water")
	world.set_test_block(first_crop, "wheat_stage_2")
	world.set_test_block(second_crop, "carrot_stage_2")
	var state: Dictionary = hub.save_service.create_world(
		"agriculture-runtime-%d" % Time.get_ticks_msec(), "star_continent", 481516
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	state["agriculture"] = _agriculture_state([
		{"crop_id":"wheat", "position":first_crop, "stage":2, "elapsed":0.0},
		{"crop_id":"carrot", "position":second_crop, "stage":2, "elapsed":0.0},
	], [first_soil, second_soil], 1000.0)
	hub.call("_begin_world", state)
	hub.call("attach_game", world, null)
	coordinator.call("activate")
	var batches: Array[Dictionary] = []
	participant.connect(
		"maturity_batch_announced",
		func(summary: Dictionary) -> void: batches.append(summary.duplicate(true))
	)
	agriculture.call("advance_time", 200.0)
	await process_frame
	await process_frame
	_check(batches.size() == 1, "two synchronous mature crops publish one player batch")
	if not batches.is_empty():
		_check(int(batches[0].get("matured_count", 0)) == 2, "maturity batch preserves both crops")
		_check(int(batches[0].get("crop_type_count", 0)) == 2, "maturity batch preserves both crop types")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("maturity_audio_count", 0)) == 1, "maturity batch consumes one audio budget")
	_check(int(lifecycle.get("matured_crop_total", 0)) == 2, "participant diagnostics count matured crops")
	_check(bool(hub.call("save_current")), "agriculture participant contributes to the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check((loaded.get("agriculture", {}).get("crops", {}) as Dictionary).size() == 2, "production save preserves both participant-owned crops")
	var character: Dictionary = hub.call("get_character_snapshot")
	_check(int(character.get("agriculture", {}).get("crop_count", 0)) == 2, "character diagnostics use bounded agriculture runtime data")
	_check(
		int(character.get("feature_lifecycle", {}).get("participant_count", 0)) == 6,
		"feature diagnostics expose all six lifecycle participants"
	)
	var batch_count := batches.size()
	hub.call("return_to_menu")
	_check(not bool(participant.call("get_lifecycle_snapshot").get("active", true)), "return-to-menu deactivates agriculture once")
	_check(int(agriculture.call("get_runtime_snapshot").get("crop_count", -1)) == 0, "return-to-menu clears agriculture runtime state")
	hub.call("_begin_world", loaded)
	hub.call("attach_game", world, null)
	coordinator.call("activate")
	await process_frame
	_check(int(agriculture.call("get_runtime_snapshot").get("crop_count", 0)) == 2, "complete reload restores participant-owned crops once")
	_check(batches.size() == batch_count, "reload does not replay maturity notifications")
	var history: Array = coordinator.call("get_snapshot").get("phase_history", [])
	hub.call("return_to_menu")
	history = coordinator.call("get_snapshot").get("phase_history", [])
	_check(
		not history.is_empty()
		and str(history.back()).contains(
			"exploration_journal_rewards,exploration_runtime,ranch_runtime,husbandry_runtime,agriculture_runtime,machine_runtime"
		),
		"reverse cleanup includes agriculture between husbandry and machine runtimes"
	)
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	world.queue_free()
	hub.queue_free()
	for _frame in 5:
		await process_frame


func _agriculture_state(
	crop_entries: Array,
	soil_positions: Array,
	manual_seconds: float = 0.0
) -> Dictionary:
	var crops: Dictionary = {}
	for raw_entry: Variant in crop_entries:
		var entry: Dictionary = raw_entry
		var position: Vector3i = entry.get("position", Vector3i.ZERO)
		crops["crop@%d,%d,%d" % [position.x, position.y, position.z]] = {
			"crop_id":str(entry.get("crop_id", "wheat")),
			"position":[position.x, position.y, position.z],
			"stage":int(entry.get("stage", 0)),
			"elapsed_seconds":float(entry.get("elapsed", 0.0)),
		}
	var soils: Dictionary = {}
	for raw_position: Variant in soil_positions:
		var position: Vector3i = raw_position
		soils["soil@%d,%d,%d" % [position.x, position.y, position.z]] = {
			"position":[position.x, position.y, position.z],
			"manual_remaining_seconds":manual_seconds,
			"hydrated":manual_seconds > 0.0,
		}
	return {
		"version":2,
		"saved_at_unix":int(Time.get_unix_time_from_system()),
		"crops":crops,
		"soil_moisture":{"version":1, "soils":soils},
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
