class_name ZombieCreature
extends "res://src/entity/base_creature.gd"


func _ready() -> void:
	species_id = "zombie"
	display_name = "僵尸"
	hostile = true
	collision_size = Vector3(0.75, 1.8, 0.65)
	if not _configured:
		apply_profile({
			"name":"僵尸",
			"max_health":20,
			"speed":2.1,
			"damage":1,
			"drops":{"rotten_flesh":[0,2]},
			"hostile_attack":{
				"species_id":"zombie",
				"source_id":"zombie",
				"detection_range":18.0,
				"attack_range":1.65,
				"windup_seconds":0.8,
				"cooldown_seconds":5.0,
				"cancel_range_multiplier":1.35,
				"cancel_recovery_seconds":0.6,
				"target_leash_multiplier":1.4,
				"telegraph_radius_multiplier":1.05,
			}
		})
	super._ready()
	add_to_group("hostile")


func _build_model() -> void:
	_make_box("Torso", Vector3(0.78, 0.88, 0.42), Vector3(0.0, 1.15, 0.0), Color("#356E68"))
	_make_box("Head", Vector3(0.6, 0.6, 0.56), Vector3(0.0, 1.86, 0.0), Color("#6C985B"))
	_make_eyes(0.29, 1.9, 0.13, 0.09, Color("#1A2418"))
	_make_box("Hair", Vector3(0.62, 0.13, 0.58), Vector3(0.0, 2.17, -0.02), Color("#304239"))
	_make_box("LeftArm", Vector3(0.24, 0.78, 0.24), Vector3(-0.53, 1.25, 0.28), Color("#618B55"))
	_make_box("RightArm", Vector3(0.24, 0.78, 0.24), Vector3(0.53, 1.25, 0.28), Color("#618B55"))
	_make_box("LeftLeg", Vector3(0.3, 0.82, 0.32), Vector3(-0.2, 0.42, 0.0), Color("#333F63"))
	_make_box("RightLeg", Vector3(0.3, 0.82, 0.32), Vector3(0.2, 0.42, 0.0), Color("#333F63"))
