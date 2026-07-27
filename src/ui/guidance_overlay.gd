class_name GuidanceOverlay
extends Control

signal guidance_visibility_changed(visible: bool)

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const UiInputPolicy = preload("res://src/ui/ui_input_policy.gd")
const InputActionsScript = preload("res://src/input/gameplay_input_actions.gd")
const KeyBadges = preload("res://src/ui/key_badge_formatter.gd")

var coordinator: Node
var feedback
var onboarding

var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_status: Label
var _prompt_panel: PanelContainer
var _prompt_title: Label
var _prompt_subtitle: Label
var _prompt_actions: RichTextLabel
var _tutorial_panel: PanelContainer
var _tutorial_progress: ProgressBar
var _tutorial_step: Label
var _tutorial_title: Label
var _tutorial_description: Label
var _tutorial_hint: RichTextLabel
var _tutorial_state: Dictionary = {}
var _prompt_state: Dictionary = {}
var _crosshair: Control
var _gameplay_active := false
var _overlay_blocked := false


func attach_crosshair(crosshair: Control) -> void:
	_crosshair = crosshair


func _update_crosshair_state(prompt: Dictionary) -> void:
	if _crosshair == null or not is_instance_valid(_crosshair):
		return
	if not _crosshair.has_method("set_target_state"):
		return
	var state := &"neutral"
	if str(prompt.get("tone", "")) == "error":
		state = &"hostile"
	elif str(prompt.get("focus_type", "")) == "block" and str(prompt.get("tone", "")) == "info":
		state = &"actionable"
	_crosshair.call("set_target_state", state)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeFactory.create_theme()
	_build_toast()
	_build_prompt()
	_build_tutorial()
	UiInputPolicy.make_passthrough_tree(self)
	set_process_input(false)


func setup(p_coordinator: Node) -> void:
	_disconnect_services()
	coordinator = p_coordinator
	feedback = coordinator.call("get_feedback") if coordinator != null else null
	onboarding = coordinator.call("get_onboarding") if coordinator != null else null
	if feedback != null:
		feedback.connect("active_toast_changed", Callable(self, "_on_toast_changed"))
		feedback.connect("prompt_changed", Callable(self, "_on_prompt_changed"))
		_on_toast_changed(feedback.call("get_active_toast"))
		_on_prompt_changed(feedback.call("get_prompt"))
	else:
		_on_toast_changed({})
		_on_prompt_changed({})
	if onboarding != null:
		onboarding.connect("state_changed", Callable(self, "_on_tutorial_state_changed"))
		_on_tutorial_state_changed(onboarding.call("get_state"))
	else:
		_on_tutorial_state_changed({})


func begin_gameplay() -> void:
	_gameplay_active = true
	set_process_input(true)
	_refresh_visibility()


func end_gameplay() -> void:
	_gameplay_active = false
	_overlay_blocked = false
	set_process_input(false)
	_toast_panel.visible = false
	_prompt_panel.visible = false
	_tutorial_panel.visible = false


func set_overlay_blocked(value: bool) -> void:
	_overlay_blocked = value
	_refresh_visibility()


func get_layout_snapshot() -> Dictionary:
	return {
		"toast": _toast_panel.get_global_rect() if _toast_panel != null else Rect2(),
		"prompt": _prompt_panel.get_global_rect() if _prompt_panel != null else Rect2(),
		"tutorial": _tutorial_panel.get_global_rect() if _tutorial_panel != null else Rect2(),
		"tutorial_visible": _tutorial_panel != null and _tutorial_panel.visible,
		"prompt_visible": _prompt_panel != null and _prompt_panel.visible,
		"toast_visible": _toast_panel != null and _toast_panel.visible,
	}


func _input(event: InputEvent) -> void:
	if not _gameplay_active:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(InputActionsScript.TOGGLE_GUIDANCE) and onboarding != null:
		onboarding.call("toggle_visibility")
		get_viewport().set_input_as_handled()


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ToastCard"
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.offset_left = -286.0
	_toast_panel.offset_right = 286.0
	_toast_panel.offset_top = 18.0
	_toast_panel.offset_bottom = 72.0
	_toast_panel.theme_type_variation = "HudPanel"
	_toast_panel.visible = false
	add_child(_toast_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_toast_panel.add_child(row)
	_toast_status = Label.new()
	_toast_status.text = "●"
	_toast_status.theme_type_variation = "MetricLabel"
	row.add_child(_toast_status)
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.theme_type_variation = "CaptionLabel"
	row.add_child(_toast_label)


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "ContextPromptCard"
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.anchor_top = 1.0
	_prompt_panel.anchor_bottom = 1.0
	_prompt_panel.offset_left = -310.0
	_prompt_panel.offset_right = 310.0
	_prompt_panel.offset_top = -224.0
	_prompt_panel.offset_bottom = -151.0
	_prompt_panel.theme_type_variation = "HudPanel"
	_prompt_panel.visible = false
	add_child(_prompt_panel)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_LG)
	_prompt_panel.add_child(content)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", Tokens.SPACE_2XS)
	content.add_child(identity)
	var eyebrow := Label.new()
	eyebrow.text = "交互"
	eyebrow.theme_type_variation = "EyebrowLabel"
	identity.add_child(eyebrow)
	_prompt_title = Label.new()
	_prompt_title.theme_type_variation = "SectionTitle"
	identity.add_child(_prompt_title)
	_prompt_subtitle = Label.new()
	_prompt_subtitle.theme_type_variation = "CaptionLabel"
	identity.add_child(_prompt_subtitle)
	_prompt_actions = RichTextLabel.new()
	_prompt_actions.bbcode_enabled = true
	_prompt_actions.scroll_active = false
	_prompt_actions.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prompt_actions.custom_minimum_size = Vector2(226, 46)
	_prompt_actions.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt_actions.add_theme_font_size_override("normal_font_size", Tokens.FONT_CAPTION)
	_prompt_actions.add_theme_color_override(
		"default_color", Tokens.color(Tokens.COLOR_ACCENT_WARM_BRIGHT)
	)
	content.add_child(_prompt_actions)


func _build_tutorial() -> void:
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.name = "TutorialCard"
	_tutorial_panel.anchor_left = 1.0
	_tutorial_panel.anchor_right = 1.0
	_tutorial_panel.anchor_top = 0.0
	_tutorial_panel.anchor_bottom = 0.0
	_tutorial_panel.offset_left = -372.0
	_tutorial_panel.offset_right = -18.0
	_tutorial_panel.offset_top = 18.0
	_tutorial_panel.offset_bottom = 214.0
	_tutorial_panel.theme_type_variation = "HudPanel"
	_tutorial_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#100C07F5", Tokens.COLOR_ACCENT_WARM, 2, Tokens.SPACE_MD)
	)
	_tutorial_panel.visible = false
	add_child(_tutorial_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_tutorial_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_tutorial_step = Label.new()
	_tutorial_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorial_step.theme_type_variation = "EyebrowLabel"
	_tutorial_step.add_theme_color_override(
		"font_color", Tokens.color(Tokens.COLOR_ACCENT_WARM_BRIGHT)
	)
	header.add_child(_tutorial_step)
	var hide_hint := UiKit.make_badge("F1 隐藏", "warm")
	header.add_child(hide_hint)
	_tutorial_title = Label.new()
	_tutorial_title.theme_type_variation = "SectionTitle"
	content.add_child(_tutorial_title)
	_tutorial_description = Label.new()
	_tutorial_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_description.theme_type_variation = "CaptionLabel"
	content.add_child(_tutorial_description)
	_tutorial_hint = RichTextLabel.new()
	_tutorial_hint.bbcode_enabled = true
	_tutorial_hint.fit_content = true
	_tutorial_hint.scroll_active = false
	_tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_hint.add_theme_font_size_override("normal_font_size", Tokens.FONT_BODY)
	_tutorial_hint.add_theme_color_override(
		"default_color", Tokens.color(Tokens.COLOR_ACCENT_WARM_BRIGHT)
	)
	content.add_child(_tutorial_hint)
	_tutorial_progress = ProgressBar.new()
	_tutorial_progress.show_percentage = false
	_tutorial_progress.min_value = 0.0
	_tutorial_progress.max_value = 1.0
	_tutorial_progress.custom_minimum_size.y = 9.0
	_tutorial_progress.add_theme_stylebox_override(
		"fill",
		Tokens.bevel_style(
			Tokens.COLOR_ACCENT_WARM, Tokens.COLOR_ACCENT_WARM_BRIGHT, 1, 1.0
		)
	)
	content.add_child(_tutorial_progress)


func _on_toast_changed(toast: Dictionary) -> void:
	if toast.is_empty():
		_toast_panel.visible = false
		return
	_toast_label.text = str(toast.get("text", ""))
	var severity := str(toast.get("severity", "info"))
	var severity_color := Tokens.severity_color(severity)
	_toast_status.add_theme_color_override("font_color", severity_color)
	_toast_label.add_theme_color_override("font_color", severity_color)
	_toast_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style(
			Tokens.COLOR_SURFACE_RAISED,
			_color_to_hex(severity_color),
			2,
			Tokens.SPACE_SM
		)
	)
	_toast_panel.visible = _gameplay_active


func _on_prompt_changed(prompt: Dictionary) -> void:
	_prompt_state = prompt.duplicate(true)
	_update_crosshair_state(prompt)
	if prompt.is_empty():
		_prompt_panel.visible = false
		return
	_prompt_title.text = str(prompt.get("title", ""))
	_prompt_subtitle.text = str(prompt.get("subtitle", ""))
	var action_parts: Array[String] = []
	for key in ["primary", "secondary"]:
		var action_text := str(prompt.get(key, "")).strip_edges()
		if not action_text.is_empty():
			action_parts.append(action_text)
	_prompt_actions.text = KeyBadges.format("\n".join(action_parts))
	var tone := str(prompt.get("tone", "info"))
	_prompt_panel.add_theme_stylebox_override(
		"panel",
		Tokens.bevel_style("#100C07EE", Tokens.tone_border(tone), 2, Tokens.SPACE_MD)
	)
	_refresh_visibility()


func _on_tutorial_state_changed(state: Dictionary) -> void:
	_tutorial_state = state.duplicate(true)
	var step: Dictionary = state.get("step", {})
	if step.is_empty():
		_tutorial_panel.visible = false
		guidance_visibility_changed.emit(false)
		return
	_tutorial_step.text = "新手引导 · %d / %d" % [
		int(state.get("step_number", 1)), int(state.get("step_count", 1))
	]
	_tutorial_title.text = str(step.get("title", ""))
	_tutorial_description.text = str(step.get("description", ""))
	_tutorial_hint.text = KeyBadges.format(str(step.get("hint", "")))
	_tutorial_progress.value = float(state.get("progress", 0.0))
	_refresh_visibility()


func _refresh_visibility() -> void:
	_prompt_panel.visible = (
		_gameplay_active and not _overlay_blocked and not _prompt_state.is_empty()
	)
	var tutorial_visible := (
		_gameplay_active
		and not _overlay_blocked
		and bool(_tutorial_state.get("visible", false))
	)
	_tutorial_panel.visible = tutorial_visible
	guidance_visibility_changed.emit(tutorial_visible)
	if _toast_panel.visible and not _gameplay_active:
		_toast_panel.visible = false


func _disconnect_services() -> void:
	if feedback != null:
		var toast_callback := Callable(self, "_on_toast_changed")
		if feedback.is_connected("active_toast_changed", toast_callback):
			feedback.disconnect("active_toast_changed", toast_callback)
		var prompt_callback := Callable(self, "_on_prompt_changed")
		if feedback.is_connected("prompt_changed", prompt_callback):
			feedback.disconnect("prompt_changed", prompt_callback)
	if onboarding != null:
		var tutorial_callback := Callable(self, "_on_tutorial_state_changed")
		if onboarding.is_connected("state_changed", tutorial_callback):
			onboarding.disconnect("state_changed", tutorial_callback)
	feedback = null
	onboarding = null


func _color_to_hex(color: Color) -> String:
	return "#%s" % color.to_html(true)
