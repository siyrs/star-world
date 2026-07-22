class_name AbyssBruteCreature
extends "res://src/entity/base_creature.gd"

var elite: bool = true
var danger_weight: float = 2.0


func apply_profile(profile: Dictionary) -> void:
	elite = bool(profile.get("elite", true))
	danger_weight = clampf(float(profile.get("danger_weight", 2.0)), 1.0, 6.0)
	super.apply_profile(profile)


func _ready() -> void:
	species_id = "abyss_brute"
	display_name = "深渊重击者"
	hostile = true
	collision_size = Vector3(1.1, 2.2, 0.9)
	if not _configured:
		apply_profile({
			"name":"深渊重击者",
			"max_health":28,
			"speed":1.45,
			"damage":4,
			"elite":true,
			"danger_weight":2.0,
			"drops":{"rotten_flesh":[1,3], "abyss_cinder":[1,1]},
			"hostile_attack":{
				"species_id":"abyss_brute",
				"source_id":"abyss_brute",
				"detection_range":20.0,
				"attack_range":2.2,
				"windup_seconds":1.35,
				"cooldown_seconds":7.0,
				"cancel_range_multiplier":1.25,
				"cancel_recovery_seconds":0.85,
				"target_leash_multiplier":1.35,
				"telegraph_radius_multiplier":1.2,
			}
		})
	super._ready()
	add_to_group("hostile")
	if elite:
		add_to_group("elite")


func _build_model() -> void:
	_make_box("Torso", Vector3(1.08, 1.15, 0.64), Vector3(0.0, 1.38, 0.0), Color("#3B2731"))
	_make_box("ChestPlate", Vector3(1.18, 0.72, 0.72), Vector3(0.0, 1.56, -0.02), Color("#5D3034"))
	_make_box("Head", Vector3(0.78, 0.72, 0.7), Vector3(0.0, 2.28, 0.0), Color("#59403E"))
	_make_eyes(0.36, 2.34, 0.17, 0.1, Color("#E04038"))
	_make_box("Brow", Vector3(0.82, 0.18, 0.74), Vector3(0.0, 2.52, 0.03), Color("#261D25"))
	_make_box("LeftHorn", Vector3(0.18, 0.34, 0.18), Vector3(-0.38, 2.78, 0.0), Color("#B54A32"))
	_make_box("RightHorn", Vector3(0.18, 0.34, 0.18), Vector3(0.38, 2.78, 0.0), Color("#B54A32"))
	_make_box("EmberCore", Vector3(0.34, 0.34, 0.12), Vector3(0.0, 1.56, -0.38), Color("#F06A36"))
	_make_box("LeftArm", Vector3(0.34, 1.02, 0.34), Vector3(-0.72, 1.42, 0.18), Color("#4A3538"))
	_make_box("RightArm", Vector3(0.34, 1.02, 0.34), Vector3(0.72, 1.42, 0.18), Color("#4A3538"))
	_make_box("LeftLeg", Vector3(0.42, 1.0, 0.42), Vector3(-0.28, 0.5, 0.0), Color("#282532"))
	_make_box("RightLeg", Vector3(0.42, 1.0, 0.42), Vector3(0.28, 0.5, 0.0), Color("#282532"))
