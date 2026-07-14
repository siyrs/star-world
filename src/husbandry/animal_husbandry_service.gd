class_name AnimalHusbandryService
extends Node

signal state_changed(entity_id: int)
signal animal_fed(result: Dictionary)
signal animal_ready(result: Dictionary)
signal baby_born(result: Dictionary)
signal animal_grew(result: Dictionary)
signal interaction_rejected(reason: String, context: Dictionary)

const RegistryScript = preload("res://src/husbandry/husbandry_registry.gd")
const PolicyScript = preload("res://src/husbandry/husbandry_policy.gd")
const SERIAL_VERSION := 1
const GROUP_ANIMALS: StringName = &"animals"
const GROUP_PERSISTENT: StringName = &"persistent_creatures"
const META_ID: StringName = &"husbandry_id"
const META_BASE_NAME: StringName = &"husbandry_base_name"

var item_registry
var inventory: Node
var spawner: Node
var world: Node
var player: Node3D
var registry = RegistryScript.new()
var policy = PolicyScript.new()
var records: Dictionary = {}

var _live: Dictionary = {}
var _active: bool = false
var _id_counter: int = 0


func _ready() -> void:
	set_process(false)


func setup(p_item_registry, p_inventory: Node, p_spawner: Node) -> void:
	item_registry = p_item_registry
	inventory = p_inventory
	spawner = p_spawner
	registry.ensure_loaded()


func attach_world(p_world: Node, p_player: Node3D) -> void:
	world = p_world
	player = p_player


func activate() -> void:
	_active = true
	set_process(true)
	_restore_managed_animals()


func detach_world() -> void:
	_active = false
	set_process(false)
	world = null
	player = null
	_live.clear()


func clear() -> void:
	detach_world()
	records.clear()
	_id_counter = 0


func get_snapshot() -> Dictionary:
	var babies := 0
	var ready := 0
	for raw_record in records.values():
		var record: Dictionary = raw_record
		if str(record.get("stage", PolicyScript.STAGE_ADULT)) == PolicyScript.STAGE_BABY:
			babies += 1
		if float(record.get("love_remaining_seconds", 0.0)) > 0.0:
			ready += 1
	return {
		"managed_animals": records.size(),
		"babies": babies,
		"ready_to_breed": ready,
		"maximum": registry.get_max_managed_animals(),
		"species_count": registry.species_count(),
	}


func get_record(husbandry_id: String) -> Dictionary:
	return records.get(husbandry_id, {}).duplicate(true)


func get_managed_count() -> int:
	return records.size()


func serialize() -> Dictionary:
	_sync_live_records()
	var serialized_records: Dictionary = {}
	for raw_id in records:
		var husbandry_id := str(raw_id)
		var record: Dictionary = records[raw_id]
		serialized_records[husbandry_id] = _serialized_record(record)
	return {
		"version": SERIAL_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"animals": serialized_records,
	}


func deserialize(data: Dictionary) -> bool:
	records.clear()
	_live.clear()
	_id_counter = 0
	var now := int(Time.get_unix_time_from_system())
	var saved_at := int(data.get("saved_at_unix", now))
	var elapsed := clampf(
		float(maxi(0, now - saved_at)), 0.0, registry.get_max_offline_seconds()
	)
	var raw_animals = data.get("animals", {})
	if raw_animals is not Dictionary:
		return data.is_empty()
	for raw_id in raw_animals:
		var husbandry_id := str(raw_id)
		var raw_record = raw_animals[raw_id]
		if husbandry_id.is_empty() or raw_record is not Dictionary:
			continue
		var record := _normalize_saved_record(husbandry_id, raw_record, elapsed)
		if not record.is_empty():
			records[husbandry_id] = record
	return true


func interact_entity(entity: Node, p_inventory: Node = null) -> Dictionary:
	var species_id := _species_id(entity)
	if (
		entity == null
		or not is_instance_valid(entity)
		or not entity.is_in_group(GROUP_ANIMALS)
		or not registry.supports_species(species_id)
	):
		return {"handled": false}
	var active_inventory: Node = p_inventory if p_inventory != null else inventory
	if (
		active_inventory == null
		or not active_inventory.has_method("get_selected_item")
		or not active_inventory.has_method("consume_selected")
	):
		return _reject("inventory_contract_missing", entity, species_id, {})
	var selected: Dictionary = active_inventory.call("get_selected_item")
	var selected_item_id := str(selected.get("item_id", ""))
	var existing_id := _husbandry_id(entity)
	var preview_state := (
		records.get(existing_id, {}).duplicate(true)
		if not existing_id.is_empty() and records.has(existing_id)
		else _default_record("", species_id, entity)
	)
	var projected_count := records.size() + (0 if records.has(existing_id) else 1)
	var profile := registry.get_species(species_id)
	var evaluation := policy.evaluate_feed(
		profile,
		preview_state,
		selected_item_id,
		projected_count,
		registry.get_max_managed_animals()
	)
	if not bool(evaluation.get("success", false)):
		return _reject(str(evaluation.get("reason", "feed_rejected")), entity, species_id, evaluation)
	var consumed: Dictionary = active_inventory.call("consume_selected", 1)
	if str(consumed.get("item_id", "")) != selected_item_id or int(consumed.get("count", 0)) != 1:
		_restore_consumed(active_inventory, consumed)
		return _reject("consume_failed", entity, species_id, evaluation)
	var was_managed := not existing_id.is_empty() and records.has(existing_id)
	var previous_record: Dictionary = records.get(existing_id, {}).duplicate(true)
	var husbandry_id := _ensure_managed(entity, species_id)
	if husbandry_id.is_empty():
		_restore_consumed(active_inventory, consumed)
		return _reject("adoption_failed", entity, species_id, evaluation)
	var action := StringName(evaluation.get("action", ""))
	match action:
		&"accelerate_growth":
			return _commit_baby_feed(
				husbandry_id,
				entity,
				profile,
				evaluation,
				active_inventory,
				consumed,
				was_managed,
				previous_record
			)
		&"enter_love":
			return _commit_adult_feed(
				husbandry_id,
				entity,
				profile,
				evaluation,
				active_inventory,
				consumed,
				was_managed,
				previous_record
			)
		_:
			_rollback_target(husbandry_id, entity, was_managed, previous_record)
			_restore_consumed(active_inventory, consumed)
			return _reject("unknown_action", entity, species_id, evaluation)


func get_entity_prompt(focus: Dictionary, selected_item_id: String) -> Dictionary:
	var species_id := str(focus.get("species_id", ""))
	if not registry.supports_species(species_id):
		return {}
	var profile := registry.get_species(species_id)
	var entity := _entity_from_focus(focus)
	var husbandry_id := _husbandry_id(entity)
	var state := (
		records.get(husbandry_id, {}).duplicate(true)
		if not husbandry_id.is_empty() and records.has(husbandry_id)
		else _default_record("", species_id, entity)
	)
	var feed_item := str(profile.get("feed_item", ""))
	var feed_name := _display_name(feed_item)
	var stage := str(state.get("stage", PolicyScript.STAGE_ADULT))
	var status := "成年 · 可繁殖"
	var secondary := "喜欢：%s" % feed_name
	var tone := "info"
	if stage == PolicyScript.STAGE_BABY:
		var growth_remaining := float(state.get("growth_remaining_seconds", 0.0))
		status = "幼年 · 约 %s 后成年" % policy.format_duration(growth_remaining)
		if selected_item_id == feed_item:
			secondary = "[鼠标右键] 喂食%s，加速成长" % feed_name
			tone = "success"
	elif float(state.get("breed_cooldown_seconds", 0.0)) > 0.0:
		status = "繁殖冷却 · %s" % policy.format_duration(
			float(state.get("breed_cooldown_seconds", 0.0))
		)
		secondary = "喜欢：%s" % feed_name
	elif float(state.get("love_remaining_seconds", 0.0)) > 0.0:
		status = "已准备繁殖 · 还剩 %s" % policy.format_duration(
			float(state.get("love_remaining_seconds", 0.0))
		)
		secondary = "寻找附近同类"
		tone = "success"
	elif selected_item_id == feed_item:
		secondary = "[鼠标右键] 喂食%s，进入繁殖状态" % feed_name
		tone = "success"
	var health_text := ""
	if focus.has("health") and focus.has("max_health"):
		health_text = "生命 %.0f / %.0f · " % [
			float(focus.get("health", 0.0)),
			float(focus.get("max_health", 0.0)),
		]
	return {
		"visible": true,
		"title": str(focus.get("display_name", profile.get("name", species_id))),
		"subtitle": health_text + status,
		"primary": "[鼠标左键] 攻击",
		"secondary": secondary,
		"tone": tone,
	}


func _process(delta: float) -> void:
	if not _active:
		return
	var safe_delta := maxf(0.0, delta)
	for raw_id in records.keys():
		var husbandry_id := str(raw_id)
		var record: Dictionary = records[husbandry_id]
		var entity := _live_entity(husbandry_id)
		if entity != null:
			record["position"] = _vector3_array(entity.global_position)
			record["health"] = float(_property_value(entity, "health", record.get("health", 1.0)))
			_apply_simulation_budget(entity)
		var love_before := float(record.get("love_remaining_seconds", 0.0))
		var cooldown_before := float(record.get("breed_cooldown_seconds", 0.0))
		record["love_remaining_seconds"] = maxf(0.0, love_before - safe_delta)
		record["breed_cooldown_seconds"] = maxf(0.0, cooldown_before - safe_delta)
		var grew := false
		if str(record.get("stage", PolicyScript.STAGE_ADULT)) == PolicyScript.STAGE_BABY:
			var growth_before := float(record.get("growth_remaining_seconds", 0.0))
			var growth_after := maxf(0.0, growth_before - safe_delta)
			record["growth_remaining_seconds"] = growth_after
			if growth_before > 0.0 and growth_after <= 0.0:
				record["stage"] = PolicyScript.STAGE_ADULT
				grew = true
		records[husbandry_id] = record
		if grew:
			_apply_record_to_entity(husbandry_id)
			var grow_result := _result_for_record(husbandry_id)
			grow_result["message"] = "%s 已经长大" % str(grow_result.get("display_name", "动物"))
			animal_grew.emit(grow_result)
			_emit_state_changed(entity)
		elif (
			(love_before > 0.0 and float(record.get("love_remaining_seconds", 0.0)) <= 0.0)
			or (
				cooldown_before > 0.0
				and float(record.get("breed_cooldown_seconds", 0.0)) <= 0.0
			)
		):
			_emit_state_changed(entity)


func _commit_baby_feed(
	husbandry_id: String,
	entity: Node,
	profile: Dictionary,
	evaluation: Dictionary,
	active_inventory: Node,
	consumed: Dictionary,
	was_managed: bool,
	previous_record: Dictionary
) -> Dictionary:
	if not records.has(husbandry_id):
		_restore_consumed(active_inventory, consumed)
		return _reject("target_changed", entity, _species_id(entity), evaluation)
	var record: Dictionary = records[husbandry_id]
	record["growth_remaining_seconds"] = float(
		evaluation.get("target_growth_remaining_seconds", 0.0)
	)
	if float(record.get("growth_remaining_seconds", 0.0)) <= 0.0:
		record["stage"] = PolicyScript.STAGE_ADULT
	records[husbandry_id] = record
	_apply_record_to_entity(husbandry_id)
	var result := _result_for_record(husbandry_id)
	result.merge(evaluation, true)
	result["handled"] = true
	result["success"] = true
	result["action"] = &"feed_baby"
	result["message"] = "%s 的成长加速了" % str(result.get("display_name", "幼年动物"))
	animal_fed.emit(result.duplicate(true))
	if str(record.get("stage", "")) == PolicyScript.STAGE_ADULT:
		animal_grew.emit(result.duplicate(true))
	_emit_state_changed(entity)
	return result


func _commit_adult_feed(
	husbandry_id: String,
	entity: Node,
	profile: Dictionary,
	evaluation: Dictionary,
	active_inventory: Node,
	consumed: Dictionary,
	was_managed: bool,
	previous_record: Dictionary
) -> Dictionary:
	if not records.has(husbandry_id):
		_restore_consumed(active_inventory, consumed)
		return _reject("target_changed", entity, _species_id(entity), evaluation)
	var record: Dictionary = records[husbandry_id]
	record["love_remaining_seconds"] = float(evaluation.get("love_seconds", 30.0))
	records[husbandry_id] = record
	var pair_id := _find_pair(husbandry_id)
	if pair_id.is_empty():
		var ready_result := _result_for_record(husbandry_id)
		ready_result.merge(evaluation, true)
		ready_result["handled"] = true
		ready_result["success"] = true
		ready_result["action"] = &"prepare_breeding"
		ready_result["message"] = "%s 已准备繁殖，再喂食附近另一只同类" % str(
			ready_result.get("display_name", "动物")
		)
		animal_ready.emit(ready_result.duplicate(true))
		_emit_state_changed(entity)
		return ready_result
	if records.size() >= registry.get_max_managed_animals():
		_rollback_target(husbandry_id, entity, was_managed, previous_record)
		_restore_consumed(active_inventory, consumed)
		return _reject("population_cap", entity, _species_id(entity), evaluation)
	var baby_id := _spawn_baby(husbandry_id, pair_id, profile)
	if baby_id.is_empty():
		_rollback_target(husbandry_id, entity, was_managed, previous_record)
		_restore_consumed(active_inventory, consumed)
		return _reject("spawn_failed", entity, _species_id(entity), evaluation)
	var cooldown := float(profile.get("breed_cooldown_seconds", 180.0))
	for parent_id in [husbandry_id, pair_id]:
		var parent_record: Dictionary = records[parent_id]
		parent_record["love_remaining_seconds"] = 0.0
		parent_record["breed_cooldown_seconds"] = cooldown
		records[parent_id] = parent_record
		_emit_state_changed(_live_entity(parent_id))
	var result := _result_for_record(baby_id)
	result["handled"] = true
	result["success"] = true
	result["action"] = &"breed_animals"
	result["parent_ids"] = [husbandry_id, pair_id]
	result["message"] = "新的%s出生了" % str(result.get("display_name", "幼年动物"))
	baby_born.emit(result.duplicate(true))
	return result


func _find_pair(husbandry_id: String) -> String:
	if not records.has(husbandry_id):
		return ""
	var first: Dictionary = records[husbandry_id]
	var first_entity := _live_entity(husbandry_id)
	if first_entity == null:
		return ""
	for raw_other_id in records:
		var other_id := str(raw_other_id)
		if other_id == husbandry_id:
			continue
		var other_entity := _live_entity(other_id)
		if other_entity == null:
			continue
		var other: Dictionary = records[other_id]
		if policy.can_pair(
			first,
			other,
			first_entity.global_position.distance_to(other_entity.global_position),
			registry.get_pair_radius()
		):
			return other_id
	return ""


func _spawn_baby(first_id: String, second_id: String, profile: Dictionary) -> String:
	if spawner == null or not spawner.has_method("spawn_creature"):
		return ""
	var first_entity := _live_entity(first_id)
	var second_entity := _live_entity(second_id)
	if first_entity == null or second_entity == null:
		return ""
	var spawn_position := (first_entity.global_position + second_entity.global_position) * 0.5
	spawn_position += Vector3(0.35, 0.1, 0.0)
	if world != null and world.has_method("resolve_ground_position"):
		var resolved: Variant = world.call("resolve_ground_position", spawn_position)
		if resolved is Vector3:
			spawn_position = resolved
	var spawned_variant: Variant = spawner.call(
		"spawn_creature", str(profile.get("id", "")), spawn_position
	)
	if spawned_variant is not Node3D:
		return ""
	var child: Node3D = spawned_variant
	var husbandry_id := _next_id()
	var record := _default_record(husbandry_id, str(profile.get("id", "")), child)
	record["stage"] = PolicyScript.STAGE_BABY
	record["growth_remaining_seconds"] = float(profile.get("growth_seconds", 300.0))
	records[husbandry_id] = record
	_register_live_creature(husbandry_id, child)
	return husbandry_id


func _ensure_managed(entity: Node, species_id: String) -> String:
	var husbandry_id := _husbandry_id(entity)
	if not husbandry_id.is_empty() and records.has(husbandry_id):
		_register_live_creature(husbandry_id, entity)
		return husbandry_id
	if records.size() >= registry.get_max_managed_animals():
		return ""
	husbandry_id = husbandry_id if not husbandry_id.is_empty() else _next_id()
	var record := _default_record(husbandry_id, species_id, entity)
	records[husbandry_id] = record
	_register_live_creature(husbandry_id, entity)
	return husbandry_id


func _register_live_creature(husbandry_id: String, entity: Node) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	_live[husbandry_id] = entity
	entity.set_meta(META_ID, husbandry_id)
	if not entity.has_meta(META_BASE_NAME):
		entity.set_meta(META_BASE_NAME, str(_property_value(entity, "display_name", entity.name)))
	if not entity.is_in_group(GROUP_PERSISTENT):
		entity.add_to_group(GROUP_PERSISTENT)
	if entity.has_signal("died"):
		var callback := Callable(self, "_on_creature_died").bind(husbandry_id)
		if not entity.is_connected("died", callback):
			entity.connect("died", callback)
	_apply_record_to_entity(husbandry_id)


func _restore_managed_animals() -> void:
	if spawner == null or not spawner.has_method("spawn_creature"):
		return
	for raw_id in records.keys():
		var husbandry_id := str(raw_id)
		if _live_entity(husbandry_id) != null:
			continue
		var record: Dictionary = records[husbandry_id]
		var position := _vector3_from_value(record.get("position", []))
		if not _vector3_is_finite(position):
			continue
		if world != null and world.has_method("resolve_ground_position"):
			var resolved: Variant = world.call("resolve_ground_position", position)
			if resolved is Vector3:
				position = resolved
		var spawned_variant: Variant = spawner.call(
			"spawn_creature", str(record.get("species_id", "")), position
		)
		if spawned_variant is Node3D:
			_register_live_creature(husbandry_id, spawned_variant)


func _apply_record_to_entity(husbandry_id: String) -> void:
	if not records.has(husbandry_id):
		return
	var entity := _live_entity(husbandry_id)
	if entity == null:
		return
	var record: Dictionary = records[husbandry_id]
	var profile := registry.get_species(str(record.get("species_id", "")))
	var baby := str(record.get("stage", PolicyScript.STAGE_ADULT)) == PolicyScript.STAGE_BABY
	entity.scale = Vector3.ONE * (registry.get_baby_scale() if baby else 1.0)
	var base_name := str(profile.get("name", entity.get_meta(META_BASE_NAME, entity.name)))
	_set_property_if_present(entity, "display_name", "幼年%s" % base_name if baby else base_name)
	var maximum := maxf(1.0, float(_property_value(entity, "max_health", 1.0)))
	_set_property_if_present(
		entity,
		"health",
		clampf(float(record.get("health", maximum)), 0.1, maximum)
	)


func _apply_simulation_budget(entity: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var should_simulate := (
		entity.global_position.distance_squared_to(player.global_position)
		<= pow(registry.get_simulation_radius(), 2.0)
	)
	entity.set_physics_process(should_simulate)
	if not should_simulate and entity is CharacterBody3D:
		entity.velocity = Vector3.ZERO


func _sync_live_records() -> void:
	for raw_id in records.keys():
		var husbandry_id := str(raw_id)
		var entity := _live_entity(husbandry_id)
		if entity == null:
			continue
		var record: Dictionary = records[husbandry_id]
		record["position"] = _vector3_array(entity.global_position)
		record["health"] = float(_property_value(entity, "health", record.get("health", 1.0)))
		records[husbandry_id] = record


func _default_record(husbandry_id: String, species_id: String, entity: Node) -> Dictionary:
	var position := Vector3.ZERO
	if entity is Node3D:
		position = entity.global_position
	var health_value := float(_property_value(entity, "health", 1.0))
	return {
		"id": husbandry_id,
		"species_id": species_id,
		"position": _vector3_array(position),
		"stage": PolicyScript.STAGE_ADULT,
		"growth_remaining_seconds": 0.0,
		"breed_cooldown_seconds": 0.0,
		"love_remaining_seconds": 0.0,
		"health": health_value,
	}


func _normalize_saved_record(
	husbandry_id: String, raw_record: Dictionary, elapsed: float
) -> Dictionary:
	var species_id := str(raw_record.get("species_id", ""))
	if not registry.supports_species(species_id):
		return {}
	var position := _vector3_from_value(raw_record.get("position", []))
	if not _vector3_is_finite(position):
		return {}
	var profile := registry.get_species(species_id)
	var stage := str(raw_record.get("stage", PolicyScript.STAGE_ADULT))
	if stage not in [PolicyScript.STAGE_ADULT, PolicyScript.STAGE_BABY]:
		stage = PolicyScript.STAGE_ADULT
	var growth_remaining := maxf(
		0.0, float(raw_record.get("growth_remaining_seconds", 0.0)) - elapsed
	)
	if stage == PolicyScript.STAGE_BABY and growth_remaining <= 0.0:
		stage = PolicyScript.STAGE_ADULT
	return {
		"id": husbandry_id,
		"species_id": species_id,
		"position": _vector3_array(position),
		"stage": stage,
		"growth_remaining_seconds": growth_remaining if stage == PolicyScript.STAGE_BABY else 0.0,
		"breed_cooldown_seconds": maxf(
			0.0, float(raw_record.get("breed_cooldown_seconds", 0.0)) - elapsed
		),
		"love_remaining_seconds": maxf(
			0.0, float(raw_record.get("love_remaining_seconds", 0.0)) - elapsed
		),
		"health": maxf(0.1, float(raw_record.get("health", 1.0))),
		"growth_seconds": float(profile.get("growth_seconds", 0.0)),
	}


func _serialized_record(record: Dictionary) -> Dictionary:
	return {
		"species_id": str(record.get("species_id", "")),
		"position": record.get("position", []).duplicate(true),
		"stage": str(record.get("stage", PolicyScript.STAGE_ADULT)),
		"growth_remaining_seconds": maxf(
			0.0, float(record.get("growth_remaining_seconds", 0.0))
		),
		"breed_cooldown_seconds": maxf(
			0.0, float(record.get("breed_cooldown_seconds", 0.0))
		),
		"love_remaining_seconds": maxf(
			0.0, float(record.get("love_remaining_seconds", 0.0))
		),
		"health": maxf(0.1, float(record.get("health", 1.0))),
	}


func _result_for_record(husbandry_id: String) -> Dictionary:
	var record := get_record(husbandry_id)
	var profile := registry.get_species(str(record.get("species_id", "")))
	return {
		"husbandry_id": husbandry_id,
		"species_id": str(record.get("species_id", "")),
		"display_name": (
			"幼年%s" % str(profile.get("name", "动物"))
			if str(record.get("stage", "")) == PolicyScript.STAGE_BABY
			else str(profile.get("name", "动物"))
		),
		"stage": str(record.get("stage", PolicyScript.STAGE_ADULT)),
		"growth_remaining_seconds": float(record.get("growth_remaining_seconds", 0.0)),
		"breed_cooldown_seconds": float(record.get("breed_cooldown_seconds", 0.0)),
		"love_remaining_seconds": float(record.get("love_remaining_seconds", 0.0)),
	}


func _rollback_target(
	husbandry_id: String,
	entity: Node,
	was_managed: bool,
	previous_record: Dictionary
) -> void:
	if was_managed:
		records[husbandry_id] = previous_record.duplicate(true)
		_register_live_creature(husbandry_id, entity)
		return
	records.erase(husbandry_id)
	_live.erase(husbandry_id)
	if entity != null and is_instance_valid(entity):
		entity.remove_meta(META_ID)
		if entity.is_in_group(GROUP_PERSISTENT):
			entity.remove_from_group(GROUP_PERSISTENT)
		entity.scale = Vector3.ONE
		_set_property_if_present(
			entity,
			"display_name",
			str(entity.get_meta(META_BASE_NAME, _property_value(entity, "display_name", entity.name)))
		)


func _on_creature_died(
	_species_id_value: String,
	_drops: Dictionary,
	_world_position: Vector3,
	husbandry_id: String
) -> void:
	var entity := _live_entity(husbandry_id)
	records.erase(husbandry_id)
	_live.erase(husbandry_id)
	_emit_state_changed(entity)


func _reject(reason: String, entity: Node, species_id: String, context: Dictionary) -> Dictionary:
	var result := context.duplicate(true)
	result["handled"] = true
	result["success"] = false
	result["reason"] = reason
	result["species_id"] = species_id
	result["display_name"] = str(registry.get_species(species_id).get("name", species_id))
	result["message"] = _message_for_reason(reason, species_id, result)
	interaction_rejected.emit(reason, result.duplicate(true))
	_emit_state_changed(entity)
	return result


func _message_for_reason(reason: String, species_id: String, context: Dictionary) -> String:
	var animal_name := str(registry.get_species(species_id).get("name", "动物"))
	var feed_name := _display_name(str(context.get("feed_item", "")))
	match reason:
		"wrong_feed":
			return "%s喜欢%s" % [animal_name, feed_name]
		"breed_cooldown":
			return "%s还需 %s 才能再次繁殖" % [
				animal_name,
				policy.format_duration(float(context.get("remaining_seconds", 0.0))),
			]
		"already_ready":
			return "%s已经准备繁殖，请寻找附近同类" % animal_name
		"population_cap":
			return "已达到可管理动物上限（%d）" % registry.get_max_managed_animals()
		"spawn_failed":
			return "幼崽出生位置不可用，饲料已退回"
		"consume_failed":
			return "饲料状态发生变化，本次喂食已取消"
		"inventory_contract_missing":
			return "背包服务暂不可用"
		_:
			return "暂时无法喂食%s" % animal_name


func _restore_consumed(active_inventory: Node, consumed: Dictionary) -> void:
	if consumed.is_empty() or active_inventory == null or not active_inventory.has_method("add_item"):
		return
	var item_id := str(consumed.get("item_id", ""))
	var count := maxi(0, int(consumed.get("count", 0)))
	if item_id.is_empty() or count <= 0:
		return
	var remaining := int(
		active_inventory.call(
			"add_item", item_id, count, consumed.get("metadata", {}).duplicate(true)
		)
	)
	if remaining > 0:
		push_error("Husbandry rollback could not restore %d x %s" % [remaining, item_id])


func _next_id() -> String:
	var base := int(Time.get_unix_time_from_system())
	while true:
		_id_counter += 1
		var candidate := "animal@%d-%d" % [base, _id_counter]
		if not records.has(candidate):
			return candidate
	return ""


func _husbandry_id(entity: Node) -> String:
	if entity == null or not is_instance_valid(entity):
		return ""
	return str(entity.get_meta(META_ID, ""))


func _species_id(entity: Node) -> String:
	return str(_property_value(entity, "species_id", ""))


func _live_entity(husbandry_id: String) -> Node3D:
	var value: Variant = _live.get(husbandry_id)
	if value is Node3D and is_instance_valid(value):
		return value
	_live.erase(husbandry_id)
	return null


func _entity_from_focus(focus: Dictionary) -> Node:
	var entity_id := int(focus.get("entity_id", 0))
	if entity_id <= 0:
		return null
	var value: Variant = instance_from_id(entity_id)
	return value if value is Node else null


func _emit_state_changed(entity: Node) -> void:
	state_changed.emit(entity.get_instance_id() if entity != null and is_instance_valid(entity) else 0)


func _display_name(item_id: String) -> String:
	if item_id.is_empty():
		return "对应饲料"
	if item_registry != null and item_registry.has_method("get_display_name"):
		return str(item_registry.call("get_display_name", item_id))
	return item_id


func _property_value(target: Object, property_name: String, fallback: Variant) -> Variant:
	if target == null:
		return fallback
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return fallback


func _set_property_if_present(target: Object, property_name: String, value: Variant) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			target.set(property_name, value)
			return true
	return false


func _vector3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3_from_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)


func _vector3_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
