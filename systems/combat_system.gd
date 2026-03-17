extends Node

const HitReaction3D = preload("res://systems/hit_reaction_3d.gd")

signal combat_started(enemy_data: Dictionary)
signal turn_started(turn_owner: String, turn_number: int)
signal player_action_executed(action: String, result: Dictionary)
signal enemy_action_executed(action: String, result: Dictionary)
signal damage_dealt(target: String, amount: int, is_critical: bool)
signal combat_ended(victory: bool, rewards: Dictionary)

enum CombatState { IDLE, ACTIVE, VICTORY, DEFEAT, FLED }

var _combat_state: CombatState = CombatState.IDLE
var _current_enemy: Dictionary = {}
var _current_character_id: String = ""
var _turn_count: int = 0
var _action_in_progress: bool = false
var _last_combat_victory: bool = false
var _pending_rewards: Dictionary = {
	"xp": 0,
	"loot": []
}

var _runtime_actor_states: Dictionary = {}

func _ready() -> void:
	if TurnSystem:
		if TurnSystem.combat_state_changed.is_connected(_on_turn_system_combat_state_changed) == false:
			TurnSystem.combat_state_changed.connect(_on_turn_system_combat_state_changed)
		if TurnSystem.actor_turn_started.is_connected(_on_actor_turn_started) == false:
			TurnSystem.actor_turn_started.connect(_on_actor_turn_started)

func start_combat(character_ref: Variant):
	var player_actor: Node3D = get_player_actor()
	var target_actor: Node3D = _resolve_target_actor(character_ref)
	if player_actor == null or target_actor == null:
		return
	if TurnSystem:
		TurnSystem.enter_combat(player_actor, target_actor)
	_refresh_current_enemy(target_actor)
	return {
		"success": true,
		"enemy": _current_enemy.duplicate(true)
	}

func perform_attack(attacker: Node, target: Node, attack_type: String = "normal", target_part: String = "body") -> Dictionary:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return {"success": false, "reason": "invalid_attacker_or_target"}
	if _action_in_progress:
		return {"success": false, "reason": "action_in_progress"}

	var action_result: Dictionary = {
		"success": false,
		"reason": "",
		"damage": 0,
		"is_critical": false,
		"target_hp": 0
	}

	var start_result: Dictionary = {
		"success": true
	}
	if TurnSystem:
		start_result = TurnSystem.request_action(attacker, TurnSystem.ACTION_TYPE_ATTACK, {
			"phase": TurnSystem.ACTION_PHASE_START,
			"target_actor": target,
			"attack_type": attack_type,
			"target_part": target_part
		})
	if not bool(start_result.get("success", false)):
		return start_result

	_action_in_progress = true
	_refresh_current_enemy(target)

	if attacker.has_method("play_attack_lunge") and target is Node3D:
		attacker.call("play_attack_lunge", (target as Node3D).global_position)

	var damage_result: Dictionary = _apply_attack(attacker, target, attack_type, target_part)
	action_result.merge(damage_result, true)

	if TurnSystem:
		TurnSystem.request_action(attacker, TurnSystem.ACTION_TYPE_ATTACK, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": bool(action_result.get("success", false)),
			"entered_combat": bool(start_result.get("entered_combat", false))
		})
		TurnSystem.exit_combat_if_resolved()

	_action_in_progress = false
	_refresh_current_enemy(target)
	return action_result

func player_attack(attack_type: String = "normal", target_part: String = "body"):
	var player_actor: Node3D = get_player_actor()
	var enemy_actor: Node3D = _resolve_current_enemy_actor()
	if player_actor == null or enemy_actor == null:
		return {"success": false, "reason": "enemy_not_found"}
	return perform_attack(player_actor, enemy_actor, attack_type, target_part)

func player_defend():
	var player_actor: Node3D = get_player_actor()
	if player_actor == null:
		return {"success": false, "reason": "player_not_found"}
	var start_result: Dictionary = {
		"success": true
	}
	if TurnSystem:
		start_result = TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_DEFEND, {
			"phase": TurnSystem.ACTION_PHASE_START
		})
	if not bool(start_result.get("success", false)):
		return start_result
	if TurnSystem:
		TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_DEFEND, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": true
		})
	player_action_executed.emit("defend", {})
	return {"success": true}

func player_use_item(item_id: String):
	var player_actor: Node3D = get_player_actor()
	if player_actor == null:
		return {"success": false, "reason": "player_not_found"}
	var start_result: Dictionary = {
		"success": true
	}
	if TurnSystem:
		start_result = TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_ITEM, {
			"phase": TurnSystem.ACTION_PHASE_START,
			"item_id": item_id
		})
	if not bool(start_result.get("success", false)):
		return start_result

	var result: Variant = null
	if InventoryModule and InventoryModule.has_method("use_item"):
		result = InventoryModule.use_item(item_id)
	if TurnSystem:
		TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_ITEM, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": result != null
		})
	player_action_executed.emit("item", {"item": item_id})
	return {"success": result != null}

func player_flee():
	var player_actor: Node3D = get_player_actor()
	if player_actor == null:
		return false
	var start_result: Dictionary = {
		"success": true
	}
	if TurnSystem:
		start_result = TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_FLEE, {
			"phase": TurnSystem.ACTION_PHASE_START
		})
	if not bool(start_result.get("success", false)):
		return false
	var flee_chance: float = clampf(0.5 + (float(GameState.player_stamina) / 100.0) * 0.2, 0.1, 0.9)
	var success: bool = randf() < flee_chance
	if success:
		_combat_state = CombatState.FLED
		if TurnSystem and TurnSystem.is_in_combat():
			TurnSystem.force_end_combat()
		combat_ended.emit(false, {})
	else:
		if TurnSystem:
			TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_FLEE, {
				"phase": TurnSystem.ACTION_PHASE_COMPLETE,
				"success": true
			})
	return success

func is_in_combat():
	return TurnSystem != null and TurnSystem.is_in_combat()

func get_combat_state():
	if not is_in_combat():
		match _combat_state:
			CombatState.VICTORY:
				return "victory"
			CombatState.DEFEAT:
				return "defeat"
			CombatState.FLED:
				return "fled"
			_:
				return "idle"

	var current_actor: Node = TurnSystem.get_current_actor()
	if current_actor != null and current_actor.is_in_group("player"):
		return "player_turn"
	return "enemy_turn"

func get_enemy_info():
	return _current_enemy.duplicate(true)

func get_player_actor() -> Node3D:
	return _resolve_player_actor()

func is_player_turn() -> bool:
	var player_actor: Node3D = _resolve_player_actor()
	if player_actor == null or TurnSystem == null:
		return false
	return TurnSystem.is_actor_current_turn(player_actor)

func end_turn() -> void:
	var player_actor: Node3D = _resolve_player_actor()
	if player_actor == null or TurnSystem == null:
		return
	if not TurnSystem.is_actor_current_turn(player_actor):
		return
	TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_DEFEND, {
		"phase": TurnSystem.ACTION_PHASE_START
	})
	TurnSystem.request_action(player_actor, TurnSystem.ACTION_TYPE_DEFEND, {
		"phase": TurnSystem.ACTION_PHASE_COMPLETE,
		"success": true
	})

func get_enemy_stats() -> Dictionary:
	return _current_enemy.get("stats", {}).duplicate(true)

func get_player_stats() -> Dictionary:
	return {
		"attack": 10 + SkillModule.get_total_damage_bonus() if SkillModule else 10,
		"hp": GameState.player_hp,
		"max_hp": GameState.player_max_hp
	}

func _apply_attack(attacker: Node, target: Node, attack_type: String, target_part: String) -> Dictionary:
	var attacker_is_player: bool = attacker.is_in_group("player")
	var damage: int = _calculate_damage(attacker, target, attack_type, target_part)
	var is_critical: bool = randf() < _resolve_crit_chance(attacker)
	if is_critical:
		damage = int(round(damage * _resolve_crit_multiplier(attacker)))

	var target_hp: int = 0
	if target.is_in_group("player"):
		GameState.damage_player(damage)
		target_hp = GameState.player_hp
	else:
		target_hp = _apply_damage_to_actor(target, damage)

	_play_hit_feedback(target as Node3D, damage, is_critical)
	damage_dealt.emit("player" if target.is_in_group("player") else "enemy", damage, is_critical)

	var result: Dictionary = {
		"success": true,
		"damage": damage,
		"is_critical": is_critical,
		"target_hp": target_hp
	}

	if attacker_is_player:
		player_action_executed.emit("attack", result)
	else:
		enemy_action_executed.emit("attack", result)

	_show_attack_dialog(attacker, target, damage, is_critical)
	_check_runtime_actor_death(target, attacker)
	return result

func _calculate_damage(attacker: Node, target: Node, attack_type: String, target_part: String) -> int:
	var base_damage: int = _resolve_base_damage(attacker)
	match attack_type:
		"heavy":
			base_damage = int(round(base_damage * 1.5))
		"quick":
			base_damage = int(round(base_damage * 0.7))
		"headshot":
			base_damage = int(round(base_damage * 2.0))

	if target_part == "head":
		base_damage = int(round(base_damage * 1.2))

	var defense: int = _resolve_defense(target)
	var variance: float = randf_range(0.85, 1.15)
	return max(1, int(round((base_damage - defense) * variance)))

func _resolve_base_damage(actor: Node) -> int:
	if actor.is_in_group("player"):
		var base_damage: int = 10
		if SkillModule:
			base_damage += SkillModule.get_total_damage_bonus()
		return base_damage

	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	var stats: Dictionary = runtime_state.get("stats", {})
	return int(stats.get("damage", 3))

func _resolve_defense(actor: Node) -> int:
	if actor.is_in_group("player"):
		var player_defense: int = int(GameState.player_defense)
		if AttributeSystem:
			player_defense += int(round(AttributeSystem.calculate_damage_reduction() * 10.0))
		return player_defense
	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	var stats: Dictionary = runtime_state.get("stats", {})
	return int(stats.get("defense", 0))

func _resolve_crit_chance(actor: Node) -> float:
	if actor.is_in_group("player"):
		return 0.15
	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	var stats: Dictionary = runtime_state.get("stats", {})
	return float(stats.get("crit_chance", 0.05))

func _resolve_crit_multiplier(actor: Node) -> float:
	if actor.is_in_group("player"):
		return 1.5
	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	var stats: Dictionary = runtime_state.get("stats", {})
	return float(stats.get("crit_damage", 1.5))

func _ensure_actor_runtime_state(actor: Node) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return {}
	var key: String = str(actor.get_instance_id())
	if _runtime_actor_states.has(key):
		return (_runtime_actor_states[key] as Dictionary).duplicate(true)

	var character_id: String = str(actor.get_meta("character_id", ""))
	var enemy_data: Dictionary = _build_runtime_enemy_from_character(character_id)
	if enemy_data.is_empty():
		enemy_data = {
			"id": character_id,
			"name": actor.name,
			"stats": {
				"hp": 10,
				"max_hp": 10,
				"damage": 3,
				"defense": 0,
				"speed": 4,
				"crit_chance": 0.05,
				"crit_damage": 1.5
			},
			"current_hp": 10,
			"behavior": "neutral",
			"loot": [],
			"xp": 10
		}
	_runtime_actor_states[key] = enemy_data.duplicate(true)
	return enemy_data.duplicate(true)

func _apply_damage_to_actor(actor: Node, damage: int) -> int:
	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	if runtime_state.is_empty():
		return 0
	runtime_state["current_hp"] = maxi(0, int(runtime_state.get("current_hp", 0)) - damage)
	_runtime_actor_states[str(actor.get_instance_id())] = runtime_state.duplicate(true)
	return int(runtime_state.get("current_hp", 0))

func _check_runtime_actor_death(target: Node, attacker: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.is_in_group("player"):
		if GameState.player_hp > 0:
			return
		_combat_state = CombatState.DEFEAT
		combat_ended.emit(false, {})
		return

	var runtime_state: Dictionary = _ensure_actor_runtime_state(target)
	if int(runtime_state.get("current_hp", 0)) > 0:
		return

	var rewards: Dictionary = _build_victory_rewards(runtime_state)
	if target.get_parent() != null:
		target.queue_free()
	_runtime_actor_states.erase(str(target.get_instance_id()))

	if attacker != null and attacker.is_in_group("player"):
		_last_combat_victory = true
		_pending_rewards["xp"] = int(_pending_rewards.get("xp", 0)) + int(rewards.get("xp", 0))
		var reward_loot: Array = _pending_rewards.get("loot", [])
		reward_loot.append_array(rewards.get("loot", []))
		_pending_rewards["loot"] = reward_loot

func _build_victory_rewards(enemy_data: Dictionary) -> Dictionary:
	var loot: Array = _calculate_character_loot(enemy_data)
	for item in loot:
		if InventoryModule:
			InventoryModule.add_item(str(item.get("item", "")), int(item.get("amount", 1)))
	return {
		"xp": int(enemy_data.get("xp", 10)),
		"loot": loot
	}

func _refresh_current_enemy(target: Node) -> void:
	if target == null or not is_instance_valid(target) or target.is_in_group("player"):
		return
	var runtime_state: Dictionary = _ensure_actor_runtime_state(target)
	_current_enemy = runtime_state.duplicate(true)
	_current_character_id = str(runtime_state.get("id", target.get_meta("character_id", "")))

func _resolve_current_enemy_actor() -> Node3D:
	if _current_character_id.is_empty():
		return _resolve_first_hostile_actor()
	if AIManager.current and AIManager.current.has_method("find_active_actor_by_character_id"):
		var actor: Variant = AIManager.current.find_active_actor_by_character_id(_current_character_id)
		if actor is Node3D and is_instance_valid(actor):
			return actor as Node3D
	return _resolve_first_hostile_actor()

func _resolve_target_actor(character_ref: Variant) -> Node3D:
	if character_ref is Node3D and is_instance_valid(character_ref):
		return character_ref as Node3D
	var character_id: String = _resolve_character_id(character_ref)
	if character_id.is_empty():
		return null
	if AIManager.current and AIManager.current.has_method("find_active_actor_by_character_id"):
		var actor: Variant = AIManager.current.find_active_actor_by_character_id(character_id)
		if actor is Node3D and is_instance_valid(actor):
			return actor as Node3D
	return null

func _resolve_first_hostile_actor() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("enemy"):
		if node is Node3D and is_instance_valid(node):
			return node as Node3D
	return null

func _resolve_character_id(character_ref: Variant) -> String:
	if character_ref is String:
		return str(character_ref)
	if character_ref is Dictionary:
		var payload: Dictionary = character_ref
		var from_character: String = str(payload.get("character_id", ""))
		if not from_character.is_empty():
			return from_character
		var from_enemy_data: Variant = payload.get("enemy_data", null)
		if from_enemy_data is String:
			return str(from_enemy_data)
		if from_enemy_data is Dictionary:
			var nested: Dictionary = from_enemy_data
			return str(nested.get("id", ""))
		return str(payload.get("id", ""))
	if character_ref is Node and (character_ref as Node).has_meta("character_id"):
		return str((character_ref as Node).get_meta("character_id"))
	return str(character_ref)

func _build_runtime_enemy_from_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not DataManager or not DataManager.has_method("get_character"):
		return {}

	var character_data: Variant = DataManager.get_character(character_id)
	if not (character_data is Dictionary):
		return {}
	var character: Dictionary = character_data
	if character.is_empty():
		return {}

	var combat: Dictionary = character.get("combat", {})
	var stats_data: Dictionary = combat.get("stats", {})
	var hp: int = int(stats_data.get("hp", 10))
	var max_hp: int = int(stats_data.get("max_hp", hp))
	var normalized_stats: Dictionary = {
		"hp": hp,
		"max_hp": max_hp,
		"damage": int(stats_data.get("damage", 3)),
		"defense": int(stats_data.get("defense", 0)),
		"speed": int(stats_data.get("speed", 5)),
		"accuracy": int(stats_data.get("accuracy", 60)),
		"crit_chance": float(stats_data.get("crit_chance", 0.05)),
		"crit_damage": float(stats_data.get("crit_damage", 1.5))
	}

	return {
		"id": str(character.get("id", character_id)),
		"name": str(character.get("name", "未知敌人")),
		"description": str(character.get("description", "")),
		"level": int(character.get("level", 1)),
		"stats": normalized_stats,
		"current_hp": hp,
		"behavior": str(combat.get("behavior", "passive")),
		"special_abilities": combat.get("special_abilities", []).duplicate(),
		"weaknesses": combat.get("weaknesses", []).duplicate(),
		"resistances": combat.get("resistances", []).duplicate(),
		"loot": combat.get("loot", []).duplicate(true),
		"xp": int(combat.get("xp", 10))
	}

func _calculate_character_loot(enemy_data: Dictionary) -> Array:
	var drops: Array = []
	var loot_entries: Array = enemy_data.get("loot", [])
	for entry in loot_entries:
		if not (entry is Dictionary):
			continue
		var chance: float = float(entry.get("chance", 0.0))
		if randf() > chance:
			continue
		var item_id: Variant = entry.get("item_id", entry.get("item", ""))
		var min_amount: int = int(entry.get("min", 1))
		var max_amount: int = int(entry.get("max", min_amount))
		var amount: int = randi_range(min_amount, max_amount)
		drops.append({
			"item": item_id,
			"amount": amount
		})
	return drops

func _resolve_player_actor() -> Node3D:
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node is Node3D and is_instance_valid(player_node):
		return player_node as Node3D
	return null

func _resolve_world_damage_text_controller() -> Node:
	var player_actor: Node3D = _resolve_player_actor()
	if player_actor != null and player_actor.has_method("get_world_damage_text_controller"):
		var controller: Variant = player_actor.call("get_world_damage_text_controller")
		if controller is Node and is_instance_valid(controller):
			return controller as Node
	return null

func _play_hit_feedback(target: Node3D, damage: int, is_critical: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	var hit_reaction: Variant = HitReaction3D.get_or_create(target)
	if hit_reaction != null:
		hit_reaction.play_hit_shake()

	var damage_text_controller: Node = _resolve_world_damage_text_controller()
	if damage_text_controller != null and damage_text_controller.has_method("show_damage_number"):
		damage_text_controller.show_damage_number(target, damage, is_critical)

func _show_attack_dialog(attacker: Node, target: Node, damage: int, is_critical: bool) -> void:
	if DialogModule == null:
		return
	var attacker_name: String = "你" if attacker.is_in_group("player") else str(attacker.get_meta("character_id", attacker.name))
	var target_name: String = "你" if target.is_in_group("player") else str(target.get_meta("character_id", target.name))
	var message: String = "%s 对 %s 造成了 %d 伤害" % [attacker_name, target_name, damage]
	if is_critical:
		message = "暴击！" + message
	DialogModule.show_dialog(message, "战斗", "")

func _on_turn_system_combat_state_changed(in_combat: bool) -> void:
	if in_combat:
		_combat_state = CombatState.ACTIVE
		_turn_count = 0
		_last_combat_victory = false
		_pending_rewards = {"xp": 0, "loot": []}
		var enemy_actor: Node3D = _resolve_first_hostile_actor()
		if enemy_actor != null:
			_refresh_current_enemy(enemy_actor)
		combat_started.emit(_current_enemy.duplicate(true))
		return

	if _combat_state == CombatState.ACTIVE:
		if GameState.player_hp <= 0:
			_combat_state = CombatState.DEFEAT
			combat_ended.emit(false, {})
		elif _last_combat_victory:
			_combat_state = CombatState.VICTORY
			combat_ended.emit(true, _pending_rewards.duplicate(true))
		else:
			_combat_state = CombatState.IDLE

func _on_actor_turn_started(actor: Node, _actor_id: String, _group_id: String, side: String, _current_ap: float) -> void:
	if _combat_state != CombatState.ACTIVE:
		return
	_turn_count += 1
	turn_started.emit("player" if side == "player" else "enemy", _turn_count)
