extends RefCounted

# 这里只定义迁移期可编辑字段白名单，内容 schema 权威仍来自 data/ JSON 与校验器。
const SUPPORTED_DOMAINS := ["items", "recipes", "characters", "maps", "dialogues", "quests", "skills", "skill_trees", "overworld"]

const EDITABLE_FIELDS := {
	"items": [
		"name",
		"description",
		"icon_path",
		"value",
		"weight",
	],
	"recipes": [
		"name",
		"description",
		"category",
		"craft_time",
		"experience_reward",
		"is_default_unlocked",
	],
	"characters": [
		"identity.display_name",
		"identity.description",
		"faction.camp_id",
		"faction.disposition",
		"combat.behavior",
	],
	"maps": [
		"name",
	],
	"dialogues": [
		"_comment",
	],
	"quests": [
		"title",
		"description",
		"time_limit",
	],
	"skills": [
		"name",
		"icon",
		"description",
		"max_level",
	],
	"skill_trees": [
		"name",
		"description",
	],
	"overworld": [
		"travel_rules.food_item_id",
		"travel_rules.night_minutes_multiplier",
		"travel_rules.risk_multiplier",
	],
}

const FIELD_TYPES := {
	"items": {
		"name": "string",
		"description": "string",
		"icon_path": "string",
		"value": "int",
		"weight": "float",
	},
	"recipes": {
		"name": "string",
		"description": "string",
		"category": "string",
		"craft_time": "float",
		"experience_reward": "int",
		"is_default_unlocked": "bool",
	},
	"characters": {
		"identity.display_name": "string",
		"identity.description": "string",
		"faction.camp_id": "string",
		"faction.disposition": "string",
		"combat.behavior": "string",
	},
	"maps": {
		"name": "string",
	},
	"dialogues": {
		"_comment": "string",
	},
	"quests": {
		"title": "string",
		"description": "string",
		"time_limit": "int",
	},
	"skills": {
		"name": "string",
		"icon": "string",
		"description": "string",
		"max_level": "int",
	},
	"skill_trees": {
		"name": "string",
		"description": "string",
	},
	"overworld": {
		"travel_rules.food_item_id": "string",
		"travel_rules.night_minutes_multiplier": "float",
		"travel_rules.risk_multiplier": "float",
	},
}


func supports_domain(domain: String) -> bool:
	return SUPPORTED_DOMAINS.has(domain)


func editable_fields(domain: String) -> Array[String]:
	var fields: Array[String] = []
	for field in EDITABLE_FIELDS.get(domain, []):
		fields.append(str(field))
	return fields


func field_type(domain: String, field_path: String) -> String:
	return str(_dictionary_or_empty(FIELD_TYPES.get(domain, {})).get(field_path, "string"))


func can_edit_field(domain: String, field_path: String) -> bool:
	return editable_fields(domain).has(field_path)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
