class_name GameUiExtensionOverlayIds
extends RefCounted

# Base GameUI owns 0..6. Feature-specific panels must use this shared extension range.
const REPAIR := 7
const EXPLORATION_JOURNAL := 8
const ALL: Array[int] = [REPAIR, EXPLORATION_JOURNAL]


static func has_unique_ids() -> bool:
	var seen: Dictionary = {}
	for overlay_id: int in ALL:
		if overlay_id <= 6 or seen.has(overlay_id):
			return false
		seen[overlay_id] = true
	return true
