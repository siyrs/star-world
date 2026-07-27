class_name BlockBreakParticles
extends Node3D

# Pooled pixel debris for block breaking. Each burst reuses a fixed pool of
# tiny shaded cubes so the effect has a hard per-frame cost ceiling, matching
# the project's budget-first philosophy; nothing here is saved or networked.

const MAX_PARTICLES := 64
const BURST_COUNT := 14
const GRAVITY := 18.0
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var _available: Array[MeshInstance3D] = []
var _active: Array[Dictionary] = []
var _materials: Dictionary = {}
var _box_mesh: BoxMesh
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 424242
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.075, 0.075, 0.075)
	for _index in MAX_PARTICLES:
		var particle := MeshInstance3D.new()
		particle.mesh = _box_mesh
		particle.visible = false
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(particle)
		_available.append(particle)


func spawn_burst(block_position: Vector3i, block_id: String) -> void:
	var base_color := BlockRegistryScript.get_color(block_id)
	if base_color.a < 0.05:
		base_color = Color("#777C82")
	var center := Vector3(block_position) + Vector3(0.5, 0.5, 0.5)
	for _index in BURST_COUNT:
		if _available.is_empty():
			break
		var particle := _available.pop_back()
		particle.visible = true
		particle.global_position = center + Vector3(
			_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)
		)
		particle.material_override = _material_for(base_color)
		_active.append(
			{
				"node": particle,
				"velocity": Vector3(
					_rng.randf_range(-2.2, 2.2),
					_rng.randf_range(2.0, 4.6),
					_rng.randf_range(-2.2, 2.2)
				),
				"remaining": _rng.randf_range(0.5, 0.7),
				"lifetime": 0.7,
			}
		)


func clear() -> void:
	for entry: Dictionary in _active:
		var particle := entry.get("node") as MeshInstance3D
		if particle != null:
			particle.visible = false
			_available.append(particle)
	_active.clear()


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	for index in range(_active.size() - 1, -1, -1):
		var entry := _active[index]
		var particle := entry.get("node") as MeshInstance3D
		if particle == null or not is_instance_valid(particle):
			_active.remove_at(index)
			continue
		var velocity := entry.get("velocity", Vector3.ZERO) as Vector3
		velocity.y -= GRAVITY * delta
		particle.global_position += velocity * delta
		entry["velocity"] = velocity
		var remaining := float(entry.get("remaining", 0.0)) - delta
		entry["remaining"] = remaining
		var lifetime := maxf(0.05, float(entry.get("lifetime", 0.7)))
		var scale := clampf(remaining / lifetime * 2.2, 0.0, 1.0)
		particle.scale = Vector3.ONE * maxf(0.05, scale)
		if remaining <= 0.0:
			particle.visible = false
			particle.scale = Vector3.ONE
			_available.append(particle)
			_active.remove_at(index)


func _material_for(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		material.metallic = 0.0
		_materials[key] = material
	return _materials[key]
