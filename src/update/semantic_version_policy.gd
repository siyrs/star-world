class_name SemanticVersionPolicy
extends RefCounted


static func normalize(value: String) -> String:
	var text := value.strip_edges()
	if text.begins_with("v") or text.begins_with("V"):
		text = text.substr(1)
	return text


static func parse(value: String) -> Dictionary:
	var normalized := normalize(value)
	if normalized.is_empty():
		return _failure("empty_version")
	var build_split := normalized.split("+", false, 1)
	var core_and_pre := str(build_split[0])
	var build := str(build_split[1]) if build_split.size() > 1 else ""
	var pre_split := core_and_pre.split("-", false, 1)
	var core := str(pre_split[0])
	var prerelease := str(pre_split[1]) if pre_split.size() > 1 else ""
	var parts := core.split(".", false)
	if parts.size() != 3:
		return _failure("invalid_core")
	var numbers: Array[int] = []
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int():
			return _failure("invalid_number")
		if part.length() > 1 and part.begins_with("0"):
			return _failure("leading_zero")
		var number := int(part)
		if number < 0:
			return _failure("negative_number")
		numbers.append(number)
	var pre_parts: Array[String] = []
	if not prerelease.is_empty():
		for identifier: String in prerelease.split(".", false):
			if identifier.is_empty() or not _is_identifier(identifier):
				return _failure("invalid_prerelease")
			pre_parts.append(identifier)
	if not build.is_empty():
		for identifier: String in build.split(".", false):
			if identifier.is_empty() or not _is_identifier(identifier):
				return _failure("invalid_build")
	return {
		"success": true,
		"normalized": normalized,
		"major": numbers[0],
		"minor": numbers[1],
		"patch": numbers[2],
		"prerelease": pre_parts,
		"build": build,
	}


static func compare(left: String, right: String) -> int:
	var a := parse(left)
	var b := parse(right)
	if not bool(a.get("success", false)) or not bool(b.get("success", false)):
		return 0
	for key: String in ["major", "minor", "patch"]:
		var a_value := int(a.get(key, 0))
		var b_value := int(b.get(key, 0))
		if a_value < b_value:
			return -1
		if a_value > b_value:
			return 1
	var a_pre: Array = a.get("prerelease", [])
	var b_pre: Array = b.get("prerelease", [])
	if a_pre.is_empty() and b_pre.is_empty():
		return 0
	if a_pre.is_empty():
		return 1
	if b_pre.is_empty():
		return -1
	var count := mini(a_pre.size(), b_pre.size())
	for index in count:
		var a_id := str(a_pre[index])
		var b_id := str(b_pre[index])
		if a_id == b_id:
			continue
		var a_numeric := a_id.is_valid_int()
		var b_numeric := b_id.is_valid_int()
		if a_numeric and b_numeric:
			return -1 if int(a_id) < int(b_id) else 1
		if a_numeric != b_numeric:
			return -1 if a_numeric else 1
		return -1 if a_id < b_id else 1
	if a_pre.size() == b_pre.size():
		return 0
	return -1 if a_pre.size() < b_pre.size() else 1


static func is_newer(candidate: String, current: String) -> bool:
	return compare(candidate, current) > 0


static func _is_identifier(value: String) -> bool:
	for index in value.length():
		var code := value.unicode_at(index)
		var allowed := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code == 45
		)
		if not allowed:
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
