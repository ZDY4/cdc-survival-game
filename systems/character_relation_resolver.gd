extends RefCounted
## CharacterRelationResolver - Resolves runtime relationship for a character.

class_name CharacterRelationResolver

const FRIENDLY_THRESHOLD: int = 30
const HOSTILE_THRESHOLD: int = -30

func resolve_for_player(character_id: String, character_data: Dictionary) -> Dictionary:
	var camp_id: String = _extract_camp_id(character_data)
	var relations_config: Dictionary = _get_camp_relations_config()
	var player_camp: String = str(relations_config.get("player_camp", "player"))
	var base_score: int = _resolve_base_score(relations_config, player_camp, camp_id)
	var relationship_bonus: int = _get_relationship_bonus(character_id)
	var total_score: int = base_score + relationship_bonus

	var attitude: String = "neutral"
	if total_score >= FRIENDLY_THRESHOLD:
		attitude = "friendly"
	elif total_score <= HOSTILE_THRESHOLD:
		attitude = "hostile"

	var social: Dictionary = character_data.get("social", {})
	var capabilities: Dictionary = social.get("capabilities", {})
	var trade_data: Dictionary = social.get("trade", {})
	var can_interact: bool = bool(capabilities.get("can_interact", true))
	var can_trade_capability: bool = bool(capabilities.get("can_trade", false))
	var trade_enabled: bool = bool(trade_data.get("enabled", false))
	var allow_attack: bool = attitude == "hostile"
	var allow_interaction: bool = can_interact and attitude != "hostile"
	var allow_trade: bool = can_trade_capability and trade_enabled and attitude == "friendly"

	return {
		"character_id": character_id,
		"camp_id": camp_id,
		"base_score": base_score,
		"relationship_bonus": relationship_bonus,
		"total_score": total_score,
		"resolved_attitude": attitude,
		"allow_attack": allow_attack,
		"allow_interaction": allow_interaction,
		"allow_trade": allow_trade
	}

func _extract_camp_id(character_data: Dictionary) -> String:
	var identity: Dictionary = character_data.get("identity", {})
	var camp_id: String = str(identity.get("camp_id", "neutral")).strip_edges()
	if camp_id.is_empty():
		return "neutral"
	return camp_id

func _get_relationship_bonus(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if GameStateManager and GameStateManager.has_method("get_relationship"):
		return int(GameStateManager.get_relationship(character_id))
	return 0

func _get_camp_relations_config() -> Dictionary:
	if DataManager and DataManager.has_method("get_camp_relations"):
		var config: Variant = DataManager.get_camp_relations()
		if config is Dictionary and not config.is_empty():
			return config
	return {
		"player_camp": "player",
		"default_relation": 0,
		"relations": {
			"player": {
				"player": 100,
				"survivor": 35,
				"raider": -40,
				"infected": -70,
				"neutral": 0
			}
		}
	}

func _resolve_base_score(relations_config: Dictionary, from_camp: String, to_camp: String) -> int:
	var default_relation: int = int(relations_config.get("default_relation", 0))
	var relations: Dictionary = relations_config.get("relations", {})
	if not relations.has(from_camp):
		return default_relation
	var row: Variant = relations.get(from_camp, {})
	if not (row is Dictionary):
		return default_relation
	return int((row as Dictionary).get(to_camp, default_relation))
