class_name AnimalProductService
extends Node

signal product_ready(result: Dictionary)
signal product_spawned(result: Dictionary)
signal state_changed(entity_id: int)

const RegistryScript = preload("res://src/husbandry/animal_product_registry.gd")
const PolicyScript = preload("res://src/husbandry/animal_product_policy.gd")
const ItemPickupScript = preload("res://src/entity/item_pickup.gd")
const SERIAL_VERSION := 1
const META_HUSBANDRY_ID: StringName = &"husbandry_id"

var item_registry
var inventory: Node
var husbandry_service: Node
var spawner: Node
var player: Node3D
var registry = RegistryScript.new()
var policy = PolicyScript.new()
var records: Dictionary = {}

var _active: bool = false
var _update_accumulator: float = 0.0


func _ready() -> void:
	set_process(false)


func setup(
	p_item_registry,
	p_inventory: Node,
	p_husbandry_service: Node,
	p_spawner: Node
) -> bool:
	_disconnect_husbandry()
	item_registry = p_item_registry
	inventory = p_inventory
	husbandry_service = p_husbandry_service
	spawner = p_spawner
	var loaded := registry.ensure_loaded()
	if husbandry_service != null and husbandry_service.has_signal("state_changed"):
		husbandry_service.connect(
			"state_changed", Callable(self, "_on_husbandry_state_changed")
		)
	return (
		loaded
		and item_registry != null
		and inventory != null
		and is_instance_valid(inventory)
		and husbandry_service != null
		and is_instance_valid(husbandry_service)
		and spawner != null
		and is_instance_valid(spawner)
	)


func attach_player(p_player: Node3D) -> void:
	player = p_player


func activate() -> void:
	_active = true
	set_process(true)
	_update_accumulator = 0.0
	_sync_records()
	_spawn_all_available()


func deactivate() -> void:
	_active = false
	set_process(false)
	_update_accumulator = 0.0
	player = null


func clear() -> void:
	deactivate()
	records.clear()


func shutdown() -> void:
	clear()
	_disconnect_husbandry()
	item_registry = null
	inventory = null
	husbandry_service = null
	spawner = null


func get_snapshot() -> Dictionary:
	var pending_total := 0
	for raw_record: Variant in records.values():
		if raw_record is Dictionary:
			pending_total += int(raw_record.get("pending_count", 0))
	return {
		"active": _active,
		"tracked_animals": records.size(),
		"pending_products": pending_total,
		"profile_count": registry.profile_count(),
	}


func get_record(husbandry_id: String) -> Dictionary:
	return records.get(husbandry_id, {}).duplicate(true)


func serialize() -> Dictionary:
	if _active:
		_sync_records()
	var saved_records: Dictionary = {}
	for raw_id: Variant in records:
		var husbandry_id := str(raw_id)
		var raw_record: Variant = records[raw_id]
		if husbandry_id.is_empty() or raw_record is not Dictionary:
			continue
		saved_records[husbandry_id] = {
			"species_id": str(raw_record.get("species_id", "")),
			"remaining_seconds": maxf(
				0.0, float(raw_record.get("remaining_seconds", 0.0))
			),
			"pending_count": maxi(0, int(raw_record.get("pending_count", 0))),
		}
	return {
		"version": SERIAL_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"records": saved_records,
	}


func deserialize(data: Dictionary) -> bool:
	records.clear()
	var now := int(Time.get_unix_time_from_system())
	var saved_at := int(data.get("saved_at_unix", now))
	var elapsed := clampf(
		float(maxi(0, now - saved_at)), 0.0, registry.get_max_offline_seconds()
	)
	var raw_records: Variant = data.get("records", {})
	if raw_records is not Dictionary:
		return data.is_empty()
	for raw_id: Variant in raw_records:
		var husbandry_id := str(raw_id)
		var raw_record: Variant = raw_records[raw_id]
		if husbandry_id.is_empty() or raw_record is not Dictionary:
			continue
		var species_id := str(raw_record.get("species_id", ""))
		var profile := registry.get_profile_for_species(species_id)
		if profile.is_empty():
			continue
		var advanced := policy.advance(profile, raw_record, elapsed)
		var state: Variant = advanced.get("state", {})
		if state is Dictionary:
			records[husbandry_id] = state.duplicate(true)
	return true


func advance(elapsed_seconds: float) -> Dictionary:
	_sync_records()
	var produced_total := 0
	var spawned_total := 0
	for raw_id: Variant in records.keys():
		var husbandry_id := str(raw_id)
		var record := get_record(husbandry_id)
		var profile := registry.get_profile_for_species(str(record.get("species_id", "")))
		if profile.is_empty():
			continue
		var advanced := policy.advance(profile, record, elapsed_seconds)
		var next_state: Variant = advanced.get("state", {})
		if next_state is not Dictionary:
			continue
		records[husbandry_id] = next_state.duplicate(true)
		var produced := maxi(0, int(advanced.get("produced_count", 0)))
		if produced > 0:
			produced_total += produced
			var ready_result := _result_for(husbandry_id, profile, produced)
			ready_result["pending_count"] = int(next_state.get("pending_count", 0))
			product_ready.emit(ready_result.duplicate(true))
			_emit_state_changed(husbandry_id)
		spawned_total += _spawn_pending(husbandry_id, profile)
	return {
		"produced": produced_total,
		"spawned": spawned_total,
		"tracked": records.size(),
	}


func get_status_for_focus(focus: Dictionary) -> String:
	var entity_id := int(focus.get("entity_id", 0))
	if entity_id <= 0:
		return ""
	var entity_value: Variant = instance_from_id(entity_id)
	if entity_value is not Node:
		return ""
	var entity := entity_value as Node
	var husbandry_id := str(entity.get_meta(META_HUSBANDRY_ID, ""))
	if husbandry_id.is_empty():
		return ""
	if _active:
		_sync_records()
	var husbandry_record := _husbandry_record(husbandry_id)
	var species_id := str(husbandry_record.get("species_id", focus.get("species_id", "")))
	var profile := registry.get_profile_for_species(species_id)
	if profile.is_empty():
		return ""
	if (
		bool(profile.get("adult_only", true))
		and str(husbandry_record.get("stage", "adult")) != "adult"
	):
		return "成年后开始产出%s" % _display_name(str(profile.get("product_item", "")))
	var record := get_record(husbandry_id)
	if record.is_empty():
		return ""
	var pending := int(record.get("pending_count", 0))
	var product_name := _display_name(str(profile.get("product_item", "")))
	if pending > 0:
		return "%s待收集 ×%d" % [product_name, pending]
	return "下次%s约 %s" % [
		product_name,
		policy.format_duration(float(record.get("remaining_seconds", 0.0))),
	]


func _process(delta: float) -> void:
	if not _active:
		return
	_update_accumulator += maxf(0.0, delta)
	var interval := registry.get_update_interval_seconds()
	if _update_accumulator < interval:
		return
	var elapsed := _update_accumulator
	_update_accumulator = fmod(_update_accumulator, interval)
	advance(elapsed)


func _sync_records() -> void:
	if husbandry_service == null or not husbandry_service.has_method("get_managed_records"):
		return
	var managed_value: Variant = husbandry_service.call("get_managed_records")
	if managed_value is not Dictionary:
		return
	var managed: Dictionary = managed_value
	var eligible: Dictionary = {}
	for raw_id: Variant in managed:
		var husbandry_id := str(raw_id)
		var raw_record: Variant = managed[raw_id]
		if husbandry_id.is_empty() or raw_record is not Dictionary:
			continue
		var husbandry_record: Dictionary = raw_record
		var species_id := str(husbandry_record.get("species_id", ""))
		var profile := registry.get_profile_for_species(species_id)
		if not policy.is_eligible(profile, husbandry_record):
			continue
		eligible[husbandry_id] = true
		if not records.has(husbandry_id):
			records[husbandry_id] = policy.initial_state(profile, husbandry_id)
		else:
			records[husbandry_id] = policy.normalize_state(
				profile, get_record(husbandry_id)
			)
	for raw_id: Variant in records.keys():
		var husbandry_id := str(raw_id)
		if not eligible.has(husbandry_id):
			records.erase(husbandry_id)


func _spawn_all_available() -> int:
	var total := 0
	for raw_id: Variant in records.keys():
		var husbandry_id := str(raw_id)
		var record := get_record(husbandry_id)
		var profile := registry.get_profile_for_species(str(record.get("species_id", "")))
		if not profile.is_empty():
			total += _spawn_pending(husbandry_id, profile)
	return total


func _spawn_pending(husbandry_id: String, profile: Dictionary) -> int:
	var record := get_record(husbandry_id)
	var pending := maxi(0, int(record.get("pending_count", 0)))
	if pending <= 0 or player == null or not is_instance_valid(player):
		return 0
	if spawner == null or not is_instance_valid(spawner):
		return 0
	var entity := _live_entity(husbandry_id)
	if entity == null:
		return 0
	var spawn_radius := registry.get_pickup_spawn_radius()
	if entity.global_position.distance_squared_to(player.global_position) > spawn_radius * spawn_radius:
		return 0
	var product_item := str(profile.get("product_item", ""))
	if (
		product_item.is_empty()
		or item_registry == null
		or not item_registry.has_method("has_item")
		or not bool(item_registry.call("has_item", product_item))
	):
		return 0
	var pickup: Node = ItemPickupScript.new()
	pickup.call("setup", product_item, pending, inventory)
	spawner.add_child(pickup)
	if pickup is Node3D:
		pickup.global_position = entity.global_position + Vector3(0.0, 0.7, 0.0)
	record["pending_count"] = 0
	records[husbandry_id] = record
	var result := _result_for(husbandry_id, profile, pending)
	result["message"] = "%s产出了%s ×%d" % [
		str(_husbandry_record(husbandry_id).get("display_name", "动物")),
		_display_name(product_item),
		pending,
	]
	product_spawned.emit(result.duplicate(true))
	_emit_state_changed(husbandry_id)
	return pending


func _result_for(husbandry_id: String, profile: Dictionary, count: int) -> Dictionary:
	var husbandry_record := _husbandry_record(husbandry_id)
	return {
		"husbandry_id": husbandry_id,
		"species_id": str(profile.get("species_id", "")),
		"display_name": str(husbandry_record.get("display_name", "动物")),
		"product_item": str(profile.get("product_item", "")),
		"product_name": _display_name(str(profile.get("product_item", ""))),
		"count": maxi(0, count),
	}


func _husbandry_record(husbandry_id: String) -> Dictionary:
	if husbandry_service == null or not husbandry_service.has_method("get_record"):
		return {}
	var value: Variant = husbandry_service.call("get_record", husbandry_id)
	return value.duplicate(true) if value is Dictionary else {}


func _live_entity(husbandry_id: String) -> Node3D:
	if husbandry_service == null or not husbandry_service.has_method("get_live_entity"):
		return null
	var value: Variant = husbandry_service.call("get_live_entity", husbandry_id)
	return value as Node3D if value is Node3D and is_instance_valid(value) else null


func _emit_state_changed(husbandry_id: String) -> void:
	var entity := _live_entity(husbandry_id)
	state_changed.emit(entity.get_instance_id() if entity != null else 0)


func _display_name(item_id: String) -> String:
	if item_registry != null and item_registry.has_method("get_display_name"):
		return str(item_registry.call("get_display_name", item_id))
	return item_id


func _on_husbandry_state_changed(_entity_id: int) -> void:
	if _active:
		_sync_records()


func _disconnect_husbandry() -> void:
	if husbandry_service == null or not husbandry_service.has_signal("state_changed"):
		return
	var callback := Callable(self, "_on_husbandry_state_changed")
	if husbandry_service.is_connected("state_changed", callback):
		husbandry_service.disconnect("state_changed", callback)


func _exit_tree() -> void:
	shutdown()
