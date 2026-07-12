class_name StarWorldPlayer
extends CharacterBody3D

signal block_broken(block_position: Vector3i, block_id: String)
signal block_placed(block_position: Vector3i, block_id: String)
signal hotbar_selection_changed(index: int, block_id: String)
signal damage_requested(amount: float, source: String)
signal respawned(position: Vector3)

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const InputActionsScript = preload("res://src/input/gameplay_input_actions.gd")
const MovementControllerScript = preload("res://src/player/player_movement_controller.gd")
const FALLBACK_HOTBAR := [
	"grass",
	"dirt",
	"stone",
	"planks",
	"stone_bricks",
	"glass",
	"stone_slab",
	"oak_stairs",
	"torch",
]
const BASE_ATTACK_DAMAGE := 1.0

@export var walk_speed := 5.4
@export var sprint_speed := 8.0
@export var jump_velocity := 6.2
@export var acceleration := 18.0
@export var air_acceleration := 5.0
@export var mouse_sensitivity := 0.0022
@export var interaction_distance := 6.0

var world: Node
var inventory: Node
var survival: Node
var input_service: Node
var selected_hotbar_index := 0
var input_enabled := false
var spawn_position := Vector3(0.5, 40.0, 0.5)
var _gravity := 9.8
var _movement_controller = MovementControllerScript.new()

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var interaction_ray: RayCast3D = $CameraPivot/Camera3D/InteractionRay


func _ready() -> void:
	InputActionsScript.ensure_default_bindings()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_configure_movement_controller()
	interaction_ray.target_position = Vector3(0.0, 0.0, -interaction_distance)
	interaction_ray.enabled = true
	set_process_unhandled_input(input_enabled)
	_emit_hotbar_selection()


func bind_world(p_world: Node) -> void:
	world = p_world
	if world != null and world.has_method("get_spawn_position"):
		spawn_position = world.call("get_spawn_position")


func bind_inventory(p_inventory: Node) -> void:
	if inventory != p_inventory:
		_disconnect_inventory_selection()
		inventory = p_inventory
	if inventory != null and inventory.has_signal("selected_slot_changed"):
		var callback := Callable(self, "_on_inventory_selection_changed")
		if not inventory.is_connected("selected_slot_changed", callback):
			inventory.connect("selected_slot_changed", callback)
		selected_hotbar_index = clampi(
			int(inventory.get("selected_slot")), 0, _get_hotbar_size() - 1
		)
	_emit_hotbar_selection()


func bind_survival(p_survival: Node) -> void:
	survival = p_survival


func bind_input_service(p_input_service: Node) -> void:
	input_service = p_input_service
	if input_service != null and input_service.has_method("ensure_bindings"):
		input_service.call("ensure_bindings")


func setup_gameplay_services(services: Dictionary) -> void:
	if services.get("inventory") is Node:
		bind_inventory(services["inventory"])
	if services.get("survival") is Node:
		bind_survival(services["survival"])
	if services.get("input") is Node:
		bind_input_service(services["input"])
	var game_ui = services.get("game_ui")
	if game_ui is Node and game_ui.has_signal("respawn_requested"):
		var callback := Callable(self, "_on_respawn_requested")
		if not game_ui.is_connected("respawn_requested", callback):
			game_ui.connect("respawn_requested", callback)


func set_inventory_service(p_inventory: Node) -> void:
	bind_inventory(p_inventory)


func set_input_enabled(enabled: bool) -> void:
	if input_enabled == enabled:
		return
	input_enabled = enabled
	set_process_unhandled_input(enabled)
	if not input_enabled:
		_movement_controller.stop_horizontal(self)


func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	var in_fluid := _is_in_fluid()
	var movement_result: Dictionary = _movement_controller.step(
		self, delta, _get_movement_vector(), _is_jump_just_pressed(), _is_sprint_pressed(), in_fluid
	)
	if bool(movement_result.get("jumped", false)):
		_report_player_action("jump")
	if global_position.y < -12.0:
		respawn()


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	var hotbar_index := _get_hotbar_selection_just_pressed()
	if hotbar_index >= 0:
		select_hotbar(hotbar_index)
	if _is_quick_save_just_pressed():
		var game := get_parent()
		if game != null and game.has_method("request_save"):
			game.call("request_save")


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0)
		)
		return
	if (
		not event is InputEventMouseButton
		or not event.pressed
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			break_target_block()
		MOUSE_BUTTON_RIGHT:
			use_selected_item()
		MOUSE_BUTTON_WHEEL_UP:
			select_hotbar(selected_hotbar_index - 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			select_hotbar(selected_hotbar_index + 1)
		_:
			return
	get_viewport().set_input_as_handled()


func break_target_block() -> bool:
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return false
	var collider := interaction_ray.get_collider()
	if collider != null and collider.has_method("take_damage"):
		collider.call("take_damage", _get_selected_attack_damage(), self)
		_report_player_action("attack")
		return true
	if world == null:
		return false
	var point := interaction_ray.get_collision_point()
	var normal := interaction_ray.get_collision_normal()
	var block_position: Vector3i = world.call("world_to_block", point - normal * 0.01)
	var removed_block: String = world.call("remove_block", block_position)
	if removed_block == BlockRegistryScript.AIR:
		return false
	var drop_item := BlockRegistryScript.get_item_id(removed_block)
	if inventory != null and not drop_item.is_empty() and inventory.has_method("add_item"):
		inventory.call("add_item", drop_item, 1)
	_report_player_action("mine")
	block_broken.emit(block_position, removed_block)
	return true


func use_selected_item() -> bool:
	var block_id := get_selected_block_id()
	if block_id != BlockRegistryScript.AIR:
		return _place_block(block_id)
	return _consume_selected_food()


# Compatibility entry point kept for existing integrations and tests.
func place_selected_block() -> bool:
	return use_selected_item()


func _place_block(block_id: String) -> bool:
	if world == null or (inventory != null and _get_selected_item_id().is_empty()):
		return false
	var target := _resolve_placement_target()
	if target.is_empty():
		return false
	return _commit_block_placement(block_id, target)


func _resolve_placement_target() -> Dictionary:
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return {}
	var point := interaction_ray.get_collision_point()
	var normal := interaction_ray.get_collision_normal()
	var block_position: Vector3i = world.call("world_to_block", point + normal * 0.01)
	var player_bounds := AABB(
		global_position + Vector3(-0.32, 0.0, -0.32), Vector3(0.64, 1.82, 0.64)
	)
	if player_bounds.intersects(AABB(Vector3(block_position), Vector3.ONE)):
		return {}
	return {
		"position": block_position,
		"previous_block": str(world.call("get_block", block_position)),
	}


func _commit_block_placement(block_id: String, target: Dictionary) -> bool:
	var block_position: Vector3i = target["position"]
	if not world.call("set_block", block_position, block_id):
		return false
	if inventory != null and inventory.has_method("consume_selected"):
		var consumed: Dictionary = inventory.call("consume_selected", 1)
		if consumed.is_empty():
			world.call("set_block", block_position, str(target["previous_block"]))
			return false
	block_placed.emit(block_position, block_id)
	return true


func select_hotbar(index: int) -> void:
	selected_hotbar_index = posmod(index, _get_hotbar_size())
	if inventory != null and inventory.has_method("select_slot"):
		inventory.call("select_slot", selected_hotbar_index)
		return
	_emit_hotbar_selection()


func get_selected_block_id() -> String:
	if inventory != null:
		return BlockRegistryScript.get_block_for_item(_get_selected_item_id())
	return FALLBACK_HOTBAR[selected_hotbar_index]


func take_damage(amount: float, source: String = "world") -> void:
	if amount <= 0.0:
		return
	damage_requested.emit(amount, source)
	if survival != null and survival.has_method("take_damage"):
		survival.call("take_damage", amount, source)


func serialize_state() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"rotation": [rotation.x, rotation.y, rotation.z],
		"look_pitch": camera_pivot.rotation.x,
	}


func restore_orientation(data: Dictionary) -> void:
	var saved_rotation = data.get("rotation", [])
	if saved_rotation is Array and saved_rotation.size() >= 3:
		rotation = Vector3(
			float(saved_rotation[0]), float(saved_rotation[1]), float(saved_rotation[2])
		)
	var pitch := float(data.get("look_pitch", 0.0))
	camera_pivot.rotation.x = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	respawned.emit(global_position)


func get_view_camera() -> Camera3D:
	return camera


func _get_selected_item_id() -> String:
	if inventory == null or not inventory.has_method("get_selected_item"):
		return ""
	var slot: Dictionary = inventory.call("get_selected_item")
	return str(slot.get("item_id", ""))


func _get_selected_item_definition(item_id: String) -> Dictionary:
	if item_id.is_empty() or inventory == null:
		return {}
	var registry = inventory.get("registry")
	if registry == null or not registry.has_method("get_item"):
		return {}
	return registry.call("get_item", item_id)


func _get_selected_attack_damage() -> float:
	var item := _get_selected_item_definition(_get_selected_item_id())
	return maxf(0.0, float(item.get("damage", BASE_ATTACK_DAMAGE)))


func _consume_selected_food() -> bool:
	var item_id := _get_selected_item_id()
	var item := _get_selected_item_definition(item_id)
	if not item.has("food") or survival == null:
		return false
	if survival.has_method("consume_selected_inventory_item"):
		return bool(survival.call("consume_selected_inventory_item", inventory))
	if survival.has_method("consume_inventory_item"):
		return bool(survival.call("consume_inventory_item", inventory, item_id))
	return false


func _is_in_fluid() -> bool:
	if world == null:
		return false
	var block_position: Vector3i = world.call("world_to_block", global_position + Vector3.UP * 0.8)
	return str(world.call("get_block", block_position)) in ["water", "lava"]


func _get_movement_vector() -> Vector2:
	if input_service != null and input_service.has_method("get_movement_vector"):
		return input_service.call("get_movement_vector")
	return Input.get_vector(
		InputActionsScript.MOVE_LEFT,
		InputActionsScript.MOVE_RIGHT,
		InputActionsScript.MOVE_FORWARD,
		InputActionsScript.MOVE_BACKWARD
	)


func _is_jump_just_pressed() -> bool:
	if input_service != null and input_service.has_method("is_jump_just_pressed"):
		return bool(input_service.call("is_jump_just_pressed"))
	return Input.is_action_just_pressed(InputActionsScript.JUMP)


func _is_sprint_pressed() -> bool:
	if input_service != null and input_service.has_method("is_sprint_pressed"):
		return bool(input_service.call("is_sprint_pressed"))
	return Input.is_action_pressed(InputActionsScript.SPRINT)


func _is_quick_save_just_pressed() -> bool:
	if input_service != null and input_service.has_method("is_quick_save_just_pressed"):
		return bool(input_service.call("is_quick_save_just_pressed"))
	return Input.is_action_just_pressed(InputActionsScript.QUICK_SAVE)


func _get_hotbar_selection_just_pressed() -> int:
	if input_service != null and input_service.has_method("get_hotbar_selection_just_pressed"):
		return int(input_service.call("get_hotbar_selection_just_pressed"))
	for index in InputActionsScript.HOTBAR_ACTIONS.size():
		if Input.is_action_just_pressed(InputActionsScript.HOTBAR_ACTIONS[index]):
			return index
	return -1


func _configure_movement_controller() -> void:
	var config := {
		"gravity": _gravity,
		"walk_speed": walk_speed,
		"sprint_speed": sprint_speed,
		"jump_velocity": jump_velocity,
		"ground_acceleration": acceleration,
		"air_acceleration": air_acceleration,
	}
	_movement_controller.configure(config)


func _report_player_action(action: String) -> void:
	if survival != null and survival.has_method("report_player_action"):
		survival.call("report_player_action", action)


func _on_inventory_selection_changed(index: int, _slot: Dictionary) -> void:
	selected_hotbar_index = clampi(index, 0, _get_hotbar_size() - 1)
	_emit_hotbar_selection()


func _disconnect_inventory_selection() -> void:
	if inventory == null or not inventory.has_signal("selected_slot_changed"):
		return
	var callback := Callable(self, "_on_inventory_selection_changed")
	if inventory.is_connected("selected_slot_changed", callback):
		inventory.disconnect("selected_slot_changed", callback)


func _get_hotbar_size() -> int:
	var fallback_size := FALLBACK_HOTBAR.size()
	if inventory == null:
		return fallback_size
	var configured_size := int(inventory.get("hotbar_size"))
	return clampi(configured_size, 1, fallback_size)


func _on_respawn_requested() -> void:
	respawn()


func _emit_hotbar_selection() -> void:
	hotbar_selection_changed.emit(selected_hotbar_index, get_selected_block_id())
