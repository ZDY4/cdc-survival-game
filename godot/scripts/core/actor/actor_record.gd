extends RefCounted

var actor_id: int
var definition_id: String
var display_name: String
var kind: String
var side: String
var group_id: String
var map_id: String = ""
var appearance_profile_id: String = ""
var model_asset: String = ""
var registration_index: int
var ap: float = 0.0
var turn_open: bool = false
var in_combat: bool = false
var grid_position: RefCounted
var inventory: Dictionary = {}
var inventory_order: Array[String] = []
var equipment: Dictionary = {}
var weapon_ammo: Dictionary = {}
var money: int = 0
var active_dialogue_id: String = ""
var active_dialogue_node_id: String = ""
var active_container_id: String = ""
var max_hp: float = 1.0
var hp: float = 1.0
var resources: Dictionary = {}
var attack_power: float = 1.0
var defense: float = 0.0
var combat_attributes: Dictionary = {}
var xp_reward: int = 0
var progression: Dictionary = {}
var ai: Dictionary = {}
var life: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"actor_id": actor_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"kind": kind,
		"side": side,
		"group_id": group_id,
		"map_id": map_id,
		"appearance_profile_id": appearance_profile_id,
		"model_asset": model_asset,
		"registration_index": registration_index,
		"ap": ap,
		"turn_open": turn_open,
		"in_combat": in_combat,
		"grid_position": grid_position.to_dictionary(),
		"inventory": inventory,
		"inventory_order": inventory_order.duplicate(),
		"equipment": equipment,
		"weapon_ammo": weapon_ammo,
		"money": money,
		"active_dialogue_id": active_dialogue_id,
		"active_dialogue_node_id": active_dialogue_node_id,
		"active_container_id": active_container_id,
		"combat": {
			"max_hp": max_hp,
			"hp": hp,
			"resources": resources.duplicate(true),
			"attack_power": attack_power,
			"defense": defense,
			"attributes": combat_attributes.duplicate(true),
			"xp_reward": xp_reward,
		},
		"progression": progression.duplicate(true),
		"ai": ai.duplicate(true),
		"life": life.duplicate(true),
	}
