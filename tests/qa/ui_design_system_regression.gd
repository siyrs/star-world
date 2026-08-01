extends SceneTree

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const DiagnosticsOverlayScript = preload("res://src/ui/diagnostics_overlay.gd")
const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_theme_contract()
	await _test_main_menu_and_subpages(Vector2i(1280, 720))
	await _test_main_menu_and_subpages(Vector2i(1024, 576))
	await _test_gameplay_overlay_contract()
	await _test_diagnostics_dashboard()
	if failures.is_empty():
		print("QA UI DESIGN SYSTEM PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA UI DESIGN SYSTEM FAILURE: %s" % failure)
		print("QA UI DESIGN SYSTEM FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_theme_contract() -> void:
	var theme := ThemeFactory.create_theme()
	var panel_theme := ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	for variation: String in [
		"PrimaryButton",
		"SecondaryButton",
		"GhostButton",
		"DangerButton",
		"MenuPrimaryButton",
		"CardButton",
		"SelectedCardButton",
		"InventorySlot",
		"InventorySlotSelected",
		"InventorySlotSwap",
	]:
		_check(
			theme.get_type_variation_base(variation) == "Button",
			"theme registers %s as one reusable button variation" % variation
		)
	for variation: String in [
		"GlassPanel",
		"ElevatedPanel",
		"CommandPanel",
		"CardPanel",
		"InsetPanel",
		"HudPanel",
		"ModalPanel",
		"DiagnosticsBackdrop",
		"DiagnosticsCard",
	]:
		_check(
			theme.get_type_variation_base(variation) == "PanelContainer",
			"theme registers %s as one reusable panel variation" % variation
		)
	var primary_normal := theme.get_stylebox("normal", "PrimaryButton")
	var secondary_normal := theme.get_stylebox("normal", "SecondaryButton")
	var focus := theme.get_stylebox("focus", "PrimaryButton") as StyleBoxFlat
	var distinct_surfaces := false
	if primary_normal is StyleBoxTexture and secondary_normal is StyleBoxTexture:
		distinct_surfaces = (
			(primary_normal as StyleBoxTexture).texture
			!= (secondary_normal as StyleBoxTexture).texture
		)
	elif primary_normal is StyleBoxFlat and secondary_normal is StyleBoxFlat:
		distinct_surfaces = (
			(primary_normal as StyleBoxFlat).bg_color
			!= (secondary_normal as StyleBoxFlat).bg_color
		)
	_check(
		primary_normal != null and secondary_normal != null and distinct_surfaces,
		"primary and secondary actions have distinct semantic surfaces"
	)
	_check(
		focus != null and focus.border_width_left >= 2 and focus.border_color == Tokens.color(Tokens.COLOR_BORDER_FOCUS),
		"keyboard focus uses the explicit high-contrast focus ring"
	)
	_check(
		_contrast_ratio(Tokens.color(Tokens.COLOR_TEXT), Tokens.color(Tokens.COLOR_SURFACE)) >= 7.0,
		"primary text and glass surface exceed the high-contrast readability target"
	)
	# Flat buttons in overlay context must meet WCAG 4.5:1 across normal/hover/pressed/focus.
	var overlay_flat_variations := [
		["GhostButton"],
		["CardButton"],
		["SelectedCardButton"],
		["ToolbarButton"],
	]
	var state_specs := [
		["normal", "font_color"],
		["hover", "font_hover_color"],
		["pressed", "font_pressed_color"],
		["focus", "font_focus_color"],
	]
	for entry: Array in overlay_flat_variations:
		var variation: String = str(entry[0])
		for spec: Array in state_specs:
			var style_name: String = str(spec[0])
			var color_prop: String = str(spec[1])
			var font_color: Color = theme.get_color(color_prop, variation)
			var stylebox := theme.get_stylebox(style_name, variation)
			var background: Color = Tokens.color(Tokens.COLOR_SURFACE)
			if stylebox is StyleBoxFlat:
				var bg: Color = (stylebox as StyleBoxFlat).bg_color
				if bg.a >= 0.01:
					background = bg
			_check(
				_contrast_ratio(font_color, background) >= 4.5,
				"overlay %s %s contrast >= 4.5" % [variation, style_name]
			)
	# Flat buttons in panel context must meet WCAG 4.5:1 across normal/hover/pressed/focus.
	var panel_flat_variations := [
		["GhostButton"],
		["CardButton"],
		["SelectedCardButton"],
		["ToolbarButton"],
	]
	for entry: Array in panel_flat_variations:
		var variation: String = str(entry[0])
		for spec: Array in state_specs:
			var style_name: String = str(spec[0])
			var color_prop: String = str(spec[1])
			var font_color: Color = panel_theme.get_color(color_prop, variation)
			var stylebox := panel_theme.get_stylebox(style_name, variation)
			var effective_bg: Color = Tokens.color(Tokens.MC_PANEL)
			if stylebox is StyleBoxFlat:
				var bg: Color = (stylebox as StyleBoxFlat).bg_color
				if bg.a >= 0.01:
					effective_bg = bg
			_check(
				_contrast_ratio(font_color, effective_bg) >= 4.5,
				"panel %s %s contrast >= 4.5" % [variation, style_name]
			)
		var disabled_font: Color = panel_theme.get_color("font_disabled_color", variation)
		var disabled_stylebox := panel_theme.get_stylebox("disabled", variation)
		var disabled_bg: Color = Tokens.color(Tokens.MC_PANEL)
		if disabled_stylebox is StyleBoxFlat:
			disabled_bg = (disabled_stylebox as StyleBoxFlat).bg_color
		var normal_font: Color = panel_theme.get_color("font_color", variation)
		var normal_stylebox := panel_theme.get_stylebox("normal", variation)
		var normal_bg: Color = Tokens.color(Tokens.MC_PANEL)
		if normal_stylebox is StyleBoxFlat:
			var nb: Color = (normal_stylebox as StyleBoxFlat).bg_color
			if nb.a >= 0.01:
				normal_bg = nb
		var disabled_contrast: float = _contrast_ratio(disabled_font, disabled_bg)
		var normal_contrast: float = _contrast_ratio(normal_font, normal_bg)
		_check(
			disabled_contrast < normal_contrast - 0.5,
			"panel %s disabled contrast (%.1f) is visibly lower than normal (%.1f)"
			% [variation, disabled_contrast, normal_contrast]
		)
	# Textured buttons always use dark pixel-art backgrounds; verify registration.
	var textured_variations := [
		"Button",
		"PrimaryButton",
		"SecondaryButton",
		"DangerButton",
		"MenuPrimaryButton",
	]
	for variation: String in textured_variations:
		_check(
			theme.get_stylebox("normal", variation) != null,
			"overlay %s has a valid normal style" % variation
		)
		_check(
			panel_theme.get_stylebox("normal", variation) != null,
			"panel %s has a valid normal style" % variation
		)
	_check(
		panel_theme.get_constant("shadow_outline_size", "PageTitle") == 0
		and panel_theme.get_constant("shadow_outline_size", "SectionTitle") == 0,
		"panel headings do not inherit dark pixel shadows"
	)
	_check(
		Tokens.SPACE_SM == 8 and Tokens.SPACE_LG == 16 and Tokens.SPACE_XL == 24,
		"design system retains one deterministic eight-point spacing rhythm"
	)


func _test_main_menu_and_subpages(viewport_size: Vector2i) -> void:
	root.size = viewport_size
	root.content_scale_size = viewport_size
	var menu = MainMenuScene.instantiate()
	root.add_child(menu)
	for _frame in 5:
		await process_frame
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var menu_snapshot: Dictionary = menu.call("get_visual_snapshot")
	var hero: Rect2 = menu_snapshot.get("hero", Rect2())
	var command: Rect2 = menu_snapshot.get("command_panel", Rect2())
	print(
		"UI_GEOMETRY menu viewport=%s menu=%s main=%s hero=%s command=%s"
		% [
			viewport_size,
			menu.get_global_rect(),
			menu_snapshot.get("main_layout", Rect2()),
			hero,
			command,
		]
	)
	_check(_rect_inside(viewport_rect, hero), "%s hero remains inside the product viewport" % viewport_size)
	_check(_rect_inside(viewport_rect, command), "%s command deck remains inside the product viewport" % viewport_size)
	_check(not hero.intersects(command), "%s hero and command deck keep separate visual hierarchy" % viewport_size)
	_check(int(menu_snapshot.get("button_count", 0)) == 6, "main menu exposes six bounded commands")
	var variations: Array = menu_snapshot.get("button_variations", [])
	_check(
		variations.size() == 6
		and str(variations[0]) == "MenuPrimaryButton"
		and str(variations[5]) == "DangerButton",
		"main command hierarchy preserves one primary CTA and one destructive exit"
	)

	var map_panel := menu.get("_map_panel") as Control
	menu.call("_show_panel", map_panel)
	await process_frame
	var map_snapshot: Dictionary = map_panel.call("get_visual_snapshot")
	print(
		"UI_GEOMETRY map viewport=%s panel=%s details=%s create=%s minimum=%s size=%s"
		% [
			viewport_size,
			map_snapshot.get("panel_rect", Rect2()),
			map_snapshot.get("details_rect", Rect2()),
			map_snapshot.get("create_rect", Rect2()),
			map_panel.get_combined_minimum_size(),
			map_panel.size,
		]
	)
	_check(_rect_inside(viewport_rect, map_snapshot.get("panel_rect", Rect2())), "map briefing fits the viewport")
	_check(int(map_snapshot.get("profile_count", 0)) == 5, "map directory exposes all five production worlds")
	_check(str(map_snapshot.get("selected_variation", "")) == "SelectedCardButton", "selected map uses the shared selected-card state")

	var settings_panel := menu.get("_settings_panel") as Control
	menu.call("_show_panel", settings_panel)
	await process_frame
	var settings_snapshot: Dictionary = settings_panel.call("get_layout_snapshot")
	_check(_rect_inside(viewport_rect, settings_snapshot.get("panel_rect", Rect2())), "settings workspace fits the viewport")
	_check(int(settings_snapshot.get("section_card_count", 0)) == 4, "settings groups controls into four scannable sections")
	_check(str(settings_snapshot.get("primary_action_variation", "")) == "PrimaryButton", "settings keeps one clear primary action")
	_check(
		not (settings_snapshot.get("scroll_rect", Rect2()) as Rect2).intersects(
			settings_snapshot.get("actions_rect", Rect2()) as Rect2
		),
		"settings scroll region never overlaps the fixed action bar"
	)

	var save_panel := menu.get("_save_panel") as Control
	menu.call("_show_panel", save_panel)
	await process_frame
	var save_snapshot: Dictionary = save_panel.call("get_virtualization_snapshot")
	var visual: Dictionary = save_snapshot.get("visual", {})
	print(
		"UI_GEOMETRY save viewport=%s panel=%s query=%s list=%s minimum=%s size=%s"
		% [
			viewport_size,
			visual.get("panel", Rect2()),
			visual.get("query_card", Rect2()),
			visual.get("list_card", Rect2()),
			save_panel.get_combined_minimum_size(),
			save_panel.size,
		]
	)
	_check(_rect_inside(viewport_rect, visual.get("panel", Rect2())), "protected save browser fits the viewport")
	_check(str(visual.get("delete_variation", "")) == "DangerButton", "world deletion is visually classified as destructive")

	menu.queue_free()
	for _frame in 4:
		await process_frame


func _test_gameplay_overlay_contract() -> void:
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)
	var game_ui = GameUIScript.new()
	root.add_child(game_ui)
	for _frame in 3:
		await process_frame
	game_ui.call("begin_gameplay")
	game_ui.call("open_inventory")
	await process_frame
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var snapshot: Dictionary = game_ui.call("get_visual_snapshot")
	_check(bool(snapshot.get("scrim_visible", false)), "blocking gameplay overlay uses one shared scrim")
	_check(_rect_inside(viewport_rect, snapshot.get("inventory_rect", Rect2())), "inventory overlay remains inside 1024x576")
	var pause_panel := game_ui.get("_pause_panel") as Control
	game_ui.call("close_overlay")
	game_ui.call("toggle_pause")
	await process_frame
	snapshot = game_ui.call("get_visual_snapshot")
	_check(_rect_inside(viewport_rect, snapshot.get("pause_rect", Rect2())), "pause modal remains inside 1024x576")
	var resume := _find_button(pause_panel, "继续游戏")
	var save := _find_button(pause_panel, "保存世界")
	_check(
		resume != null and resume.theme_type_variation == "PrimaryButton",
		"pause modal gives resume the primary action hierarchy"
	)
	_check(
		save != null and save.theme_type_variation == "SecondaryButton",
		"pause modal keeps save as the secondary action"
	)
	game_ui.call("end_gameplay")
	game_ui.queue_free()
	for _frame in 4:
		await process_frame


func _test_diagnostics_dashboard() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var overlay = DiagnosticsOverlayScript.new()
	root.add_child(overlay)
	for _frame in 3:
		await process_frame
	overlay.call("set_overlay_visible", true)
	await process_frame
	var snapshot: Dictionary = overlay.call("get_visual_snapshot")
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var runtime_card: Rect2 = snapshot.get("runtime_card", Rect2())
	var operations_card: Rect2 = snapshot.get("operations_card", Rect2())
	_check(_rect_inside(viewport_rect, snapshot.get("panel", Rect2())), "F3 dashboard fits the desktop viewport")
	_check(_rect_inside(viewport_rect, runtime_card) and _rect_inside(viewport_rect, operations_card), "both diagnostic cards fit the viewport")
	_check(not runtime_card.intersects(operations_card), "runtime and operations cards remain visually separated")
	_check(_all_controls_are_passthrough(overlay), "diagnostics dashboard remains fully mouse-passthrough")
	overlay.queue_free()
	for _frame in 3:
		await process_frame


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _all_controls_are_passthrough(node: Node) -> bool:
	if node == null:
		return false
	if node is Control:
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE:
			return false
	for child: Node in node.get_children():
		if not _all_controls_are_passthrough(child):
			return false
	return true


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x - 0.5
		and candidate.position.y >= container_rect.position.y - 0.5
		and candidate.end.x <= container_rect.end.x + 0.5
		and candidate.end.y <= container_rect.end.y + 0.5
	)


func _contrast_ratio(first: Color, second: Color) -> float:
	var lighter := maxf(_relative_luminance(first), _relative_luminance(second))
	var darker := minf(_relative_luminance(first), _relative_luminance(second))
	return (lighter + 0.05) / (darker + 0.05)


func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


func _linear_channel(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
