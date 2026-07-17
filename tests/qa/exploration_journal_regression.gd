extends SceneTree

const JournalRegistryScript = preload("res://src/exploration/exploration_journal_registry.gd")
const JournalPolicyScript = preload("res://src/exploration/exploration_journal_policy.gd")
const JournalServiceScript = preload("res://src/exploration/exploration_journal_service.gd")
const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const ProspectingMigrationScript = preload("res://src/exploration/prospecting_state_migration.gd")
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const InputActionsScript = preload("res://src/input/gameplay_input_actions.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const ExtensionOverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var profile_id := "star_continent"

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(floori(float(position.x) / 16.0), floori(float(position.z) / 16.0))

	func get_initial_block(position: Vector3i) -> String:
		if posmod(position.x + position.y + position.z, 11) == 0:
			return "diamond_ore"
		if posmod(position.x * 2 - position.y + position.z, 7) == 0:
			return "iron_ore"
		if posmod(position.x - position.z + position.y, 5) == 0:
			return "coal_ore"
		return "stone"


class FakeDanger:
	extends Node

	func get_snapshot() -> Dictionary:
		return {
			"tier_id":"dangerous",
			"tier_label":"危险",
			"score":72,
			"reasons":["夜晚", "附近敌对生物"],
		}


class FakeClock:
	extends Node
	var day_count := 3
	var time_of_day := 14.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1024, 576)
	_test_registry_and_overlay_contracts()
	_test_migration_safety()
	await _test_service_stable_ordering()
	_test_journal_policy()
	await _test_production_ui_contract()
	if failures.is_empty():
		print("QA EXPLORATION JOURNAL PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION JOURNAL FAILURE: %s" % failure)
		print("QA EXPLORATION JOURNAL FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_overlay_contracts() -> void:
	var registry = JournalRegistryScript.new()
	_check(registry.schema_version == 1, "exploration journal schema version is stable")
	_check(registry.get_validation_errors().is_empty(), "exploration journal data has no validation errors")
	_check(registry.get_milestones().size() == 7, "production exploration journal exposes seven milestones")
	_check(int(registry.get_config().get("max_visible_records", 0)) == 24, "journal visible history is bounded")
	_check(ExtensionOverlayIds.has_unique_ids(), "feature overlay ids are unique and outside the base range")
	_check(ExtensionOverlayIds.REPAIR == 7, "repair overlay keeps its compatibility id")
	_check(ExtensionOverlayIds.EXPLORATION_JOURNAL == 8, "journal receives a non-conflicting extension id")
	InputActionsScript.ensure_default_bindings()
	_check(InputMap.has_action(InputActionsScript.TOGGLE_EXPLORATION_JOURNAL), "journal input action exists")
	var has_j_binding := false
	for event: InputEvent in InputMap.action_get_events(InputActionsScript.TOGGLE_EXPLORATION_JOURNAL):
		if event is InputEventKey and (event.keycode == KEY_J or event.physical_keycode == KEY_J):
			has_j_binding = true
			break
	_check(has_j_binding, "journal input action retains the J key")
	var context = InputContextScript.new()
	root.add_child(context)
	_check(context.set_context(InputContextScript.CONTEXT_JOURNAL), "journal is a valid input context")
	_check(not context.is_gameplay_input_enabled(), "journal context blocks player gameplay input")
	context.queue_free()


func _test_migration_safety() -> void:
	var raw_state := {
		"version": 1,
		"records": [
			_make_record("0,0:middle", [0,0], 90, "middle", "normal", "safe"),
			_make_record("1,0:deep", [1,0], 4, "deep", "promising", "dangerous"),
			{
				"record_key":"0,0:middle",
				"chunk":[0,0],
				"profile_id":"abyss_world",
				"depth_band_id":"middle",
				"depth_label":"中层",
				"density_id":"rich",
				"density_label":"富集",
				"ore_ratio":0.25,
				"dominant_block_id":"diamond_ore",
				"dominant_label":"钻石矿",
				"danger_tier_id":"severe",
				"danger_label":"极高",
				"danger_score":96,
				"danger_reasons":["岩浆", "岩浆", "夜晚", "敌对生物", "深层", "洞穴", "额外原因"],
				"message":"更新记录",
				"world_day":5,
				"world_time":27.25,
				"positions":[[1,2,3]],
			},
		],
		"last_result":{
			"handled":true,
			"success":true,
			"record_key":"0,0:middle",
			"chunk":[0,0],
			"profile_id":"abyss_world",
			"depth_band_id":"middle",
			"density_id":"rich",
			"danger_tier_id":"severe",
			"danger_score":96,
			"message":"更新记录",
			"positions":[[1,2,3]],
			"ore_positions":[[4,5,6]],
			"coordinates":[7,8,9],
			"secret":"must not survive",
		},
	}
	var normalized := ProspectingMigrationScript.normalize_exploration_state(raw_state)
	_check(int(normalized.get("version", 0)) == 3, "legacy exploration state migrates to version 3")
	var records: Array = normalized.get("records", [])
	_check(records.size() == 2, "duplicate record keys collapse to the newest entry")
	_check(str(records[0].get("record_key", "")) == "1,0:deep", "dedupe preserves relative order of surviving records")
	_check(str(records[1].get("record_key", "")) == "0,0:middle", "newest duplicate moves to the journal tail")
	_check(int(records[0].get("sequence", 0)) == 1 and int(records[1].get("sequence", 0)) == 2, "migration assigns stable monotonic sequences")
	_check(int(records[1].get("world_day", 0)) == 5, "migration preserves in-world discovery day")
	_check(is_equal_approx(float(records[1].get("world_time", 0.0)), 3.25), "migration normalizes in-world discovery time")
	_check((records[1].get("danger_reasons", []) as Array).size() <= 6, "migration bounds and deduplicates danger reasons")
	var last_result: Dictionary = normalized.get("last_result", {})
	_check(int(last_result.get("sequence", 0)) == 2, "matching last result inherits the canonical sequence")
	_check(not last_result.has("positions") and not last_result.has("ore_positions") and not last_result.has("coordinates"), "last result strips exact coordinate fields")
	_check(not last_result.has("secret"), "last result uses a strict persistence whitelist")


func _test_service_stable_ordering() -> void:
	var item_registry = ItemRegistryScript.new()
	_check(item_registry.load_from_file(), "production item registry loads for journal service tests")
	var prospecting = ProspectingServiceScript.new()
	var danger := FakeDanger.new()
	var clock := FakeClock.new()
	var world := FakeWorld.new()
	var player := Node3D.new()
	root.add_child(prospecting)
	root.add_child(danger)
	root.add_child(clock)
	root.add_child(world)
	root.add_child(player)
	_check(prospecting.setup(item_registry, danger, clock), "prospecting accepts the journal clock dependency")
	player.global_position = Vector3(2.5, 20.0, 2.5)
	prospecting.attach_world(world, player)
	var first: Dictionary = prospecting.use_item("prospecting_kit", 1000)
	_check(bool(first.get("success", false)), "first discovery succeeds")
	_check(int(first.get("sequence", 0)) == 1, "first discovery starts sequence one")
	_check(int(first.get("world_day", 0)) == 3 and is_equal_approx(float(first.get("world_time", 0.0)), 14.5), "discovery captures the in-world clock")
	clock.day_count = 4
	clock.time_of_day = 21.25
	var refreshed: Dictionary = prospecting.use_item("prospecting_kit", 2100)
	_check(bool(refreshed.get("success", false)), "same area can be refreshed after cooldown")
	_check(int(prospecting.get_snapshot().get("record_count", 0)) == 1, "refreshing one record does not duplicate journal rows")
	_check(int(prospecting.get_record(str(refreshed.get("record_key", ""))).get("sequence", 0)) == 2, "refreshed record receives the newest sequence")
	player.global_position = Vector3(34.5, 20.0, 2.5)
	clock.day_count = 5
	clock.time_of_day = 6.0
	var second: Dictionary = prospecting.use_item("prospecting_kit", 3200)
	_check(bool(second.get("success", false)) and int(second.get("sequence", 0)) == 3, "new area advances the stable sequence")
	_check(int(prospecting.get_snapshot().get("record_count", 0)) == 2, "new chunk adds one journal row")
	var serialized := prospecting.serialize()
	_check(int(serialized.get("version", 0)) == 3, "prospecting serializes the hardened version 3 contract")
	var restored = ProspectingServiceScript.new()
	root.add_child(restored)
	restored.setup(item_registry, danger, clock)
	restored.deserialize(serialized)
	var restored_records := restored.get_records()
	_check(restored_records.size() == 2, "stable records survive reload")
	_check(int(restored_records[0].get("sequence", 0)) == 1 and int(restored_records[1].get("sequence", 0)) == 2, "reload compacts sequence gaps without changing order")
	restored.attach_world(world, player)
	player.global_position = Vector3(50.5, 20.0, 2.5)
	var third: Dictionary = restored.use_item("prospecting_kit", 5000)
	_check(int(third.get("sequence", 0)) == 3, "post-reload discovery continues after the restored order")
	var journal = JournalServiceScript.new()
	root.add_child(journal)
	_check(journal.setup(restored), "journal service accepts prospecting as its single record source")
	_check(int(journal.get_snapshot().get("record_count", 0)) == 3, "journal service derives the restored discovery count")
	journal.queue_free()
	prospecting.queue_free()
	restored.queue_free()
	danger.queue_free()
	clock.queue_free()
	world.queue_free()
	player.queue_free()
	await process_frame
	await process_frame


func _test_journal_policy() -> void:
	var registry = JournalRegistryScript.new()
	var records: Array[Dictionary] = []
	var depth_ids: Array[String] = ["upper", "middle", "lower", "deep"]
	for index in 12:
		var density_id := "rich" if index == 2 else "normal"
		var danger_id := "severe" if index == 5 else "safe"
		var record := _make_record(
			"%d,0:%s" % [index, depth_ids[index % depth_ids.size()]],
			[index, 0],
			index + 1,
			depth_ids[index % depth_ids.size()],
			density_id,
			danger_id
		)
		record["world_day"] = 1 + index / 3
		record["world_time"] = float(index * 2)
		records.append(record)
	var snapshot := JournalPolicyScript.build_snapshot(records, registry.get_config())
	_check(int(snapshot.get("record_count", 0)) == 12, "journal policy counts bounded records")
	_check(int(snapshot.get("unique_chunk_count", 0)) == 12, "journal policy counts unique chunks")
	_check(int(snapshot.get("depth_band_count", 0)) == 4, "journal policy detects all four depth bands")
	_check(int(snapshot.get("rich_count", 0)) == 1, "journal policy detects rich discoveries")
	_check(int(snapshot.get("completed_milestone_count", 0)) == 7, "complete exploration history unlocks all production milestones")
	var visible_records: Array = snapshot.get("records", [])
	_check(int(visible_records[0].get("sequence", 0)) == 12, "journal policy presents newest discoveries first")
	_check(JournalPolicyScript.map_label("abyss_world") == "深渊世界", "journal policy resolves player-facing map names")


func _test_production_ui_contract() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var journal: Node = hub.get("exploration_journal_service")
	var prospecting: Node = hub.get("prospecting_service")
	var game_ui: Node = hub.get("game_ui")
	_check(journal != null and prospecting != null, "production service hub composes journal and prospecting services")
	_check(game_ui != null and game_ui.has_method("get_exploration_journal_panel"), "production GameUI exposes the journal panel")
	if journal == null or prospecting == null or game_ui == null:
		hub.queue_free()
		await process_frame
		return
	var records: Array[Dictionary] = []
	for index in 4:
		records.append(
			_make_record(
				"%d,1:middle" % index,
				[index, 1],
				index + 1,
				"middle",
				"rich" if index == 3 else "normal",
				"dangerous" if index == 3 else "safe"
			)
		)
	prospecting.call("deserialize", {"version":3, "records":records, "last_result":{}})
	journal.call("refresh")
	game_ui.call("begin_gameplay")
	_check(bool(game_ui.call("open_exploration_journal")), "production GameUI opens the journal")
	await process_frame
	var panel: Node = game_ui.call("get_exploration_journal_panel")
	_check(int(game_ui.call("get_active_overlay")) == ExtensionOverlayIds.EXPLORATION_JOURNAL, "journal uses its non-conflicting production overlay id")
	_check(str(hub.input_context.call("get_context")) == str(InputContextScript.CONTEXT_JOURNAL), "opening the journal switches to the journal input context")
	_check(panel != null and bool(panel.get("visible")), "production journal panel becomes visible")
	if panel != null:
		var summary := str(panel.call("get_summary_text"))
		var record_texts: Array = panel.call("get_record_texts")
		_check(summary.contains("已记录 4 条发现"), "journal summary uses the authoritative derived count")
		_check(record_texts.size() == 4, "journal panel renders all available recent records")
		_check(str(record_texts[0]).begins_with("#4"), "journal panel renders newest sequence first")
		_check(not str(record_texts).contains("ore_positions") and not str(record_texts).contains("coordinates"), "journal panel never renders forbidden coordinate payloads")
		var rects: Dictionary = panel.call("get_layout_rects")
		var panel_rect: Rect2 = rects.get("panel", Rect2())
		_check(panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0, "journal panel stays inside the compact viewport origin")
		_check(panel_rect.end.x <= 1024.0 and panel_rect.end.y <= 576.0, "journal panel fits the 1024x576 product contract")
	game_ui.call("toggle_exploration_journal")
	await process_frame
	_check(int(game_ui.call("get_active_overlay")) == 0, "J toggle closes the journal overlay")
	_check(str(hub.input_context.call("get_context")) == str(InputContextScript.CONTEXT_GAMEPLAY), "closing the journal restores gameplay context")
	game_ui.call("end_gameplay")
	hub.queue_free()
	await process_frame
	await process_frame


func _make_record(
	record_key: String,
	chunk: Array,
	sequence: int,
	depth_id: String,
	density_id: String,
	danger_id: String
) -> Dictionary:
	var depth_labels := {"upper":"浅层", "middle":"中层", "lower":"下层", "deep":"深层"}
	var density_labels := {"normal":"普通", "promising":"可观", "rich":"富集"}
	var danger_labels := {"safe":"低", "dangerous":"危险", "severe":"极高"}
	return {
		"record_key":record_key,
		"chunk":chunk.duplicate(),
		"profile_id":"abyss_world" if danger_id != "safe" else "star_continent",
		"depth_band_id":depth_id,
		"depth_label":str(depth_labels.get(depth_id, "未知")),
		"density_id":density_id,
		"density_label":str(density_labels.get(density_id, "普通")),
		"ore_ratio":0.08 if density_id == "rich" else 0.03,
		"dominant_block_id":"iron_ore",
		"dominant_label":"铁矿",
		"danger_tier_id":danger_id,
		"danger_label":str(danger_labels.get(danger_id, "未知")),
		"danger_score":92 if danger_id == "severe" else (72 if danger_id == "dangerous" else 18),
		"danger_reasons":["夜晚"] if danger_id != "safe" else [],
		"message":"粗粒度趋势",
		"sequence":sequence,
		"world_day":2,
		"world_time":8.5,
		"scanned_at_msec":sequence * 100,
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
