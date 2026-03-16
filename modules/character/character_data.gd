extends RefCounted
## CharacterData - Unified character data model for NPCs and enemies.

class_name CharacterData

const DEFAULT_PLACEHOLDER := {
	"head_color": "#f2d6b2",
	"body_color": "#5d90e0",
	"leg_color": "#3c5c90"
}

const DEFAULT_COMBAT_STATS := {
	"hp": 50,
	"max_hp": 50,
	"damage": 5,
	"defense": 2,
	"speed": 5,
	"accuracy": 70,
	"crit_chance": 0.05,
	"crit_damage": 1.5,
	"evasion": 0.05
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

const DEFAULT_SOCIAL_TRADE := {
	"enabled": false,
	"buy_price_modifier": 1.0,
	"sell_price_modifier": 1.0,
	"money": 0,
	"inventory": []
}

const DEFAULT_SOCIAL_RECRUITMENT := {
	"enabled": false,
	"min_charisma": 0,
	"min_friendliness": 70,
	"min_trust": 50,
	"required_quests": [],
	"required_items": [],
	"cost_items": [],
	"cost_money": 0
}

const DEFAULT_SOCIAL_CAPABILITIES := {
	"can_interact": true,
	"can_trade": false,
	"can_give_quest": false,
	"can_recruit": false
}

var id: String = ""
var name: String = ""
var description: String = ""
var level: int = 1

var identity: Dictionary = {"camp_id": "neutral"}
var visual: Dictionary = {
	"portrait_path": "",
	"avatar_path": "",
	"model_path": "",
	"placeholder": DEFAULT_PLACEHOLDER.duplicate(true)
}
var combat: Dictionary = {
	"stats": DEFAULT_COMBAT_STATS.duplicate(true),
	"ai": DEFAULT_COMBAT_AI.duplicate(true),
	"behavior": "neutral",
	"loot": [],
	"xp": 10
}
var social: Dictionary = {
	"title": "",
	"dialog_id": "",
	"mood": DEFAULT_SOCIAL_MOOD.duplicate(true),
	"trade": DEFAULT_SOCIAL_TRADE.duplicate(true),
	"recruitment": DEFAULT_SOCIAL_RECRUITMENT.duplicate(true),
	"capabilities": DEFAULT_SOCIAL_CAPABILITIES.duplicate(true)
}

func serialize() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"level": level,
		"identity": identity.duplicate(true),
		"visual": visual.duplicate(true),
		"combat": combat.duplicate(true),
		"social": social.duplicate(true)
	}

func deserialize(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	name = str(data.get("name", ""))
	description = str(data.get("description", ""))
	level = int(data.get("level", 1))

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
		"stats": DEFAULT_COMBAT_STATS.duplicate(true),
		"ai": DEFAULT_COMBAT_AI.duplicate(true),
		"behavior": "neutral",
		"loot": [],
		"xp": 10
	}
	var combat_data: Dictionary = data.get("combat", {})
	combat["behavior"] = str(combat_data.get("behavior", "neutral"))
	combat["xp"] = int(combat_data.get("xp", 10))
	combat["loot"] = combat_data.get("loot", []).duplicate(true)
	var stats_copy: Dictionary = DEFAULT_COMBAT_STATS.duplicate(true)
	stats_copy.merge(combat_data.get("stats", {}), true)
	combat["stats"] = stats_copy
	var ai_copy: Dictionary = DEFAULT_COMBAT_AI.duplicate(true)
	ai_copy.merge(combat_data.get("ai", {}), true)
	combat["ai"] = ai_copy

	social = {
		"title": "",
		"dialog_id": "",
		"mood": DEFAULT_SOCIAL_MOOD.duplicate(true),
		"trade": DEFAULT_SOCIAL_TRADE.duplicate(true),
		"recruitment": DEFAULT_SOCIAL_RECRUITMENT.duplicate(true),
		"capabilities": DEFAULT_SOCIAL_CAPABILITIES.duplicate(true)
	}
	var social_data: Dictionary = data.get("social", {})
	social["title"] = str(social_data.get("title", ""))
	social["dialog_id"] = str(social_data.get("dialog_id", ""))
	var mood_copy: Dictionary = DEFAULT_SOCIAL_MOOD.duplicate(true)
	mood_copy.merge(social_data.get("mood", {}), true)
	social["mood"] = mood_copy
	var trade_copy: Dictionary = DEFAULT_SOCIAL_TRADE.duplicate(true)
	trade_copy.merge(social_data.get("trade", {}), true)
	social["trade"] = trade_copy
	var recruitment_copy: Dictionary = DEFAULT_SOCIAL_RECRUITMENT.duplicate(true)
	recruitment_copy.merge(social_data.get("recruitment", {}), true)
	social["recruitment"] = recruitment_copy
	var capabilities_copy: Dictionary = DEFAULT_SOCIAL_CAPABILITIES.duplicate(true)
	capabilities_copy.merge(social_data.get("capabilities", {}), true)
	social["capabilities"] = capabilities_copy

func get_display_name() -> String:
	var title: String = str(social.get("title", ""))
	if title.is_empty():
		return name
	return "%s·%s" % [title, name]
