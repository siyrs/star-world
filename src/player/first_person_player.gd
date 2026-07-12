class_name StarWorldPlayer
extends CharacterBody3D

signal block_broken(block_position: Vector3i, block_id: String)
signal block_placed(block_position: Vector3i, block_id: String)
signal hotbar_selection_changed(index: int, block_id: String)
signal damage_requested(amount: float, source: String)
signal respawned(position: Vector3)

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const FALLBACK_HOTBAR := ["grass", "dirt", "stone", "planks", "stone_bricks", "glass", "stone_slab", "oak_stairs", "torch"]
const BASE_ATTACK_DAMAGE := 1.0

@export var walk_speed := 5.4
@export var sprint_speed := 8.0
@export var jump_velocity := 6.2
@export var acceleration := 18.0
@export var air_acceleration := 5.0
@export var mouse_sensitivity := 0.0022
@export var interaction_distance := 6.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var interaction_ray: RayCast3D = $CameraPivot/Camera3D/InteractionRay

var world: Node
var inventory: Node
var survival: Node
var selected_hotbar_index := 0
var input_enabled := true
var spawn_position := Vector3(0.5, 40.0, 0.5)
var _gravity := 9.8


func _ready() -> void:
	_ensure_input_actions()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	interaction_ray.target_position = Vector3(0.0, 0.0, -interaction_distance)
	interaction_ray.enabled = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_emit_hotbar_selection()


func bind_world(p_world: Node) -> void:
	world = p_world
	if world != null and world.has_method("get_spawn_position"):
		spawn_position = world.call("get_spawn_position")


func bind_inventory(p_inventory: Node) -> void:
	inventory = p_inventory
	if inventory != null and inventory.has_signal("selected_slot_changed"):
		var callback := Callable(self, "_on_inventory_selection_changed")
		if not inventory.is_connected("selected_slot_changed", callback):
			inventory.connect("selected_slot_changed", callback)
	_emit_hotbar_selection()


func bind_survival(p_survival: Node) -> void:
	survival = p_survival


func setup_gameplay_services(services: Dictionary) -> void:
	if services.get("inventory") is Node:
		bind_inventory(services["inventory"])
	if services.get("survival") is Node:
		bind_survival(services["survival"])
	var game_ui = services.get("game_ui")
	if game_ui is Node and game_ui.has_signal("respawn_requested"):
		var callback := Callable(self, "_on_respawn_requested")
		if not game_ui.is_connected("respawn_requested", callback):
			game_ui.connect("respawn_requested", callback)


func set_inventory_service(p_inventory: Node) -> void:
	bind_inventory(p_inventory)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not input_enabled:
		velocity.x = 0.0
		velocity.z = 0.0


func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	var in_fluid := _is_in_fluid()
	if not is_on_floor():
		velocity.y -= _gravity * delta * (0.28 if in_fluid else 1.0)
	if Input.is_action_just_pressed("jump") and (is_on_floor() or in_fluid):
		velocity.y = jump_velocity * (0.7 if in_fluid else 1.0)
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if in_fluid:
		target_speed *= 0.55
	var current_acceleration := acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, direction.x * target_speed, current_acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * target_speed, current_acceleration * delta)
	move_and_slide()
	if global_position.y < -12.0:
		respawn()


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	for index in 9:
		if Input.is_action_just_pressed("hotbar_%d" % (index + 1)):
			select_hotbar(index)
	if Input.is_action_just_pressed("quick_save"):
		var game := get_parent()
		if game != null and game.has_method("request_save"):
			game.call("request_save")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: break_target_block()
			MOUSE_BUTTON_RIGHT: place_selected_block()
			MOUSE_BUTTON_WHEEL_UP: select_hotbar(selected_hotbar_index - 1)
			MOUSE_BUTTON_WHEEL_DOWN: select_hotbar(selected_hotbar_index + 1)


func break_target_block() -> bool:
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return false
	var collider := interaction_ray.get_collider()
	if collider != null and collider.has_method("take_damage"):
		collider.call("take_damage", _get_selected_attack_damage(), self)
		if survival != null and survival.has_method("report_player_action"):
			survival.call("report_player_action", "attack")
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
	if survival != null and survival.has_method("report_player_action"):
		survival.call("report_player_action", "mine")
	block_broken.emit(block_position, removed_block)
	return true


func place_selected_block() -> bool:
	var block_id := get_selected_block_id()
	if block_id == BlockRegistryScript.AIR:
		return _consume_selected_food()
	if world == null:
		return false
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return false
	var point := interaction_ray.get_collision_point()
	var normal := interaction_ray.get_collision_normal()
	var block_position: Vector3i = world.call("world_to_block", point + normal * 0.01)
	var player_bounds := AABB(global_position + Vector3(-0.32, 0.0, -0.32), Vector3(0.64, 1.82, 0.64))
	var block_bounds := AABB(Vector3(block_position), Vector3.ONE)
	if player_bounds.intersects(block_bounds):
		return false
	if not world.call("set_block", block_position, block_id):
		return false
	if inventory != null and inventory.has_method("consume_selected"):
		inventory.call("consume_selected", 1)
	block_placed.emit(block_position, block_id)
	return true


func select_hotbar(index: int) -> void:
	selected_hotbar_index = posmod(index, 9)
	if inventory != null and inventory.has_method("select_slot"):
		inventory.call("select_slot", selected_hotbar_index)
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
	if not item.has("food") or survival == null or not survival.has_method("consume_inventory_item"):
		return false
	return bool(survival.call("consume_inventory_item", inventory, item_id))


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	respawned.emit(global_position)


func get_view_camera() -> Camera3D:
	return camera


func _is_in_fluid() -> bool:
	if world == null:
		return false
	var block_position: Vector3i = world.call("world_to_block", global_position + Vector3.UP * 0.8)
	return str(world.call("get_block", block_position)) in ["water", "lava"]


func _on_inventory_selection_changed(index: int, _slot: Dictionary) -> void:
	selected_hotbar_index = clampi(index, 0, 8)
	_emit_hotbar_selection()


func _on_respawn_requested() -> void:
	respawn()


func _emit_hotbar_selection() -> void:
	hotbar_selection_changed.emit(selected_hotbar_index, get_selected_block_id())


func _ensure_input_actions() -> void:
	_register_key_action("move_forward", KEY_W)
	_register_key_action("move_backward", KEY_S)
	_register_key_action("move_left", KEY_A)
	_register_key_action("move_right", KEY_D)
	_register_key_action("jump", KEY_SPACE)
	_register_key_action("sprint", KEY_SHIFT)
	_register_key_action("quick_save", KEY_F5)
	for index in 9:
		_register_key_action("hotbar_%d" % (index + 1), KEY_1 + index)


func _register_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action, key_event)
