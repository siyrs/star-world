class_name ReliableAnimalProductService
extends "res://src/husbandry/animal_product_service.gd"

var _active_pickups: Dictionary = {}
var _announced_pending: Dictionary = {}
var _restoring_pickups := false


func activate() -> void:
	# Everything already pending at world activation is historical state. Seed the
	# announcement ledger before materialization so reload, expiration recovery and
	# menu re-entry cannot replay a new-product notification.
	_announced_pending.clear()
	for raw_id: Variant in records.keys():
		var husbandry_id := str(raw_id)
		_announced_pending[husbandry_id] = maxi(
			0, int(get_record(husbandry_id).get("pending_count", 0))
		)
	_restoring_pickups = true
	super.activate()
	_restoring_pickups = false


func deactivate() -> void:
	_clear_runtime_pickups()
	super.deactivate()


func clear() -> void:
	_announced_pending.clear()
	super.clear()


func get_snapshot() -> Dictionary:
	var snapshot := super.get_snapshot()
	var active_count := 0
	for raw_id: Variant in _active_pickups.keys():
		if _active_pickup(str(raw_id)) != null:
			active_count += 1
	snapshot["active_pickups"] = active_count
	snapshot["announcement_ledger_count"] = _announced_pending.size()
	return snapshot


func _spawn_all_available() -> int:
	_cleanup_announcement_ledger()
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
		_announce_pending_delta(husbandry_id, profile, pending)
		return materialized

	pickup = ItemPickupScript.new()
	pickup.call("setup", product_item, pending, inventory)
	spawner.add_child(pickup)
	if pickup is Node3D:
		pickup.global_position = entity.global_position + Vector3(0.0, 0.7, 0.0)
	_register_pickup(husbandry_id, pickup)
	materialized = pending
	_announce_pending_delta(husbandry_id, profile, pending)
	_emit_state_changed(husbandry_id)
	return materialized


func _announce_pending_delta(
	husbandry_id: String,
	profile: Dictionary,
	pending: int
) -> void:
	var normalized_pending := maxi(0, pending)
	var announced := clampi(
		int(_announced_pending.get(husbandry_id, 0)),
		0,
		normalized_pending
	)
	var new_count := normalized_pending - announced
	_announced_pending[husbandry_id] = normalized_pending
	if _restoring_pickups or new_count <= 0:
		return
	var product_item := str(profile.get("product_item", ""))
	var result := _result_for(husbandry_id, profile, new_count)
	result["pending_count"] = normalized_pending
	result["message"] = "%s产出了%s ×%d" % [
		str(_husbandry_record(husbandry_id).get("display_name", "动物")),
		_display_name(product_item),
		new_count,
	]
	product_spawned.emit(result.duplicate(true))


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
	var next_pending := maxi(
		0,
		int(record.get("pending_count", 0)) - maxi(0, accepted_count)
	)
	record["pending_count"] = next_pending
	records[husbandry_id] = record
	_announced_pending[husbandry_id] = mini(
		int(_announced_pending.get(husbandry_id, next_pending)),
		next_pending
	)
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


func _cleanup_announcement_ledger() -> void:
	for raw_id: Variant in _announced_pending.keys():
		if not records.has(str(raw_id)):
			_announced_pending.erase(raw_id)
