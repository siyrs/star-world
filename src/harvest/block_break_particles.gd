class_name BlockBreakParticles
extends Node3D

const MAX_PARTICLES := 64
const BURST_COUNT := 14
const MAX_MATERIALS := 128
const GRAVITY := 18.0
const MAX_FRAME_STEP := 0.1
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var _available: Array[MeshInstance3D] = []
var _active: Array[Dictionary] = []
var _materials: Dictionary = {}
var _box_mesh: BoxMesh
var _rng := RandomNumberGenerator.new()
var _burst_count := 0
var _spawned_particle_count := 0
var _recycled_particle_count := 0
var _material_cache_hit_count := 0
var _material_cache_miss_count := 0
var _material_cache_overflow_count := 0


func _ready() -> void:
	_rng.seed = 424242
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.075, 0.075, 0.075)
	for _index: int in MAX_PARTICLES:
		var particle := MeshInstance3D.new()
		particle.mesh = _box_mesh
		particle.visible = false
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(particle)
		_available.append(particle)
	set_process(false)


func spawn_burst(block_position: Vector3i, block_id: String) -> void:
	var base_color: Color = BlockRegistryScript.get_color(block_id)
	if base_color.a < 0.05:
		base_color = Color("#777C82")
	var center: Vector3 = Vector3(block_position) + Vector3(0.5, 0.5, 0.5)
	var spawned := 0
	for _index: int in BURST_COUNT:
		if _available.is_empty():
			break
		var particle: MeshInstance3D = _available.pop_back()
		particle.visible = true
		particle.scale = Vector3.ONE
		particle.global_position = center + Vector3(
			_rng.randf_range(-0.3, 0.3),
			_rng.randf_range(-0.3, 0.3),
			_rng.randf_range(-0.3, 0.3)
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
		spawned += 1
	_burst_count += 1
	_spawned_particle_count += spawned
	set_process(not _active.is_empty())


func clear() -> void:
	for entry: Dictionary in _active:
		_recycle(entry.get("node") as MeshInstance3D)
	_active.clear()
	set_process(false)


func get_snapshot() -> Dictionary:
	return {
		"pool_capacity": MAX_PARTICLES,
		"active_count": _active.size(),
		"available_count": _available.size(),
		"material_count": _materials.size(),
		"material_limit": MAX_MATERIALS,
		"processing": is_processing(),
		"burst_count": _burst_count,
		"spawned_particle_count": _spawned_particle_count,
		"recycled_particle_count": _recycled_particle_count,
		"material_cache_hit_count": _material_cache_hit_count,
		"material_cache_miss_count": _material_cache_miss_count,
		"material_cache_overflow_count": _material_cache_overflow_count,
	}


func _process(delta: float) -> void:
	if _active.is_empty():
		set_process(false)
		return
	var elapsed: float = clampf(delta, 0.0, MAX_FRAME_STEP)
	for index: int in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[index]
		var particle := entry.get("node") as MeshInstance3D
		if particle == null or not is_instance_valid(particle):
			_active.remove_at(index)
			continue
		var velocity: Vector3 = entry.get("velocity", Vector3.ZERO) as Vector3
		velocity.y -= GRAVITY * elapsed
		particle.global_position += velocity * elapsed
		entry["velocity"] = velocity
		var remaining: float = float(entry.get("remaining", 0.0)) - elapsed
		entry["remaining"] = remaining
		var lifetime: float = maxf(0.05, float(entry.get("lifetime", 0.7)))
		var scale_value: float = clampf(remaining / lifetime * 2.2, 0.0, 1.0)
		particle.scale = Vector3.ONE * maxf(0.05, scale_value)
		if remaining <= 0.0:
			_recycle(particle)
			_active.remove_at(index)
	if _active.is_empty():
		set_process(false)


func _recycle(particle: MeshInstance3D) -> void:
	if particle == null or not is_instance_valid(particle):
		return
	particle.visible = false
	particle.scale = Vector3.ONE
	particle.material_override = null
	if particle not in _available:
		_available.append(particle)
		_recycled_particle_count += 1


func _material_for(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html(false)
	if _materials.has(key):
		_material_cache_hit_count += 1
		return _materials[key] as StandardMaterial3D
	_material_cache_miss_count += 1
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic = 0.0
	if _materials.size() < MAX_MATERIALS:
		_materials[key] = material
	else:
		_material_cache_overflow_count += 1
	return material
