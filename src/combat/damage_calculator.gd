class_name DamageCalculator
extends RefCounted

const DEFENSE_SCALE := 20.0
const MAX_MITIGATION_RATIO := 0.80
const MIN_DAMAGE := 0.5


func calculate(attacker: Dictionary, defender: Dictionary = {}, source: String = "attack") -> Dictionary:
	var attack_values := _values(attacker)
	var defense_values := _values(defender)
	var raw_damage := maxf(0.0, float(attack_values.get("attack_damage", 1.0)))
	return calculate_raw(raw_damage, defense_values, source)


func calculate_raw(raw_damage: float, defender: Dictionary = {}, source: String = "damage") -> Dictionary:
	var defense_values := _values(defender)
	var normalized_raw := maxf(0.0, raw_damage)
	var defense := maxf(0.0, float(defense_values.get("defense", 0.0)))
	var mitigation_ratio := 0.0
	if defense > 0.0:
		mitigation_ratio = minf(MAX_MITIGATION_RATIO, defense / (defense + DEFENSE_SCALE))
	var final_damage := 0.0
	if normalized_raw > 0.0:
		final_damage = maxf(MIN_DAMAGE, normalized_raw * (1.0 - mitigation_ratio))
	var absorbed := maxf(0.0, normalized_raw - final_damage)
	return {
		"source": source,
		"raw_damage": normalized_raw,
		"final_damage": final_damage,
		"damage": final_damage,
		"defense": defense,
		"mitigation_ratio": mitigation_ratio,
		"absorbed": absorbed,
		"blocked": absorbed,
	}


func _values(snapshot: Dictionary) -> Dictionary:
	var final_values = snapshot.get("final", null)
	if final_values is Dictionary:
		return final_values
	var attributes = snapshot.get("attributes", null)
	if attributes is Dictionary:
		return attributes
	return snapshot
