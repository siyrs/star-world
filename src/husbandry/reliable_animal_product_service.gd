class_name ReliableAnimalProductService
extends "res://src/husbandry/animal_product_service.gd"

const ItemPickupScript = preload("res://src/entity/item_pickup.gd")

var _active_pickups: Dictionary = {}
var _restoring_pickups := false


func activate() -> void:
	_restoring_pickups = true
	super.activate()
	_restoring_pickups = false


func deactivate() -> void:
	_clear_runtime_pickups()
	super.deactivate()


func get_snapshot() -> Dictionary:
	var snapshot := super.get_snapshot()
	var active_count := 0
	for raw_id: Variant in _active_pickups.keys():
		if _active_pickup(str(raw_id)) != null:
			active_count += 1
	snapshot["active_pickups"] = active_count
	return snapshot


func _spawn_all_available() -> int:
	var total := 0
	for raw_id: Variant in records.keys():
		var husbandry_id := str(raw_id)
		var record := get_record(husbandry_id)
		var profile := registry.get_profile_for_species(
			str(record.get("species_id", ""))
		)
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

	var pickup := _active_pickup(husbandry_id)
	var materialized := 0
	if pickup != null:
		var current_count := maxi(0, int(pickup.get("item_count")))
		var missing_count := maxi(0, pending - current_count)
		if missing_count > 0 and pickup.has_method("merge_items"):
			var remaining := int(pickup.call("merge_items", missing_count, true))
			materialized = missing_count - maxi(0, remaining)
		return materialized

	pickup = ItemPickupScript.new()
	pickup.call("setup", product_item, pending, inventory)
	spawner.add_child(pickup)
	if pickup is Node3D:
		pickup.global_position = entity.global_position + Vector3(0.0, 0.7, 0.0)
	_register_pickup(husbandry_id, pickup)
	materialized = pending

	if not _restoring_pickups:
		var result := _result_for(husbandry_id, profile, pending)
		result["message"] = "%s产出了%s ×%d" % [
			str(_husbandry_record(husbandry_id).get("display_name", "动物")),
			_display_name(product_item),
			pending,
		]
		product_spawned.emit(result.duplicate(true))
	_emit_state_changed(husbandry_id)
	return materialized


func _register_pickup(husbandry_id: String, pickup: Node) -> void:
	_active_pickups[husbandry_id] = pickup
	pickup.collected.connect(
		Callable(self, "_on_pickup_collected").bind(husbandry_id, pickup)
	)
	pickup.expired.connect(
		Callable(self, "_on_pickup_expired").bind(husbandry_id, pickup)
	)
	pickup.tree_exiting.connect(
		Callable(self, "_on_pickup_tree_exiting").bind(husbandry_id, pickup)
	)


func _on_pickup_collected(
	_item_id: String,
	accepted_count: int,
	husbandry_id: String,
	pickup: Node
) -> void:
	if _active_pickup(husbandry_id) != pickup or not records.has(husbandry_id):
		return
	var record := get_record(husbandry_id)
	record["pending_count"] = maxi(
		0,
		int(record.get("pending_count", 0)) - maxi(0, accepted_count)
	)
	records[husbandry_id] = record
	_emit_state_changed(husbandry_id)


func _on_pickup_expired(
	_item_id: String,
	_item_count: int,
	husbandry_id: String,
	pickup: Node
) -> void:
	_forget_pickup(husbandry_id, pickup)


func _on_pickup_tree_exiting(husbandry_id: String, pickup: Node) -> void:
	_forget_pickup(husbandry_id, pickup)


func _forget_pickup(husbandry_id: String, pickup: Node) -> void:
	var current: Variant = _active_pickups.get(husbandry_id)
	if current == pickup:
		_active_pickups.erase(husbandry_id)


func _active_pickup(husbandry_id: String) -> Node:
	var value: Variant = _active_pickups.get(husbandry_id)
	if value is Node and is_instance_valid(value) and not value.is_queued_for_deletion():
		return value
	_active_pickups.erase(husbandry_id)
	return null


func _clear_runtime_pickups() -> void:
	for value: Variant in _active_pickups.values():
		if value is Node and is_instance_valid(value) and not value.is_queued_for_deletion():
			value.queue_free()
	_active_pickups.clear()
