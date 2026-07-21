extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://double-door-desktop.png"
const CLEANUP_FRAMES := 8

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024,576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null,"production game exposes the ServiceHub")
	if hub == null:
		await _finish(game,hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Double-Door-%d" % Time.get_ticks_msec(),
		"star_continent",
		64192735
	)
	_world_id = str(state.get("metadata",{}).get("id",""))
	_check(not _world_id.is_empty(),"desktop door journey creates a temporary world")
	game.begin_world_state(state)
	_check(await _wait_for_world_ready(game,hub,_world_id),"production world reaches a bounded ready state")
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var doors: Node = hub.get("door_interaction_service") as Node
	_check(player != null and bool(player.get("input_enabled")),"production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")),"production voxel world is ready")
	_check(doors != null and hub.get_node_or_null("DoorInteraction") == doors,"production door service uses its stable node path")
	if player == null or world == null or doors == null:
		await _finish(game,hub)
		return

	var player_block: Vector3i = world.call("world_to_block",player.global_position)
	var lower_position := Vector3i(player_block.x,player_block.y,player_block.z-3)
	var upper_position := lower_position+Vector3i.UP
	var anchor_position := lower_position+Vector3i.FORWARD
	_prepare_door_area(world,player_block,lower_position,anchor_position)
	await physics_frame
	await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("oak_door",2,{"batch":"door-desktop"})
	hub.inventory.add_item("wooden_axe",1,{"durability":60})
	var door_slot := _find_inventory_slot(hub.inventory,"oak_door")
	var axe_slot := _find_inventory_slot(hub.inventory,"wooden_axe")
	_check(door_slot >= 0 and axe_slot >= 0,"door journey resolves door and axe hotbar slots")
	hub.inventory.select_slot(door_slot)
	await process_frame

	world.call("set_block",upper_position,"stone")
	await _aim_at(player,world.call("block_to_world",anchor_position))
	var blocked_preview: Dictionary = player.call("get_placement_preview_state")
	_check(str(blocked_preview.get("reason","")) == "door_upper_occupied","real preview rejects an occupied upper door cell")
	_check((blocked_preview.get("placement_boxes",[]) as Array).size() == 2,"blocked preview still shows the complete double-door silhouette")
	world.call("set_block",upper_position,"air")
	await physics_frame
	await _aim_at(player,world.call("block_to_world",anchor_position))
	var valid_preview: Dictionary = player.call("get_placement_preview_state")
	_check(bool(valid_preview.get("valid",false)),"real preview accepts two empty cells above solid support")
	_check((valid_preview.get("placement_boxes",[]) as Array).size() == 2,"green preview renders both door halves")
	_check(_array_to_vector3i(valid_preview.get("placement_companion_position",[])) == upper_position,"preview exposes the exact upper companion cell")
	var upper_outline := player.get_interaction_preview().get_node_or_null("PlacementOutline_1") as MeshInstance3D
	_check(upper_outline != null and upper_outline.visible,"production preview renders a separate upper outline")

	await _right_click_center()
	var lower_id := str(world.call("get_block",lower_position))
	var upper_id := str(world.call("get_block",upper_position))
	_check(DoorPolicyScript.is_valid_pair(lower_id,upper_id),"real right click atomically places matching door halves")
	_check(not DoorPolicyScript.is_open(lower_id),"newly placed door starts closed")
	_check(hub.inventory.count_item("oak_door") == 1,"double-door placement consumes exactly one item")
	world.call("set_block",anchor_position,"air")
	await physics_frame
	await _aim_at(player,world.call("block_to_world",lower_position))
	await _right_click_center()
	lower_id = str(world.call("get_block",lower_position))
	upper_id = str(world.call("get_block",upper_position))
	_check(DoorPolicyScript.is_valid_pair(lower_id,upper_id) and DoorPolicyScript.is_open(lower_id),"real right click opens both persisted halves")
	var open_box := DoorPolicyScript.local_box(lower_id)
	_check(open_box.position.x in [0.0,0.875] or open_box.position.z in [0.0,0.875],"open collision rotates to a doorway edge")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(),"desktop viewport renders the open double door")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size,"door evidence uses the 1024x576 product resolution")
		_save_image(image)

	await _aim_at(player,world.call("block_to_world",lower_position))
	await _right_click_center()
	lower_id = str(world.call("get_block",lower_position))
	upper_id = str(world.call("get_block",upper_position))
	_check(DoorPolicyScript.is_valid_pair(lower_id,upper_id) and not DoorPolicyScript.is_open(lower_id),"second real right click closes both halves")

	hub.inventory.select_slot(axe_slot)
	await process_frame
	await _aim_at(player,world.call("block_to_world",upper_position))
	await _hold_left_until_removed(world,upper_position,180)
	_check(str(world.call("get_block",lower_position)) == "air" and str(world.call("get_block",upper_position)) == "air","real harvesting of the upper half removes the complete door")
	_check(hub.inventory.count_item("oak_door") == 2,"paired harvest returns exactly one door item")

	world.call("set_block",anchor_position,"stone")
	hub.inventory.select_slot(door_slot)
	await process_frame
	await _aim_at(player,world.call("block_to_world",anchor_position))
	await _right_click_center()
	world.call("set_block",anchor_position,"air")
	await physics_frame
	await _aim_at(player,world.call("block_to_world",lower_position))
	await _right_click_center()
	lower_id = str(world.call("get_block",lower_position))
	upper_id = str(world.call("get_block",upper_position))
	_check(DoorPolicyScript.is_valid_pair(lower_id,upper_id) and DoorPolicyScript.is_open(lower_id),"replacement door is open before persistence")
	_check(bool(hub.save_current()),"double door joins the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var serialized := JSON.stringify(loaded)
	_check(not serialized.contains("door_runtime") and not loaded.has("doors"),"door state uses existing block overrides without a parallel domain")
	var doors_before_reload: int = int(hub.inventory.count_item("oak_door"))
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	game.begin_world_state(loaded)
	_check(await _wait_for_world_ready(game,hub,_world_id),"full door reload reaches a bounded ready state")
	world = game.world
	player = game.player
	lower_id = str(world.call("get_block",lower_position))
	upper_id = str(world.call("get_block",upper_position))
	_check(DoorPolicyScript.is_valid_pair(lower_id,upper_id),"full reload restores one matching double-door pair")
	_check(DoorPolicyScript.is_open(lower_id),"full reload preserves the open state")
	_check(hub.inventory.count_item("oak_door") == doors_before_reload,"full reload does not duplicate door items")
	var snapshot: Dictionary = doors.call("get_snapshot")
	_check(snapshot.has("placement_count") and snapshot.has("toggle_count"),"door service exposes bounded runtime diagnostics")
	await _finish(game,hub)


func _prepare_door_area(
	world: Node,
	player_block: Vector3i,
	lower_position: Vector3i,
	anchor_position: Vector3i
) -> void:
	for x in range(player_block.x-2,player_block.x+3):
		for z in range(player_block.z-5,player_block.z+1):
			for y in range(lower_position.y,lower_position.y+4):
				world.call("set_block",Vector3i(x,y,z),"air")
	world.call("set_block",lower_position+Vector3i.DOWN,"stone")
	world.call("set_block",anchor_position,"stone")
	world.call("set_block",lower_position,"air")
	world.call("set_block",lower_position+Vector3i.UP,"air")


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in 180:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	if camera != null:
		camera.look_at(target,Vector3.UP)
	await physics_frame
	await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus",true)
	await process_frame


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT,true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT,false)
	await process_frame
	await process_frame


func _hold_left_until_removed(world: Node, target_position: Vector3i, max_frames: int) -> void:
	_mouse_button(MOUSE_BUTTON_LEFT,true)
	for _frame in max_frames:
		await process_frame
		if str(world.call("get_block",target_position)) == "air":
			break
	_mouse_button(MOUSE_BUTTON_LEFT,false)
	await process_frame
	await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size)*0.5
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (1 << (int(button)-1)) if pressed else 0
	event.pressed = pressed
	root.push_input(event)


func _find_inventory_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot",index)
		if str(slot.get("item_id","")) == item_id:
			return index
	return -1


func _array_to_vector3i(value: Variant) -> Vector3i:
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]),int(value[1]),int(value[2]))
	return Vector3i.ZERO


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path),"double-door screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA DOUBLE DOOR DESKTOP PASS | checks=%d | capture=%s" % [checks,_capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DOUBLE DOOR DESKTOP FAILURE: %s" % failure)
		print("QA DOUBLE DOOR DESKTOP FAIL | checks=%d | failures=%d" % [checks,failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
