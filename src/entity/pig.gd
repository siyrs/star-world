class_name PigCreature
extends "res://src/entity/base_creature.gd"


func _ready() -> void:
	species_id = "pig"
	display_name = "猪"
	collision_size = Vector3(1.0, 1.0, 1.25)
	if not _configured:
		apply_profile({"name":"猪", "max_health":8, "speed":1.9, "damage":0, "drops":{"raw_pork":[1,3]}})
	super._ready()
	add_to_group("animals")


func _build_model() -> void:
	_make_box("Body", Vector3(1.0, 0.72, 1.25), Vector3(0.0, 0.68, 0.0), Color("#E78F92"))
	_make_box("Head", Vector3(0.8, 0.68, 0.64), Vector3(0.0, 0.76, 0.82), Color("#F09A9E"))
	_make_eyes(1.15, 0.84, 0.16, 0.08, Color("#2A1618"))
	_make_box("Snout", Vector3(0.48, 0.3, 0.23), Vector3(0.0, 0.68, 1.23), Color("#D97981"))
	_make_box("LeftEar", Vector3(0.22, 0.25, 0.12), Vector3(-0.29, 1.18, 0.78), Color("#C86672"))
	_make_box("RightEar", Vector3(0.22, 0.25, 0.12), Vector3(0.29, 1.18, 0.78), Color("#C86672"))
	for x in [-0.32, 0.32]:
		for z in [-0.4, 0.4]:
			_make_box("Leg", Vector3(0.2, 0.45, 0.2), Vector3(x, 0.24, z), Color("#CA7278"))
