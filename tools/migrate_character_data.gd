extends SceneTree
## Migrates legacy npc/enemy aggregate data into per-file character data.

const NPC_SOURCE_PATH: String = "res://data/json/npcs.json"
const ENEMY_SOURCE_PATH: String = "res://data/json/enemies.json"
const TARGET_DIR: String = "res://data/characters"
const CAMP_RELATIONS_PATH: String = "res://data/json/camp_relations.json"

func _init() -> void:
	var exit_code: int = run()
	quit(exit_code)

func run() -> int:
	var npcs: Dictionary = _load_json_dictionary(NPC_SOURCE_PATH)
	var enemies: Dictionary = _load_json_dictionary(ENEMY_SOURCE_PATH)
	var duplicate_ids: Array[String] = _find_duplicates(npcs, enemies)
	if not duplicate_ids.is_empty():
		push_error("[CharacterMigration] Duplicate IDs between npcs/enemies: %s" % ", ".join(duplicate_ids))
		return 1

	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TARGET_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TARGET_DIR))

	var total_written: int = 0
	for npc_id in npcs.keys():
		var npc_record: Variant = npcs[npc_id]
		if not (npc_record is Dictionary):
			continue
		var converted_npc: Dictionary = _convert_npc(str(npc_id), npc_record as Dictionary)
		_write_character_file(converted_npc)
		total_written += 1

	for enemy_id in enemies.keys():
		var enemy_record: Variant = enemies[enemy_id]
		if not (enemy_record is Dictionary):
			continue
		var converted_enemy: Dictionary = _convert_enemy(str(enemy_id), enemy_record as Dictionary)
		_write_character_file(converted_enemy)
		total_written += 1

	_write_default_camp_relations()
	print("[CharacterMigration] Wrote %d character files." % total_written)
	return 0

func _find_duplicates(npcs: Dictionary, enemies: Dictionary) -> Array[String]:
	var duplicates: Array[String] = []
	for key in npcs.keys():
		var id_text: String = str(key)
		if enemies.has(id_text):
			duplicates.append(id_text)
	duplicates.sort()
	return duplicates

func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json_text: String = FileAccess.get_file_as_string(path)
	if json_text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Dictionary:
		return parsed
	return {}

func _write_character_file(character_data: Dictionary) -> void:
	var character_id: String = str(character_data.get("id", "")).strip_edges()
	if character_id.is_empty():
		return
	var target_path: String = "%s/%s.json" % [TARGET_DIR, character_id]
	var file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		push_error("[CharacterMigration] Failed to open file for writing: %s" % target_path)
		return
	file.store_string(JSON.stringify(character_data, "\t", false))
	file.close()

func _write_default_camp_relations() -> void:
	var relations := {
		"player_camp": "player",
		"default_relation": 0,
		"relations": {
			"player": {
				"player": 100,
				"survivor": 35,
				"raider": -40,
				"infected": -70,
				"neutral": 0
			},
			"survivor": {
				"player": 30,
				"survivor": 40,
				"raider": -25,
				"infected": -60,
				"neutral": 0
			},
			"raider": {
				"player": -40,
				"survivor": -25,
				"raider": 20,
				"infected": -20,
				"neutral": -5
			},
			"infected": {
				"player": -70,
				"survivor": -60,
				"raider": -20,
				"infected": 15,
				"neutral": -20
			}
		}
	}
	var file: FileAccess = FileAccess.open(CAMP_RELATIONS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[CharacterMigration] Failed to write camp relations file")
		return
	file.store_string(JSON.stringify(relations, "\t", false))
	file.close()

func _convert_npc(npc_id: String, npc: Dictionary) -> Dictionary:
	var mood: Dictionary = npc.get("mood", {})
	var trade_data: Dictionary = npc.get("trade_data", {})
	var recruitment_data: Dictionary = npc.get("recruitment", {})
	var can_trade: bool = bool(npc.get("can_trade", false))
	var can_give_quest: bool = bool(npc.get("can_give_quest", false))
	var can_recruit: bool = bool(npc.get("can_recruit", false))
	var camp_id: String = "survivor"
	var npc_type: int = int(npc.get("npc_type", 0))
	if npc_type == 2:
		camp_id = "raider"
	if npc_id.begins_with("bandit"):
		camp_id = "raider"

	var raw_combat_data: Dictionary = npc.get("combat_data", {})
	var raw_stats: Dictionary = npc.get("combat_stats", {})
	if raw_stats.is_empty() and not raw_combat_data.is_empty():
		raw_stats = raw_combat_data

	var converted: Dictionary = {
		"id": str(npc.get("id", npc_id)),
		"name": str(npc.get("name", npc_id)),
		"description": str(npc.get("description", "")),
		"level": int(npc.get("level", 1)),
		"identity": {
			"camp_id": camp_id
		},
		"visual": {
			"portrait_path": str(npc.get("portrait_path", "")),
			"avatar_path": str(npc.get("avatar_path", "")),
			"model_path": str(npc.get("model_path", "")),
			"placeholder": {
				"head_color": "#eecba0",
				"body_color": "#6a9add",
				"leg_color": "#3c5c90"
			}
		},
		"combat": {
			"stats": {
				"hp": int(raw_stats.get("hp", 60)),
				"max_hp": int(raw_stats.get("max_hp", int(raw_stats.get("hp", 60)))),
				"damage": int(raw_stats.get("damage", 4)),
				"defense": int(raw_stats.get("defense", 2)),
				"speed": int(raw_stats.get("speed", 4)),
				"accuracy": int(raw_stats.get("accuracy", 70)),
				"crit_chance": 0.05,
				"crit_damage": 1.5,
				"evasion": 0.05
			},
			"ai": {
				"aggro_range": 0.0,
				"attack_range": 1.2,
				"wander_radius": 3.0,
				"leash_distance": 5.0,
				"decision_interval": 1.2,
				"attack_cooldown": 999.0
			},
			"behavior": "neutral",
			"loot": [],
			"xp": int(maxi(10, int(npc.get("level", 1)) * 5))
		},
		"social": {
			"title": str(npc.get("title", "")),
			"dialog_tree_id": str(npc.get("dialog_tree_id", "")),
			"mood": {
				"friendliness": int(mood.get("friendliness", 50)),
				"trust": int(mood.get("trust", 30)),
				"fear": int(mood.get("fear", 0)),
				"anger": int(mood.get("anger", 0))
			},
			"trade": {
				"enabled": can_trade,
				"buy_price_modifier": float(trade_data.get("buy_price_modifier", 1.0)),
				"sell_price_modifier": float(trade_data.get("sell_price_modifier", 1.0)),
				"money": int(trade_data.get("money", 0)),
				"inventory": _normalize_trade_inventory(trade_data.get("inventory", []))
			},
			"recruitment": {
				"enabled": can_recruit,
				"min_charisma": int(recruitment_data.get("min_charisma", 0)),
				"min_friendliness": int(recruitment_data.get("min_friendliness", 70)),
				"min_trust": int(recruitment_data.get("min_trust", 50)),
				"required_quests": recruitment_data.get("required_quests", []).duplicate(),
				"required_items": recruitment_data.get("required_items", []).duplicate(true),
				"cost_items": recruitment_data.get("cost_items", []).duplicate(true),
				"cost_money": int(recruitment_data.get("cost_money", 0))
			},
			"capabilities": {
				"can_interact": true,
				"can_trade": can_trade,
				"can_give_quest": can_give_quest,
				"can_recruit": can_recruit
			}
		}
	}
	return converted

func _convert_enemy(enemy_id: String, enemy: Dictionary) -> Dictionary:
	var enemy_camp: String = "infected"
	if enemy_id.begins_with("bandit"):
		enemy_camp = "raider"

	var raw_stats: Dictionary = enemy.get("stats", {})
	var raw_ai: Dictionary = enemy.get("ai", {})
	var loot_list: Array = []
	for entry in enemy.get("loot", []):
		if not (entry is Dictionary):
			continue
		var item_value: Variant = entry.get("item", "")
		var normalized_item: Variant = str(item_value)
		if item_value is float or item_value is int:
			normalized_item = int(item_value)
		loot_list.append({
			"item_id": normalized_item,
			"chance": float(entry.get("chance", 0.0)),
			"min": int(entry.get("min", 1)),
			"max": int(entry.get("max", 1))
		})

	return {
		"id": enemy_id,
		"name": str(enemy.get("name", enemy_id)),
		"description": str(enemy.get("description", "")),
		"level": int(enemy.get("level", 1)),
		"identity": {
			"camp_id": enemy_camp
		},
		"visual": {
			"portrait_path": str(enemy.get("portrait_path", "")),
			"avatar_path": str(enemy.get("avatar_path", "")),
			"model_path": "",
			"placeholder": {
				"head_color": "#f5b6b6",
				"body_color": "#b64545",
				"leg_color": "#7d2f2f"
			}
		},
		"combat": {
			"stats": {
				"hp": int(raw_stats.get("hp", 30)),
				"max_hp": int(raw_stats.get("max_hp", int(raw_stats.get("hp", 30)))),
				"damage": int(raw_stats.get("damage", 5)),
				"defense": int(raw_stats.get("defense", 1)),
				"speed": int(raw_stats.get("speed", 4)),
				"accuracy": int(raw_stats.get("accuracy", 60)),
				"crit_chance": 0.05,
				"crit_damage": 1.5,
				"evasion": 0.03
			},
			"ai": {
				"aggro_range": float(raw_ai.get("aggro_range", 6.0)),
				"attack_range": float(raw_ai.get("attack_range", 1.3)),
				"wander_radius": float(raw_ai.get("wander_radius", 4.0)),
				"leash_distance": float(raw_ai.get("leash_distance", 8.0)),
				"decision_interval": float(raw_ai.get("decision_interval", 0.8)),
				"attack_cooldown": float(raw_ai.get("attack_cooldown", 1.4))
			},
			"behavior": str(enemy.get("behavior", "aggressive")),
			"loot": loot_list,
			"xp": int(enemy.get("xp", 10))
		},
		"social": {
			"title": "",
			"dialog_tree_id": "",
			"mood": {
				"friendliness": 0,
				"trust": 0,
				"fear": 0,
				"anger": 90
			},
			"trade": {
				"enabled": false,
				"buy_price_modifier": 1.0,
				"sell_price_modifier": 1.0,
				"money": 0,
				"inventory": []
			},
			"recruitment": {
				"enabled": false,
				"min_charisma": 0,
				"min_friendliness": 100,
				"min_trust": 100,
				"required_quests": [],
				"required_items": [],
				"cost_items": [],
				"cost_money": 0
			},
			"capabilities": {
				"can_interact": false,
				"can_trade": false,
				"can_give_quest": false,
				"can_recruit": false
			}
		}
	}

func _normalize_trade_inventory(inventory: Array) -> Array:
	var result: Array = []
	for entry in inventory:
		if not (entry is Dictionary):
			continue
		var item_entry: Dictionary = entry
		var item_value: Variant = item_entry.get("id", "")
		var normalized_id: Variant = str(item_value)
		if item_value is float or item_value is int:
			normalized_id = int(item_value)
		result.append({
			"id": normalized_id,
			"count": int(item_entry.get("count", 1)),
			"price": int(item_entry.get("price", 0))
		})
	return result
