extends SceneTree

const PolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const PromptResolverScript = preload("res://src/experience/interaction_prompt_resolver.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_contract()
	await _test_prompt_feedback()
	await _test_player_preview_scene()
	if failures.is_empty():
		print("QA PLACEMENT PREVIEW PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PLACEMENT PREVIEW FAILURE: %s" % failure)
		print(
			"QA PLACEMENT PREVIEW FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_policy_contract() -> void:
	var policy = PolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[4, 10, 4],
		"placement_position":[5, 10, 4],
		"placement_target_block_id":"air",
	}
	var valid: Dictionary = policy.evaluate(
		focus, "planks", AABB(Vector3(20, 10, 20), Vector3(0.64, 1.82, 0.64))
	)
	_check(bool(valid.get("target_visible", false)), "block focus exposes a target outline")
	_check(bool(valid.get("placement_visible", false)), "selected blocks expose a placement ghost")
	_check(bool(valid.get("valid", false)), "empty adjacent cell is a valid placement preview")
	_check(str(valid.get("reason", "")) == "ok", "valid preview uses the stable ok reason")

	var occupied_focus := focus.duplicate(true)
	occupied_focus["placement_target_block_id"] = "stone"
	var occupied: Dictionary = policy.evaluate(occupied_focus, "planks")
	_check(not bool(occupied.get("valid", true)), "occupied placement cells are rejected")
	_check(str(occupied.get("reason", "")) == "occupied", "occupied preview explains its reason")

	var overlapping: Dictionary = policy.evaluate(
		focus, "planks", AABB(Vector3(5, 10, 4), Vector3(0.64, 1.82, 0.64))
	)
	_check(not bool(overlapping.get("valid", true)), "player-overlapping placement cells are rejected")
	_check(str(overlapping.get("reason", "")) == "player_overlap", "player overlap has a stable reason")

	var no_block: Dictionary = policy.evaluate(focus, "air")
	_check(bool(no_block.get("target_visible", false)), "target outline remains useful with empty hands")
	_check(not bool(no_block.get("placement_visible", true)), "empty hands do not show a placement ghost")


func _test_prompt_feedback() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	host.add_child(inventory)
	await process_frame
	inventory.clear()
	inventory.add_item("oak_planks", 2)
	inventory.select_slot(0)
	var policy = PolicyScript.new()
	var focus := {
		"type":"block",
		"block_id":"stone",
		"display_name":"石头",
		"hit_position":[4, 10, 4],
		"placement_position":[5, 10, 4],
		"placement_target_block_id":"air",
	}
	focus["placement_preview"] = policy.evaluate(focus, "planks")
	var resolver = PromptResolverScript.new()
	var no_focus_prompt: Dictionary = resolver.resolve({}, inventory, null)
	_check(
		"绿色预览格" in str(no_focus_prompt.get("secondary", "")),
		"no-focus building prompt makes right click conditional on a visible preview",
	)
	_check(
		str(no_focus_prompt.get("tone", "")) == "warning",
		"no-focus building prompt is presented as guidance instead of a valid action",
	)
	var prompt: Dictionary = resolver.resolve(focus, inventory, null)
	_check("放置" in str(prompt.get("secondary", "")), "valid preview keeps the right-click placement action")
	_check("绿色预览格" in str(prompt.get("subtitle", "")), "valid preview is explained with text, not color alone")

	focus["placement_target_block_id"] = "stone"
	focus["placement_preview"] = policy.evaluate(focus, "planks")
	prompt = resolver.resolve(focus, inventory, null)
	_check("无法放置" in str(prompt.get("secondary", "")), "invalid preview removes the misleading placement action")
	_check("已被石头占用" in str(prompt.get("subtitle", "")), "occupied preview names the blocking voxel")
	host.queue_free()
	await process_frame


func _test_player_preview_scene() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	var placement_failure: Dictionary = {}
	player.connect(
		"gameplay_action_reported",
		func(action: StringName, payload: Dictionary) -> void:
			if action == &"place_failed":
				placement_failure.merge(payload, true)
	)
	_check(
		not bool(player.call("_place_block", "planks")),
		"invalid placement attempts are rejected",
	)
	_check(
		not placement_failure.is_empty()
		and "绿色预览格" in str(placement_failure.get("message", "")),
		"invalid right click reports an actionable placement failure",
	)
	var preview: Node = player.call("get_interaction_preview")
	_check(preview != null, "production player scene mounts the world interaction preview")
	if preview == null:
		player.queue_free()
		await process_frame
		return
	player.set_input_enabled(true)
	var preview_state := {
		"target_visible":true,
		"target_position":[1, 2, 3],
		"placement_visible":true,
		"placement_position":[2, 2, 3],
		"selected_block_id":"planks",
		"valid":true,
		"reason":"ok",
	}
	player.emit_signal(
		"interaction_focus_changed",
		{"type":"block", "placement_preview":preview_state}
	)
	await process_frame
	var snapshot: Dictionary = preview.call("get_snapshot")
	_check(bool(snapshot.get("valid", false)), "preview component consumes the player's enriched focus snapshot")
	var target_outline := preview.get_node_or_null("TargetOutline") as MeshInstance3D
	var placement_outline := preview.get_node_or_null("PlacementOutline") as MeshInstance3D
	var placement_fill := preview.get_node_or_null("PlacementFill") as MeshInstance3D
	_check(target_outline != null and target_outline.visible, "target outline is visible for a block focus")
	_check(placement_outline != null and placement_outline.visible, "placement outline is visible for a selected block")
	_check(placement_fill != null and placement_fill.visible, "placement ghost fill is visible for a selected block")
	_check(_contains_no_collision_object(preview), "preview rendering never adds physics collision")
	player.set_input_enabled(false)
	await process_frame
	_check(target_outline != null and not target_outline.visible, "blocking gameplay input hides target feedback")
	_check(placement_fill != null and not placement_fill.visible, "blocking gameplay input hides placement feedback")
	player.queue_free()
	await process_frame
	await process_frame


func _contains_no_collision_object(node: Node) -> bool:
	if node is CollisionObject3D:
		return false
	for child: Node in node.get_children():
		if not _contains_no_collision_object(child):
			return false
	return true


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
