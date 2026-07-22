extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const AutomationPolicy = preload("res://src/machine/machine_automation_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://machine-scale-desktop.png"
const DOMAIN_MACHINE_COUNT := 256
const ACTIVE_MACHINE_COUNT := 128
const TOTAL_MACHINE_COUNT := DOMAIN_MACHINE_COUNT * 2
const GRID_COLUMNS := 32
const GRID_SPACING := 3
const AUTOMATION_FULL_PASSES := 32
const READY_FRAMES := 600
const CLEANUP_FRAMES := 10
const MAX_SETUP_MILLISECONDS := 30000.0
const MAX_AUTOMATION_MILLISECONDS := 30000.0
const MAX_PROCESS_MILLISECONDS := 30000.0
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_RELOAD_MILLISECONDS := 30000.0
const MAX_SAVE_BYTES := 3000000

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}
var _machine_records: Array[Dictionary] = []
var _completion_summaries: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Machine-Scale-%d" % Time.get_ticks_msec(),
		"star_continent",
		93451027
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "machine scale acceptance creates a temporary production world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a bounded ready state",
	)
	var world: Node = game.world
	var player: CharacterBody3D = game.player
	var scheduler: Node = hub.get("machine_runtime") as Node
	var participant: Node = hub.get("machine_runtime_participant") as Node
	var furnace: Node = hub.get("furnace_service") as Node
	var stonecutter: Node = hub.get("stonecutter_service") as Node
	var automation: Node = hub.get("machine_automation_service") as Node
	var containers: Node = hub.get("container_storage") as Node
	_check(
		world != null
		and player != null
		and scheduler != null
		and participant != null
		and furnace != null
		and stonecutter != null
		and automation != null
		and containers != null,
		"production machine scale services are mounted",
	)
	if (
		world == null
		or player == null
		or scheduler == null
		or participant == null
		or furnace == null
		or stonecutter == null
		or automation == null
		or containers == null
	):
		await _finish(game, hub)
		return
	participant.connect(
		"machine_batch_announced",
		func(summary: Dictionary) -> void:
			_completion_summaries.append(summary.duplicate(true))
	)
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var machine_y := clampi(player_block.y + 14, 24, 54)
	var base_x := player_block.x + 18
	var base_z := player_block.z - 24
	var fixture := _build_machine_fixture(base_x, base_z, machine_y)
	var mutations: Array = fixture.get("mutations", [])
	_machine_records = fixture.get("records", [])
	_check(
		_machine_records.size() == TOTAL_MACHINE_COUNT,
		"scale fixture contains five hundred twelve production machines",
	)
	_check(
		mutations.size() > 1200 and mutations.size() <= 4096,
		"machine field uses a bounded shared world mutation batch",
	)
	_force_load_mutation_chunks(world, mutations)
	world.call("reset_chunk_rebuild_stats")
	var setup_started := Time.get_ticks_usec()
	var setup_result: Dictionary = world.call(
		"apply_block_mutations", mutations, "machine_scale_fixture"
	)
	var setup_milliseconds := float(Time.get_ticks_usec() - setup_started) / 1000.0
	_check(bool(setup_result.get("success", false)), "machine field blocks commit through the production batch API")
	_check(
		int(setup_result.get("changed", 0)) > 1200,
		"machine fixture changes the expected world scale",
	)
	_check(setup_milliseconds <= MAX_SETUP_MILLISECONDS, "machine field setup stays inside thirty seconds")

	var registration_started := Time.get_ticks_usec()
	for record: Dictionary in _machine_records:
		var service: Node = furnace if str(record.get("machine_type", "")) == "furnace" else stonecutter
		var machine_id := str(record.get("machine_id", ""))
		_check(bool(service.call("open_machine", machine_id)), "production machine registers %s" % machine_id)
		service.call("close_machine")
		if not bool(record.get("active", false)):
			continue
		var input_container_id := str(record.get("input_container_id", ""))
		var output_container_id := str(record.get("output_container_id", ""))
		_check(
			not (containers.call("ensure_container", input_container_id, "chest", 27) as Dictionary).is_empty()
			and not (containers.call("ensure_container", output_container_id, "chest", 27) as Dictionary).is_empty(),
			"active machine has production input and output containers",
		)
		if str(record.get("machine_type", "")) == "furnace":
			_check(int(containers.call("add_item", input_container_id, "raw_iron", 1)) == 0, "furnace input chest receives raw iron")
			_check(int(containers.call("add_item", input_container_id, "coal", 1)) == 0, "furnace input chest receives fuel")
		else:
			_check(int(containers.call("add_item", input_container_id, "stone", 1)) == 0, "stonecutter input chest receives stone")
	var registration_milliseconds := float(Time.get_ticks_usec() - registration_started) / 1000.0
	var before_automation: Dictionary = automation.call("get_runtime_snapshot")
	_check(
		int(before_automation.get("tracked_machine_count", 0)) == TOTAL_MACHINE_COUNT
		and int(before_automation.get("candidate_sort_count", -1)) == 0,
		"event-maintained automation directory contains all machines without repeated sorting",
	)

	var automation_started := Time.get_ticks_usec()
	for _cycle in AUTOMATION_FULL_PASSES:
		scheduler.call("advance_time", 0.5, true)
	var feed_milliseconds := float(Time.get_ticks_usec() - automation_started) / 1000.0
	_check(feed_milliseconds <= MAX_AUTOMATION_MILLISECONDS, "full candidate feed pass remains inside thirty seconds")
	var after_feed: Dictionary = automation.call("get_runtime_snapshot")
	_check(
		int(after_feed.get("candidate_sort_count", 0)) == 1
		and int(after_feed.get("total_input_items", 0)) == 384,
		"five hundred twelve candidates sort once and feed all active machines exactly",
	)

	var process_started := Time.get_ticks_usec()
	scheduler.call("advance_time", 6.5, true)
	var process_milliseconds := float(Time.get_ticks_usec() - process_started) / 1000.0
	var summary: Dictionary = participant.call("flush_pending_completion_batch")
	_check(process_milliseconds <= MAX_PROCESS_MILLISECONDS, "all active machines finish inside thirty seconds")
	_check(
		int(summary.get("completed_jobs", 0)) == ACTIVE_MACHINE_COUNT * 2
		and int(summary.get("item_total", 0)) == 384
		and int(summary.get("machine_count", 0)) == ACTIVE_MACHINE_COUNT * 2,
		"completion feedback preserves all two hundred fifty-six jobs and outputs",
	)
	_check(
		int(summary.get("sampled_event_count", 0)) == 64
		and int(summary.get("dropped_event_samples", 0)) == 192
		and int(summary.get("dropped_event_count", -1)) == 0,
		"completion diagnostics bound samples without dropping valid machine events",
	)
	_check(
		_completion_summaries.size() == 1,
		"synchronous multi-machine completion produces one player-facing summary",
	)
	var representative_id := _find_machine_with_output(furnace, "furnace")
	_check(not representative_id.is_empty(), "at least one completed furnace retains output for UI evidence")
	if not representative_id.is_empty():
		_check(
			bool(hub.game_ui.open_furnace(representative_id, "规模化共享调度熔炉")),
			"real furnace overlay opens a completed indexed machine",
		)
		var panel: Node = hub.game_ui.get_furnace_panel()
		if panel != null:
			panel.call("refresh")
			var output_button: Button = panel.get("_output_button") as Button
			_check(
				output_button != null
				and output_button.text.contains("铁锭")
				and output_button.icon != null,
				"scale evidence displays the real machine output icon and count",
			)
	_report = _build_report(
		setup_result,
		setup_milliseconds,
		registration_milliseconds,
		feed_milliseconds,
		process_milliseconds,
		furnace,
		stonecutter,
		automation,
		summary
	)
	await _capture_visual_evidence(game, player, base_x, base_z, machine_y)

	var output_started := Time.get_ticks_usec()
	for _cycle in AUTOMATION_FULL_PASSES:
		scheduler.call("advance_time", 0.5, true)
	var output_milliseconds := float(Time.get_ticks_usec() - output_started) / 1000.0
	_report["output_automation_milliseconds"] = output_milliseconds
	_check(output_milliseconds <= MAX_AUTOMATION_MILLISECONDS, "full output collection pass remains inside thirty seconds")
	var collected := _verify_output_containers(containers)
	_check(int(collected.get("furnace_outputs", 0)) == ACTIVE_MACHINE_COUNT, "all furnace outputs reach lower chests")
	_check(int(collected.get("stonecutter_outputs", 0)) == ACTIVE_MACHINE_COUNT * 2, "all stonecutter outputs reach lower chests")
	var final_automation: Dictionary = automation.call("get_runtime_snapshot")
	_check(
		int(final_automation.get("total_output_items", 0)) == 384
		and int(final_automation.get("candidate_sort_count", 0)) == 1,
		"output collection preserves exact throughput without another directory sort",
	)
	_report["automation"] = final_automation.duplicate(true)
	_report["collected_outputs"] = collected.duplicate(true)

	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.save_current())
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	_check(saved, "large machine field joins the production atomic save transaction")
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "machine scale save remains below three megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "machine scale save remains inside ten seconds")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "machine scale world reloads from the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "machine scale JSON load remains inside ten seconds")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("activity_index")
		and not serialized.contains("candidate_sort_count")
		and not serialized.contains("completion_event_samples")
		and not serialized.contains("scheduler_call_count"),
		"machine indexes, samples and runtime counters remain transient",
	)
	_report["save_bytes"] = save_bytes
	_report["save_milliseconds"] = save_milliseconds
	_report["load_milliseconds"] = load_milliseconds

	var summaries_before_reload := _completion_summaries.size()
	var reload_started := Time.get_ticks_usec()
	hub.return_to_menu()
	for _frame in 10:
		await process_frame
	game.begin_world_state(loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full machine scale reload reaches a bounded playable state",
	)
	var reload_milliseconds := float(Time.get_ticks_usec() - reload_started) / 1000.0
	_check(reload_milliseconds <= MAX_RELOAD_MILLISECONDS, "machine scale first playable reload remains inside thirty seconds")
	furnace = hub.get("furnace_service") as Node
	stonecutter = hub.get("stonecutter_service") as Node
	automation = hub.get("machine_automation_service") as Node
	containers = hub.get("container_storage") as Node
	_check(
		int(furnace.call("get_runtime_snapshot").get("machine_count", 0)) == DOMAIN_MACHINE_COUNT
		and int(stonecutter.call("get_runtime_snapshot").get("machine_count", 0)) == DOMAIN_MACHINE_COUNT,
		"full reload restores both machine domains exactly once",
	)
	var reloaded_outputs := _verify_output_containers(containers)
	_check(reloaded_outputs == collected, "full reload restores all collected outputs without duplication")
	_check(_completion_summaries.size() == summaries_before_reload, "world reload does not replay completion feedback")
	var reloaded_automation: Dictionary = automation.call("get_runtime_snapshot")
	_check(
		int(reloaded_automation.get("candidate_sort_count", -1)) == 0
		and int(reloaded_automation.get("total_transfer_count", -1)) == 0,
		"new world session starts with clean transient automation diagnostics",
	)
	_report["reload_ready_milliseconds"] = reload_milliseconds
	_write_report()
	await _finish(game, hub)


func _build_machine_fixture(base_x: int, base_z: int, machine_y: int) -> Dictionary:
	var mutations: Array = []
	var records: Array[Dictionary] = []
	for global_index in TOTAL_MACHINE_COUNT:
		var furnace_domain := global_index < DOMAIN_MACHINE_COUNT
		var domain_index := global_index if furnace_domain else global_index - DOMAIN_MACHINE_COUNT
		var active := domain_index < ACTIVE_MACHINE_COUNT
		var column := global_index % GRID_COLUMNS
		var row := int(global_index / GRID_COLUMNS)
		var position := Vector3i(
			base_x + column * GRID_SPACING,
			machine_y,
			base_z + row * GRID_SPACING
		)
		var machine_type := "furnace" if furnace_domain else "stonecutter"
		var block_id := machine_type
		var machine_id := "%s@%d,%d,%d" % [machine_type, position.x, position.y, position.z]
		mutations.append({"position": position + Vector3i.DOWN * 2, "block_id": "stone_bricks"})
		mutations.append({"position": position, "block_id": block_id})
		var input_container_id := ""
		var output_container_id := ""
		if active:
			var input_position := AutomationPolicy.input_position(position)
			var output_position := AutomationPolicy.output_position(position)
			mutations.append({"position": input_position, "block_id": "chest"})
			mutations.append({"position": output_position, "block_id": "chest"})
			input_container_id = AutomationPolicy.container_id(input_position)
			output_container_id = AutomationPolicy.container_id(output_position)
		records.append({
			"machine_type": machine_type,
			"machine_id": machine_id,
			"position": position,
			"active": active,
			"input_container_id": input_container_id,
			"output_container_id": output_container_id,
		})
	return {"mutations": mutations, "records": records}


func _find_machine_with_output(service: Node, machine_type: String) -> String:
	for record: Dictionary in _machine_records:
		if str(record.get("machine_type", "")) != machine_type or not bool(record.get("active", false)):
			continue
		var machine_id := str(record.get("machine_id", ""))
		var output: Dictionary = service.call("get_slot", machine_id, "output")
		if int(output.get("count", 0)) > 0:
			return machine_id
	return ""


func _verify_output_containers(containers: Node) -> Dictionary:
	var furnace_outputs := 0
	var stonecutter_outputs := 0
	var nonempty_output_containers := 0
	for record: Dictionary in _machine_records:
		if not bool(record.get("active", false)):
			continue
		var container_id := str(record.get("output_container_id", ""))
		var item_id := "iron_ingot" if str(record.get("machine_type", "")) == "furnace" else "stone_stairs"
		var count := _count_container_item(containers, container_id, item_id)
		if count > 0:
			nonempty_output_containers += 1
		if str(record.get("machine_type", "")) == "furnace":
			furnace_outputs += count
		else:
			stonecutter_outputs += count
	return {
		"furnace_outputs": furnace_outputs,
		"stonecutter_outputs": stonecutter_outputs,
		"nonempty_output_containers": nonempty_output_containers,
	}


func _count_container_item(containers: Node, container_id: String, item_id: String) -> int:
	var total := 0
	var slot_count := int(containers.call("get_slot_count", container_id))
	for index in slot_count:
		var slot: Dictionary = containers.call("get_slot", container_id, index)
		if str(slot.get("item_id", "")) == item_id:
			total += maxi(0, int(slot.get("count", 0)))
	return total


func _build_report(
	setup_result: Dictionary,
	setup_milliseconds: float,
	registration_milliseconds: float,
	feed_milliseconds: float,
	process_milliseconds: float,
	furnace: Node,
	stonecutter: Node,
	automation: Node,
	summary: Dictionary
) -> Dictionary:
	var rebuild: Dictionary = setup_result.get("rebuild", {})
	return {
		"schema_version": 1,
		"world_id": _world_id,
		"machine_count": TOTAL_MACHINE_COUNT,
		"active_machine_count": ACTIVE_MACHINE_COUNT * 2,
		"furnace_count": DOMAIN_MACHINE_COUNT,
		"stonecutter_count": DOMAIN_MACHINE_COUNT,
		"world_mutation_count": int(setup_result.get("requested", 0)),
		"world_changed_count": int(setup_result.get("changed", 0)),
		"world_rebuild_requests": int(rebuild.get("request_count", 0)),
		"world_rebuild_executions": int(rebuild.get("execution_count", 0)),
		"world_rebuild_coalesced": int(rebuild.get("coalesced_count", 0)),
		"setup_milliseconds": setup_milliseconds,
		"registration_milliseconds": registration_milliseconds,
		"feed_automation_milliseconds": feed_milliseconds,
		"processing_milliseconds": process_milliseconds,
		"completion_summary": summary.duplicate(true),
		"furnace_runtime": furnace.call("get_runtime_snapshot"),
		"stonecutter_runtime": stonecutter.call("get_runtime_snapshot"),
		"automation_runtime": automation.call("get_runtime_snapshot"),
	}


func _capture_visual_evidence(
	game: Node3D,
	player: CharacterBody3D,
	base_x: int,
	base_z: int,
	machine_y: int
) -> void:
	player.set_physics_process(false)
	player.global_position = Vector3(
		base_x + GRID_COLUMNS * GRID_SPACING * 0.5,
		machine_y + 42.0,
		base_z - 42.0
	)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.get_view_camera().look_at(
		Vector3(
			base_x + GRID_COLUMNS * GRID_SPACING * 0.5,
			machine_y,
			base_z + 8.0 * GRID_SPACING
		),
		Vector3.UP
	)
	_add_metric_overlay(game)
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders the machine scale fixture")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "machine scale evidence uses 1024x576 product resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var error := image.save_png(_capture_path)
		_check(error == OK and FileAccess.file_exists(_capture_path), "machine scale screenshot is saved")
	player.set_physics_process(true)


func _add_metric_overlay(game: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "MachineScaleEvidence"
	layer.layer = 96
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(455, 225)
	var label := Label.new()
	var furnace_runtime: Dictionary = _report.get("furnace_runtime", {})
	var stone_runtime: Dictionary = _report.get("stonecutter_runtime", {})
	var automation_runtime: Dictionary = _report.get("automation_runtime", {})
	var summary: Dictionary = _report.get("completion_summary", {})
	label.text = (
		"MACHINE SCALE ACCEPTANCE\n"
		+ "Machines  %d total / %d active jobs\n"
		+ "Completion  %d jobs / %d items / %d samples\n"
		+ "Furnace eval  %d  |  idle avoided %d\n"
		+ "Stonecutter eval  %d  |  idle avoided %d\n"
		+ "Automation candidates %d  |  sorts %d\n"
		+ "Input throughput %d items\n"
		+ "World rebuilds %d requests → %d executions"
	) % [
		TOTAL_MACHINE_COUNT,
		ACTIVE_MACHINE_COUNT * 2,
		int(summary.get("completed_jobs", 0)),
		int(summary.get("item_total", 0)),
		int(summary.get("sampled_event_count", 0)),
		int(furnace_runtime.get("evaluated_machine_count", 0)),
		int(furnace_runtime.get("avoided_idle_evaluation_count", 0)),
		int(stone_runtime.get("evaluated_machine_count", 0)),
		int(stone_runtime.get("avoided_idle_evaluation_count", 0)),
		int(automation_runtime.get("tracked_machine_count", 0)),
		int(automation_runtime.get("candidate_sort_count", 0)),
		int(automation_runtime.get("total_input_items", 0)),
		int(_report.get("world_rebuild_requests", 0)),
		int(_report.get("world_rebuild_executions", 0)),
	]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	layer.add_child(panel)
	game.add_child(layer)


func _force_load_mutation_chunks(world: Node, mutations: Array) -> void:
	var coords: Dictionary = {}
	for raw_change: Variant in mutations:
		if raw_change is not Dictionary:
			continue
		var position := _vector3i_from((raw_change as Dictionary).get("position", []))
		coords[world.call("block_to_chunk", position)] = true
	for raw_coord: Variant in coords.keys():
		world.call("force_load_chunk", Vector2i(raw_coord))


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		var runtime: Node = hub.get("machine_runtime") as Node
		if (
			world != null
			and player != null
			and runtime != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(hub.get("current_world_id")) == expected_world_id
			and bool(runtime.call("is_active"))
		):
			return true
	return false


func _file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


func _write_report() -> void:
	_report["capture_path"] = _capture_path
	_report["report_path"] = _report_path
	_report["checks"] = checks
	_report["failure_count"] = failures.size()
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "machine scale JSON report can be opened")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "\t", false))
	file.flush()
	file.close()
	_check(FileAccess.file_exists(_report_path), "machine scale JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA MACHINE SCALE DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE SCALE DESKTOP FAILURE: %s" % failure)
		print(
			"QA MACHINE SCALE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
