class_name FurnaceService
extends Node

signal machine_changed(machine_id: String, snapshot: Dictionary)
signal active_machine_changed(machine_id: String)
signal item_transferred(
	machine_id: String, direction: String, slot_name: String, item_id: String, count: int
)
signal fuel_consumed(machine_id: String, item_id: String, burn_seconds: float)
signal smelting_started(machine_id: String, recipe_id: String)
signal item_smelted(machine_id: String, recipe_id: String, output: Dictionary)
signal transfer_rejected(machine_id: String, reason: String)
signal machine_removed(machine_id: String)

const RecipeRegistryScript = preload("res://src/machine/furnace_recipe_registry.gd")
const FuelRegistryScript = preload("res://src/machine/fuel_registry.gd")

const SERIAL_VERSION := 1
const MACHINE_TYPE := "furnace"
const SLOT_INPUT := "input"
const SLOT_FUEL := "fuel"
const SLOT_OUTPUT := "output"
const VALID_SLOTS := [SLOT_INPUT, SLOT_FUEL, SLOT_OUTPUT]
const MAX_OFFLINE_SECONDS := 4 * 60 * 60
const MAX_SIMULATION_ITERATIONS := 512
const SNAPSHOT_INTERVAL_SECONDS := 0.1
const EPSILON := 0.0001

var item_registry
var recipes = RecipeRegistryScript.new()
var fuels = FuelRegistryScript.new()
var _machines: Dictionary = {}
var _active_machine_id := ""
var _snapshot_accumulator := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)


func setup(p_item_registry) -> void:
	item_registry = p_item_registry
	if recipes.recipe_count() <= 0:
		recipes.load_from_file()
	if fuels.fuel_count() <= 0:
		fuels.load_from_file()


func _process(delta: float) -> void:
	if delta <= 0.0 or _machines.is_empty():
		return
	advance_time(delta, true)
	_snapshot_accumulator += delta
	if _snapshot_accumulator < SNAPSHOT_INTERVAL_SECONDS:
		return
	_snapshot_accumulator = 0.0
	if not _active_machine_id.is_empty() and _machines.has(_active_machine_id):
		machine_changed.emit(
			_active_machine_id, get_machine_snapshot(_active_machine_id)
		)


func clear() -> void:
	_machines.clear()
	_snapshot_accumulator = 0.0
	_set_active_machine("")


func ensure_machine(machine_id: String) -> bool:
	if not _is_valid_machine_id(machine_id):
		return false
	if not _machines.has(machine_id):
		_machines[machine_id] = _new_machine_state()
	return true


func has_machine(machine_id: String) -> bool:
	return _machines.has(machine_id)


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
	var burn_total := maxf(0.0, float(state.get("burn_total_seconds", 0.0)))
	state["machine_id"] = resolved_id
	state["active"] = resolved_id == _active_machine_id
	state["recipe"] = recipe
	state["progress_ratio"] = (
		clampf(float(state.get("progress_seconds", 0.0)) / duration, 0.0, 1.0)
		if not recipe.is_empty()
		else 0.0
	)
	state["fuel_ratio"] = (
		clampf(float(state.get("burn_remaining_seconds", 0.0)) / burn_total, 0.0, 1.0)
		if burn_total > EPSILON
		else 0.0
	)
	state["status"] = _status_for_state(state, recipe)
	state["can_remove"] = can_remove_machine(resolved_id)
	return state


func get_slot(machine_id: String, slot_name: String) -> Dictionary:
	if not _machines.has(machine_id) or not VALID_SLOTS.has(slot_name):
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
	if fuels.is_fuel(item_id):
		return transfer_from_inventory(inventory, inventory_index, SLOT_FUEL, machine_id)
	_reject(_resolve_machine_id(machine_id), "unsupported_item")
	return false


func transfer_from_inventory(
	inventory, inventory_index: int, target_slot: String, machine_id: String = ""
) -> bool:
	var resolved_id := _resolve_machine_id(machine_id)
	if (
		inventory == null
		or not _machines.has(resolved_id)
		or target_slot not in [SLOT_INPUT, SLOT_FUEL]
	):
		return false
	var source: Dictionary = inventory.get_slot(inventory_index)
	if source.is_empty():
		return false
	var item_id := str(source.get("item_id", ""))
	var metadata: Dictionary = source.get("metadata", {})
	if target_slot == SLOT_INPUT and not recipes.has_input(item_id):
		_reject(resolved_id, "unsupported_input")
		return false
	if target_slot == SLOT_FUEL and not fuels.is_fuel(item_id):
		_reject(resolved_id, "unsupported_fuel")
		return false
	var state: Dictionary = _machines[resolved_id]
	var target: Dictionary = state.get(target_slot, {})
	var capacity := _slot_capacity(target, item_id, metadata)
	var accepted := mini(int(source.get("count", 0)), capacity)
	if accepted <= 0:
		_reject(resolved_id, "slot_full_or_mismatch")
		return false
	var removed: Dictionary = inventory.remove_from_slot(inventory_index, accepted)
	if removed.is_empty():
		return false
	state[target_slot] = _merge_slot(target, removed)
	if target_slot == SLOT_INPUT:
		_reset_recipe_if_needed(state)
	_machines[resolved_id] = state
	item_transferred.emit(resolved_id, "inventory_to_machine", target_slot, item_id, accepted)
	_emit_machine_changed(resolved_id)
	return true


func transfer_to_inventory(inventory, slot_name: String, machine_id: String = "") -> bool:
	var resolved_id := _resolve_machine_id(machine_id)
	if inventory == null or not _machines.has(resolved_id) or not VALID_SLOTS.has(slot_name):
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
	item_transferred.emit(resolved_id, "machine_to_inventory", slot_name, item_id, moved)
	_emit_machine_changed(resolved_id)
	return true


func can_remove_machine(machine_id: String) -> bool:
	if not _machines.has(machine_id):
		return true
	var state: Dictionary = _machines[machine_id]
	for slot_name in VALID_SLOTS:
		var slot: Dictionary = state.get(slot_name, {})
		if not slot.is_empty() and int(slot.get("count", 0)) > 0:
			return false
	return (
		float(state.get("burn_remaining_seconds", 0.0)) <= EPSILON
		and float(state.get("progress_seconds", 0.0)) <= EPSILON
	)


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
	var elapsed := maxf(0.0, seconds)
	if elapsed <= EPSILON:
		return changed_ids
	for raw_id in _machines.keys():
		var machine_id := str(raw_id)
		var state: Dictionary = _machines[machine_id]
		if _advance_machine(machine_id, state, elapsed, emit_events):
			_machines[machine_id] = state
			changed_ids.append(machine_id)
	return changed_ids


func serialize() -> Dictionary:
	var saved_machines: Dictionary = {}
	for machine_id in _machines:
		saved_machines[str(machine_id)] = _machines[machine_id].duplicate(true)
	return {
		"version": SERIAL_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"furnaces": saved_machines,
	}


func deserialize(data: Dictionary) -> bool:
	clear()
	var raw_machines = data.get("furnaces", data.get("machines", {}))
	if raw_machines is not Dictionary:
		return false
	for raw_id in raw_machines:
		var machine_id := str(raw_id)
		var raw_state = raw_machines[raw_id]
		if not _is_valid_machine_id(machine_id) or raw_state is not Dictionary:
			continue
		_machines[machine_id] = _normalize_machine_state(raw_state)
	var now := int(Time.get_unix_time_from_system())
	var saved_at := int(data.get("saved_at_unix", now))
	var offline_seconds := clampi(now - saved_at, 0, MAX_OFFLINE_SECONDS)
	if offline_seconds > 0:
		advance_time(float(offline_seconds), false)
	return true


func _advance_machine(
	machine_id: String, state: Dictionary, seconds: float, emit_events: bool
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
		if float(state.get("burn_remaining_seconds", 0.0)) <= EPSILON:
			if not _consume_one_fuel(machine_id, state, emit_events):
				break
			changed = true
			if emit_events:
				smelting_started.emit(machine_id, recipe_id)
		var duration := maxf(0.1, float(recipe.get("duration_seconds", 1.0)))
		var progress := clampf(float(state.get("progress_seconds", 0.0)), 0.0, duration)
		var burn_remaining := maxf(0.0, float(state.get("burn_remaining_seconds", 0.0)))
		var step := minf(remaining, minf(burn_remaining, maxf(EPSILON, duration - progress)))
		if step <= EPSILON:
			break
		progress += step
		burn_remaining = maxf(0.0, burn_remaining - step)
		remaining = maxf(0.0, remaining - step)
		state["progress_seconds"] = progress
		state["burn_remaining_seconds"] = burn_remaining
		changed = true
		if progress + EPSILON >= duration:
			var output := _complete_recipe(state, recipe)
			if output.is_empty():
				break
			state["progress_seconds"] = 0.0
			if emit_events:
				item_smelted.emit(machine_id, recipe_id, output.duplicate(true))
		if burn_remaining <= EPSILON:
			state["burn_remaining_seconds"] = 0.0
	return changed


func _consume_one_fuel(machine_id: String, state: Dictionary, emit_events: bool) -> bool:
	var fuel_slot: Dictionary = state.get(SLOT_FUEL, {})
	var item_id := str(fuel_slot.get("item_id", ""))
	var burn_seconds := fuels.get_burn_seconds(item_id)
	if item_id.is_empty() or int(fuel_slot.get("count", 0)) <= 0 or burn_seconds <= 0.0:
		return false
	fuel_slot["count"] = int(fuel_slot.get("count", 0)) - 1
	if int(fuel_slot.get("count", 0)) <= 0:
		fuel_slot = {}
	state[SLOT_FUEL] = fuel_slot
	state["burn_total_seconds"] = burn_seconds
	state["burn_remaining_seconds"] = burn_seconds
	if emit_events:
		fuel_consumed.emit(machine_id, item_id, burn_seconds)
	return true


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
	if (
		str(slot.get("item_id", "")) != item_id
		or slot.get("metadata", {}) != metadata
	):
		return 0
	return maxi(0, max_stack - int(slot.get("count", 0)))


func _merge_slot(target: Dictionary, incoming: Dictionary) -> Dictionary:
	if target.is_empty():
		return incoming.duplicate(true)
	var result := target.duplicate(true)
	result["count"] = int(result.get("count", 0)) + int(incoming.get("count", 0))
	return result


func _status_for_state(state: Dictionary, recipe: Dictionary) -> String:
	var input_slot: Dictionary = state.get(SLOT_INPUT, {})
	if input_slot.is_empty():
		return "放入可烧制的原料"
	if recipe.is_empty():
		return "当前原料无法烧制"
	if not _can_accept_output(state, recipe):
		return "产出槽空间不足，请先取走物品"
	if float(state.get("burn_remaining_seconds", 0.0)) > EPSILON:
		return "烧制中"
	var fuel_slot: Dictionary = state.get(SLOT_FUEL, {})
	if fuel_slot.is_empty():
		return "放入煤炭、木材或木棍作为燃料"
	if not fuels.is_fuel(str(fuel_slot.get("item_id", ""))):
		return "当前燃料无效"
	return "准备点燃"


func _new_machine_state() -> Dictionary:
	return {
		"type": MACHINE_TYPE,
		SLOT_INPUT: {},
		SLOT_FUEL: {},
		SLOT_OUTPUT: {},
		"active_recipe_id": "",
		"progress_seconds": 0.0,
		"burn_remaining_seconds": 0.0,
		"burn_total_seconds": 0.0,
	}


func _normalize_machine_state(raw_state: Dictionary) -> Dictionary:
	var result := _new_machine_state()
	for slot_name in VALID_SLOTS:
		result[slot_name] = _normalize_slot(raw_state.get(slot_name, {}))
	result["active_recipe_id"] = str(raw_state.get("active_recipe_id", ""))
	result["progress_seconds"] = maxf(0.0, float(raw_state.get("progress_seconds", 0.0)))
	result["burn_remaining_seconds"] = maxf(
		0.0, float(raw_state.get("burn_remaining_seconds", 0.0))
	)
	result["burn_total_seconds"] = maxf(
		result["burn_remaining_seconds"], float(raw_state.get("burn_total_seconds", 0.0))
	)
	_reset_recipe_if_needed(result)
	return result


func _normalize_slot(raw_slot: Variant) -> Dictionary:
	if raw_slot is not Dictionary or item_registry == null:
		return {}
	var item_id := str(raw_slot.get("item_id", ""))
	var count := int(raw_slot.get("count", 0))
	if item_id.is_empty() or count <= 0 or not item_registry.has_item(item_id):
		return {}
	return {
		"item_id": item_id,
		"count": mini(count, int(item_registry.get_max_stack(item_id))),
		"metadata": raw_slot.get("metadata", {}).duplicate(true),
	}


func _resolve_machine_id(machine_id: String) -> String:
	return _active_machine_id if machine_id.is_empty() else machine_id


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


func _is_valid_machine_id(machine_id: String) -> bool:
	return (
		not machine_id.is_empty()
		and machine_id.length() <= 128
		and "\n" not in machine_id
		and "\r" not in machine_id
	)
