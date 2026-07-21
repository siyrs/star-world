extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://connected-block-shapes-desktop.png"
const CLEANUP_FRAMES := 8

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(),OUTPUT_PATH)
	root.size = Vector2i(1024,576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null,"production game exposes the service hub")
	if hub == null:
		await _finish(game,hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Connected-Shapes-%d" % Time.get_ticks_msec(),
		"star_continent",
		59318427
	)
	_world_id = str(state.get("metadata",{}).get("id",""))
	_check(not _world_id.is_empty(),"desktop connected-shape journey creates a temporary world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game,hub,_world_id),
		"production world reaches a bounded ready state"
	)
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	_check(player != null and bool(player.get("input_enabled")),"production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")),"production voxel world is ready")
	if player == null or world == null:
		await _finish(game,hub)
		return
	var camera: Camera3D = player.call("get_view_camera")
	var player_block: Vector3i = world.call("world_to_block",player.global_position)
	var target_y := floori(camera.global_position.y)
	var pane_anchor := Vector3i(player_block.x,target_y,player_block.z-5)
	var pane_far := pane_anchor+Vector3i.BACK
	var pane_near := pane_far+Vector3i.BACK
	var fence_anchor := Vector3i(player_block.x+3,target_y,player_block.z-5)
	var fence_far := fence_anchor+Vector3i.BACK
	var fence_near := fence_far+Vector3i.BACK
	_prepare_corridor(world,player_block,target_y,player_block.x-1,player_block.x+4,player_block.z-7,player_block.z-1)
	world.call("set_block",pane_anchor,"stone")
	world.call("set_block",fence_anchor,"stone")
	for position in [pane_far,pane_near,fence_far,fence_near]:
		world.call("set_block",position,"air")
	await physics_frame
	await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("glass_pane",4,{"batch":"connected-desktop"})
	hub.inventory.add_item("oak_fence",3,{"batch":"connected-desktop"})
	var pane_slot := _find_inventory_slot(hub.inventory,"glass_pane")
	var fence_slot := _find_inventory_slot(hub.inventory,"oak_fence")
	_check(pane_slot >= 0 and fence_slot >= 0,"desktop journey resolves pane and fence inventory slots")
	hub.inventory.select_slot(pane_slot)
	await process_frame

	await _aim_at(player,world.call("block_to_world",pane_anchor))
	var first_focus: Dictionary = player.call("get_interaction_focus")
	var first_preview: Dictionary = first_focus.get("placement_preview",{})
	_check(
		_array_to_vector3i(first_preview.get("placement_position",[])) == pane_far,
		"first pane preview resolves the far build cell"
	)
	await _right_click_center()
	_check(
		BlockRegistryScript.get_item_id(str(world.call("get_block",pane_far))) == "glass_pane",
		"real right click places the first glass pane"
	)
	_check(hub.inventory.count_item("glass_pane") == 3,"first pane placement consumes exactly one item")
	world.call("set_block",pane_anchor,"air")
	await physics_frame
	await process_frame

	await _aim_at(player,world.call("block_to_world",pane_far))
	var second_focus: Dictionary = player.call("get_interaction_focus")
	var second_preview: Dictionary = second_focus.get("placement_preview",{})
	_check(
		_array_to_vector3i(second_preview.get("placement_position",[])) == pane_near,
		"second pane preview uses the visible pane surface"
	)
	_check(
		int(second_preview.get("placement_connection_mask",0)) == ConnectionPolicyScript.NORTH,
		"preview expands toward the existing pane"
	)
	_check(
		(second_preview.get("placement_boxes",[]) as Array).size() == 2,
		"real preview renders one post and one connecting arm"
	)
	var placement_outline_1 := player.get_interaction_preview().get_node_or_null(
		"PlacementOutline_1"
	) as MeshInstance3D
	_check(
		placement_outline_1 != null and placement_outline_1.visible,
		"second connection arm is visible in the production placement preview"
	)
	await _right_click_center()
	_check(
		BlockRegistryScript.get_item_id(str(world.call("get_block",pane_near))) == "glass_pane",
		"second real right click commits the connected pane"
	)
	_check(
		ConnectionPolicyScript.resolve_mask(
			str(world.call("get_block",pane_near)),
			ConnectionPolicyScript.read_neighbors(world,pane_near)
		) == ConnectionPolicyScript.NORTH,
		"placed pane derives its live north connection without a stored mask"
	)

	hub.inventory.select_slot(fence_slot)
	await process_frame
	await _aim_at(player,world.call("block_to_world",fence_anchor))
	await _right_click_center()
	_check(str(world.call("get_block",fence_far)) == "oak_fence","real right click places the first fence post")
	world.call("set_block",fence_anchor,"air")
	await physics_frame
	await process_frame
	await _aim_at(player,world.call("block_to_world",fence_far))
	var fence_focus: Dictionary = player.call("get_interaction_focus")
	var fence_preview: Dictionary = fence_focus.get("placement_preview",{})
	_check(
		int(fence_preview.get("placement_connection_mask",0)) == ConnectionPolicyScript.NORTH,
		"fence preview derives the same-family north connection"
	)
	_check(
		(fence_preview.get("placement_boxes",[]) as Array).size() == 3,
		"fence preview renders one post and two rails"
	)
	await _right_click_center()
	_check(str(world.call("get_block",fence_near)) == "oak_fence","second fence placement commits the connected rails")
	_check(
		ConnectionPolicyScript.resolve_mask(
			"oak_fence",
			ConnectionPolicyScript.read_neighbors(world,fence_near)
		) == ConnectionPolicyScript.NORTH,
		"production fence geometry reads the live adjacent post"
	)

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(),"desktop viewport renders connected pane and fence shapes")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size,"connected-shape evidence uses 1024x576 product resolution")
		_save_image(image)

	world.call("remove_block",pane_far)
	await process_frame
	await physics_frame
	await _aim_at(player,world.call("block_to_world",pane_near))
	var isolated_focus: Dictionary = player.call("get_interaction_focus")
	var isolated_preview: Dictionary = isolated_focus.get("placement_preview",{})
	_check(
		int(isolated_preview.get("target_connection_mask",0))
		== (ConnectionPolicyScript.EAST|ConnectionPolicyScript.WEST),
		"removing the neighbor rebuilds the surviving pane"
	)
	_check(
		(isolated_preview.get("target_boxes",[]) as Array).size() == 1,
		"surviving pane returns to its orientation-compatible isolated silhouette"
	)
	world.call("set_block",pane_far,"glass_pane")
	await process_frame

	_check(bool(hub.save_current()),"connected blocks join the production world save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var serialized := JSON.stringify(loaded)
	_check(not serialized.contains("connection_mask"),"derived connection masks never enter the world save")
	_check(not loaded.has("connected_shapes"),"world save adds no parallel connected-shape domain")
	var panes_before_reload: int = int(hub.inventory.count_item("glass_pane"))
	var fences_before_reload: int = int(hub.inventory.count_item("oak_fence"))
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	game.begin_world_state(loaded)
	_check(
		await _wait_for_world_ready(game,hub,_world_id),
		"full connected-shape reload reaches a bounded ready state"
	)
	world = game.world
	player = game.player
	_check(
		BlockRegistryScript.get_item_id(str(world.call("get_block",pane_far))) == "glass_pane"
		and BlockRegistryScript.get_item_id(str(world.call("get_block",pane_near))) == "glass_pane",
		"full reload restores both pane blocks exactly once"
	)
	_check(
		str(world.call("get_block",fence_far)) == "oak_fence"
		and str(world.call("get_block",fence_near)) == "oak_fence",
		"full reload restores both fence blocks exactly once"
	)
	_check(
		ConnectionPolicyScript.resolve_mask(
			str(world.call("get_block",pane_near)),
			ConnectionPolicyScript.read_neighbors(world,pane_near)
		) == ConnectionPolicyScript.NORTH
		and ConnectionPolicyScript.resolve_mask(
			"oak_fence",
			ConnectionPolicyScript.read_neighbors(world,fence_near)
		) == ConnectionPolicyScript.NORTH,
		"full reload restores connected silhouettes without persisted masks"
	)
	_check(
		hub.inventory.count_item("glass_pane") == panes_before_reload
		and hub.inventory.count_item("oak_fence") == fences_before_reload,
		"full reload does not duplicate building items"
	)
	await _finish(game,hub)


func _prepare_corridor(
	world: Node,
	player_block: Vector3i,
	target_y: int,
	min_x: int,
	max_x: int,
	min_z: int,
	max_z: int
) -> void:
	for x in range(min_x,max_x+1):
		for z in range(min_z,max_z+1):
			for y in range(target_y-1,target_y+2):
				world.call("set_block",Vector3i(x,y,z),"air")
	var support_y := maxi(1,target_y-2)
	for x in range(min_x,max_x+1):
		for z in range(min_z,max_z+1):
			world.call("set_block",Vector3i(x,support_y,z),"stone")
	world.call("set_block",Vector3i(player_block.x,support_y,player_block.z),"stone")


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
	var center := Vector2(root.size)*0.5
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_RIGHT
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_RIGHT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _find_inventory_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot",index)
		if str(slot.get("item_id","")) == item_id:
			return index
	return -1


func _array_to_vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]),int(value[1]),int(value[2]))
	return Vector3i.ZERO


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path),"connected-shape screenshot is saved")


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
		print(
			"QA CONNECTED BLOCK SHAPES DESKTOP PASS | checks=%d | capture=%s"
			% [checks,_capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA CONNECTED BLOCK SHAPES DESKTOP FAILURE: %s" % failure)
		print(
			"QA CONNECTED BLOCK SHAPES DESKTOP FAIL | checks=%d | failures=%d"
			% [checks,failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
