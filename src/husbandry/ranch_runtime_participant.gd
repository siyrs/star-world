class_name RanchRuntimeParticipant
extends Node

signal following_transition_announced(kind: String, count: int, snapshot: Dictionary)
signal product_batch_announced(summary: Dictionary)

const AttractionServiceScript = preload(
	"res://src/husbandry/animal_attraction_service.gd"
)
const ProductServiceScript = preload(
	"res://src/husbandry/animal_product_service.gd"
)
const ProductStateMigrationScript = preload(
	"res://src/husbandry/animal_product_state_migration.gd"
)
const NotificationPolicyScript = preload(
	"res://src/husbandry/ranch_notification_policy.gd"
)

var hub: Node
var attraction_service: Node
var product_service: Node
var _bound_player: Node3D
var _installed := false
var _active := false
var _shutdown := false
var _last_following_count := 0
var _following_start_count := 0
var _following_stop_count := 0
var _product_batch_count := 0
var _product_item_total := 0
var _product_audio_count := 0
var _last_product_summary: Dictionary = {}
var _pending_product_counts: Dictionary = {}
var _pending_product_names: Dictionary = {}
var _pending_husbandry_ids: Dictionary = {}
var _product_flush_scheduled := false


func get_dependencies() -> Array[StringName]:
	return []


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	hub = p_hub
	var inventory: Node = hub.get("inventory") as Node
	var spawner: Node = hub.get("creature_spawner") as Node
	var husbandry_service: Node = hub.get("husbandry_service") as Node
	var husbandry_interaction: Node = hub.get("husbandry_interaction") as Node
	if (
		inventory == null
		or spawner == null
		or husbandry_service == null
		or husbandry_interaction == null
		or not hub.has_method("_add_service")
	):
		return false
	attraction_service = hub.call(
		"_add_service", AttractionServiceScript.new(), "AnimalAttractionService"
	) as Node
	if attraction_service == null or not bool(
		attraction_service.call("setup", inventory, spawner)
	):
		_dispose_service(attraction_service)
		attraction_service = null
		return false
	product_service = hub.call(
		"_add_service", ProductServiceScript.new(), "AnimalProductService"
	) as Node
	if product_service == null or not bool(
		product_service.call(
			"setup",
			inventory.get("registry"),
			inventory,
			husbandry_service,
			spawner
		)
	):
		if attraction_service.has_method("shutdown"):
			attraction_service.call("shutdown")
		_dispose_service(product_service)
		_dispose_service(attraction_service)
		product_service = null
		attraction_service = null
		return false
	hub.set("animal_attraction_service", attraction_service)
	hub.set("animal_product_service", product_service)
	if husbandry_interaction.has_method("set_product_service"):
		husbandry_interaction.call("set_product_service", product_service)
	_connect_runtime_signals()
	_installed = true
	_shutdown = false
	return true


func normalize_world_state(state: Dictionary) -> Dictionary:
	return ProductStateMigrationScript.normalize_world_state(state)


func begin_world(state: Dictionary) -> void:
	_active = false
	_last_following_count = 0
	_reset_pending_product_batch()
	_unbind_player()
	if attraction_service != null and attraction_service.has_method("clear"):
		attraction_service.call("clear")
	if product_service != null:
		if product_service.has_method("clear"):
			product_service.call("clear")
		var normalized := normalize_world_state(state)
		product_service.call("deserialize", normalized.get("animal_products", {}))


func attach_game(
	_world,
	player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	_unbind_player()
	if attraction_service != null:
		attraction_service.call("attach_player", player)
	if product_service != null:
		product_service.call("attach_player", player)
	_bound_player = player


func activate() -> void:
	if _active:
		return
	_active = true
	if attraction_service != null:
		attraction_service.call("activate")
	if product_service != null:
		product_service.call("activate")


func save_into(payload: Dictionary) -> void:
	if product_service != null:
		payload["animal_products"] = product_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["animal_attraction"] = (
		attraction_service.call("get_snapshot") if attraction_service != null else {}
	)
	snapshot["animal_products"] = (
		product_service.call("get_snapshot") if product_service != null else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_last_following_count = 0
	_reset_pending_product_batch()
	_unbind_player()
	if attraction_service != null and attraction_service.has_method("clear"):
		attraction_service.call("clear")
	if product_service != null and product_service.has_method("clear"):
		product_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	_disconnect_runtime_signals()
	var husbandry_interaction: Node = (
		hub.get("husbandry_interaction") as Node
		if hub != null and is_instance_valid(hub)
		else null
	)
	if husbandry_interaction != null and husbandry_interaction.has_method("set_product_service"):
		husbandry_interaction.call("set_product_service", null)
	if attraction_service != null and attraction_service.has_method("shutdown"):
		attraction_service.call("shutdown")
	if product_service != null and product_service.has_method("shutdown"):
		product_service.call("shutdown")


func get_attraction_service() -> Node:
	return attraction_service


func get_product_service() -> Node:
	return product_service


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"attraction_ready": (
			attraction_service != null and is_instance_valid(attraction_service)
		),
		"product_ready": product_service != null and is_instance_valid(product_service),
		"bound_player_id": (
			_bound_player.get_instance_id()
			if _bound_player != null and is_instance_valid(_bound_player)
			else 0
		),
		"following_count": _last_following_count,
		"following_start_count": _following_start_count,
		"following_stop_count": _following_stop_count,
		"product_batch_count": _product_batch_count,
		"product_item_total": _product_item_total,
		"product_audio_count": _product_audio_count,
		"product_flush_scheduled": _product_flush_scheduled,
		"pending_product_types": _pending_product_counts.size(),
		"last_product_summary": _last_product_summary.duplicate(true),
	}


func flush_pending_product_batch() -> Dictionary:
	_flush_product_batch()
	return _last_product_summary.duplicate(true)


func _connect_runtime_signals() -> void:
	_connect_if_needed(
		attraction_service, "following_changed", Callable(self, "_on_following_changed")
	)
	_connect_if_needed(
		product_service, "product_spawned", Callable(self, "_on_product_spawned")
	)


func _disconnect_runtime_signals() -> void:
	_disconnect_if_needed(
		attraction_service, "following_changed", Callable(self, "_on_following_changed")
	)
	_disconnect_if_needed(
		product_service, "product_spawned", Callable(self, "_on_product_spawned")
	)


func _connect_if_needed(target: Node, signal_name: String, callback: Callable) -> void:
	if (
		target != null
		and is_instance_valid(target)
		and target.has_signal(signal_name)
		and not target.is_connected(signal_name, callback)
	):
		target.connect(signal_name, callback)


func _disconnect_if_needed(target: Node, signal_name: String, callback: Callable) -> void:
	if (
		target != null
		and is_instance_valid(target)
		and target.has_signal(signal_name)
		and target.is_connected(signal_name, callback)
	):
		target.disconnect(signal_name, callback)


func _on_following_changed(count: int) -> void:
	var normalized_count := maxi(0, count)
	var transition := NotificationPolicyScript.following_transition(
		_last_following_count, normalized_count
	)
	_last_following_count = normalized_count
	if not _active or transition.is_empty():
		return
	var kind := str(transition.get("kind", ""))
	if kind == "started":
		_following_start_count += 1
	elif kind == "stopped":
		_following_stop_count += 1
	_publish_message(
		str(transition.get("message", "牧场跟随状态已更新")),
		str(transition.get("severity", "info")),
		"ranch_following:%s" % kind,
		float(transition.get("duration", 2.6))
	)
	following_transition_announced.emit(
		kind, normalized_count, get_lifecycle_snapshot()
	)


func _on_product_spawned(result: Dictionary) -> void:
	if not _active:
		return
	var item_id := str(result.get("product_item", "")).strip_edges()
	var count := maxi(0, int(result.get("count", 0)))
	if item_id.is_empty() or count <= 0:
		return
	_pending_product_counts[item_id] = int(_pending_product_counts.get(item_id, 0)) + count
	_pending_product_names[item_id] = str(result.get("product_name", item_id))
	var husbandry_id := str(result.get("husbandry_id", "")).strip_edges()
	if not husbandry_id.is_empty():
		_pending_husbandry_ids[husbandry_id] = true
	if not _product_flush_scheduled:
		_product_flush_scheduled = true
		call_deferred("_flush_product_batch")


func _flush_product_batch() -> void:
	_product_flush_scheduled = false
	if not _active:
		_reset_pending_product_batch()
		return
	var summary := NotificationPolicyScript.product_batch(
		_pending_product_counts,
		_pending_product_names,
		_pending_husbandry_ids
	)
	_reset_pending_product_batch()
	if summary.is_empty():
		return
	_product_batch_count += 1
	_product_item_total += maxi(0, int(summary.get("total_count", 0)))
	summary["batch_index"] = _product_batch_count
	_last_product_summary = summary.duplicate(true)
	_publish_message(
		str(summary.get("message", "牧场产物已生成")),
		str(summary.get("severity", "success")),
		"ranch_product_batch:%d" % _product_batch_count,
		float(summary.get("duration", 3.2))
	)
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")
		_product_audio_count += 1
	product_batch_announced.emit(summary.duplicate(true))


func _reset_pending_product_batch() -> void:
	_product_flush_scheduled = false
	_pending_product_counts.clear()
	_pending_product_names.clear()
	_pending_husbandry_ids.clear()


func _unbind_player() -> void:
	if attraction_service != null and attraction_service.has_method("attach_player"):
		attraction_service.call("attach_player", null)
	if product_service != null and product_service.has_method("attach_player"):
		product_service.call("attach_player", null)
	_bound_player = null


func _publish_message(
	message: String, severity: String, dedupe_key: String, duration: float
) -> void:
	if hub != null and hub.has_method("_publish_character_message"):
		hub.call("_publish_character_message", message, severity, dedupe_key, duration)


func _dispose_service(service: Node) -> void:
	if service == null or not is_instance_valid(service):
		return
	var parent := service.get_parent()
	if parent != null:
		parent.remove_child(service)
	service.queue_free()
