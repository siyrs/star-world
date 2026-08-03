extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")

const OUTPUT_PATH := "user://crafting-desktop-acceptance.png"
const WORLD_READY_FRAMES := 720
const CLEANUP_FRAMES := 24
const WORKBENCH_DISTANCE := 3
const CONTROL_READY_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(
		OS.get_cmdline_user_args(),
		OUTPUT_PATH,
	)
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return

	var state: Dictionary = hub.get("save_service").create_world(
		"Crafting-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		97531864,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(
		not _world_id.is_empty(),
		"crafting journey creates a temporary production world",
	)
	if _world_id.is_empty():
		await _finish(game, hub)
		return
	game.call("begin_world_state", state)
	var ready := await _wait_for_world_ready(game, hub)
	_check(ready, "production world reaches a bounded ready state")
	if not ready:
		await _finish(game, hub)
		return

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var inventory: Node = hub.get("inventory") as Node
	var crafting: Node = hub.get("crafting") as Node
	var game_ui: Node = hub.get("game_ui") as Node
	_check(
		player != null
		and world != null
		and inventory != null
		and crafting != null
		and game_ui != null,
		"production player, voxel world, inventory, crafting and UI are mounted",
	)
	if (
		player == null
		or world == null
		or inventory == null
		or crafting == null
		or game_ui == null
	):
		await _finish(game, hub)
		return

	var arena: Dictionary = _build_arena(world, player)
	var arena_position: Vector3 = arena.get(
		"player_position",
		player.global_position,
	)
	var arena_floor_y := int(arena.get("floor_y", 0))
	player.global_position = arena_position
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 180)
	var settled_position := player.global_position
	_check(
		_is_finite_position(settled_position)
		and settled_position.y >= float(arena_floor_y) + 0.75
		and settled_position.y <= float(arena_floor_y) + 3.5
		and Vector2(
			settled_position.x - arena_position.x,
			settled_position.z - arena_position.z,
		).length() <= 1.0,
		"QA arena keeps the production player stable on live collision",
	)

	var workbench_position: Vector3i = arena.get(
		"workbench_position",
		Vector3i.ZERO,
	)
	var placed := bool(
		world.call("set_block", workbench_position, "crafting_table")
	)
	_check(
		placed
		or str(world.call("get_block", workbench_position)) == "crafting_table",
		"QA setup places one real crafting table block",
	)
	for _frame in 4:
		await physics_frame
		await process_frame

	inventory.call("clear")
	_check(
		int(inventory.call("count_item", "oak_log")) == 0,
		"crafting fixture starts without hidden materials",
	)
	_check(
		bool(player.get("input_enabled")),
		"production gameplay input is active before opening crafting",
	)
	_check(
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"gameplay owns captured desktop mouse",
	)

	await _tap_key(KEY_C)
	_check(
		int(game_ui.call("get_active_overlay"))
		== GameUIScript.Overlay.CRAFTING,
		"real C input opens the hand-crafting overlay",
	)
	_check(
		not bool(player.get("input_enabled")),
		"crafting overlay blocks world movement input",
	)
	_check(
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"crafting overlay releases the pointer",
	)
	var panel: Control = game_ui.get("crafting_panel") as Control
	_check(
		panel != null and panel.visible,
		"production crafting panel is visible",
	)
	if panel == null:
		await _finish(game, hub)
		return
	var hand_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(hand_snapshot.get("station", "")) == "hand",
		"C opens the hand station instead of granting workbench access",
	)
	_check(
		str(hand_snapshot.get("result_kind", "")) == "idle",
		"newly opened station starts without stale result feedback",
	)

	var planks_button := await _wait_for_recipe_button(panel, "oak_planks")
	_check(
		planks_button != null,
		"hand panel exposes the log-to-planks recipe by stable output identity",
	)
	_check(
		planks_button != null
		and str(planks_button.get_meta("recipe_id", "")) == "planks_from_log",
		"recipe button exposes its stable recipe id",
	)
	_check(
		planks_button != null and planks_button.disabled,
		"missing material keeps the recipe visibly disabled",
	)
	var slots_before_disabled_click: Dictionary = inventory.call("serialize")
	if planks_button != null:
		await _click_control(planks_button)
	_check(
		inventory.call("serialize") == slots_before_disabled_click,
		"clicking a disabled recipe cannot mutate inventory",
	)

	await _tap_key(KEY_C)
	_check(
		int(game_ui.call("get_active_overlay")) == GameUIScript.Overlay.NONE,
		"second real C input closes hand crafting",
	)
	_check(
		bool(player.get("input_enabled")),
		"closing hand crafting restores gameplay input",
	)
	_check(
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"closing hand crafting recaptures the mouse",
	)

	_check(
		int(inventory.call("add_item", "oak_log", 2)) == 0,
		"fixture grants exactly two real logs",
	)
	await _tap_key(KEY_C)
	planks_button = await _wait_for_recipe_button(panel, "oak_planks")
	_check(
		planks_button != null and not planks_button.disabled,
		"material availability enables the real recipe button",
	)
	if planks_button != null:
		await _click_control(planks_button)
		planks_button = await _wait_for_recipe_button(panel, "oak_planks")
		await _click_control(planks_button)
	_check(
		int(inventory.call("count_item", "oak_log")) == 0,
		"two pointer clicks consume both logs",
	)
	_check(
		int(inventory.call("count_item", "oak_planks")) == 8,
		"two pointer clicks produce eight planks",
	)
	var planks_result: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(planks_result.get("result_kind", "")) == "success"
		and str(planks_result.get("result_recipe_id", ""))
		== "planks_from_log",
		"successful pointer crafting publishes exact recipe feedback",
	)

	var sticks_button := await _wait_for_recipe_button(panel, "stick")
	_check(
		sticks_button != null and not sticks_button.disabled,
		"new planks immediately enable the sticks recipe",
	)
	if sticks_button != null:
		await _click_control(sticks_button)
	_check(
		int(inventory.call("count_item", "oak_planks")) == 6,
		"stick crafting consumes two planks",
	)
	_check(
		int(inventory.call("count_item", "stick")) == 4,
		"stick crafting produces four sticks",
	)

	var table_button := await _wait_for_recipe_button(panel, "crafting_table")
	_check(
		table_button != null and not table_button.disabled,
		"hand station exposes the crafting-table recipe",
	)
	if table_button != null:
		await _click_control(table_button)
	_check(
		int(inventory.call("count_item", "oak_planks")) == 2,
		"crafting table consumes four planks",
	)
	_check(
		int(inventory.call("count_item", "crafting_table")) == 1,
		"crafting table enters the authoritative inventory",
	)

	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == GameUIScript.Overlay.NONE,
		"Esc closes hand crafting through the normal overlay contract",
	)
	_check(
		bool(player.get("input_enabled")),
		"Esc restores production gameplay input",
	)

	await _aim_at(
		player,
		world.call("block_to_world", workbench_position),
	)
	_check(
		_focus_hits_block(player, workbench_position),
		"real center focus resolves the crafting table",
	)
	await _right_click_center()
	_check(
		int(game_ui.call("get_active_overlay"))
		== GameUIScript.Overlay.CRAFTING,
		"real right click opens crafting through the workbench block interaction",
	)
	var workbench_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(workbench_snapshot.get("station", "")) == "workbench",
		"block interaction grants the workbench station",
	)

	var sword_button := await _wait_for_recipe_button(panel, "wooden_sword")
	_check(
		sword_button != null and not sword_button.disabled,
		"workbench enables a station-only wooden sword recipe",
	)
	if sword_button != null:
		await _click_control(sword_button)
	_check(
		int(inventory.call("count_item", "oak_planks")) == 0,
		"wooden sword consumes the final two planks",
	)
	_check(
		int(inventory.call("count_item", "stick")) == 3,
		"wooden sword consumes one stick",
	)
	_check(
		int(inventory.call("count_item", "wooden_sword")) == 1,
		"workbench output enters authoritative inventory",
	)
	var sword_result: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(sword_result.get("result_kind", "")) == "success"
		and str(sword_result.get("result_recipe_id", ""))
		== "wooden_sword",
		"workbench success displays the exact crafted recipe",
	)

	# Keep a rendered button alive while changing the service condition underneath
	# it. The following real pointer click must fail atomically and expose feedback.
	_check(
		int(inventory.call("add_item", "oak_planks", 3)) == 0,
		"failure fixture temporarily enables the wooden pickaxe",
	)
	for _frame in 2:
		await process_frame
	var pickaxe_button := await _wait_for_recipe_button(panel, "wooden_pickaxe")
	_check(
		pickaxe_button != null and not pickaxe_button.disabled,
		"wooden pickaxe is enabled before the stale-station race",
	)
	var before_failed_click: Dictionary = inventory.call("serialize")
	crafting.set("active_station", "hand")
	if pickaxe_button != null:
		await _click_control(pickaxe_button)
	_check(
		inventory.call("serialize") == before_failed_click,
		"failed pointer crafting is atomic and preserves every slot",
	)
	_check(
		int(inventory.call("count_item", "wooden_pickaxe")) == 0,
		"failed station race creates no output item",
	)
	var failure_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(failure_snapshot.get("result_kind", "")) == "error"
		and str(failure_snapshot.get("result_recipe_id", ""))
		== "wooden_pickaxe",
		"service failure publishes exact recipe error feedback",
	)
	_check(
		str(failure_snapshot.get("result_text", "")).contains("工位"),
		"failure feedback explains the station or material requirement",
	)

	crafting.call("set_station", "workbench")
	_check(
		int(inventory.call("remove_item", "oak_planks", 3)) == 3,
		"failure fixture removes its temporary planks exactly",
	)
	for _frame in 2:
		await process_frame
	pickaxe_button = await _wait_for_recipe_button(panel, "wooden_pickaxe")
	_check(
		pickaxe_button != null and pickaxe_button.disabled,
		"insufficient planks disable the station-only pickaxe recipe",
	)
	var after_failure_cleanup: Dictionary = inventory.call("serialize")
	if pickaxe_button != null:
		await _click_control(pickaxe_button)
	_check(
		inventory.call("serialize") == after_failure_cleanup,
		"disabled workbench recipe cannot consume remaining sticks",
	)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(
		image != null and not image.is_empty(),
		"workbench journey renders a non-empty desktop frame",
	)
	if image != null and not image.is_empty():
		_check(
			image.get_size() == root.size,
			"crafting evidence uses the requested 1024x576 viewport",
		)
		_save_image(image)

	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == GameUIScript.Overlay.NONE,
		"Esc closes the workbench overlay",
	)
	_check(
		bool(player.get("input_enabled")),
		"workbench close restores player input",
	)
	var expected_inventory: Dictionary = inventory.call("serialize")
	_check(
		bool(hub.call("save_current")),
		"crafting inventory joins the authoritative world save",
	)
	var saved_state: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(not saved_state.is_empty(), "saved crafting world is loadable")
	var saved_inventory: Dictionary = _canonical_inventory(
		saved_state.get("inventory", {}),
	)
	if saved_inventory != expected_inventory:
		print(
			"CRAFTING_SAVE_INVENTORY_MISMATCH expected=%s actual=%s"
			% [
				JSON.stringify(expected_inventory),
				JSON.stringify(saved_inventory),
			]
		)
	_check(
		saved_inventory == expected_inventory,
		"world.json contains the exact crafted inventory in canonical form",
	)

	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	_check(
		str(hub.get("current_world_id")).is_empty(),
		"return to menu clears the crafting session",
	)
	game.call("begin_world_state", saved_state)
	var reloaded := await _wait_for_world_ready(game, hub)
	_check(
		reloaded,
		"saved crafting world reloads through production composition",
	)
	if not reloaded:
		await _finish(game, hub)
		return
	_check(
		inventory.call("serialize") == expected_inventory,
		"reload restores crafted items without loss or duplication",
	)
	_check(
		int(inventory.call("count_item", "crafting_table")) == 1,
		"reload preserves the crafted table item exactly once",
	)
	_check(
		int(inventory.call("count_item", "wooden_sword")) == 1,
		"reload preserves the station-only sword exactly once",
	)
	_check(
		int(inventory.call("count_item", "stick")) == 3,
		"reload preserves the remaining materials exactly",
	)
	_check(
		int(inventory.call("count_item", "oak_log")) == 0
		and int(inventory.call("count_item", "oak_planks")) == 0
		and int(inventory.call("count_item", "wooden_pickaxe")) == 0,
		"reload does not resurrect consumed materials or failed output",
	)

	await _tap_key(KEY_C)
	_check(
		int(game_ui.call("get_active_overlay"))
		== GameUIScript.Overlay.CRAFTING,
		"crafting remains usable after a complete reload",
	)
	var reloaded_panel: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(reloaded_panel.get("station", "")) == "hand",
		"reload returns C crafting to the safe hand station",
	)
	_check(
		str(reloaded_panel.get("result_kind", "")) == "idle",
		"reopening after reload clears stale success and failure feedback",
	)
	await _tap_key(KEY_ESCAPE)
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in WORLD_READY_FRAMES:
		await process_frame
		var world: Node = (
			game.get("world") as Node
			if is_instance_valid(game)
			else null
		)
		var player: Node = (
			game.get("player") as Node
			if is_instance_valid(game)
			else null
		)
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(hub.get("current_world_id")) == _world_id
		):
			return true
	return false


func _build_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call(
		"world_to_block",
		player.global_position,
	)
	var floor_y := clampi(origin.y - 1, 2, 58)
	var changes: Array = []
	for x_offset in range(-5, 6):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(
				origin.x + x_offset,
				floor_y,
				origin.z + z_offset,
			)
			changes.append({
				"position": floor_position,
				"block_id": "stone",
			})
			for y_offset in range(1, 5):
				changes.append({
					"position": floor_position + Vector3i(0, y_offset, 0),
					"block_id": "air",
				})
	if world.has_method("apply_block_mutations"):
		world.call(
			"apply_block_mutations",
			changes,
			"qa_crafting_desktop_arena",
		)
	else:
		for change: Dictionary in changes:
			world.call(
				"set_block",
				change.get("position", Vector3i.ZERO),
				str(change.get("block_id", "air")),
			)
	return {
		"floor_y": floor_y,
		"player_position": Vector3(
			origin.x + 0.5,
			floor_y + 1.25,
			origin.z + 0.5,
		),
		"workbench_position": Vector3i(
			origin.x,
			floor_y + 1,
			origin.z - WORKBENCH_DISTANCE,
		),
	}


func _settle_player(
	player: CharacterBody3D,
	frame_limit: int,
) -> void:
	var stable_frames := 0
	var previous := player.global_position
	for _frame in frame_limit:
		await physics_frame
		await process_frame
		var current := player.global_position
		if current.distance_to(previous) <= 0.002:
			stable_frames += 1
			if stable_frames >= 8:
				return
		else:
			stable_frames = 0
		previous = current


func _wait_for_recipe_button(
	panel: Node,
	output_item_id: String,
) -> Button:
	for _frame in CONTROL_READY_FRAMES:
		var button := _find_recipe_button(panel, output_item_id)
		if button != null and is_instance_valid(button) and not button.is_queued_for_deletion():
			return button
		await process_frame
	return null


func _find_recipe_button(
	panel: Node,
	output_item_id: String,
) -> Button:
	var recipe_list: Node = panel.get("_recipe_list") as Node
	if recipe_list == null:
		return null
	for child: Node in recipe_list.get_children():
		if (
			child is Button
			and str(child.get_meta("output_item_id", "")) == output_item_id
		):
			return child as Button
	return null


func _click_control(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var visible := await _ensure_control_visible(control)
	var identity := str(control.get_meta("recipe_id", control.name))
	_check(
		visible,
		"real pointer target is visible inside its scroll viewport: %s" % identity,
	)
	if not visible:
		return
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = target
		event.global_position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = (
			MOUSE_BUTTON_MASK_LEFT
			if pressed
			else 0
		)
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame


func _ensure_control_visible(control: Control) -> bool:
	var scroll := _ancestor_scroll_container(control)
	if scroll != null:
		scroll.ensure_control_visible(control)
		for _frame in 3:
			await process_frame
		scroll.ensure_control_visible(control)
		await RenderingServer.frame_post_draw
		await process_frame
		var viewport_rect := scroll.get_global_rect().grow(-3.0)
		return viewport_rect.has_point(control.get_global_rect().get_center())
	await process_frame
	return Rect2(Vector2.ZERO, Vector2(root.size)).has_point(
		control.get_global_rect().get_center(),
	)


func _ancestor_scroll_container(control: Control) -> ScrollContainer:
	var current: Node = control.get_parent()
	while current != null:
		if current is ScrollContainer:
			return current as ScrollContainer
		current = current.get_parent()
	return null


func _canonical_inventory(raw_data: Variant) -> Dictionary:
	if raw_data is not Dictionary:
		return {}
	var data: Dictionary = raw_data
	var verifier = InventoryScript.new(
		maxi(9, int(data.get("slot_count", 36))),
		maxi(1, int(data.get("hotbar_size", 9))),
	)
	var restored := bool(verifier.deserialize(data))
	var result: Dictionary = verifier.serialize() if restored else {}
	verifier.free()
	return result


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.look_at(target, Vector3.UP)
	for _frame in 2:
		await physics_frame
		await process_frame
	var ray := player.get_node_or_null(
		"CameraPivot/Camera3D/InteractionRay",
	) as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _focus_hits_block(player: Node, expected: Vector3i) -> bool:
	var raw_focus: Variant = player.call("get_interaction_focus")
	if raw_focus is not Dictionary:
		return false
	var focus: Dictionary = raw_focus
	return (
		str(focus.get("type", "")) == "block"
		and _vector3i(focus.get("hit_position", [])) == expected
	)


func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(
			int(value[0]),
			int(value[1]),
			int(value[2]),
		)
	return Vector3i.ZERO


func _is_finite_position(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (
		1 << (int(button) - 1)
		if pressed
		else 0
	)
	event.pressed = pressed
	root.push_input(event)


func _tap_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"crafting desktop screenshot is saved",
	)


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in 12:
				await process_frame
		if (
			not _world_id.is_empty()
			and hub.get("save_service") != null
			and bool(
				hub.get("save_service").call(
					"world_exists",
					_world_id,
				)
			)
		):
			hub.get("save_service").call("delete_world", _world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null:
			if audio.has_method("dispose"):
				audio.call("dispose")
			elif audio.has_method("shutdown"):
				audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA CRAFTING DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA CRAFTING DESKTOP FAILURE: %s" % failure)
	print(
		"QA CRAFTING DESKTOP FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
