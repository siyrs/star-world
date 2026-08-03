extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")

const OUTPUT_PATH := "user://repair-desktop-acceptance.png"
const WORLD_READY_FRAMES := 720
const CLEANUP_FRAMES := 24
const STATION_DISTANCE := 3
const CONTROL_READY_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


class ReadOnlyRepairInventory:
	extends Node

	var source: Node
	var slot_count := 36

	func setup(p_source: Node) -> void:
		source = p_source
		slot_count = maxi(1, int(source.get("slot_count")))

	func get_slot(index: int) -> Dictionary:
		if source == null:
			return {}
		return source.call("get_slot", index)

	func count_item(item_id: String) -> int:
		if source == null:
			return 0
		return int(source.call("count_item", item_id))


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
		"Repair-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		86420975,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(
		not _world_id.is_empty(),
		"repair journey creates a temporary production world",
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
	var repair_service: Node = hub.get("repair_service") as Node
	var game_ui: Node = hub.get("game_ui") as Node
	_check(
		player != null
		and world != null
		and inventory != null
		and repair_service != null
		and game_ui != null,
		"production player, voxel world, inventory, repair service and UI are mounted",
	)
	if (
		player == null
		or world == null
		or inventory == null
		or repair_service == null
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

	var station_position: Vector3i = arena.get(
		"station_position",
		Vector3i.ZERO,
	)
	var placed := bool(
		world.call("set_block", station_position, "repair_station")
	)
	_check(
		placed
		or str(world.call("get_block", station_position)) == "repair_station",
		"QA setup places one real repair station block",
	)
	for _frame in 4:
		await physics_frame
		await process_frame

	inventory.call("clear")
	_check(
		int(
			inventory.call(
				"add_item",
				"iron_pickaxe",
				1,
				{"durability": 50, "custom_name": "闭环验收铁镐"},
			)
		) == 0,
		"fixture grants one damaged metadata-bearing iron pickaxe",
	)
	inventory.call("select_slot", 0)
	_check(
		int(inventory.call("count_item", "iron_ingot")) == 0,
		"repair fixture starts without hidden material",
	)

	await _aim_at(
		player,
		world.call("block_to_world", station_position),
	)
	_check(
		_focus_hits_block(player, station_position),
		"real center focus resolves the repair station",
	)
	await _right_click_center()
	_check(
		str(hub.get("input_context").call("get_context")) == "repair",
		"real right click enters the dedicated repair input context",
	)
	_check(
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"repair overlay releases the desktop pointer",
	)
	_check(
		not bool(player.get("input_enabled")),
		"repair overlay blocks world movement input",
	)
	var panel: Control = game_ui.call("get_repair_panel") as Control
	_check(
		panel != null and panel.visible,
		"production repair panel is visible",
	)
	if panel == null:
		await _finish(game, hub)
		return
	_check(
		_rect_is_inside_viewport(panel.get_global_rect()),
		"repair panel stays inside the 1024x576 viewport",
	)
	var layout: Dictionary = panel.call("get_layout_rects")
	_check(
		Rect2(layout.get("list", Rect2())).size.y > 0.0,
		"repair list has a measurable production layout",
	)

	var missing_button := await _wait_for_repair_button(panel, "inventory:0")
	_check(
		missing_button != null,
		"repair panel exposes the damaged pickaxe by stable target identity",
	)
	_check(
		missing_button != null
		and str(missing_button.get_meta("target_id", "")) == "inventory:0"
		and str(missing_button.get_meta("item_id", "")) == "iron_pickaxe",
		"repair action publishes stable target and item identities",
	)
	_check(
		missing_button != null and missing_button.disabled,
		"missing material keeps the real repair action visibly disabled",
	)
	var before_disabled_click: Dictionary = inventory.call("serialize")
	if missing_button != null:
		await _click_control(missing_button)
	_check(
		inventory.call("serialize") == before_disabled_click,
		"clicking a disabled repair action cannot mutate inventory",
	)
	var missing_snapshot: Dictionary = panel.call("get_visual_snapshot")
	var missing_targets: Dictionary = missing_snapshot.get("targets", {})
	var missing_target: Dictionary = missing_targets.get("inventory:0", {})
	_check(
		bool(missing_target.get("disabled", false))
		and str(missing_target.get("text", "")).contains("材料不足"),
		"repair snapshot exposes the player-visible missing-material state",
	)

	await _tap_key(KEY_ESCAPE)
	_check(
		str(hub.get("input_context").call("get_context")) == "gameplay",
		"Esc closes repair and restores gameplay context",
	)
	_check(
		bool(player.get("input_enabled")),
		"closing repair restores production player input",
	)
	_check(
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"closing repair recaptures the gameplay mouse",
	)

	_check(
		int(inventory.call("add_item", "iron_ingot", 2)) == 0,
		"fixture grants exactly two matching repair materials",
	)
	await _aim_at(
		player,
		world.call("block_to_world", station_position),
	)
	await _right_click_center()
	var repair_button := await _wait_for_repair_button(panel, "inventory:0")
	_check(
		repair_button != null and not repair_button.disabled,
		"material availability enables the real repair action",
	)
	if repair_button != null:
		await _click_control(repair_button)
	var repaired: Dictionary = inventory.call("get_slot", 0)
	_check(
		int(repaired.get("metadata", {}).get("durability", 0)) == 113,
		"real pointer repair writes the deterministic durability",
	)
	_check(
		str(repaired.get("metadata", {}).get("custom_name", ""))
		== "闭环验收铁镐",
		"successful repair preserves unrelated item metadata",
	)
	_check(
		int(inventory.call("count_item", "iron_ingot")) == 1,
		"successful repair consumes exactly one ingot",
	)
	var success_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(success_snapshot.get("status_kind", "")) == "success"
		and str(success_snapshot.get("status_target_id", "")) == "inventory:0"
		and str(success_snapshot.get("status_text", "")).contains("恢复"),
		"successful pointer repair publishes exact target-level feedback",
	)

	var stale_button := await _wait_for_repair_button(panel, "inventory:0")
	_check(
		stale_button != null and not stale_button.disabled,
		"remaining material keeps the second repair action enabled",
	)
	var before_stale_failure: Dictionary = inventory.call("serialize")
	var read_only_inventory := ReadOnlyRepairInventory.new()
	read_only_inventory.setup(inventory)
	hub.add_child(read_only_inventory)
	repair_service.set("inventory", read_only_inventory)
	if stale_button != null:
		await _click_control(stale_button)
	repair_service.set("inventory", inventory)
	read_only_inventory.queue_free()
	_check(
		inventory.call("serialize") == before_stale_failure,
		"stale service failure is atomic and preserves every inventory slot",
	)
	var failure_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(failure_snapshot.get("status_kind", "")) == "warning"
		and str(failure_snapshot.get("status_target_id", "")) == "inventory:0"
		and str(failure_snapshot.get("status_text", "")).contains("背包服务"),
		"stale service failure publishes exact target-level error feedback",
	)
	panel.call("refresh")
	await process_frame

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(
		image != null and not image.is_empty(),
		"repair closed-loop journey renders a non-empty desktop frame",
	)
	if image != null and not image.is_empty():
		_check(
			image.get_size() == root.size,
			"repair evidence uses the requested 1024x576 viewport",
		)
		_save_image(image)

	await _tap_key(KEY_ESCAPE)
	_check(
		str(hub.get("input_context").call("get_context")) == "gameplay",
		"closing the repaired session restores gameplay before save",
	)
	var expected_inventory: Dictionary = inventory.call("serialize")
	_check(
		bool(hub.call("save_current")),
		"repaired inventory joins the authoritative world save",
	)
	var saved_state: Dictionary = hub.get("save_service").call(
		"load_world",
		_world_id,
	)
	_check(
		not saved_state.is_empty(),
		"saved repair world is loadable",
	)
	_check(
		_canonical_inventory(saved_state.get("inventory", {}))
		== _canonical_inventory(expected_inventory),
		"world.json contains the exact repaired inventory in canonical form",
	)
	var saved_world: Dictionary = saved_state.get("world", {})
	var saved_overrides: Dictionary = saved_world.get("block_overrides", {})
	var station_key := "%d,%d,%d" % [
		station_position.x,
		station_position.y,
		station_position.z,
	]
	_check(
		str(saved_overrides.get(station_key, "")) == "repair_station",
		"authoritative save retains the real repair station block",
	)

	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	_check(
		str(hub.get("current_world_id")).is_empty(),
		"return to menu clears the repair session",
	)

	game.call("begin_world_state", saved_state)
	var reloaded := await _wait_for_world_ready(game, hub)
	_check(
		reloaded,
		"saved repair world reloads through production composition",
	)
	if not reloaded:
		await _finish(game, hub)
		return

	_check(
		inventory.call("serialize") == expected_inventory,
		"reload restores the exact repaired inventory without duplication",
	)
	var reloaded_pickaxe: Dictionary = inventory.call("get_slot", 0)
	_check(
		int(
			reloaded_pickaxe.get("metadata", {}).get(
				"durability",
				0,
			)
		) == 113,
		"reload preserves the repaired durability exactly",
	)
	_check(
		str(
			reloaded_pickaxe.get("metadata", {}).get(
				"custom_name",
				"",
			)
		) == "闭环验收铁镐",
		"reload preserves the repaired item's custom metadata",
	)
	_check(
		int(inventory.call("count_item", "iron_ingot")) == 1,
		"reload preserves the remaining repair material exactly",
	)
	_check(
		str(world.call("get_block", station_position)) == "repair_station",
		"reload restores the real repair station world override",
	)

	await _aim_at(
		player,
		world.call("block_to_world", station_position),
	)
	_check(
		_focus_hits_block(player, station_position),
		"reloaded player can focus the persisted repair station",
	)
	await _right_click_center()
	var reloaded_button := await _wait_for_repair_button(panel, "inventory:0")
	_check(
		reloaded_button != null and not reloaded_button.disabled,
		"repair remains usable after a complete reload",
	)
	var reloaded_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(reloaded_snapshot.get("status_kind", "")) == "idle",
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
			"qa_repair_desktop_arena",
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
		"station_position": Vector3i(
			origin.x,
			floor_y + 1,
			origin.z - STATION_DISTANCE,
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


func _wait_for_repair_button(
	panel: Node,
	target_id: String,
) -> Button:
	for _frame in CONTROL_READY_FRAMES:
		var button: Button = panel.call(
			"get_repair_button",
			target_id,
		) as Button
		if (
			button != null
			and is_instance_valid(button)
			and not button.is_queued_for_deletion()
		):
			return button
		await process_frame
	return null


func _click_control(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var visible := await _ensure_control_visible(control)
	var identity := str(control.get_meta("target_id", control.name))
	_check(
		visible,
		"real pointer target is visible inside its scroll viewport: %s"
		% identity,
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
		return viewport_rect.has_point(
			control.get_global_rect().get_center(),
		)
	await process_frame
	return Rect2(
		Vector2.ZERO,
		Vector2(root.size),
	).has_point(control.get_global_rect().get_center())


func _ancestor_scroll_container(control: Control) -> ScrollContainer:
	var current: Node = control.get_parent()
	while current != null:
		if current is ScrollContainer:
			return current as ScrollContainer
		current = current.get_parent()
	return null


func _rect_is_inside_viewport(rect: Rect2) -> bool:
	var transformed_start := _canvas_to_viewport(rect.position)
	var transformed_end := _canvas_to_viewport(rect.end)
	var transformed_rect := Rect2(
		transformed_start,
		transformed_end - transformed_start,
	)
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	return (
		transformed_rect.position.x >= -0.5
		and transformed_rect.position.y >= -0.5
		and transformed_rect.end.x <= bounds.end.x + 0.5
		and transformed_rect.end.y <= bounds.end.y + 0.5
	)


func _canvas_to_viewport(position: Vector2) -> Vector2:
	return root.get_final_transform() * position


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
		"repair desktop screenshot is saved",
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
			"QA REPAIR DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA REPAIR DESKTOP FAILURE: %s" % failure)
	print(
		"QA REPAIR DESKTOP FAIL | checks=%d | failures=%d"
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