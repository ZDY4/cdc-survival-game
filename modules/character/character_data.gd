extends RefCounted
## CharacterData - Unified character data model for NPCs and enemies.

class_name CharacterData
const AttributeSystemScript = preload("res://systems/attribute_system.gd")

const DEFAULT_PLACEHOLDER := {
	"head_color": "#f2d6b2",
	"body_color": "#5d90e0",
	"leg_color": "#3c5c90"
}

const DEFAULT_COMBAT_AI := {
	"aggro_range": 6.0,
	"attack_range": 1.3,
	"wander_radius": 3.0,
	"leash_distance": 8.0,
	"decision_interval": 0.8,
	"attack_cooldown": 1.5
}

const DEFAULT_SOCIAL_MOOD := {
	"friendliness": 50,
	"trust": 30,
	"fear": 0,
	"anger": 0
}

const DEFAULT_SKILLS := {
	"initial_tree_ids": [],
	"initial_skills_by_tree": {}
}

var id: String = ""
var name: String = ""
var description: String = ""
var level: int = 1
var attributes: Dictionary = AttributeSystemScript.create_default_container({}, ["base", "combat"], {"hp": 50})

var identity: Dictionary = {"camp_id": "neutral"}
var visual: Dictionary = {
	"portrait_path": "",
	"avatar_path": "",
	"model_path": "",
	"placeholder": DEFAULT_PLACEHOLDER.duplicate(true)
}
var combat: Dictionary = {
	"ai": DEFAULT_COMBAT_AI.duplicate(true),
	"behavior": "neutral",
	"loot": [],
	"xp": 10
}
var social: Dictionary = {
	"title": "",
	"dialog_id": "",
	"mood": DEFAULT_SOCIAL_MOOD.duplicate(true)
}
var skills: Dictionary = DEFAULT_SKILLS.duplicate(true)

func serialize() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"level": level,
		"attributes": attributes.duplicate(true),
		"identity": identity.duplicate(true),
		"visual": visual.duplicate(true),
		"combat": combat.duplicate(true),
		"social": social.duplicate(true),
		"skills": skills.duplicate(true)
	}

func deserialize(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	name = str(data.get("name", ""))
	description = str(data.get("description", ""))
	level = int(data.get("level", 1))
	attributes = AttributeSystemScript.normalize_attribute_container(
		data.get("attributes", AttributeSystemScript.create_default_container({}, ["base", "combat"], {"hp": 50}))
	).duplicate(true)

	var identity_data: Dictionary = data.get("identity", {})
	identity = {"camp_id": str(identity_data.get("camp_id", "neutral"))}

	visual = {
		"portrait_path": "",
		"avatar_path": "",
		"model_path": "",
		"placeholder": DEFAULT_PLACEHOLDER.duplicate(true)
	}
	var visual_data: Dictionary = data.get("visual", {})
	visual["portrait_path"] = str(visual_data.get("portrait_path", ""))
	visual["avatar_path"] = str(visual_data.get("avatar_path", ""))
	visual["model_path"] = str(visual_data.get("model_path", ""))
	var placeholder_data: Dictionary = visual_data.get("placeholder", {})
	var placeholder_copy: Dictionary = DEFAULT_PLACEHOLDER.duplicate(true)
	placeholder_copy.merge(placeholder_data, true)
	visual["placeholder"] = placeholder_copy

	combat = {
		"ai": DEFAULT_COMBAT_AI.duplicate(true),
		"behavior": "neutral",
		"loot": [],
		"xp": 10
	}
	var combat_data: Dictionary = data.get("combat", {})
	combat["behavior"] = str(combat_data.get("behavior", "neutral"))
	combat["xp"] = int(combat_data.get("xp", 10))
	combat["loot"] = combat_data.get("loot", []).duplicate(true)
	var ai_copy: Dictionary = DEFAULT_COMBAT_AI.duplicate(true)
	ai_copy.merge(combat_data.get("ai", {}), true)
	combat["ai"] = ai_copy

	social = {
		"title": "",
		"dialog_id": "",
		"mood": DEFAULT_SOCIAL_MOOD.duplicate(true)
	}
	var social_data: Dictionary = data.get("social", {})
	social["title"] = str(social_data.get("title", ""))
	social["dialog_id"] = str(social_data.get("dialog_id", ""))
	var mood_copy: Dictionary = DEFAULT_SOCIAL_MOOD.duplicate(true)
	mood_copy.merge(social_data.get("mood", {}), true)
	social["mood"] = mood_copy

	skills = DEFAULT_SKILLS.duplicate(true)
	var skills_data: Dictionary = data.get("skills", {})
	var initial_tree_ids: Array[String] = []
	var raw_tree_ids: Variant = skills_data.get("initial_tree_ids", [])
	if raw_tree_ids is Array:
		for tree_id_variant in raw_tree_ids:
			initial_tree_ids.append(str(tree_id_variant))
	skills["initial_tree_ids"] = initial_tree_ids

	var initial_skills_by_tree: Dictionary = {}
	var raw_skills_by_tree: Variant = skills_data.get("initial_skills_by_tree", {})
	if raw_skills_by_tree is Dictionary:
		var source: Dictionary = raw_skills_by_tree
		for tree_id_variant in source.keys():
			var tree_id: String = str(tree_id_variant)
			var skill_ids: Array[String] = []
			var tree_skills_variant: Variant = source.get(tree_id_variant, [])
			if tree_skills_variant is Array:
				for skill_id_variant in tree_skills_variant:
					skill_ids.append(str(skill_id_variant))
			initial_skills_by_tree[tree_id] = skill_ids
	skills["initial_skills_by_tree"] = initial_skills_by_tree

func get_display_name() -> String:
	var title: String = str(social.get("title", ""))
	if title.is_empty():
		return name
	return "%s·%s" % [title, name]
