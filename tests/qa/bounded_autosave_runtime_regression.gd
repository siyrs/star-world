extends SceneTree

const AutosaveScript = preload("res://src/save/autosave_runtime_participant.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []


class FakePauseService:
	extends Node
	signal pause_changed(paused: bool)
	var _paused := false

	func set_paused(value: bool) -> void:
		if _paused == value:
			return
		_paused = value
		pause_changed.emit(_paused)

	func is_paused() -> bool:
		return _paused


class FakeHub:
	extends Node
	signal world_save_completed(world_id: String)
	signal settings_applied(settings: Dictionary)
	var simulation_pause: Node
	var current_settings: Dictionary = SettingsPolicy.defaults()
	var current_world_id := "fake-world"
	var save_results: Array[bool] = []
	var save_count := 0

	func save_current(_world_state: Dictionary = {}, _player_state: Dictionary = {}) -> bool:
		save_count += 1
		var success := true
		if not save_results.is_empty():
			success = bool(save_results.pop_front())
		if success:
			world_save_completed.emit(current_world_id)
		return success


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_settings_policy()
	await _test_active_time_pause_and_manual_reset()
	await _test_bounded_failure_backoff()
	await _test_production_composition_and_real_save()
	if failures.is_empty():
		print("QA BOUNDED AUTOSAVE RUNTIME PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED AUTOSAVE RUNTIME FAILURE: %s" % failure)
		print(
			"QA BOUNDED AUTOSAVE RUNTIME FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_settings_policy() -> void:
	_check(
		SettingsPolicy.allowed_autosave_minutes() == [0, 2, 5, 10, 15],
		"autosave settings expose one bounded deterministic choice list"
	)
	var normalized: Dictionary = SettingsPolicy.normalize({
		"mouse_sensitivity": INF,
		"render_distance": 99,
		"master_volume": -4.0,
		"cycle_minutes": 500,
		"autosave_minutes": 9,
		"show_tutorial": "not-a-bool",
		"unknown_setting": "discard",
	})
	_check(
		is_equal_approx(float(normalized.get("mouse_sensitivity", 0.0)), 0.18)
		and int(normalized.get("render_distance", 0)) == 5
		and is_zero_approx(float(normalized.get("master_volume", -1.0)))
		and int(normalized.get("cycle_minutes", 0)) == 30,
		"canonical settings policy normalizes invalid and out-of-range values"
	)
	_check(
		int(normalized.get("autosave_minutes", -1)) == 10,
		"unsupported autosave intervals normalize to the nearest allowed value"
	)
	_check(
		not normalized.has("unknown_setting")
		and normalized.keys().all(
			func(key: Variant) -> bool: return key in SettingsPolicy.DEFAULTS
		),
		"canonical settings use a strict persistence whitelist"
	)
	_check(
		SettingsPolicy.normalize_autosave_minutes(1) == 0,
		"equal-distance autosave normalization prefers the safer lower interval"
	)


func _test_active_time_pause_and_manual_reset() -> void:
	var fixture := _create_fake_fixture()
	var hub: FakeHub = fixture.hub
	var pause: FakePauseService = fixture.pause
	var runtime: Node = fixture.runtime
	_check(
		runtime.call("get_dependencies") == [
			&"machine_runtime",
			&"agriculture_runtime",
			&"husbandry_runtime",
			&"ranch_runtime",
			&"exploration_runtime",
			&"exploration_journal_rewards",
		],
		"autosave retains its six explicit compatibility dependencies"
	)
	runtime.call("begin_world", {"metadata":{"id":"fake-world"}})
	runtime.call("activate")
	runtime.call("configure_interval_minutes", 1.0)
	_check(
		not bool(runtime.call("advance_active_time", 59.0)),
		"autosave remains idle before the active-time interval"
	)
	_check(
		bool(runtime.call("advance_active_time", 1.0)),
		"autosave becomes due exactly at the active-time interval"
	)
	await _settle_deferred()
	var snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		hub.save_count == 1
		and int(snapshot.get("attempt_count", 0)) == 1
		and int(snapshot.get("success_count", 0)) == 1
		and is_zero_approx(float(snapshot.get("elapsed_active_seconds", -1.0))),
		"one due interval commits exactly one successful save and resets the clock"
	)

	runtime.call("configure_interval_minutes", 5.0)
	runtime.call("advance_active_time", 120.0)
	var before_settings: Dictionary = runtime.call("get_snapshot")
	hub.settings_applied.emit({"autosave_minutes":5, "render_distance":4})
	var after_settings: Dictionary = runtime.call("get_snapshot")
	_check(
		is_equal_approx(
			float(after_settings.get("elapsed_active_seconds", 0.0)),
			float(before_settings.get("elapsed_active_seconds", -1.0))
		)
		and int(after_settings.get("configuration_count", 0))
		== int(before_settings.get("configuration_count", -1)),
		"unrelated settings do not silently restart the autosave countdown"
	)
	hub.settings_applied.emit({"autosave_minutes":10})
	snapshot = runtime.call("get_snapshot")
	_check(
		is_equal_approx(float(snapshot.get("interval_minutes", 0.0)), 10.0)
		and is_zero_approx(float(snapshot.get("elapsed_active_seconds", -1.0))),
		"changing the autosave interval starts one new deterministic window"
	)

	runtime.call("configure_interval_minutes", 1.0)
	runtime.call("advance_active_time", 20.0)
	pause.set_paused(true)
	_check(
		not bool(runtime.call("advance_active_time", 120.0)),
		"real pause prevents autosave active-time advancement"
	)
	snapshot = runtime.call("get_snapshot")
	_check(
		bool(snapshot.get("paused", false))
		and is_equal_approx(float(snapshot.get("elapsed_active_seconds", 0.0)), 20.0),
		"paused time is excluded instead of becoming an immediate resume save"
	)
	pause.set_paused(false)
	_check(
		bool(runtime.call("advance_active_time", 40.0)),
		"active-time countdown resumes from the preserved pre-pause value"
	)
	var saves_before_manual := hub.save_count
	hub.save_current()
	await _settle_deferred()
	snapshot = runtime.call("get_snapshot")
	_check(
		hub.save_count == saves_before_manual + 1
		and not bool(snapshot.get("pending", true))
		and int(snapshot.get("manual_reset_count", 0)) >= 1,
		"manual save cancels a queued autosave and resets the same countdown"
	)

	var payload := {"sentinel":"kept"}
	runtime.call("save_into", payload)
	_check(
		payload == {"sentinel":"kept"},
		"autosave scheduling evidence never creates a second world persistence domain"
	)
	runtime.call("configure_interval_minutes", 0.0)
	_check(
		not bool(runtime.call("get_snapshot").get("enabled", true))
		and not bool(runtime.call("advance_active_time", 999.0)),
		"zero-minute configuration disables only automatic checkpoints"
	)
	runtime.call("shutdown")
	runtime.call("shutdown")
	_check(
		bool(runtime.call("get_snapshot").get("shutdown", false)),
		"autosave shutdown remains idempotent"
	)
	fixture.host.queue_free()
	await process_frame


func _test_bounded_failure_backoff() -> void:
	var fixture := _create_fake_fixture()
	var hub: FakeHub = fixture.hub
	var runtime: Node = fixture.runtime
	hub.save_results = [false, false, false, true]
	runtime.call("begin_world", {"metadata":{"id":"fake-world"}})
	runtime.call("activate")
	runtime.call("configure_interval_minutes", 10.0)
	var expected_delays := [15.0, 60.0, 300.0]
	var completion_snapshots: Array[Dictionary] = []
	runtime.connect(
		"autosave_completed",
		func(success: bool, snapshot: Dictionary) -> void:
			var recorded := snapshot.duplicate(true)
			recorded["signal_success"] = success
			completion_snapshots.append(recorded)
	)
	_check(
		bool(runtime.call("advance_active_time", 600.0)),
		"first full interval schedules the failure fixture"
	)
	for failure_index in expected_delays.size():
		await _settle_deferred()
		var snapshot: Dictionary = runtime.call("get_snapshot")
		var expected_delay: float = expected_delays[failure_index]
		_check(
			int(snapshot.get("consecutive_failure_count", 0)) == failure_index + 1
			and is_equal_approx(
				float(snapshot.get("last_retry_delay_seconds", 0.0)), expected_delay
			),
			"failure %d applies the bounded %.0f-second retry tier"
			% [failure_index + 1, expected_delay]
		)
		_check(
			is_equal_approx(
				float(snapshot.get("next_in_seconds", -1.0)), expected_delay
			),
			"failure %d exposes its exact next retry countdown" % (failure_index + 1)
		)
		_check(
			bool(runtime.call("advance_active_time", expected_delay)),
			"failure %d retries only after the configured active-time delay"
			% (failure_index + 1)
		)
	await _settle_deferred()
	var final_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		hub.save_count == 4
		and int(final_snapshot.get("attempt_count", 0)) == 4
		and int(final_snapshot.get("failure_count", 0)) == 3
		and int(final_snapshot.get("retry_count", 0)) == 3
		and int(final_snapshot.get("success_count", 0)) == 1,
		"three failures and one recovery produce exact bounded counters"
	)
	_check(
		int(final_snapshot.get("consecutive_failure_count", -1)) == 0
		and is_zero_approx(float(final_snapshot.get("last_retry_delay_seconds", -1.0)))
		and bool(final_snapshot.get("last_success", false)),
		"successful retry clears transient failure pressure"
	)
	_check(
		completion_snapshots.size() == 4
		and not bool(completion_snapshots[0].get("signal_success", true))
		and bool(completion_snapshots.back().get("signal_success", false)),
		"one completion fact is emitted for every real save attempt"
	)
	runtime.call("shutdown")
	fixture.host.queue_free()
	await process_frame


func _test_production_composition_and_real_save() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 5:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle") as Node
	var runtime: Node = hub.get("autosave_runtime_participant") as Node
	_check(
		coordinator != null
		and runtime != null
		and coordinator.has_participant(&"autosave_runtime"),
		"production service hub installs the bounded autosave participant"
	)
	_check(
		int(coordinator.call("get_snapshot").get("participant_count", 0)) == 8,
		"production lifecycle contains eight explicit participants"
	)
	_check(
		coordinator.call("get_participant_dependencies", &"autosave_runtime")
		== [
			"machine_runtime",
			"agriculture_runtime",
			"husbandry_runtime",
			"ranch_runtime",
			"exploration_runtime",
			"exploration_journal_rewards",
		],
		"production autosave retains six explicit ordering dependencies while final registration protects weather cleanup"
	)
	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	hub.main_menu.settings_changed.emit({"autosave_minutes":5})
	var initial_snapshot: Dictionary = runtime.call("get_snapshot") if runtime != null else {}
	_check(
		is_equal_approx(float(initial_snapshot.get("interval_minutes", 0.0)), 5.0),
		"production settings signal configures the autosave participant"
	)

	var state: Dictionary = hub.save_service.create_world(
		"qa-bounded-autosave-%d" % Time.get_ticks_msec(),
		"star_continent",
		26072026
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "production save service creates an autosave test world")
	if world_id.is_empty():
		await _finish_production_fixture(hub, runtime, original_settings, world_id)
		return
	hub.call("_begin_world", state)
	runtime.call("activate")
	runtime.set_process(false)
	runtime.call("configure_interval_minutes", 0.01)
	var apples_before := int(hub.inventory.call("count_item", "apple"))
	hub.inventory.call("add_item", "apple", 3)
	_check(
		int(hub.inventory.call("count_item", "apple")) == apples_before + 3,
		"production inventory contains an unsaved autosave mutation"
	)
	_check(
		bool(runtime.call("advance_active_time", 0.6)),
		"production autosave can be deterministically advanced by active time"
	)
	await _settle_deferred()
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check(
		_count_inventory_item(loaded.get("inventory", {}), "apple") == apples_before + 3,
		"real autosave transaction persists the production inventory mutation"
	)
	_check(
		not loaded.has("autosave"),
		"real world payload excludes transient autosave scheduling state"
	)
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(
		character_snapshot.has("autosave")
		and int(character_snapshot.get("autosave", {}).get("success_count", 0)) >= 1,
		"bounded autosave diagnostics are visible through the production snapshot"
	)

	hub.call(
		"_on_autosave_completed",
		false,
		{"last_retry_delay_seconds":60.0}
	)
	var feedback: Node = hub.player_experience.call("get_feedback") as Node
	var failure_toast: Dictionary = feedback.call("get_active_toast") if feedback != null else {}
	_check(
		str(failure_toast.get("text", "")).contains("60 秒后重试"),
		"composition layer converts a failure fact into an actionable retry message"
	)
	if feedback != null:
		feedback.call("clear")
	hub.call("_on_autosave_completed", true, runtime.call("get_snapshot"))
	var success_toast: Dictionary = feedback.call("get_active_toast") if feedback != null else {}
	_check(
		str(success_toast.get("text", "")) == "世界已自动保存",
		"composition layer presents successful automatic checkpoints"
	)

	hub.call("return_to_menu")
	var cleared_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		hub.current_world_id.is_empty()
		and not bool(cleared_snapshot.get("active", true))
		and str(cleared_snapshot.get("current_world_id", "")).is_empty(),
		"reverse lifecycle cleanup disables autosave before releasing world state"
	)
	await _finish_production_fixture(hub, runtime, original_settings, world_id)


func _create_fake_fixture() -> Dictionary:
	var host := FakeHub.new()
	var pause := FakePauseService.new()
	host.simulation_pause = pause
	root.add_child(host)
	host.add_child(pause)
	var runtime := AutosaveScript.new()
	host.add_child(runtime)
	_check(bool(runtime.call("install", host)), "autosave participant installs on a valid save hub")
	runtime.set_process(false)
	return {"host":host, "hub":host, "pause":pause, "runtime":runtime}


func _finish_production_fixture(
	hub: Node,
	runtime: Node,
	original_settings: Dictionary,
	world_id: String
) -> void:
	if hub != null and is_instance_valid(hub):
		hub.main_menu.settings_changed.emit(original_settings)
		if not world_id.is_empty() and hub.save_service.world_exists(world_id):
			hub.save_service.delete_world(world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
			_check(
				bool(audio.call("is_disposed")) and audio.get_child_count() == 0,
				"autosave fixture terminally disposes generated audio nodes"
			)
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
		var accessibility: Node = hub.get("ui_accessibility") as Node
		if accessibility != null and accessibility.has_method("dispose"):
			accessibility.call("dispose")
	if runtime != null and is_instance_valid(runtime):
		runtime.call("shutdown")
	if hub != null and is_instance_valid(hub):
		hub.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame


func _count_inventory_item(serialized: Dictionary, item_id: String) -> int:
	var total := 0
	var raw_slots: Variant = serialized.get("slots", [])
	if raw_slots is not Array:
		return 0
	for raw_slot: Variant in raw_slots:
		if raw_slot is Dictionary and str(raw_slot.get("item_id", "")) == item_id:
			total += maxi(0, int(raw_slot.get("count", 0)))
	return total


func _settle_deferred() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)