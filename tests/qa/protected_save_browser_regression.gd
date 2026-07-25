extends SceneTree

const ProtectedPanelScript = preload(
	"res://src/ui/protected_save_browser_panel.gd"
)

var checks := 0
var failures: Array[String] = []


class FakeProtectedSaveService:
	extends Node

	var worlds: Array = []
	var trash_entries: Array[Dictionary] = []
	var list_count := 0
	var trash_call_count := 0
	var restore_call_count := 0
	var permanent_delete_call_count := 0
	var reject_with_trash_full := false

	func _init() -> void:
		for index in 4:
			worlds.append({
				"id": "protected-world-%d" % index,
				"name": "Protected World %d" % index,
				"map_id": "star_continent",
				"seed": 1600000 + index,
				"updated_at": "2026-07-25T00:0%d:00" % index,
				"save_bytes": 4096 + index,
			})

	func list_worlds() -> Array:
		list_count += 1
		return worlds

	func get_catalog_diagnostics() -> Dictionary:
		return {
			"last_world_count": worlds.size(),
			"last_elapsed_milliseconds": 1.0,
			"last_deferred_recovery_count": 0,
			"primary_repair_budget": 8,
			"last_deferred_authoritative_read_count": 0,
			"authoritative_read_budget": 32,
			"last_deferred_catalog_rebuild_count": 0,
			"catalog_rebuild_budget": 16,
			"staged_catalog_entry_count": 0,
			"catalog_stage_capacity": 64,
			"last_stage_hit_count": 0,
		}

	func get_recovery_diagnostics() -> Dictionary:
		return {}

	func trash_world(world_id: String) -> Dictionary:
		trash_call_count += 1
		if reject_with_trash_full:
			return {"ok": false, "reason": "trash_full"}
		for index in range(worlds.size() - 1, -1, -1):
			var metadata: Dictionary = worlds[index]
			if str(metadata.get("id", "")) != world_id:
				continue
			worlds.remove_at(index)
			var trash_id := "%s-trashed-%d" % [world_id, trash_call_count]
			var entry := metadata.duplicate(true)
			entry["trash_id"] = trash_id
			entry["world_id"] = world_id
			trash_entries.push_front(entry)
			return {
				"ok": true,
				"reason": "ok",
				"world_id": world_id,
				"trash_id": trash_id,
				"entry": entry,
			}
		return {"ok": false, "reason": "world_missing"}

	func restore_trashed_world(trash_id: String) -> Dictionary:
		restore_call_count += 1
		for index in range(trash_entries.size() - 1, -1, -1):
			var entry: Dictionary = trash_entries[index]
			if str(entry.get("trash_id", "")) != trash_id:
				continue
			trash_entries.remove_at(index)
			var metadata := entry.duplicate(true)
			metadata.erase("trash_id")
			metadata.erase("world_id")
			metadata["id"] = str(entry.get("world_id", ""))
			worlds.append(metadata)
			return {
				"ok": true,
				"reason": "ok",
				"world_id": str(metadata.get("id", "")),
				"trash_id": trash_id,
				"entry": entry,
			}
		return {"ok": false, "reason": "trash_missing_or_invalid"}

	func get_last_trashed_world() -> Dictionary:
		return trash_entries[0].duplicate(true) if not trash_entries.is_empty() else {}

	func delete_world(_world_id: String) -> bool:
		permanent_delete_call_count += 1
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := FakeProtectedSaveService.new()
	root.add_child(service)
	var panel := ProtectedPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(service)
	await process_frame

	var initial: Dictionary = panel.get_virtualization_snapshot()
	_check(
		bool(initial.get("trash_service_shared", false))
		and not bool(initial.get("undo_available", true)),
		"panel reuses a supplied protected service and starts with undo disabled"
	)
	panel.call("_select_slot", 0)
	var first_world_id := str(panel.get("_selected_world_id"))
	var delete_button := panel.get("_delete_button") as Button
	var undo_button := panel.get("_undo_delete_button") as Button
	_check(
		first_world_id == "protected-world-3"
		and delete_button != null
		and undo_button != null,
		"newest real row is selected and protection controls are installed"
	)

	delete_button.emit_signal("pressed")
	var armed: Dictionary = panel.get_virtualization_snapshot()
	_check(
		bool(armed.get("delete_confirmation_armed", false))
		and str(armed.get("pending_delete_world_id", "")) == first_world_id
		and service.trash_call_count == 0,
		"first delete click only arms confirmation and performs no deletion"
	)
	_check(
		delete_button.text == "确认移到回收站"
		and service.worlds.size() == 4,
		"armed confirmation is visible while all worlds remain intact"
	)

	panel.call("_select_slot", 1)
	var changed_selection: Dictionary = panel.get_virtualization_snapshot()
	_check(
		not bool(changed_selection.get("delete_confirmation_armed", true))
		and delete_button.text == "删除所选",
		"changing selection clears the pending destructive action"
	)
	var second_world_id := str(panel.get("_selected_world_id"))
	delete_button.emit_signal("pressed")
	delete_button.emit_signal("pressed")
	await process_frame
	var trashed: Dictionary = panel.get_virtualization_snapshot()
	_check(
		service.trash_call_count == 1
		and service.permanent_delete_call_count == 0
		and service.worlds.size() == 3,
		"second click moves one world through trash and never calls permanent delete"
	)
	_check(
		bool(trashed.get("undo_available", false))
		and not undo_button.disabled
		and str(trashed.get("last_trashed_world_id", "")) == second_world_id,
		"successful trash enables undo for the exact world id"
	)

	panel.call("apply_query", "protected-world-0", "updated_desc")
	panel.call("_select_slot", 0)
	delete_button.emit_signal("pressed")
	panel.call("apply_query", "protected-world-1", "updated_desc")
	var hidden_selection: Dictionary = panel.get_virtualization_snapshot()
	_check(
		not bool(hidden_selection.get("delete_confirmation_armed", true))
		and str(panel.get("_selected_world_id")).is_empty(),
		"filtering a selected world out clears confirmation and hidden deletion state"
	)

	undo_button.emit_signal("pressed")
	await process_frame
	var restored: Dictionary = panel.get_virtualization_snapshot()
	_check(
		service.restore_call_count == 1
		and service.worlds.size() == 4
		and str(restored.get("applied_query", "not-empty")).is_empty(),
		"undo restores the world and clears the query so it is visible"
	)
	_check(
		not bool(restored.get("undo_available", true))
		and undo_button.disabled,
		"consumed undo state disables the restore control"
	)

	service.reject_with_trash_full = true
	panel.call("_select_slot", 0)
	var worlds_before_failure := service.worlds.size()
	delete_button.emit_signal("pressed")
	delete_button.emit_signal("pressed")
	var rejected: Dictionary = panel.get_virtualization_snapshot()
	_check(
		service.worlds.size() == worlds_before_failure
		and not bool(rejected.get("delete_confirmation_armed", true))
		and str(panel.get("_status").text).contains("回收站已满"),
		"trash-full rejection preserves the world and resets confirmation"
	)
	_check(
		service.permanent_delete_call_count == 0,
		"protected browser never falls back to irreversible deletion"
	)

	panel.queue_free()
	service.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA PROTECTED SAVE BROWSER PASS | checks=%d" % checks
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PROTECTED SAVE BROWSER FAILURE: %s" % failure)
		print(
			"QA PROTECTED SAVE BROWSER FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
