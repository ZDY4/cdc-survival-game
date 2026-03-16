extends RefCounted
## Shared item-id helpers for editor and runtime item lookups.

class_name ItemIdResolver

# 1. Constants
const GENERATED_ITEM_TEXTURE_DIR: String = "res://assets/generated/items"
const ITEM_DATA_DIR: String = "res://data/items"
const ITEM_ID_ALIASES: Dictionary = {
	# Weapons
	"fist": "1001",
	"knife": "1002",
	"baseball_bat": "1003",
	"pistol": "1004",
	"pipe_wrench": "1013",
	"machete": "1014",
	"katana": "1015",
	"chainsaw": "1016",
	"slingshot": "1017",
	"shotgun": "1018",
	"rifle": "1019",
	"assault_rifle": "1020",
	# Ammo / materials / consumables
	"ammo_pistol": "1009",
	"ammo_shotgun": "1021",
	"ammo_rifle": "1022",
	"stone": "1023",
	"medkit": "1005",
	"first_aid_kit": "1005",
	"bandage": "1006",
	"canned_food": "1007",
	"food_canned": "1007",
	"water_bottle": "1008",
	"scrap_metal": "1010",
	"cloth": "1011",
	"component_electronic": "1012",
	"electronics": "1012",
	"ammo": "1009",
	"weapon": "1002",
	"armor": "2004",
	"food": "1007",
	"water": "1008",
	# Equipment
	"helmet_makeshift": "2001",
	"helmet_military": "2002",
	"helmet_advanced": "2003",
	"armor_cloth": "2004",
	"armor_leather": "2005",
	"armor_metal": "2006",
	"armor_tactical": "2007",
	"armor_heavy": "2008",
	"armor_hazmat": "2009",
	"gloves_leather": "2010",
	"gloves_tactical": "2011",
	"gloves_power": "2012",
	"pants_jeans": "2013",
	"pants_tactical": "2014",
	"shoes_sneakers": "2015",
	"boots_combat": "2016",
	"boots_advanced": "2017",
	"backpack_small": "2018",
	"backpack_medium": "2019",
	"backpack_large": "2020",
	"ring_luck": "2021",
	"amulet_health": "2022",
	"watch_survival": "2023",
	"backpack": "2018",
	"hazmat_suit": "2009",
	# Other items
	"antiseptic": "1030",
	"antibiotics": "1031",
	"medicine": "1032",
	"painkiller": "1033",
	"snack": "1034",
	"juice": "1035",
	"military_rations": "1036",
	"raw_meat": "1037",
	"herbal_medicine": "1038",
	"stimpack": "1039",
	"rare_medicine": "1040",
	"splint": "1041",
	"spear": "1050",
	"wood": "1100",
	"metal": "1101",
	"nails": "1102",
	"rope": "1103",
	"plastic": "1104",
	"gunpowder": "1105",
	"steel_ingot": "1106",
	"advanced_parts": "1107",
	"rare_materials": "1108",
	"rare_component": "1109",
	"mutant_organ": "1110",
	"rotten_flesh": "1111",
	"metal_sheet": "1112",
	"gear": "1113",
	"wire": "1114",
	"machine_part": "1115",
	"weapon_part": "1116",
	"medical_supplies": "1117",
	"tools": "1118",
	"advanced_tools": "1119",
	"basic_tools": "1120",
	"medical_equipment": "1121",
	"surgical_kit": "1122",
	"syringe": "1123",
	"medical_scissors": "1124",
	"crowbar": "1125",
	"flashlight": "1126",
	"battery": "1127",
	"radio": "1128",
	"flare": "1129",
	"map": "1130",
	"map_fragment": "1131",
	"school_map": "1132",
	"survival_guide": "1133",
	"documents": "1134",
	"personal_items": "1135",
	"stationery": "1136",
	"keys": "1137",
	"key": "1138",
	"bottle": "1139",
	"glass_bottle": "1140",
	"hidden_stash": "1141",
	"hidden_cache": "1142",
	"personal_cache": "1143",
	"tool_kit": "1144",
	"generator": "1145",
	"water_collector": "1146",
	"fuel": "1147",
	"keycard_subway": "1148",
	"weapon_pipe": "1013",
	"lockpick": "1150",
	"screwdriver": "1151",
	"repair_weapon": "1152",
	"repair_armor": "1153",
	"repair_tool": "1154",
	"repair_kit_advanced": "1155",
	"barricade_wood": "1156",
	"grow_box": "1157",
	"dog_fang": "1158",
	"leather": "1159",
	"rare_loot": "1160",
	"valuable_item": "1161",
	"valuable_loot": "1162",
	"test_item": "1163",
	"test": "1164",
	"extra_item": "1165",
	"hammer": "1166",
	"cloth_armor": "2004",
	"leather_jacket": "2005",
	"kevlar_vest": "2007",
	"helmet": "2001"
}

# 6. Public methods
static func resolve_item_id(item_id: String, known_items: Dictionary = {}) -> String:
	var key: String = str(item_id).strip_edges()
	if key.is_empty():
		return ""
	if not known_items.is_empty() and known_items.has(key):
		return key
	if ITEM_ID_ALIASES.has(key):
		return str(ITEM_ID_ALIASES[key])
	return key

static func load_item_data_from_json(item_id: String) -> Dictionary:
	var resolved_id: String = resolve_item_id(item_id)
	if resolved_id.is_empty():
		return {}

	var item_path: String = "%s/%s.json" % [ITEM_DATA_DIR, resolved_id]
	if not FileAccess.file_exists(item_path):
		return {}

	var file := FileAccess.open(item_path, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

static func build_generated_texture_path(icon_path: String) -> String:
	var trimmed_icon_path: String = str(icon_path).strip_edges()
	if trimmed_icon_path.is_empty():
		return ""
	var icon_name: String = trimmed_icon_path.get_file().get_basename()
	if icon_name.is_empty():
		return ""
	return "%s/%s.png" % [GENERATED_ITEM_TEXTURE_DIR, icon_name]
