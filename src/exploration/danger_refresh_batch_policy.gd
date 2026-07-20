class_name DangerRefreshBatchPolicy
extends RefCounted

const MAX_VISIBLE_TRIGGERS := 4
const TRIGGER_PRIORITY: Array[String] = [
	"threat_changed",
	"ecology_changed",
	"phase_changed",
]


static func build(
	trigger_counts: Dictionary,
	event_count: int,
	dropped_event_count: int = 0
) -> Dictionary:
	var normalized_counts: Dictionary = {}
	for raw_trigger: Variant in trigger_counts.keys():
		var trigger := str(raw_trigger).strip_edges()
		var count := maxi(0, int(trigger_counts.get(raw_trigger, 0)))
		if trigger.is_empty() or count <= 0:
			continue
		normalized_counts[trigger] = int(normalized_counts.get(trigger, 0)) + count
	var triggers: Array[String] = []
	for raw_trigger: Variant in normalized_counts.keys():
		triggers.append(str(raw_trigger))
	triggers.sort_custom(
		func(a: String, b: String) -> bool:
			var a_priority := _priority(a)
			var b_priority := _priority(b)
			return a < b if a_priority == b_priority else a_priority < b_priority
	)
	var accepted_events := maxi(0, event_count)
	var visible_triggers: Array[String] = []
	var visible_limit := mini(MAX_VISIBLE_TRIGGERS, triggers.size())
	for index in range(visible_limit):
		visible_triggers.append(triggers[index])
	var trigger_key := "+".join(visible_triggers)
	if triggers.size() > visible_limit:
		trigger_key += "+more"
	return {
		"event_count": accepted_events,
		"dropped_event_count": maxi(0, dropped_event_count),
		"coalesced_event_count": maxi(0, accepted_events - 1),
		"unique_trigger_count": triggers.size(),
		"triggers": triggers,
		"trigger_counts": normalized_counts.duplicate(true),
		"primary_trigger": triggers[0] if not triggers.is_empty() else "manual",
		"trigger_key": trigger_key if not trigger_key.is_empty() else "manual",
	}


static func _priority(trigger: String) -> int:
	var index := TRIGGER_PRIORITY.find(trigger)
	return index if index >= 0 else TRIGGER_PRIORITY.size()
