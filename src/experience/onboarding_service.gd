class_name OnboardingService
extends Node

signal state_changed(state: Dictionary)
signal tutorial_completed

const SERIAL_VERSION := 2
const STEPS := [
	{
		"id": "move",
		"title": "迈出第一步",
		"description": "使用 W、A、S、D 在世界中移动",
		"hint": "W  A  S  D",
	},
	{
		"id": "look",
		"title": "观察这个世界",
		"description": "移动鼠标，让屏幕正中心的准星指向不同方块",
		"hint": "移动鼠标",
	},
	{
		"id": "mine",
		"title": "采集一个方块",
		"description": "用准星瞄准方块，按住鼠标左键直到采集完成",
		"hint": "按住鼠标左键",
	},
	{
		"id": "place",
		"title": "放置一个方块",
		"description": "选中快捷栏中的方块，瞄准目标表面并按鼠标右键",
		"hint": "数字键选择 · 鼠标右键",
	},
	{
		"id": "inventory",
		"title": "整理背包",
		"description": "打开角色与背包界面，查看快捷栏和装备",
		"hint": "E",
	},
	{
		"id": "crafting",
		"title": "开始合成",
		"description": "打开随身合成，浏览当前可以制作的配方",
		"hint": "C",
	},
]

const ACTION_ALIASES := {
	"harvest_no_drop":"mine",
	"block_broken":"mine",
	"block_placed":"place",
	"open_inventory":"inventory",
	"open_crafting":"crafting",
}

var enabled := true
var dismissed := false
var completed := false
var _current_index := 0
var _completed_actions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_state()


func reset() -> void:
	dismissed = false
	completed = false
	_current_index = 0
	_completed_actions.clear()
	refresh_state()


func restart() -> void:
	reset()


func refresh_state() -> void:
	state_changed.emit(get_state())


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	refresh_state()


func set_dismissed(value: bool) -> void:
	if dismissed == value:
		return
	dismissed = value
	refresh_state()


func toggle_visibility() -> void:
	if not enabled or completed:
		return
	set_dismissed(not dismissed)


func report_action(action: StringName) -> bool:
	if completed:
		return false
	var action_id := _canonical_action_id(str(action))
	if not _is_known_action(action_id):
		return false
	var was_known := bool(_completed_actions.get(action_id, false))
	_completed_actions[action_id] = true
	var before_index := _current_index
	_advance_completed_steps()
	if was_known and before_index == _current_index:
		return false
	refresh_state()
	return true


func skip() -> void:
	if completed:
		return
	for step in STEPS:
		_completed_actions[str(step.get("id", ""))] = true
	_current_index = STEPS.size()
	completed = true
	dismissed = false
	refresh_state()
	tutorial_completed.emit()


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"completed": completed,
		"dismissed": dismissed,
		"current_index": _current_index,
		"completed_actions": _completed_actions.duplicate(true),
	}


func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		reset()
		return false
	completed = bool(data.get("completed", false))
	dismissed = bool(data.get("dismissed", false))
	_current_index = clampi(int(data.get("current_index", 0)), 0, STEPS.size())
	_completed_actions.clear()
	var raw_actions = data.get("completed_actions", {})
	if raw_actions is Dictionary:
		for key in raw_actions:
			var action_id := _canonical_action_id(str(key))
			if _is_known_action(action_id) and bool(raw_actions[key]):
				_completed_actions[action_id] = true
	if completed:
		_current_index = STEPS.size()
	else:
		_advance_completed_steps(false)
	refresh_state()
	return true


func get_state() -> Dictionary:
	var step: Dictionary = {}
	if not completed and _current_index >= 0 and _current_index < STEPS.size():
		step = STEPS[_current_index].duplicate(true)
	return {
		"enabled": enabled,
		"visible": enabled and not dismissed and not completed,
		"dismissed": dismissed,
		"completed": completed,
		"current_index": _current_index,
		"step_number": mini(_current_index + 1, STEPS.size()),
		"step_count": STEPS.size(),
		"progress": (
			1.0 if completed else float(_current_index) / float(maxi(1, STEPS.size()))
		),
		"step": step,
		"completed_actions": _completed_actions.duplicate(true),
	}


func is_completed() -> bool:
	return completed


func _advance_completed_steps(emit_completion: bool = true) -> void:
	while _current_index < STEPS.size():
		var step_id := str(STEPS[_current_index].get("id", ""))
		if not bool(_completed_actions.get(step_id, false)):
			break
		_current_index += 1
	if _current_index >= STEPS.size() and not completed:
		completed = true
		dismissed = false
		if emit_completion:
			tutorial_completed.emit()


func _canonical_action_id(action_id: String) -> String:
	return str(ACTION_ALIASES.get(action_id, action_id))


func _is_known_action(action_id: String) -> bool:
	for step in STEPS:
		if str(step.get("id", "")) == action_id:
			return true
	return false
