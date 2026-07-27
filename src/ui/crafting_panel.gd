class_name CraftingPanel
extends PanelContainer

signal panel_closed
signal item_crafted(recipe_id: String)

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")
const UiKit = preload("res://src/ui/ui_kit.gd")
const STATIONS := ["hand", "workbench"]

var crafting
var inventory
var _station_select: OptionButton
var _recipe_list: VBoxContainer
var _summary: Label
var _recipe_count_badge: Label
var _recipe_scroll: ScrollContainer


func _ready() -> void:
	theme = ThemeFactory.create_theme(ThemeFactory.CONTEXT_PANEL)
	theme_type_variation = "ElevatedPanel"
	custom_minimum_size = Vector2(820, 540)
	_build_ui()


func setup(p_crafting, p_inventory) -> void:
	_disconnect_services()
	crafting = p_crafting
	inventory = p_inventory
	if inventory != null:
		inventory.inventory_changed.connect(refresh)
	if crafting != null:
		crafting.craft_succeeded.connect(_on_craft_succeeded)
	refresh()


func open_station(station: String) -> void:
	var index := STATIONS.find(station)
	index = maxi(0, index)
	_station_select.select(index)
	_set_station(index)


func refresh() -> void:
	if _recipe_list == null:
		return
	for child in _recipe_list.get_children():
		child.queue_free()
	if crafting == null:
		_summary.text = "合成服务未连接"
		_summary.theme_type_variation = "DangerLabel"
		_recipe_count_badge.text = "0 配方"
		return
	var recipes: Array = crafting.get_recipes()
	var visible_count := 0
	var available_count := 0
	for recipe in recipes:
		var recipe_station := str(recipe.get("station", "hand"))
		if (
			recipe_station != crafting.active_station
			and not (recipe_station == "hand" and crafting.active_station == "workbench")
		):
			continue
		visible_count += 1
		var recipe_id := str(recipe.get("id", ""))
		var can_craft: bool = bool(crafting.can_craft(recipe_id))
		if can_craft:
			available_count += 1
		var button := Button.new()
		button.theme_type_variation = "RecipeButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _recipe_text(recipe)
		button.tooltip_text = button.text
		button.custom_minimum_size.y = 52.0
		button.disabled = not can_craft
		button.pressed.connect(func() -> void: crafting.craft(recipe_id))
		_recipe_list.add_child(button)
	_summary.theme_type_variation = "CaptionLabel"
	_summary.text = "%s · 当前可制作 %d 项；材料不足的配方会保持可见。" % [
		_station_name(crafting.active_station), available_count
	]
	_recipe_count_badge.text = "%d / %d 配方" % [visible_count, crafting.recipe_count()]


func get_visual_snapshot() -> Dictionary:
	return {
		"panel": get_global_rect(),
		"recipe_scroll": _recipe_scroll.get_global_rect() if _recipe_scroll != null else Rect2(),
		"recipe_button_count": _recipe_list.get_child_count() if _recipe_list != null else 0,
		"station": crafting.active_station if crafting != null else "",
		"summary": _summary.text if _summary != null else "",
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Tokens.SPACE_MD)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", Tokens.SPACE_XS)
	header.add_child(heading)
	heading.add_child(UiKit.make_eyebrow("合成"))
	heading.add_child(UiKit.make_title("合成配方"))
	heading.add_child(UiKit.make_subtitle("可制作状态会随着背包材料实时更新；工作台同时包含随身配方。"))
	_station_select = OptionButton.new()
	_station_select.add_item("随身合成")
	_station_select.add_item("工作台")
	_station_select.custom_minimum_size = Vector2(144, Tokens.CONTROL_HEIGHT_MD)
	_station_select.disabled = true
	_station_select.tooltip_text = "工位由当前打开的世界方块决定"
	header.add_child(_station_select)
	var close_button := UiKit.style_button(
		Button.new(), "GhostButton", Vector2(150, Tokens.CONTROL_HEIGHT_MD)
	)
	close_button.text = "关闭 [C / Esc]"
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)

	var status_card := UiKit.make_card("CardPanel")
	root.add_child(status_card)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	status_card.add_child(status_row)
	_summary = Label.new()
	_summary.theme_type_variation = "CaptionLabel"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_row.add_child(_summary)
	_recipe_count_badge = UiKit.make_badge("0 配方", "info")
	status_row.add_child(_recipe_count_badge)

	var recipe_card := UiKit.make_card("InsetPanel")
	recipe_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(recipe_card)
	var recipe_root := VBoxContainer.new()
	recipe_root.add_theme_constant_override("separation", Tokens.SPACE_SM)
	recipe_card.add_child(recipe_root)
	var section_title := Label.new()
	section_title.text = "可见配方"
	section_title.theme_type_variation = "SectionTitle"
	recipe_root.add_child(section_title)
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_scroll.custom_minimum_size = Vector2(760, 330)
	recipe_root.add_child(_recipe_scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_recipe_scroll.add_child(_recipe_list)


func _set_station(index: int) -> void:
	if crafting != null:
		crafting.set_station(STATIONS[clampi(index, 0, STATIONS.size() - 1)])
	refresh()


func _on_craft_succeeded(recipe_id: String, _output: Dictionary) -> void:
	item_crafted.emit(recipe_id)
	refresh()


func _recipe_text(recipe: Dictionary) -> String:
	var ingredients: Array[String] = []
	for item_id in recipe.get("ingredients", {}):
		var item_name: String = (
			str(inventory.registry.get_display_name(str(item_id)))
			if inventory != null
			else str(item_id)
		)
		ingredients.append("%s ×%d" % [item_name, int(recipe["ingredients"][item_id])])
	var output: Dictionary = recipe.get("output", {})
	var output_name: String = (
		str(inventory.registry.get_display_name(str(output.get("id", ""))))
		if inventory != null
		else str(output.get("id", ""))
	)
	return "%s   →   %s ×%d" % [
		"  +  ".join(ingredients), output_name, int(output.get("count", 1))
	]


func _station_name(station: String) -> String:
	return {"hand": "随身合成", "workbench": "工作台"}.get(station, station)


func _disconnect_services() -> void:
	if inventory != null:
		var callback := Callable(self, "refresh")
		if inventory.inventory_changed.is_connected(callback):
			inventory.inventory_changed.disconnect(callback)
	if crafting != null:
		var callback := Callable(self, "_on_craft_succeeded")
		if crafting.craft_succeeded.is_connected(callback):
			crafting.craft_succeeded.disconnect(callback)
