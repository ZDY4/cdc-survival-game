extends RefCounted

const FORMAT_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "settlements", "overworld", "shops"]
const VALIDATE_CHANGED_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "settlements", "overworld", "shops", "appearance"]
const FORMAT_PATH_ROOTS := {
	"items": "data/items/",
	"recipes": "data/recipes/",
	"characters": "data/characters/",
	"maps": "data/maps/",
	"dialogues": "data/dialogues/",
	"quests": "data/quests/",
	"skills": "data/skills/",
	"skill_trees": "data/skill_trees/",
	"settlements": "data/settlements/",
	"overworld": "data/overworld/",
	"shops": "data/shops/",
}


static func format_domain_names() -> String:
	return "item, recipe, character, map, dialogue, quest, skill, skill_tree, settlement, overworld, shop"


static func validate_domain_names() -> String:
	return "item, recipe, character, map, dialogue, quest, skill, skill_tree, settlement, overworld, shop, appearance"


static func git_status_paths_for_format() -> Array[String]:
	var paths: Array[String] = []
	for domain in FORMAT_DOMAINS:
		paths.append(str(FORMAT_PATH_ROOTS[domain]).trim_suffix("/"))
	return paths


static func domain_for_relative_path(relative_path: String) -> String:
	for domain in FORMAT_PATH_ROOTS.keys():
		var root := str(FORMAT_PATH_ROOTS[domain])
		if relative_path.begins_with(root) and relative_path.ends_with(".json"):
			return str(domain)
	return ""


static func supports_format_domain(domain: String) -> bool:
	return FORMAT_DOMAINS.has(domain)
