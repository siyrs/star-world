extends SceneTree

func _initialize() -> void:
	var AttributeScript = load("res://src/attribute/attribute_service.gd")
	var Calculator = load("res://src/combat/damage_calculator.gd")
	var attributes = AttributeScript.new()
	attributes.add_modifier({"attack_damage": 5})
	assert(float(attributes.get_snapshot()["attack_damage"]) == 6.0)
	var result = Calculator.new().calculate(attributes.get_snapshot(), {"defense": 4})
	assert(float(result["damage"]) >= 1.0)
	quit()
