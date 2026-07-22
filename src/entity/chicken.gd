class_name ChickenCreature
extends "res://src/entity/base_creature.gd"


func _ready() -> void:
	species_id = "chicken"
	display_name = "鸡"
	collision_size = Vector3(0.65, 0.8, 0.65)
	if not _configured:
		apply_profile({"name":"鸡", "max_health":4, "speed":2.2, "damage":0, "drops":{"raw_chicken":[1,2], "feather":[0,2]}})
	super._ready()
	add_to_group("animals")


func _build_model() -> void:
	_make_box("Body", Vector3(0.62, 0.5, 0.72), Vector3(0.0, 0.52, 0.0), Color("#F2F1E8"))
	_make_box("Head", Vector3(0.42, 0.42, 0.42), Vector3(0.0, 0.86, 0.28), Color("#FAF9EF"))
	_make_eyes(0.5, 0.9, 0.1, 0.07, Color("#241812"))
	_make_box("Beak", Vector3(0.28, 0.14, 0.22), Vector3(0.0, 0.82, 0.57), Color("#E9A72E"))
	_make_box("Comb", Vector3(0.18, 0.16, 0.18), Vector3(0.0, 1.13, 0.23), Color("#D84B3F"))
	_make_box("LeftWing", Vector3(0.12, 0.36, 0.48), Vector3(-0.37, 0.56, 0.0), Color("#DFDDD3"))
	_make_box("RightWing", Vector3(0.12, 0.36, 0.48), Vector3(0.37, 0.56, 0.0), Color("#DFDDD3"))
	_make_box("LeftLeg", Vector3(0.1, 0.3, 0.1), Vector3(-0.16, 0.16, 0.0), Color("#DA992B"))
	_make_box("RightLeg", Vector3(0.1, 0.3, 0.1), Vector3(0.16, 0.16, 0.0), Color("#DA992B"))
