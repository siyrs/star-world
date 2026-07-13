class_name DamageCalculator
extends RefCounted

## Pure combat calculation policy.
## Does not access Player, UI or entities directly.

func calculate(attack: Dictionary, defense: Dictionary) -> Dictionary:
	var attack_power := maxf(0.0, float(attack.get("attack_damage", 1.0)))
	var defense_power := maxf(0.0, float(defense.get("defense", 0.0)))
	var damage := maxf(1.0, attack_power - defense_power * 0.5)
	return {
		"damage": damage,
		"blocked": defense_power,
	}
