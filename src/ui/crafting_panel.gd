class_name CraftingPanel
extends PanelContainer

signal panel_closed
signal item_crafted(recipe_id: String)

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const STATIONS := ["hand", "workbench"]

var crafting
var inventory
var _station_select: OptionButton
var _recipe_list: VBoxContainer
var _summary: Label


func _ready() -> void:
	theme = ThemeFactory.create_theme()
	custom_minimum_size = Vector2(760, 590)
	_build_ui()


func setup(p_crafting, p_inventory) -> void:
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
		return
	var recipes: Array = crafting.get_recipes()
	var visible_count := 0
	for recipe in recipes:
		var recipe_station := str(recipe.get("station", "hand"))
		if (
			recipe_station != crafting.active_station
			and not (recipe_station == "hand" and crafting.active_station == "workbench")
		):
			continue
		visible_count += 1
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _recipe_text(recipe)
		button.tooltip_text = button.text
		var recipe_id := str(recipe.get("id", ""))
		button.disabled = not crafting.can_craft(recipe_id)
		button.pressed.connect(func() -> void: crafting.craft(recipe_id))
		_recipe_list.add_child(button)
	_summary.text = (
		"当前工位: %s   可见配方: %d / 全部 %d"
		% [_station_name(crafting.active_station), visible_count, crafting.recipe_count()]
	)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "合成"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_station_select = OptionButton.new()
	_station_select.add_item("随身合成")
	_station_select.add_item("工作台")
	_station_select.disabled = true
	_station_select.tooltip_text = "工位由当前打开的世界方块决定"
	header.add_child(_station_select)
	var close_button := Button.new()
	close_button.text = "关闭 [C / Esc]"
	close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(close_button)
	_summary = Label.new()
	root.add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_recipe_list)


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
		ingredients.append("%s×%d" % [item_name, int(recipe["ingredients"][item_id])])
	var output: Dictionary = recipe.get("output", {})
	var output_name: String = (
		str(inventory.registry.get_display_name(str(output.get("id", ""))))
		if inventory != null
		else str(output.get("id", ""))
	)
	return "%s  →  %s×%d" % [" + ".join(ingredients), output_name, int(output.get("count", 1))]


func _station_name(station: String) -> String:
	return {"hand": "随身", "workbench": "工作台"}.get(station, station)
