extends RefCounted

const FORMAT_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "dialogue_rules", "quests", "skills", "skill_trees", "settlements", "overworld", "shops", "world_tiles", "ai", "json"]
const VALIDATE_CHANGED_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "dialogue_rules", "quests", "skills", "skill_trees", "settlements", "overworld", "shops", "world_tiles", "appearance", "ai", "json"]
const FORMAT_PATH_ROOTS := {
	"items": "data/items/",
	"recipes": "data/recipes/",
	"characters": "data/characters/",
	"maps": "data/maps/",
	"dialogues": "data/dialogues/",
	"dialogue_rules": "data/dialogue_rules/",
	"quests": "data/quests/",
	"skills": "data/skills/",
	"skill_trees": "data/skill_trees/",
	"settlements": "data/settlements/",
	"overworld": "data/overworld/",
	"shops": "data/shops/",
	"world_tiles": "data/world_tiles/",
	"ai": "data/ai/",
	"json": "data/json/",
}
const VALIDATE_PATH_ROOTS := {
	"items": "data/items/",
	"recipes": "data/recipes/",
	"characters": "data/characters/",
	"maps": "data/maps/",
	"dialogues": "data/dialogues/",
	"dialogue_rules": "data/dialogue_rules/",
	"quests": "data/quests/",
	"skills": "data/skills/",
	"skill_trees": "data/skill_trees/",
	"settlements": "data/settlements/",
	"overworld": "data/overworld/",
	"shops": "data/shops/",
	"world_tiles": "data/world_tiles/",
	"appearance": "data/appearance/",
	"ai": "data/ai/",
	"json": "data/json/",
}


static func format_domain_names() -> String:
	return "item, recipe, character, map, dialogue, dialogue_rule, quest, skill, skill_tree, settlement, overworld, shop, world_tile, ai, json"


static func validate_domain_names() -> String:
	return "item, recipe, character, map, dialogue, dialogue_rule, quest, skill, skill_tree, settlement, overworld, shop, world_tile, appearance, ai, json"


static func git_status_paths_for_format() -> Array[String]:
	var paths: Array[String] = []
	for domain in FORMAT_DOMAINS:
		paths.append(str(FORMAT_PATH_ROOTS[domain]).trim_suffix("/"))
	return paths


static func git_status_paths_for_validate() -> Array[String]:
	var paths: Array[String] = []
	for domain in VALIDATE_CHANGED_DOMAINS:
		paths.append(str(VALIDATE_PATH_ROOTS[domain]).trim_suffix("/"))
	return paths


static func domain_for_relative_path(relative_path: String) -> String:
	for domain in FORMAT_PATH_ROOTS.keys():
		var root := str(FORMAT_PATH_ROOTS[domain])
		if relative_path.begins_with(root) and relative_path.ends_with(".json"):
			return str(domain)
	return ""


static func validate_domain_for_relative_path(relative_path: String) -> String:
	for domain in VALIDATE_PATH_ROOTS.keys():
		var root := str(VALIDATE_PATH_ROOTS[domain])
		if relative_path.begins_with(root) and relative_path.ends_with(".json"):
			return str(domain)
	return ""


static func supports_format_domain(domain: String) -> bool:
	return FORMAT_DOMAINS.has(domain)
