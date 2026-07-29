class_name HeldItemMeshFactory
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const TextureAtlasScript = preload("res://src/block/block_texture_atlas.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const FIREARM_TOOL_TYPES: Array[String] = ["pistol", "carbine", "shotgun"]

const FACE_DIRECTIONS := [
	Vector3(1,0,0),
	Vector3(-1,0,0),
	Vector3(0,1,0),
	Vector3(0,-1,0),
	Vector3(0,0,1),
	Vector3(0,0,-1),
]
const FACE_ORDER := [0,1,2,0,2,3]


func build_model(item_id: String, definition: Dictionary, block_id: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = "HeldItemModel"
	root.set_meta("item_id",item_id)
	root.set_meta("block_id",block_id)
	var kind := _classify(definition,block_id)
	root.set_meta("model_kind",kind)
	match kind:
		"block":
			_build_block(root,block_id)
		"firearm":
			_build_firearm(root,definition)
		"tool":
			_build_tool(root,definition)
		"food":
			_build_food(root,definition)
		"utility":
			_build_utility(root,definition)
		"armor":
			_build_armor(root,definition)
		"item":
			_build_item(root,definition)
	root.set_meta("part_count",_mesh_part_count(root))
	return root


func _classify(definition: Dictionary, block_id: String) -> String:
	if block_id not in ["","air"] or str(definition.get("category","")) == "block":
		return "block"
	var tool_type := str(definition.get("tool_type",""))
	if tool_type in FIREARM_TOOL_TYPES:
		return "firearm"
	if not tool_type.is_empty():
		return "tool"
	match str(definition.get("category","")):
		"food":
			return "food"
		"utility":
			return "utility"
		"armor":
			return "armor"
		_:
			return "item"


func _build_block(root: Node3D, block_id: String) -> void:
	var resolved := block_id if BlockRegistryScript.has_block(block_id) and block_id != "air" else "stone"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Block"
	mesh_instance.mesh = _build_block_mesh(resolved)
	mesh_instance.material_override = _block_material()
	mesh_instance.rotation_degrees = Vector3(18.0,-28.0,0.0)
	root.add_child(mesh_instance)


func _build_firearm(root: Node3D, definition: Dictionary) -> void:
	var body_color := _item_color(definition)
	var dark := body_color.darkened(0.30)
	var metal := body_color.lightened(0.18)
	var wood := Color("#8B5A32")
	var tool_type := str(definition.get("tool_type", "pistol"))
	match tool_type:
		"pistol":
			_add_box(root,"Grip",Vector3(0.18,0.42,0.20),Vector3(0.03,-0.24,0.10),dark)
			_add_box(root,"Frame",Vector3(0.24,0.22,0.62),Vector3(0.0,0.02,-0.16),body_color)
			_add_box(root,"Slide",Vector3(0.27,0.16,0.72),Vector3(0.0,0.17,-0.18),metal)
			_add_box(root,"Barrel",Vector3(0.12,0.12,0.34),Vector3(0.0,0.12,-0.67),dark)
			_add_box(root,"Sight",Vector3(0.08,0.07,0.10),Vector3(0.0,0.29,-0.43),Color("#222427"))
			root.rotation_degrees = Vector3(-6.0,0.0,0.0)
		"carbine":
			_add_box(root,"Stock",Vector3(0.34,0.28,0.62),Vector3(0.0,-0.02,0.50),wood)
			_add_box(root,"Receiver",Vector3(0.34,0.32,0.72),Vector3(0.0,0.03,-0.06),body_color)
			_add_box(root,"Grip",Vector3(0.18,0.42,0.20),Vector3(0.02,-0.30,0.10),dark)
			_add_box(root,"Magazine",Vector3(0.22,0.38,0.24),Vector3(0.0,-0.31,-0.20),metal.darkened(0.12))
			_add_box(root,"Handguard",Vector3(0.28,0.25,0.64),Vector3(0.0,0.03,-0.73),dark)
			_add_box(root,"Barrel",Vector3(0.10,0.10,0.72),Vector3(0.0,0.05,-1.39),metal)
			_add_box(root,"FrontSight",Vector3(0.08,0.16,0.08),Vector3(0.0,0.18,-1.47),Color("#202326"))
			_add_box(root,"RearSight",Vector3(0.10,0.10,0.12),Vector3(0.0,0.25,-0.16),Color("#202326"))
			root.rotation_degrees = Vector3(-2.0,0.0,0.0)
		"shotgun":
			_add_box(root,"Stock",Vector3(0.36,0.30,0.72),Vector3(0.0,-0.03,0.55),wood)
			_add_box(root,"Receiver",Vector3(0.34,0.32,0.64),Vector3(0.0,0.02,-0.10),body_color)
			_add_box(root,"Grip",Vector3(0.18,0.40,0.20),Vector3(0.02,-0.30,0.10),wood.darkened(0.18))
			_add_box(root,"Pump",Vector3(0.38,0.28,0.54),Vector3(0.0,-0.03,-0.74),wood.darkened(0.10))
			_add_box(root,"Barrel",Vector3(0.13,0.13,1.18),Vector3(0.0,0.12,-1.12),metal)
			_add_box(root,"Tube",Vector3(0.11,0.11,0.88),Vector3(0.0,-0.04,-0.98),dark)
			_add_box(root,"BeadSight",Vector3(0.07,0.07,0.07),Vector3(0.0,0.23,-1.70),Color("#E2C45B"))
			root.rotation_degrees = Vector3(-2.0,0.0,0.0)


func _build_tool(root: Node3D, definition: Dictionary) -> void:
	var head_color := _item_color(definition)
	var handle_color := Color("#8B5A2B")
	var tool_type := str(definition.get("tool_type","tool"))
	_add_box(root,"Handle",Vector3(0.10,0.72,0.10),Vector3(0.0,-0.08,0.0),handle_color)
	match tool_type:
		"sword":
			_add_box(root,"Blade",Vector3(0.13,0.74,0.07),Vector3(0.0,0.46,0.0),head_color)
			_add_box(root,"Guard",Vector3(0.46,0.09,0.11),Vector3(0.0,0.08,0.0),head_color.darkened(0.12))
			_add_box(root,"Pommel",Vector3(0.17,0.13,0.13),Vector3(0.0,-0.48,0.0),head_color.darkened(0.18))
		"pickaxe":
			_add_box(root,"PickHead",Vector3(0.64,0.12,0.12),Vector3(0.0,0.34,0.0),head_color)
			_add_box(root,"PickTipLeft",Vector3(0.12,0.22,0.12),Vector3(-0.28,0.25,0.0),head_color.darkened(0.08))
			_add_box(root,"PickTipRight",Vector3(0.12,0.22,0.12),Vector3(0.28,0.25,0.0),head_color.darkened(0.08))
		"axe":
			_add_box(root,"AxeHead",Vector3(0.36,0.34,0.12),Vector3(0.13,0.30,0.0),head_color)
			_add_box(root,"AxeEdge",Vector3(0.08,0.38,0.14),Vector3(0.34,0.30,0.0),head_color.lightened(0.12))
		"shovel":
			_add_box(root,"ShovelBlade",Vector3(0.30,0.34,0.09),Vector3(0.0,0.38,0.0),head_color)
			_add_box(root,"ShovelTip",Vector3(0.24,0.10,0.10),Vector3(0.0,0.59,0.0),head_color.lightened(0.08))
		"hoe":
			_add_box(root,"HoeHead",Vector3(0.48,0.11,0.11),Vector3(0.13,0.34,0.0),head_color)
			_add_box(root,"HoeEdge",Vector3(0.11,0.24,0.12),Vector3(0.32,0.24,0.0),head_color.darkened(0.08))
		_:
			_add_box(root,"ToolHead",Vector3(0.36,0.25,0.12),Vector3(0.0,0.32,0.0),head_color)
	root.rotation_degrees = Vector3(0.0,0.0,-24.0)


func _build_food(root: Node3D, definition: Dictionary) -> void:
	var color := _item_color(definition)
	_add_box(root,"FoodBody",Vector3(0.42,0.42,0.12),Vector3.ZERO,color)
	_add_box(root,"FoodHighlight",Vector3(0.18,0.16,0.14),Vector3(-0.08,0.08,-0.01),color.lightened(0.20))
	_add_box(root,"FoodShadow",Vector3(0.15,0.13,0.14),Vector3(0.11,-0.10,0.0),color.darkened(0.20))


func _build_utility(root: Node3D, definition: Dictionary) -> void:
	var color := _item_color(definition)
	_add_box(root,"UtilityBody",Vector3(0.40,0.44,0.16),Vector3.ZERO,color.darkened(0.08))
	_add_box(root,"UtilityInset",Vector3(0.28,0.30,0.18),Vector3(0.0,-0.02,-0.01),color)
	_add_box(root,"UtilityHandle",Vector3(0.34,0.08,0.10),Vector3(0.0,0.27,0.0),Color("#727B82"))


func _build_armor(root: Node3D, definition: Dictionary) -> void:
	var color := _item_color(definition)
	_add_box(root,"ArmorBody",Vector3(0.42,0.42,0.16),Vector3.ZERO,color)
	_add_box(root,"ArmorRim",Vector3(0.48,0.10,0.18),Vector3(0.0,-0.20,0.0),color.darkened(0.18))


func _build_item(root: Node3D, definition: Dictionary) -> void:
	var color := _item_color(definition)
	_add_box(root,"ItemBody",Vector3(0.34,0.40,0.10),Vector3.ZERO,color)
	_add_box(root,"ItemPixel",Vector3(0.13,0.13,0.12),Vector3(-0.07,0.08,0.0),color.lightened(0.18))


func _add_box(
	parent: Node3D,
	part_name: String,
	size: Vector3,
	position: Vector3,
	color: Color
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = _solid_material(color)
	parent.add_child(instance)
	return instance


func _build_block_mesh(block_id: String) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var display_mask := ConnectionPolicyScript.display_mask(block_id)
	var boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes(
		block_id,
		display_mask
	)
	for box_index in boxes.size():
		var box: AABB = boxes[box_index]
		for face_index in FACE_DIRECTIONS.size():
			if not ShapeGeometryScript.face_enabled(
				block_id,
				box_index,
				face_index,
				boxes
			):
				continue
			var normal: Vector3 = FACE_DIRECTIONS[face_index]
			var shade := Color.WHITE
			if normal.y < -0.5:
				shade = Color(0.72,0.72,0.72,1.0)
			elif absf(normal.y) < 0.5:
				shade = Color(0.88,0.88,0.88,1.0)
			var uvs: Array[Vector2] = TextureAtlasScript.get_uvs(block_id,face_index)
			var corners: Array[Vector3] = ShapeGeometryScript.face_vertices(box,face_index)
			for corner_index in FACE_ORDER:
				tool.set_normal(normal)
				tool.set_color(shade)
				tool.set_uv(uvs[corner_index])
				tool.add_vertex(corners[corner_index]-Vector3.ONE*0.5)
	return tool.commit()


func _block_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = TextureAtlasScript.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 120
	material.roughness = 0.9
	return material


func _solid_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.no_depth_test = true
	material.render_priority = 120
	return material


func _item_color(definition: Dictionary) -> Color:
	return Color(str(definition.get("color","#D7D7D7")))


func _mesh_part_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _mesh_part_count(child)
	return count
