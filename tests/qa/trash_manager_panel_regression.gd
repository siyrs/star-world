extends SceneTree

const TrashManagerPanelScript = preload(
	"res://src/ui/save_trash_manager_panel.gd"
)
const SLOT_COUNT := 32
const ROW_POOL_LIMIT := 24

var checks := 0
var failures: Array[String] = []


class FakeTrashService:
	extends Node

	var slots: Array[Dictionary] = []
	var list_count := 0
	var restore_call_count := 0
	var purge_call_count := 0
	var permanent_delete_call_count := 0
	var last_restored_trash_id := ""
	var last_purged_trash_id := ""

	func _init() -> void:
		for index in 32:
			var valid := index < 31
			slots.append({
				"version": 1,
				"trash_id": "trash-slot-%02d" % index,
				"world_id": "managed-world-%02d" % index if valid else "",
				"name": "Managed World %02d" % index if valid else "损坏的回收站条目",
				"map_id": "star_continent" if valid else "invalid_manifest",
				"seed": 1900000 + index if valid else 0,
				"save_bytes": 4096 + index,
				"deleted_unix_usec": 2000000 - index,
				"deleted_at": "2026-07-25T00:%02d:00" % (index % 60),
				"valid": valid,
				"restorable": valid,
				"purgeable": true,
				"reason": "ok" if valid else "manifest_missing_or_invalid",
			})

	func list_trash_slots(limit: int = 32) -> Array:
		list_count += 1
		var result: Array = []
		for index in mini(limit, slots.size()):
			result.append(slots[index])
		return result

	func get_trash_diagnostics() -> Dictionary:
		var invalid := 0
		for entry: Dictionary in slots:
			if not bool(entry.get("valid", false)):
				invalid += 1
		return {
			"trash_capacity": 32,
			"trash_entry_count": slots.size(),
			"valid_entry_count": slots.size() - invalid,
			"invalid_entry_count": invalid,
			"overflow_entry_count": 0,
		}

	func restore_trashed_world(trash_id: String) -> Dictionary:
		restore_call_count += 1
		for index in range(slots.size() - 1, -1, -1):
			var entry: Dictionary = slots[index]
			if str(entry.get("trash_id", "")) != trash_id:
				continue
			if not bool(entry.get("valid", false)):
				return {"ok": false, "reason": "trash_missing_or_invalid"}
			slots.remove_at(index)
			last_restored_trash_id = trash_id
			return {
				"ok": true,
				"world_id": str(entry.get("world_id", "")),
				"trash_id": trash_id,
				"entry": entry,
			}
		return {"ok": false, "reason": "trash_missing_or_invalid"}

	func purge_trash_slot(trash_id: String) -> bool:
		purge_call_count += 1
		for index in range(slots.size() - 1, -1, -1):
			if str(slots[index].get("trash_id", "")) == trash_id:
				slots.remove_at(index)
				last_purged_trash_id = trash_id
				return true
		return false

	func delete_world(_world_id: String) -> bool:
		permanent_delete_call_count += 1
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := FakeTrashService.new()
	root.add_child(service)
	var panel := TrashManagerPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.setup(service)
	await process_frame
	var initial: Dictionary = panel.get_management_snapshot()
	_check(
		int(initial.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(initial.get("row_create_count", -1)) == ROW_POOL_LIMIT,
		"manager creates exactly twenty-four reusable rows"
	)
	_check(
		int(initial.get("total_slot_count", -1)) == SLOT_COUNT
		and int(initial.get("page_count", -1)) == 2
		and int(initial.get("valid_slot_count", -1)) == 31
		and int(initial.get("invalid_slot_count", -1)) == 1,
		"thirty-two slots expose two pages with one damaged entry"
	)
	_check(
		service.list_count == 1,
		"initial manager refresh performs exactly one bounded service list"
	)
	panel.show_page(1)
	var second_page := panel.get_visible_trash_ids()
	_check(
		second_page.size() == 8
		and second_page[0] == "trash-slot-24"
		and second_page[7] == "trash-slot-31",
		"second page reuses the row pool for the final eight slots"
	)
	_check(
		service.list_count == 1,
		"page navigation performs no additional trash-directory scan"
	)

	panel.call("_select_slot", 7)
	var row_slots: Array = panel.get("_row_slots")
	var invalid_restore_button := row_slots[7].get("restore") as Button
	_check(
		invalid_restore_button != null and invalid_restore_button.disabled,
		"damaged slot visibly disables restore"
	)
	panel.call("_restore_slot", 7)
	_check(
		service.restore_call_count == 0,
		"damaged slot never reaches the restore service"
	)
	panel.call("_purge_selected")
	var armed: Dictionary = panel.get_management_snapshot()
	_check(
		bool(armed.get("purge_confirmation_armed", false))
		and str(armed.get("pending_purge_trash_id", "")) == "trash-slot-31"
		and service.purge_call_count == 0,
		"first permanent-clean click only arms the exact damaged slot"
	)
	panel.call("_select_slot", 0)
	var changed_selection: Dictionary = panel.get_management_snapshot()
	_check(
		not bool(changed_selection.get("purge_confirmation_armed", true)),
		"changing trash selection cancels permanent-clean confirmation"
	)
	panel.call("_select_slot", 7)
	panel.call("_purge_selected")
	panel.call("_purge_selected")
	await process_frame
	var after_purge: Dictionary = panel.get_management_snapshot()
	_check(
		service.purge_call_count == 1
		and service.last_purged_trash_id == "trash-slot-31"
		and int(after_purge.get("total_slot_count", -1)) == 31
		and int(after_purge.get("invalid_slot_count", -1)) == 0,
		"second click purges only the selected damaged slot and frees one capacity unit"
	)

	panel.show_page(1)
	var list_count_before_restore := service.list_count
	panel.call("_restore_slot", 0)
	await process_frame
	var after_restore: Dictionary = panel.get_management_snapshot()
	_check(
		service.restore_call_count == 1
		and service.last_restored_trash_id == "trash-slot-24",
		"row restore targets an explicitly selected older valid entry"
	)
	_check(
		int(after_restore.get("total_slot_count", -1)) == 30
		and int(after_restore.get("physical_entry_count", -1)) == 30,
		"selected restore consumes one slot and refreshes bounded diagnostics"
	)
	_check(
		service.list_count == list_count_before_restore + 1,
		"successful restore performs one explicit bounded refresh"
	)
	_check(
		service.permanent_delete_call_count == 0,
		"trash manager never calls the active-world permanent delete API"
	)

	var back_count := 0
	panel.back_requested.connect(func() -> void: back_count += 1)
	var back_button := _find_button(panel, "返回存档")
	_check(back_button != null, "manager exposes an explicit return-to-saves control")
	if back_button != null:
		back_button.emit_signal("pressed")
	_check(back_count == 1, "return control emits one bounded navigation request")

	panel.queue_free()
	service.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA TRASH MANAGER PANEL PASS | checks=%d | rows=%d | slots=%d"
			% [checks, ROW_POOL_LIMIT, SLOT_COUNT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA TRASH MANAGER PANEL FAILURE: %s" % failure)
		print(
			"QA TRASH MANAGER PANEL FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _find_button(node: Node, text: String) -> Button:
	for child: Node in node.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
