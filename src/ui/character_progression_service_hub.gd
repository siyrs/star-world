class_name CharacterProgressionServiceHub
extends "res://src/ui/tool_progression_service_hub.gd"

const EquipmentServiceScript = preload("res://src/equipment/equipment_service.gd")
const AttributeServiceScript = preload("res://src/attribute/attribute_service.gd")
const CombatServiceScript = preload("res://src/combat/combat_service.gd")
const RangedCombatServiceScript = preload("res://src/combat/ranged_combat_service.gd")
const AgricultureRuntimeParticipantScript = preload(
	"res://src/agriculture/scalable_agriculture_runtime_participant.gd"
)
const RestServiceScript = preload("res://src/rest/rest_service.gd")
const AGRICULTURE_RUNTIME_FEATURE := &"agriculture_runtime"

var equipment_service: Node
var attribute_service: Node
var combat_service: Node
var ranged_combat_service: Node
var agriculture_service: Node
var agriculture_interaction: Node
var agriculture_runtime_participant: Node
var rest_service: Node


func _ready() -> void:
	super._ready()
	equipment_service = _add_service(EquipmentServiceScript.new(), "EquipmentService")
	equipment_service.call("setup", inventory.registry)
	attribute_service = _add_service(AttributeServiceScript.new(), "AttributeService")
	attribute_service.call("setup", equipment_service)
	combat_service = _add_service(CombatServiceScript.new(), "CombatService")
	combat_service.call("setup", attribute_service, equipment_service)
	ranged_combat_service = _add_service(
		RangedCombatServiceScript.new(), "RangedCombatService"
	)
	ranged_combat_service.call("setup", inventory, equipment_service, combat_service)
	agriculture_runtime_participant = _register_feature_participant(
		AGRICULTURE_RUNTIME_FEATURE,
		AgricultureRuntimeParticipantScript.new(),
		"agriculture runtime"
	)
	if agriculture_runtime_participant != null:
		agriculture_service = agriculture_runtime_participant.call(
			"get_agriculture_service"
		) as Node
		agriculture_interaction = agriculture_runtime_participant.call(
			"get_interaction_service"
		) as Node
	rest_service = _add_service(RestServiceScript.new(), "RestService")
	rest_service.call("setup", day_night)
	if block_interaction != null and block_interaction.has_method("register_extension"):
		block_interaction.call("register_extension", rest_service)
	if game_ui != null and game_ui.has_method("setup_character_progression"):
		game_ui.call(
			"setup_character_progression",
			equipment_service,
			attribute_service,
			combat_service,
			ranged_combat_service
		)
	_connect_character_feedback()
	_connect_ranged_feedback()
	_connect_rest_feedback()


func _begin_world(state: Dictionary) -> void:
	if ranged_combat_service != null:
		ranged_combat_service.call("clear", "begin_world")
	if equipment_service != null:
		equipment_service.call("deserialize", state.get("equipment", {}))
	if attribute_service != null:
		attribute_service.call("deserialize", state.get("attributes", {}))
	if rest_service != null:
		rest_service.call("deserialize", state.get("rest", {}))
	super._begin_world(state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if rest_service != null:
		rest_service.call("attach_world", world, player)
	if player == null:
		return
	if player.has_method("bind_equipment_service"):
		player.call("bind_equipment_service", equipment_service)
	if player.has_method("bind_attribute_service"):
		player.call("bind_attribute_service", attribute_service)
	if player.has_method("bind_combat_service"):
		player.call("bind_combat_service", combat_service)
	if player.has_method("bind_ranged_combat_service"):
		player.call("bind_ranged_combat_service", ranged_combat_service)


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if equipment_service != null:
		current_state["equipment"] = equipment_service.call("serialize")
	if attribute_service != null:
		current_state["attributes"] = attribute_service.call("serialize")
	if rest_service != null:
		current_state["rest"] = rest_service.call("serialize")
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	_clear_progression_state("world_start_failed")
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		_clear_progression_state("return_to_menu")


func get_character_snapshot() -> Dictionary:
	return {
		"equipment": (
			equipment_service.call("get_snapshot") if equipment_service != null else {}
		),
		"attributes": (
			attribute_service.call("get_snapshot") if attribute_service != null else {}
		),
		"combat": combat_service.call("get_snapshot") if combat_service != null else {},
		"ranged_combat": (
			ranged_combat_service.call("get_snapshot")
			if ranged_combat_service != null
			else {}
		),
		"agriculture": (
			agriculture_service.call("get_runtime_snapshot")
			if agriculture_service != null
			and agriculture_service.has_method("get_runtime_snapshot")
			else {}
		),
		"rest": rest_service.call("get_snapshot") if rest_service != null else {},
	}


func _exit_tree() -> void:
	if (
		block_interaction != null
		and rest_service != null
		and block_interaction.has_method("unregister_extension")
	):
		block_interaction.call("unregister_extension", rest_service)
	_clear_progression_state("shutdown")
	super._exit_tree()


func _connect_character_feedback() -> void:
	if equipment_service == null:
		return
	equipment_service.connect("item_equipped", Callable(self, "_on_item_equipped"))
	equipment_service.connect("item_unequipped", Callable(self, "_on_item_unequipped"))
	equipment_service.connect("item_broken", Callable(self, "_on_equipped_item_broken"))


func _connect_ranged_feedback() -> void:
	if ranged_combat_service == null:
		return
	ranged_combat_service.connect("shot_fired", Callable(self, "_on_ranged_shot_fired"))
	ranged_combat_service.connect("shot_rejected", Callable(self, "_on_ranged_shot_rejected"))
	ranged_combat_service.connect("reload_started", Callable(self, "_on_ranged_reload_started"))
	ranged_combat_service.connect("reload_completed", Callable(self, "_on_ranged_reload_completed"))
	ranged_combat_service.connect("reload_cancelled", Callable(self, "_on_ranged_reload_cancelled"))


func _connect_rest_feedback() -> void:
	if rest_service == null:
		return
	rest_service.connect("spawn_point_changed", Callable(self, "_on_spawn_point_changed"))
	rest_service.connect("spawn_point_cleared", Callable(self, "_on_spawn_point_cleared"))


func _on_item_equipped(slot_id: String, item: Dictionary, _previous: Dictionary) -> void:
	var item_id := str(item.get("item_id", ""))
	var display_name := str(inventory.registry.get_display_name(item_id))
	_publish_character_message(
		"已装备 %s" % display_name, "success", "equipment:equip:%s" % slot_id
	)
	if audio_service != null and audio_service.has_method("play_craft"):
		audio_service.call("play_craft")


func _on_item_unequipped(slot_id: String, item: Dictionary) -> void:
	var item_id := str(item.get("item_id", ""))
	var display_name := str(inventory.registry.get_display_name(item_id))
	_publish_character_message(
		"已卸下 %s" % display_name, "info", "equipment:unequip:%s" % slot_id
	)


func _on_equipped_item_broken(
	slot_id: String, _item_id: String, display_name: String, _reason: String
) -> void:
	_publish_character_message(
		"%s 已损坏" % display_name, "warning", "equipment:broken:%s" % slot_id, 3.2
	)


func _on_ranged_shot_fired(result: Dictionary) -> void:
	var attack_kind := str(result.get("attack_kind", "ranged"))
	if attack_kind == "firearm":
		var weapon_name := str(result.get("weapon_display_name", "枪械"))
		var loaded := int(result.get("magazine_after", 0))
		var capacity := int(result.get("magazine_capacity", 0))
		_publish_character_message(
			"%s 开火 · 弹匣 %d/%d" % [weapon_name, loaded, capacity],
			"info",
			"firearm:fired:%s" % str(result.get("weapon_item_id", "")),
			0.75
		)
		return
	_publish_character_message(
		"箭矢已发射 · 蓄力 %d%%" % int(round(float(result.get("charge_ratio", 0.0)) * 100.0)),
		"info",
		"ranged:fired",
		1.4
	)


func _on_ranged_shot_rejected(result: Dictionary) -> void:
	var reason := str(result.get("reason", "rejected"))
	var message: String = str({
		"no_ammo": "没有箭矢",
		"undercharged": "蓄力不足，未消耗箭矢",
		"cooldown": "武器尚未准备好",
		"projectile_capacity": "场景中的飞行箭矢已达到上限",
		"weapon_changed": "操作期间武器已改变",
		"empty_magazine": "弹匣已空，按 R 或左肩键换弹",
		"reloading": "正在换弹",
		"already_reloading": "已经在换弹",
		"no_reserve_ammo": "没有备用弹药",
		"magazine_full": "弹匣已满",
	}.get(reason, "本次远程攻击未生效"))
	_publish_character_message(
		message, "warning", "ranged:rejected:%s" % reason, 2.2
	)


func _on_ranged_reload_started(result: Dictionary) -> void:
	_publish_character_message(
		"%s 开始换弹" % str(result.get("weapon_display_name", "枪械")),
		"info",
		"firearm:reload:start",
		1.2
	)


func _on_ranged_reload_completed(result: Dictionary) -> void:
	_publish_character_message(
		"换弹完成 · 弹匣 %d/%d" % [
			int(result.get("magazine_after", 0)),
			int(result.get("magazine_capacity", 0)),
		],
		"success",
		"firearm:reload:complete",
		1.4
	)


func _on_ranged_reload_cancelled(result: Dictionary) -> void:
	_publish_character_message(
		"换弹已取消 · %s" % str(result.get("reason", "cancelled")),
		"warning",
		"firearm:reload:cancel",
		1.4
	)


func _on_spawn_point_changed(_position: Vector3, _bed_position: Vector3i) -> void:
	if audio_service != null and audio_service.has_method("play_block_place"):
		audio_service.call("play_block_place", "wool")


func _on_spawn_point_cleared(reason: String) -> void:
	var message := (
		"床已被移除，重生点恢复为世界出生点"
		if reason == "bed_removed"
		else "床的安全空间已失效，重生点恢复为世界出生点"
	)
	_publish_character_message(message, "warning", "rest:spawn_cleared", 3.2)


func _publish_character_message(
	message: String, severity: String, dedupe_key: String, duration: float = 2.2
) -> void:
	if player_experience != null and player_experience.has_method("publish_message"):
		player_experience.call("publish_message", message, severity, duration, dedupe_key)


func _clear_progression_state(reason: String = "clear") -> void:
	if ranged_combat_service != null and ranged_combat_service.has_method("clear"):
		ranged_combat_service.call("clear", reason)
	if rest_service != null and rest_service.has_method("clear"):
		rest_service.call("clear")
	if equipment_service != null and equipment_service.has_method("clear"):
		equipment_service.call("clear")
	if attribute_service != null and attribute_service.has_method("reset"):
		attribute_service.call("reset")
