class_name StonecutterService
extends Node

signal machine_changed(machine_id: String, snapshot: Dictionary)
signal active_machine_changed(machine_id: String)
signal item_transferred(
	machine_id: String, direction: String, slot_name: String, item_id: String, count: int
)
signal processing_started(machine_id: String, recipe_id: String)
signal item_processed(machine_id: String, recipe_id: String, output: Dictionary)
signal transfer_rejected(machine_id: String, reason: String)
signal machine_removed(machine_id: String)

const RecipeRegistryScript = preload("res://src/machine/stonecutter_recipe_registry.gd")
const ProgressPolicyScript = preload("res://src/machine/machine_progress_policy.gd")
const StateMigrationScript = preload("res://src/machine/machine_state_migration.gd")

const SERIAL_VERSION := 1
const MACHINE_TYPE := "stonecutter"
const SLOT_INPUT := "input"
const SLOT_OUTPUT := "output"
const VALID_SLOTS := [SLOT_INPUT, SLOT_OUTPUT]
const MAX_OFFLINE_SECONDS := 4 * 60 * 60
const MAX_SIMULATION_ITERATIONS := 512
const SNAPSHOT_INTERVAL_SECONDS := 0.1
const EPSILON := 0.0001
const MAX_MACHINE_ID_LENGTH := 128

var item_registry
var recipes = RecipeRegistryScript.new()
var _machines: Dictionary = {}
var _active_machine_id := ""
var _snapshot_accumulator := 0.0
var _external_scheduler := false
var _shutdown := false
var _runtime_tick_count := 0
var _total_changed_machine_count := 0
var _simulation_iteration_limit_hits := 0
var _last_runtime_summary: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(not _external_scheduler)


func setup(p_item_registry) -> bool:
	item_registry = p_item_registry
	if recipes.recipe_count() <= 0:
		recipes.load_from_file()
	return (
		item_registry != null
		and recipes.recipe_count() > 0
		and recipes.get_validation_errors().is_empty()
	)


func is_ready() -> bool:
	return (
		item_registry != null
		and recipes.recipe_count() > 0
		and recipes.get_validation_errors().is_empty()
	)


func set_external_scheduler(value: bool) -> void:
	_external_scheduler = value
	set_process(not _external_scheduler and not _shutdown)


func is_externally_scheduled() -> bool:
	return _external_scheduler


func _process(delta: float) -> void:
	if _external_scheduler or _shutdown:
		return
	advance_machine_runtime(delta, true)


func advance_machine_runtime(seconds: float, emit_events: bool = true) -> Dictionary:
	var elapsed := ProgressPolicyScript.normalize_elapsed(seconds, float(MAX_OFFLINE_SECONDS))
	if elapsed <= 0.0:
		return _last_runtime_summary.duplicate(true)
	var changed_ids := advance_time(elapsed, emit_events)
	_snapshot_accumulator += elapsed
	var active_snapshot_emitted := false
	if _snapshot_accumulator >= SNAPSHOT_INTERVAL_SECONDS:
		_snapshot_accumulator = 0.0
		if not _active_machine_id.is_empty() and _machines.has(_active_machine_id):
			machine_changed.emit(
				_active_machine_id,
				get_machine_snapshot(_active_machine_id)
			)
			active_snapshot_emitted = true
	_runtime_tick_count += 1
	_total_changed_machine_count += changed_ids.size()
	_last_runtime_summary = {
		"machine_type": MACHINE_TYPE,
		"elapsed_seconds": elapsed,
		"machine_count": _machines.size(),
		"changed_machine_count": changed_ids.size(),
		"changed_machine_ids": changed_ids.duplicate(),
		"active_snapshot_emitted": active_snapshot_emitted,
		"runtime_tick_count": _runtime_tick_count,
	}
	return _last_runtime_summary.duplicate(true)


func get_runtime_snapshot() -> Dictionary:
	var processing_count := 0
	var blocked_count := 0
	var ready_count := 0
	for machine_id: String in get_machine_ids():
		var state: Dictionary = _machines.get(machine_id, {})
		var recipe := _resolve_recipe(state)
		if recipe.is_empty():
			continue
		if not _can_accept_output(state, recipe):
			blocked_count += 1
		elif float(state.get("progress_seconds", 0.0)) > EPSILON:
			processing_count += 1
		else:
			ready_count += 1
	return {
		"machine_type": MACHINE_TYPE,
		"machine_count": _machines.size(),
		"active_machine_id": _active_machine_id,
		"externally_scheduled": _external_scheduler,
		"processing_count": processing_count,
		"blocked_count": blocked_count,
		"ready_count": ready_count,
		"runtime_tick_count": _runtime_tick_count,
		"total_changed_machine_count": _total_changed_machine_count,
		"simulation_iteration_limit_hits": _simulation_iteration_limit_hits,
		"last_runtime_summary": _last_runtime_summary.duplicate(true),
	}


func clear() -> void:
	_machines.clear()
	_snapshot_accumulator = 0.0
	_last_runtime_summary.clear()
	_set_active_machine("")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	set_process(false)
	clear()
	item_registry = null


func ensure_machine(machine_id: String) -> bool:
	if not _is_valid_machine_id(machine_id):
		return false
	if not _machines.has(machine_id):
		_machines[machine_id] = _new_machine_state()
	return true


func has_machine(machine_id: String) -> bool:
	return _machines.has(machine_id)


func get_machine_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _machines.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func open_machine(machine_id: String) -> bool:
	if not ensure_machine(machine_id):
		return false
	_set_active_machine(machine_id)
	_emit_machine_changed(machine_id)
	return true


func close_machine() -> void:
	_set_active_machine("")


func get_active_machine_id() -> String:
	return _active_machine_id


func get_machine_snapshot(machine_id: String = "") -> Dictionary:
	var resolved_id := _resolve_machine_id(machine_id)
	if not _machines.has(resolved_id):
		return {}
	var state: Dictionary = _machines[resolved_id].duplicate(true)
	var recipe := _resolve_recipe(state)
	var duration := maxf(0.1, float(recipe.get("duration_seconds", 1.0)))
	var progress := maxf(0.0, float(state.get("progress_seconds", 0.0)))
	var queued_jobs := _queued_jobs(state, recipe)
	state["machine_id"] = resolved_id
	state["active"] = resolved_id == _active_machine_id
	state["recipe"] = recipe
	state["progress_ratio"] = (
		ProgressPolicyScript.progress_ratio(progress, duration)
		if not recipe.is_empty()
		else 0.0
	)
	state["remaining_seconds"] = (
		ProgressPolicyScript.remaining_seconds(progress, duration)
		if not recipe.is_empty() and queued_jobs > 0
		else 0.0
	)
	state["queued_jobs"] = queued_jobs
	state["queued_output_count"] = _queued_output_count(recipe, queued_jobs)
	state["estimated_total_seconds"] = (
		ProgressPolicyScript.estimated_total_seconds(progress, duration, queued_jobs)
		if not recipe.is_empty()
		else 0.0
	)
	state["status"] = _status_for_state(state, recipe)
	state["can_remove"] = can_remove_machine(resolved_id)
	state["runtime_managed"] = _external_scheduler
	return state


func get_slot(machine_id: String, slot_name: String) -> Dictionary:
	if not _machines.has(machine_id) or slot_name not in VALID_SLOTS:
		return {}
	var state: Dictionary = _machines[machine_id]
	return state.get(slot_name, {}).duplicate(true)


func transfer_from_inventory_auto(inventory, inventory_index: int, machine_id: String = "") -> bool:
	var source: Dictionary = inventory.get_slot(inventory_index) if inventory != null else {}
	if source.is_empty():
		return false
	var item_id := str(source.get("item_id", ""))
	if recipes.has_input(item_id):
		return transfer_from_inventory(inventory, inventory_index, SLOT_INPUT, machine_id)
	_reject(_resolve_machine_id(machine_id), "unsupported_item")
	return false


func transfer_from_inventory(
	inventory, inventory_index: int, target_slot: String, machine_id: String = ""
) -> bool:
	var resolved_id := _resolve_machine_id(machine_id)
	if (
		inventory == null
		or not _machines.has(resolved_id)
		or target_slot != SLOT_INPUT
	):
		return false
	var source: Dictionary = inventory.get_slot(inventory_index)
	if source.is_empty():
		return false
	var item_id := str(source.get("item_id", ""))
	var metadata: Dictionary = source.get("metadata", {})
	if not recipes.has_input(item_id):
		_reject(resolved_id, "unsupported_input")
		return false
	var state: Dictionary = _machines[resolved_id]
	var target: Dictionary = state.get(SLOT_INPUT, {})
	var capacity := _slot_capacity(target, item_id, metadata)
	var accepted := mini(int(source.get("count", 0)), capacity)
	if accepted <= 0:
		_reject(resolved_id, "slot_full_or_mismatch")
		return false
	var removed: Dictionary = inventory.remove_from_slot(inventory_index, accepted)
	if removed.is_empty():
		return false
	state[SLOT_INPUT] = _merge_slot(target, removed)
	_reset_recipe_if_needed(state)
	_machines[resolved_id] = state
	item_transferred.emit(
		resolved_id,
		"inventory_to_machine",
		SLOT_INPUT,
		item_id,
		accepted
	)
	_emit_machine_changed(resolved_id)
	return true


func transfer_to_inventory(inventory, slot_name: String, machine_id: String = "") -> bool:
	var resolved_id := _resolve_machine_id(machine_id)
	if inventory == null or not _machines.has(resolved_id) or slot_name not in VALID_SLOTS:
		return false
	var state: Dictionary = _machines[resolved_id]
	var source: Dictionary = state.get(slot_name, {})
	if source.is_empty():
		return false
	var item_id := str(source.get("item_id", ""))
	var source_count := int(source.get("count", 0))
	var metadata: Dictionary = source.get("metadata", {})
	var remaining := int(inventory.add_item(item_id, source_count, metadata))
	var moved := source_count - remaining
	if moved <= 0:
		_reject(resolved_id, "inventory_full")
		return false
	if remaining <= 0:
		state[slot_name] = {}
	else:
		source["count"] = remaining
		state[slot_name] = source
	if slot_name == SLOT_INPUT:
		_reset_recipe_if_needed(state)
	_machines[resolved_id] = state
	item_transferred.emit(
		resolved_id,
		"machine_to_inventory",
		slot_name,
		item_id,
		moved
	)
	_emit_machine_changed(resolved_id)
	return true


func can_remove_machine(machine_id: String) -> bool:
	if not _machines.has(machine_id):
		return true
	var state: Dictionary = _machines[machine_id]
	for slot_name: String in VALID_SLOTS:
		var slot: Dictionary = state.get(slot_name, {})
		if not slot.is_empty() and int(slot.get("count", 0)) > 0:
			return false
	return float(state.get("progress_seconds", 0.0)) <= EPSILON


func remove_machine(machine_id: String, require_empty: bool = true) -> bool:
	if not _machines.has(machine_id):
		return true
	if require_empty and not can_remove_machine(machine_id):
		return false
	_machines.erase(machine_id)
	if _active_machine_id == machine_id:
		_set_active_machine("")
	machine_removed.emit(machine_id)
	return true


func advance_time(seconds: float, emit_events: bool = true) -> Array[String]:
	var changed_ids: Array[String] = []
	var elapsed := ProgressPolicyScript.normalize_elapsed(seconds, float(MAX_OFFLINE_SECONDS))
	if elapsed <= EPSILON:
		return changed_ids
	for machine_id: String in get_machine_ids():
		var state: Dictionary = _machines[machine_id]
		if _advance_machine(machine_id, state, elapsed, emit_events):
			_machines[machine_id] = state
			changed_ids.append(machine_id)
	return changed_ids


func serialize() -> Dictionary:
	var saved_machines: Dictionary = {}
	for machine_id: String in get_machine_ids():
		saved_machines[machine_id] = _machines[machine_id].duplicate(true)
	return {
		"version": SERIAL_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"stonecutters": saved_machines,
	}


func deserialize(data: Dictionary) -> bool:
	clear()
	var normalized := StateMigrationScript.normalize_machine_state(data)
	var raw_machines: Variant = normalized.get("stonecutters", {})
	if raw_machines is not Dictionary:
		return false
	for raw_id: Variant in raw_machines.keys():
		var machine_id := str(raw_id)
		var raw_state: Variant = raw_machines.get(raw_id, {})
		if not _is_valid_machine_id(machine_id) or raw_state is not Dictionary:
			continue
		_machines[machine_id] = _normalize_machine_state(raw_state)
	var now := int(Time.get_unix_time_from_system())
	var saved_at := int(normalized.get("saved_at_unix", now))
	var offline_seconds := clampi(now - saved_at, 0, MAX_OFFLINE_SECONDS)
	if offline_seconds > 0:
		advance_time(float(offline_seconds), false)
	return true


func _advance_machine(
	machine_id: String,
	state: Dictionary,
	seconds: float,
	emit_events: bool
) -> bool:
	var remaining := maxf(0.0, seconds)
	var changed := false
	var iterations := 0
	while remaining > EPSILON and iterations < MAX_SIMULATION_ITERATIONS:
		iterations += 1
		var recipe := _resolve_recipe(state)
		if recipe.is_empty():
			if (
				not str(state.get("active_recipe_id", "")).is_empty()
				or float(state.get("progress_seconds", 0.0)) > EPSILON
			):
				state["active_recipe_id"] = ""
				state["progress_seconds"] = 0.0
				changed = true
			break
		var recipe_id := str(recipe.get("id", ""))
		if str(state.get("active_recipe_id", "")) != recipe_id:
			state["active_recipe_id"] = recipe_id
			state["progress_seconds"] = 0.0
			changed = true
		if not _can_accept_output(state, recipe):
			break
		var duration := maxf(0.1, float(recipe.get("duration_seconds", 1.0)))
		var progress := clampf(float(state.get("progress_seconds", 0.0)), 0.0, duration)
		if progress <= EPSILON and emit_events:
			processing_started.emit(machine_id, recipe_id)
		var step := minf(remaining, maxf(EPSILON, duration - progress))
		if step <= EPSILON:
			break
		progress += step
		remaining = maxf(0.0, remaining - step)
		state["progress_seconds"] = progress
		changed = true
		if progress + EPSILON >= duration:
			var output := _complete_recipe(state, recipe)
			if output.is_empty():
				break
			state["progress_seconds"] = 0.0
			if emit_events:
				item_processed.emit(
					machine_id,
					recipe_id,
					output.duplicate(true)
				)
	if remaining > EPSILON and iterations >= MAX_SIMULATION_ITERATIONS:
		_simulation_iteration_limit_hits += 1
	return changed


func _complete_recipe(state: Dictionary, recipe: Dictionary) -> Dictionary:
	if not _can_accept_output(state, recipe):
		return {}
	var input_definition: Dictionary = recipe.get("input", {})
	var output_definition: Dictionary = recipe.get("output", {})
	var input_slot: Dictionary = state.get(SLOT_INPUT, {})
	var input_count := maxi(1, int(input_definition.get("count", 1)))
	input_slot["count"] = int(input_slot.get("count", 0)) - input_count
	if int(input_slot.get("count", 0)) <= 0:
		input_slot = {}
	state[SLOT_INPUT] = input_slot
	var output_id := str(output_definition.get("id", ""))
	var output_count := maxi(1, int(output_definition.get("count", 1)))
	var output_slot: Dictionary = state.get(SLOT_OUTPUT, {})
	if output_slot.is_empty():
		output_slot = {"item_id": output_id, "count": output_count}
	else:
		output_slot["count"] = int(output_slot.get("count", 0)) + output_count
	state[SLOT_OUTPUT] = output_slot
	return {"item_id": output_id, "count": output_count}


func _resolve_recipe(state: Dictionary) -> Dictionary:
	var input_slot: Dictionary = state.get(SLOT_INPUT, {})
	var item_id := str(input_slot.get("item_id", ""))
	if item_id.is_empty():
		return {}
	var recipe := recipes.get_recipe_for_input(item_id)
	if recipe.is_empty():
		return {}
	var required := maxi(1, int(recipe.get("input", {}).get("count", 1)))
	return recipe if int(input_slot.get("count", 0)) >= required else {}


func _can_accept_output(state: Dictionary, recipe: Dictionary) -> bool:
	if item_registry == null or recipe.is_empty():
		return false
	var output_definition: Dictionary = recipe.get("output", {})
	var output_id := str(output_definition.get("id", ""))
	var output_count := maxi(1, int(output_definition.get("count", 1)))
	if output_id.is_empty() or not item_registry.has_item(output_id):
		return false
	var output_slot: Dictionary = state.get(SLOT_OUTPUT, {})
	if output_slot.is_empty():
		return output_count <= int(item_registry.get_max_stack(output_id))
	return (
		str(output_slot.get("item_id", "")) == output_id
		and output_slot.get("metadata", {}) == {}
		and int(output_slot.get("count", 0)) + output_count
		<= int(item_registry.get_max_stack(output_id))
	)


func _queued_jobs(state: Dictionary, recipe: Dictionary) -> int:
	if item_registry == null or recipe.is_empty():
		return 0
	var input_definition: Dictionary = recipe.get("input", {})
	var output_definition: Dictionary = recipe.get("output", {})
	var output_id := str(output_definition.get("id", ""))
	if output_id.is_empty() or not item_registry.has_item(output_id):
		return 0
	var input_slot: Dictionary = state.get(SLOT_INPUT, {})
	var output_slot: Dictionary = state.get(SLOT_OUTPUT, {})
	return ProgressPolicyScript.queued_jobs(
		int(input_slot.get("count", 0)),
		maxi(1, int(input_definition.get("count", 1))),
		maxi(1, int(output_definition.get("count", 1))),
		int(output_slot.get("count", 0)),
		int(item_registry.get_max_stack(output_id))
	)


func _queued_output_count(recipe: Dictionary, queued_jobs: int) -> int:
	if recipe.is_empty():
		return 0
	return ProgressPolicyScript.queued_output_count(
		queued_jobs,
		maxi(1, int(recipe.get("output", {}).get("count", 1)))
	)


func _reset_recipe_if_needed(state: Dictionary) -> void:
	var recipe := _resolve_recipe(state)
	var recipe_id := str(recipe.get("id", ""))
	if str(state.get("active_recipe_id", "")) == recipe_id:
		return
	state["active_recipe_id"] = recipe_id
	state["progress_seconds"] = 0.0


func _slot_capacity(slot: Dictionary, item_id: String, metadata: Dictionary) -> int:
	if item_registry == null or not item_registry.has_item(item_id):
		return 0
	var max_stack := int(item_registry.get_max_stack(item_id))
	if slot.is_empty():
		return max_stack
	if str(slot.get("item_id", "")) != item_id or slot.get("metadata", {}) != metadata:
		return 0
	return maxi(0, max_stack - int(slot.get("count", 0)))


func _merge_slot(target: Dictionary, incoming: Dictionary) -> Dictionary:
	if target.is_empty():
		return incoming.duplicate(true)
	var result := target.duplicate(true)
	result["count"] = int(result.get("count", 0)) + int(incoming.get("count", 0))
	return result


func _normalize_machine_state(raw_state: Dictionary) -> Dictionary:
	var normalized := _new_machine_state()
	for slot_name: String in VALID_SLOTS:
		var raw_slot: Variant = raw_state.get(slot_name, {})
		if raw_slot is not Dictionary:
			continue
		var item_id := str(raw_slot.get("item_id", ""))
		if item_registry == null or not item_registry.has_item(item_id):
			continue
		var count := clampi(
			int(raw_slot.get("count", 0)),
			0,
			int(item_registry.get_max_stack(item_id))
		)
		if count <= 0:
			continue
		var slot := {"item_id": item_id, "count": count}
		var raw_metadata: Variant = raw_slot.get("metadata", {})
		if raw_metadata is Dictionary and not raw_metadata.is_empty():
			slot["metadata"] = raw_metadata.duplicate(true)
		normalized[slot_name] = slot
	var recipe := _resolve_recipe(normalized)
	var recipe_id := str(recipe.get("id", ""))
	var duration := maxf(0.1, float(recipe.get("duration_seconds", 1.0)))
	normalized["active_recipe_id"] = recipe_id
	normalized["progress_seconds"] = (
		clampf(float(raw_state.get("progress_seconds", 0.0)), 0.0, duration)
		if not recipe.is_empty()
		else 0.0
	)
	return normalized


func _new_machine_state() -> Dictionary:
	return {
		"type": MACHINE_TYPE,
		SLOT_INPUT: {},
		SLOT_OUTPUT: {},
		"active_recipe_id": "",
		"progress_seconds": 0.0,
	}


func _status_for_state(state: Dictionary, recipe: Dictionary) -> String:
	var input_slot: Dictionary = state.get(SLOT_INPUT, {})
	if input_slot.is_empty():
		return "等待石材原料"
	if recipe.is_empty():
		return "当前原料无法切割"
	if not _can_accept_output(state, recipe):
		return "产出槽已满或物品不匹配"
	if float(state.get("progress_seconds", 0.0)) > EPSILON:
		return "正在切割"
	return "准备切割"


func _resolve_machine_id(machine_id: String) -> String:
	return machine_id if not machine_id.is_empty() else _active_machine_id


func _is_valid_machine_id(machine_id: String) -> bool:
	return (
		not machine_id.is_empty()
		and machine_id.length() <= MAX_MACHINE_ID_LENGTH
		and "\n" not in machine_id
		and "\r" not in machine_id
	)


func _set_active_machine(machine_id: String) -> void:
	if _active_machine_id == machine_id:
		return
	_active_machine_id = machine_id
	active_machine_changed.emit(_active_machine_id)


func _emit_machine_changed(machine_id: String) -> void:
	if _machines.has(machine_id):
		machine_changed.emit(machine_id, get_machine_snapshot(machine_id))


func _reject(machine_id: String, reason: String) -> void:
	transfer_rejected.emit(machine_id, reason)
