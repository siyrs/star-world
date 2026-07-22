class_name PickupVisualResourceCache
extends RefCounted

const MAX_MATERIALS := 256
const PICKUP_BOX_SIZE := Vector3(0.3, 0.3, 0.3)
const PICKUP_COLLISION_RADIUS := 0.32

static var _box_mesh: BoxMesh
static var _collision_shape: SphereShape3D
static var _materials: Dictionary = {}
static var _mesh_create_count := 0
static var _shape_create_count := 0
static var _material_create_count := 0
static var _material_hit_count := 0
static var _material_overflow_count := 0


static func get_box_mesh() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = PICKUP_BOX_SIZE
		_mesh_create_count += 1
	return _box_mesh


static func get_collision_shape() -> SphereShape3D:
	if _collision_shape == null:
		_collision_shape = SphereShape3D.new()
		_collision_shape.radius = PICKUP_COLLISION_RADIUS
		_shape_create_count += 1
	return _collision_shape


static func get_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	var cached: Variant = _materials.get(key)
	if cached is StandardMaterial3D:
		_material_hit_count += 1
		return cached as StandardMaterial3D
	var material := _create_material(color)
	if _materials.size() >= MAX_MATERIALS:
		_material_overflow_count += 1
		return material
	_materials[key] = material
	_material_create_count += 1
	return material


static func get_stats() -> Dictionary:
	return {
		"material_count": _materials.size(),
		"material_capacity": MAX_MATERIALS,
		"mesh_create_count": _mesh_create_count,
		"shape_create_count": _shape_create_count,
		"material_create_count": _material_create_count,
		"material_hit_count": _material_hit_count,
		"material_overflow_count": _material_overflow_count,
		"box_mesh_id": _box_mesh.get_instance_id() if _box_mesh != null else 0,
		"collision_shape_id": (
			_collision_shape.get_instance_id() if _collision_shape != null else 0
		),
	}


static func reset_stats(clear_resources: bool = false) -> void:
	_mesh_create_count = 0
	_shape_create_count = 0
	_material_create_count = 0
	_material_hit_count = 0
	_material_overflow_count = 0
	if clear_resources:
		_box_mesh = null
		_collision_shape = null
		_materials.clear()


static func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.25
	material.roughness = 0.82
	return material
