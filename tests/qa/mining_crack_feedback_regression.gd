extends SceneTree

const PolicyScript = preload("res://src/harvest/mining_feedback_policy.gd")
const TextureFactoryScript = preload("res://src/harvest/mining_crack_texture_factory.gd")
const OverlayScript = preload("res://src/harvest/mining_crack_overlay.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class FakePlayer:
	extends Node3D
	signal gameplay_action_reported(action: StringName, payload: Dictionary)
	var input_enabled := true
	var harvest_service: Node

	func get_view_camera() -> Camera3D:
		return null


class FakeHarvestService:
	extends Node
	signal harvest_progress_changed(snapshot: Dictionary)
	signal harvest_cancelled(reason: String)
	signal harvest_completed(result: Dictionary)
	signal harvest_rejected(reason: String, snapshot: Dictionary)
	var active_snapshot: Dictionary = {}

	func get_active_snapshot() -> Dictionary:
		return active_snapshot.duplicate(true)

	func emit_progress(snapshot: Dictionary) -> void:
		active_snapshot = snapshot.duplicate(true)
		harvest_progress_changed.emit(snapshot.duplicate(true))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy()
	_test_texture_factory()
	await _test_overlay_lifecycle()
	_test_production_scene_contract()
	if failures.is_empty():
		print("QA MINING CRACK FEEDBACK PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MINING CRACK FEEDBACK FAILURE: %s" % failure)
		print("QA MINING CRACK FEEDBACK FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_policy() -> void:
	_check(PolicyScript.stage_for_ratio(0.0) == 0, "zero progress starts at crack stage zero")
	_check(PolicyScript.stage_for_ratio(0.099) == 0, "first tenth remains stage zero")
	_check(PolicyScript.stage_for_ratio(0.10) == 1, "second tenth advances to stage one")
	_check(PolicyScript.stage_for_ratio(0.55) == 5, "middle progress maps to a middle crack stage")
	_check(PolicyScript.stage_for_ratio(1.0) == 9, "completed ratio clamps to the final crack stage")
	var hidden: Dictionary = PolicyScript.evaluate({}, true)
	_check(not bool(hidden.get("visible", true)) and str(hidden.get("reason", "")) == "no_progress", "empty progress hides feedback")
	var blocked: Dictionary = PolicyScript.evaluate({"status":"progress", "position":[1,2,3], "ratio":0.5}, false)
	_check(not bool(blocked.get("visible", true)) and str(blocked.get("reason", "")) == "input_blocked", "blocked gameplay hides feedback")
	var invalid: Dictionary = PolicyScript.evaluate({"status":"progress", "position":[], "ratio":0.5}, true)
	_check(not bool(invalid.get("visible", true)) and str(invalid.get("reason", "")) == "invalid_position", "invalid target coordinates are rejected")
	var active: Dictionary = PolicyScript.evaluate(
		{"status":"progress", "position":[-4,21,8], "ratio":0.64, "block_id":"stone", "target_key":"stone@-4,21,8"},
		true
	)
	_check(bool(active.get("visible", false)), "valid progress produces visible feedback")
	_check(int(active.get("stage", -1)) == 6, "valid progress exposes the expected stage")
	_check(active.get("block_position", Vector3i.ZERO) == Vector3i(-4,21,8), "valid progress preserves negative world coordinates")
	_check(str(active.get("block_id", "")) == "stone", "valid progress preserves the block identity")


func _test_texture_factory() -> void:
	TextureFactoryScript.reset_cache_for_tests()
	var first_counts: Array[int] = []
	for stage in TextureFactoryScript.STAGE_COUNT:
		var image: Image = TextureFactoryScript.get_image(stage)
		_check(image != null and not image.is_empty(), "crack stage %d exposes a runtime image" % stage)
		_check(image.get_size() == Vector2i(16,16), "crack stage %d keeps the pixel contract" % stage)
		var opaque := _alpha_pixel_count(image)
		first_counts.append(opaque)
		_check(opaque > 0, "crack stage %d contains visible crack pixels" % stage)
		if stage > 0:
			_check(opaque >= first_counts[stage - 1], "crack coverage never decreases at stage %d" % stage)
		var texture: Texture2D = TextureFactoryScript.get_texture(stage)
		_check(texture != null and texture.get_size() == Vector2(16,16), "crack stage %d exposes a matching texture" % stage)
	_check(first_counts[9] > first_counts[0] * 3, "final crack stage is substantially denser than the first")
	var checksum := _image_checksum(TextureFactoryScript.get_image(9))
	TextureFactoryScript.reset_cache_for_tests()
	_check(_image_checksum(TextureFactoryScript.get_image(9)) == checksum, "procedural crack textures rebuild deterministically")


func _test_overlay_lifecycle() -> void:
	var player := FakePlayer.new()
	var harvest := FakeHarvestService.new()
	var overlay = OverlayScript.new()
	root.add_child(player)
	player.add_child(harvest)
	player.add_child(overlay)
	player.harvest_service = harvest
	await process_frame
	overlay.setup(player, harvest)
	var first := {"status":"progress", "position":[2,11,-3], "ratio":0.04, "block_id":"stone", "target_key":"stone@2,11,-3"}
	harvest.emit_progress(first)
	await process_frame
	var snapshot: Dictionary = overlay.get_snapshot()
	_check(bool(snapshot.get("visible", false)), "progress signal shows the production overlay")
	_check(int(snapshot.get("stage", -1)) == 0, "early progress selects the first crack texture")
	_check(overlay.global_position.is_equal_approx(Vector3(2.5,11.5,-2.5)), "overlay centers itself on the target voxel")
	_check(not bool(snapshot.get("has_collision", true)), "mining feedback tree contains no collision objects")
	harvest.emit_progress({"status":"progress", "position":[2,11,-3], "ratio":0.76, "block_id":"stone"})
	await process_frame
	_check(int(overlay.get_snapshot().get("stage", -1)) == 7, "later progress advances the visible crack stage")
	harvest.emit_progress({"status":"progress", "position":[4,12,-6], "ratio":0.22, "block_id":"dirt"})
	await process_frame
	_check(overlay.global_position.is_equal_approx(Vector3(4.5,12.5,-5.5)), "changing targets moves the same overlay instead of leaking nodes")
	player.input_enabled = false
	overlay.call("_process", 0.3)
	_check(not bool(overlay.get_snapshot().get("visible", true)), "disabled player input immediately hides cracks")
	player.input_enabled = true
	harvest.emit_progress(first)
	await process_frame
	_check(bool(overlay.get_snapshot().get("visible", false)), "fresh progress can restore cracks after gameplay resumes")
	harvest.harvest_cancelled.emit("released")
	await process_frame
	_check(not bool(overlay.get_snapshot().get("visible", true)), "harvest cancellation clears the overlay")
	harvest.emit_progress(first)
	harvest.harvest_completed.emit({"status":"completed"})
	await process_frame
	_check(not bool(overlay.get_snapshot().get("visible", true)), "harvest completion clears the overlay")
	harvest.emit_progress(first)
	harvest.harvest_rejected.emit("protected", {})
	await process_frame
	_check(not bool(overlay.get_snapshot().get("visible", true)), "harvest rejection clears stale cracks")
	player.queue_free()
	await process_frame
	await process_frame


func _test_production_scene_contract() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	var overlay := player.get_node_or_null("MiningCrackOverlay")
	_check(overlay != null, "production Player scene mounts MiningCrackOverlay")
	_check(player.get_node_or_null("CameraPivot/Camera3D/HeldItemView") != null, "mining cracks coexist with the first-person held item view")
	if overlay != null:
		_check(not _tree_has_collision(overlay), "production mining overlay remains presentation-only")
	player.queue_free()


func _alpha_pixel_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a > 0.01:
				count += 1
	return count


func _image_checksum(image: Image) -> int:
	var checksum := 17
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			checksum = int((checksum * 31 + int(color.r * 255.0) + int(color.g * 255.0) * 3 + int(color.b * 255.0) * 5 + int(color.a * 255.0) * 7) % 2147483647)
	return checksum


func _tree_has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _tree_has_collision(child):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
