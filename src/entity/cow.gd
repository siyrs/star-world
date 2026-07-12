class_name CowCreature
extends "res://src/entity/base_creature.gd"


func _ready() -> void:
	species_id = "cow"
	display_name = "牛"
	collision_size = Vector3(1.2, 1.35, 1.65)
	if not _configured:
		apply_profile({"name":"牛", "max_health":10, "speed":1.7, "damage":0, "drops":{"raw_beef":[1,3], "leather":[0,2]}})
	super._ready()
	add_to_group("animals")


func _build_model() -> void:
	_make_box("Body", Vector3(1.15, 0.9, 1.55), Vector3(0.0, 0.93, 0.0), Color("#6B4230"))
	_make_box("Patch", Vector3(1.17, 0.35, 0.55), Vector3(0.0, 1.05, -0.15), Color("#EDE7DC"))
	_make_box("Head", Vector3(0.86, 0.78, 0.68), Vector3(0.0, 1.02, 1.02), Color("#5B372A"))
	_make_box("Muzzle", Vector3(0.62, 0.32, 0.28), Vector3(0.0, 0.89, 1.48), Color("#C08D79"))
	_make_box("LeftHorn", Vector3(0.13, 0.22, 0.13), Vector3(-0.39, 1.49, 1.02), Color("#E6D6A8"))
	_make_box("RightHorn", Vector3(0.13, 0.22, 0.13), Vector3(0.39, 1.49, 1.02), Color("#E6D6A8"))
	for x in [-0.39, 0.39]:
		for z in [-0.52, 0.52]:
			_make_box("Leg", Vector3(0.23, 0.65, 0.23), Vector3(x, 0.33, z), Color("#4C3026"))
