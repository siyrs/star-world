class_name MapProfileCatalog
extends RefCounted

const PROFILE_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]

const LABELS := {
	"star_continent": "星辰大陆",
	"desert_ruins": "荒漠遗迹",
	"frozen_wastes": "极寒冰原",
	"sky_islands": "天空群岛",
	"abyss_world": "深渊世界",
}


static func is_valid(profile_id: String) -> bool:
	return profile_id in PROFILE_IDS


static func get_ids() -> Array[String]:
	return PROFILE_IDS.duplicate()


static func label(profile_id: String) -> String:
	return str(LABELS.get(profile_id, profile_id if not profile_id.is_empty() else "未知地图"))
