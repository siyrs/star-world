class_name BlockRegistry
extends RefCounted

const AIR := "air"
const BEDROCK := "bedrock"

const BLOCK_IDS := [
	"air", "grass", "dirt", "stone", "cobblestone", "sand", "snow",
	"wood", "leaves", "water", "lava", "planks", "stone_bricks", "glass",
	"stone_slab", "oak_stairs", "coal_ore", "iron_ore", "gold_ore",
	"diamond_ore", "crafting_table", "furnace", "chest", "oak_door",
	"oak_fence", "ladder", "torch", "wool", "ice", "bedrock",
	"farmland", "wheat_stage_0", "wheat_stage_1", "wheat_stage_2", "wheat_stage_3",
	"farmland_wet",
	"carrot_stage_0", "carrot_stage_1", "carrot_stage_2", "carrot_stage_3",
	"potato_stage_0", "potato_stage_1", "potato_stage_2", "potato_stage_3",
	"oak_bed", "repair_station",
	# Directional variants are appended so existing numeric block IDs stay stable.
	"oak_stairs_east", "oak_stairs_north", "oak_stairs_west",
	# Glass panes were previously an unplaceable item; append real world variants.
	"glass_pane", "glass_pane_ns",
	# New machines append their IDs so old world numeric block IDs remain stable.
	"stonecutter"
]

const DEFINITIONS := {
	"air": {"name":"空气", "color":"#00000000", "solid":false, "transparent":true, "collectible":false, "item_id":"", "hardness":0.0},
	"grass": {"name":"草方块", "color":"#61A84B", "solid":true, "transparent":false, "collectible":true, "item_id":"grass_block", "hardness":0.7},
	"dirt": {"name":"泥土", "color":"#79533A", "solid":true, "transparent":false, "collectible":true, "item_id":"dirt", "hardness":0.6},
	"stone": {"name":"石头", "color":"#777C82", "solid":true, "transparent":false, "collectible":true, "item_id":"stone", "hardness":1.5},
	"cobblestone": {"name":"圆石", "color":"#686D72", "solid":true, "transparent":false, "collectible":true, "item_id":"cobblestone", "hardness":1.8},
	"sand": {"name":"沙子", "color":"#DCCB86", "solid":true, "transparent":false, "collectible":true, "item_id":"sand", "hardness":0.5},
	"snow": {"name":"雪块", "color":"#EAF4F7", "solid":true, "transparent":false, "collectible":true, "item_id":"snow_block", "hardness":0.4},
	"wood": {"name":"原木", "color":"#74502D", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_log", "hardness":2.0},
	"leaves": {"name":"树叶", "color":"#397A38", "solid":true, "transparent":true, "collectible":true, "item_id":"leaves", "hardness":0.3},
	"water": {"name":"水", "color":"#3487D8", "solid":false, "transparent":true, "collectible":false, "item_id":"water_bucket", "hardness":100.0},
	"lava": {"name":"岩浆", "color":"#F06423", "solid":false, "transparent":true, "collectible":false, "item_id":"lava_bucket", "hardness":100.0, "emissive":true},
	"planks": {"name":"木板", "color":"#B5834E", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_planks", "hardness":1.7},
	"stone_bricks": {"name":"石砖", "color":"#85888A", "solid":true, "transparent":false, "collectible":true, "item_id":"stone_bricks", "hardness":2.0},
	"glass": {"name":"玻璃", "color":"#BFE4EA", "solid":true, "transparent":true, "collectible":true, "item_id":"glass", "hardness":0.3},
	"stone_slab": {"name":"石台阶", "color":"#85888A", "solid":true, "transparent":false, "collectible":true, "item_id":"stone_slab", "hardness":2.0, "shape":"slab"},
	"oak_stairs": {"name":"木楼梯", "color":"#B5834E", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_stairs", "hardness":1.7, "shape":"stairs", "orientation_family":"oak_stairs", "rotation_quarters":0},
	"coal_ore": {"name":"煤矿石", "color":"#3E4144", "solid":true, "transparent":false, "collectible":true, "item_id":"coal", "place_item_id":"coal_ore", "hardness":2.4},
	"iron_ore": {"name":"铁矿石", "color":"#BA967C", "solid":true, "transparent":false, "collectible":true, "item_id":"raw_iron", "place_item_id":"iron_ore", "hardness":2.7},
	"gold_ore": {"name":"金矿石", "color":"#E4C343", "solid":true, "transparent":false, "collectible":true, "item_id":"raw_gold", "place_item_id":"gold_ore", "hardness":3.0},
	"diamond_ore": {"name":"钻石矿石", "color":"#4DD8D0", "solid":true, "transparent":false, "collectible":true, "item_id":"diamond", "place_item_id":"diamond_ore", "hardness":3.5},
	"crafting_table": {"name":"工作台", "color":"#9A6333", "solid":true, "transparent":false, "collectible":true, "item_id":"crafting_table", "hardness":2.0},
	"furnace": {"name":"熔炉", "color":"#55595D", "solid":true, "transparent":false, "collectible":true, "item_id":"furnace", "hardness":3.0},
	"chest": {"name":"箱子", "color":"#A66B2C", "solid":true, "transparent":false, "collectible":true, "item_id":"chest", "hardness":2.0},
	"oak_door": {"name":"木门", "color":"#9B6331", "solid":true, "transparent":true, "collectible":true, "item_id":"oak_door", "hardness":1.5},
	"oak_fence": {"name":"木栅栏", "color":"#A87540", "solid":true, "transparent":true, "collectible":true, "item_id":"oak_fence", "hardness":1.5},
	"ladder": {"name":"梯子", "color":"#B98245", "solid":false, "transparent":true, "collectible":true, "item_id":"ladder", "hardness":0.5},
	"torch": {"name":"火把", "color":"#F3B63F", "solid":false, "transparent":true, "collectible":true, "item_id":"torch", "hardness":0.1, "emissive":true},
	"wool": {"name":"羊毛", "color":"#F0EFE8", "solid":true, "transparent":false, "collectible":true, "item_id":"wool", "hardness":0.5},
	"ice": {"name":"冰", "color":"#A8DDEB", "solid":true, "transparent":true, "collectible":true, "item_id":"snow_block", "hardness":0.5},
	"bedrock": {"name":"基岩", "color":"#25272A", "solid":true, "transparent":false, "collectible":false, "item_id":"", "hardness":-1.0},
	"farmland": {"name":"干燥耕地", "color":"#5C3924", "solid":true, "transparent":false, "collectible":true, "item_id":"dirt", "hardness":0.65},
	"wheat_stage_0": {"name":"小麦幼苗", "color":"#5F9E49", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.28},
	"wheat_stage_1": {"name":"生长中的小麦", "color":"#7AAA48", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.48},
	"wheat_stage_2": {"name":"抽穗的小麦", "color":"#A9B84A", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.72},
	"wheat_stage_3": {"name":"成熟小麦", "color":"#D8B94F", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.96},
	"farmland_wet": {"name":"湿润耕地", "color":"#3E291C", "solid":true, "transparent":false, "collectible":true, "item_id":"dirt", "hardness":0.65},
	"carrot_stage_0": {"name":"胡萝卜幼苗", "color":"#4F9946", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.24},
	"carrot_stage_1": {"name":"生长中的胡萝卜", "color":"#62A94C", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.42},
	"carrot_stage_2": {"name":"茂盛的胡萝卜", "color":"#78B653", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.62},
	"carrot_stage_3": {"name":"成熟胡萝卜", "color":"#E98332", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.80},
	"potato_stage_0": {"name":"马铃薯幼苗", "color":"#4E8845", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.24},
	"potato_stage_1": {"name":"生长中的马铃薯", "color":"#63964D", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.44},
	"potato_stage_2": {"name":"开花的马铃薯", "color":"#86A85A", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.66},
	"potato_stage_3": {"name":"成熟马铃薯", "color":"#B89152", "solid":false, "transparent":true, "collectible":true, "item_id":"", "hardness":0.08, "shape":"crop", "crop_height":0.84},
	"oak_bed": {"name":"橡木床", "color":"#B94E4A", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_bed", "hardness":0.9, "shape":"bed"},
	"repair_station": {"name":"修理台", "color":"#8B7667", "solid":true, "transparent":false, "collectible":true, "item_id":"repair_station", "hardness":2.4},
	"oak_stairs_east": {"name":"木楼梯", "color":"#B5834E", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_stairs", "hardness":1.7, "shape":"stairs", "orientation_family":"oak_stairs", "rotation_quarters":1, "visual_parent":"oak_stairs"},
	"oak_stairs_north": {"name":"木楼梯", "color":"#B5834E", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_stairs", "hardness":1.7, "shape":"stairs", "orientation_family":"oak_stairs", "rotation_quarters":2, "visual_parent":"oak_stairs"},
	"oak_stairs_west": {"name":"木楼梯", "color":"#B5834E", "solid":true, "transparent":false, "collectible":true, "item_id":"oak_stairs", "hardness":1.7, "shape":"stairs", "orientation_family":"oak_stairs", "rotation_quarters":3, "visual_parent":"oak_stairs"},
	"glass_pane": {"name":"玻璃板", "color":"#C8EDF1", "solid":true, "transparent":true, "collectible":true, "item_id":"glass_pane", "hardness":0.3, "shape":"pane", "orientation_family":"glass_pane", "rotation_quarters":0, "visual_parent":"glass"},
	"glass_pane_ns": {"name":"玻璃板", "color":"#C8EDF1", "solid":true, "transparent":true, "collectible":true, "item_id":"glass_pane", "hardness":0.3, "shape":"pane", "orientation_family":"glass_pane", "rotation_quarters":1, "visual_parent":"glass"},
	"stonecutter": {"name":"石材切割机", "color":"#6F777C", "solid":true, "transparent":false, "collectible":true, "item_id":"stonecutter", "hardness":3.0, "visual_parent":"repair_station"}
}


static func has_block(block_id: String) -> bool:
	return DEFINITIONS.has(block_id)


static func get_definition(block_id: String) -> Dictionary:
	return DEFINITIONS.get(block_id, DEFINITIONS[AIR])


static func get_numeric_id(block_id: String) -> int:
	var index := BLOCK_IDS.find(block_id)
	return index if index >= 0 else 0


static func get_block_id(numeric_id: int) -> String:
	return BLOCK_IDS[numeric_id] if numeric_id >= 0 and numeric_id < BLOCK_IDS.size() else AIR


static func get_color(block_id: String) -> Color:
	return Color(str(get_definition(block_id).get("color", "#FF00FF")))


static func is_solid(block_id: String) -> bool:
	return bool(get_definition(block_id).get("solid", false))


static func is_transparent(block_id: String) -> bool:
	return bool(get_definition(block_id).get("transparent", false))


static func is_collectible(block_id: String) -> bool:
	return bool(get_definition(block_id).get("collectible", false))


static func get_item_id(block_id: String) -> String:
	return str(get_definition(block_id).get("item_id", ""))


static func get_place_item_id(block_id: String) -> String:
	var definition := get_definition(block_id)
	return str(definition.get("place_item_id", definition.get("item_id", "")))


static func get_block_for_item(item_id: String) -> String:
	for block_id in BLOCK_IDS:
		if get_place_item_id(block_id) == item_id:
			return block_id
	return AIR
