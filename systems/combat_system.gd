extends Node

const AttributeSystemScript = preload("res://systems/attribute_system.gd")
const TargetAttackAbilityScript = preload("res://systems/target_attack_ability.gd")
const ValueUtils = preload("res://core/value_utils.gd")
const AIManagerScript = preload("res://systems/ai/ai_manager.gd")

signal combat_started(enemy_data: Dictionary)
signal turn_started(turn_owner: String, turn_number: int)
signal player_action_executed(action: String, result: Dictionary)
signal enemy_action_executed(action: String, result: Dictionary)
signal damage_dealt(target: String, amount: int, is_critical: bool)
signal combat_ended(victory: bool, rewards: Dictionary)

enum CombatState { IDLE, ACTIVE, VICTORY, DEFEAT }

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
var _pending_presentation_actions: Dictionary = {}

func _ready() -> void:
	if TurnSystem:
		if TurnSystem.combat_state_changed.is_connected(_on_turn_system_combat_state_changed) == false:
			TurnSystem.combat_state_changed.connect(_on_turn_system_combat_state_changed)
		if TurnSystem.actor_turn_started.is_connected(_on_actor_turn_started) == false:
			TurnSystem.actor_turn_started.connect(_on_actor_turn_started)
	if ActionPresentationSystem:
		if ActionPresentationSystem.presentation_completed.is_connected(_on_action_presentation_completed) == false:
			ActionPresentationSystem.presentation_completed.connect(_on_action_presentation_completed)

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

	var damage_result: Dictionary = _apply_attack(attacker, target, attack_type, target_part)
	action_result.merge(damage_result, true)
	var presentation_result: Dictionary = _build_attack_action_result(
		attacker,
		target,
		attack_type,
		target_part,
		action_result
	)
	action_result["presentation"] = presentation_result.duplicate()
	var handle: Dictionary = _start_action_presentation(presentation_result)
	if bool(handle.get("started", false)) and bool(presentation_result.get("wait_for_presentation", false)):
		var job_id: String = str(handle.get("job_id", ""))
		if not job_id.is_empty():
			_pending_presentation_actions[job_id] = {
				"attacker": attacker,
				"target": target,
				"action_type": TurnSystem.ACTION_TYPE_ATTACK,
				"success": bool(action_result.get("success", false)),
				"entered_combat": bool(start_result.get("entered_combat", false))
			}
			action_result["presentation_job_id"] = job_id
			return action_result

	_finalize_attack_action(
		attacker,
		target,
		bool(action_result.get("success", false)),
		bool(start_result.get("entered_combat", false))
	)
	return action_result

func player_attack(attack_type: String = "normal", target_part: String = "body"):
	var player_actor: Node3D = get_player_actor()
	var enemy_actor: Node3D = _resolve_current_enemy_actor()
	if player_actor == null or enemy_actor == null:
		return {"success": false, "reason": "enemy_not_found"}
	return perform_attack(player_actor, enemy_actor, attack_type, target_part)


func begin_targeted_attack(attacker: Node, context: Dictionary = {}) -> Dictionary:
	if attacker == null or not is_instance_valid(attacker):
		return {"success": false, "reason": "invalid_attacker"}

	var handler: TargetAttackAbility = _create_target_attack_handler(attacker, context)
	if handler == null:
		return {"success": false, "reason": "attack_handler_unavailable"}

	var targeting_context: Dictionary = context.duplicate(true)
	targeting_context["caster"] = attacker
	targeting_context["attack_range_cells"] = resolve_attack_range_cells(attacker, context)
	targeting_context["scene_root"] = _resolve_scene_root(attacker, context)
	var session: Dictionary = handler.begin_targeting(targeting_context)

	if attacker.is_in_group("player") \
	and not bool(context.get("ai", false)) \
	and AbilityTargetingSystem != null \
	and AbilityTargetingSystem.has_method("begin_attack_targeting"):
		return AbilityTargetingSystem.begin_attack_targeting(handler, targeting_context)

	return {
		"success": true,
		"state": "targeting_started",
		"session": session
	}


func resolve_attack_range_cells(attacker: Node, context: Dictionary = {}) -> int:
	if context.has("attack_range_cells"):
		return maxi(1, ValueUtils.to_int(context.get("attack_range_cells", 1), 1))
	if attacker != null and attacker.is_in_group("player"):
		var player_range: int = _resolve_player_attack_range(attacker)
		if player_range > 0:
			return player_range
	if context.has("attack_range"):
		return maxi(1, ceili(float(context.get("attack_range", 1.0))))
	return 1

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

func is_in_combat():
	return TurnSystem != null and TurnSystem.is_in_combat()

func get_combat_state():
	if not is_in_combat():
		match _combat_state:
			CombatState.VICTORY:
				return "victory"
			CombatState.DEFEAT:
				return "defeat"
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

func complete_player_turn() -> bool:
	var player_actor: Node3D = _resolve_player_actor()
	if player_actor == null or TurnSystem == null:
		return false
	if not TurnSystem.has_method("end_current_turn"):
		return false
	return bool(TurnSystem.end_current_turn(player_actor))

func get_enemy_stats() -> Dictionary:
	return _current_enemy.get("stats", {}).duplicate(true)

func get_player_stats() -> Dictionary:
	var snapshot: Dictionary = _get_effective_actor_stats(get_player_actor())
	return {
		"attack": ValueUtils.to_int(snapshot.get("attack_power", 0)),
		"hp": ValueUtils.to_int(snapshot.get("hp", 0)),
		"max_hp": ValueUtils.to_int(snapshot.get("max_hp", 0))
	}

func _apply_attack(attacker: Node, target: Node, attack_type: String, target_part: String) -> Dictionary:
	var attacker_is_player: bool = attacker.is_in_group("player")
	var damage: int = _calculate_damage(attacker, target, attack_type, target_part)
	var is_critical: bool = randf() < _resolve_crit_chance(attacker)
	if is_critical:
		damage = ValueUtils.to_int(round(damage * _resolve_crit_multiplier(attacker)))

	var target_hp: int = 0
	if target.is_in_group("player"):
		GameState.damage_player(damage)
		target_hp = ValueUtils.to_int(GameState.get_player_attributes_snapshot().get("hp", 0))
	else:
		target_hp = _apply_damage_to_actor(target, damage)

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
	var attacker_stats: Dictionary = _get_effective_actor_stats(attacker)
	var target_stats: Dictionary = _get_effective_actor_stats(target)
	var base_damage: float = float(attacker_stats.get("attack_power", 1.0))
	match attack_type:
		"heavy":
			base_damage *= 1.5
		"quick":
			base_damage *= 0.7
		"headshot":
			base_damage *= 2.0

	if target_part == "head":
		base_damage *= 1.2

	var accuracy_factor: float = clampf(
		float(attacker_stats.get("accuracy", 70.0)) / 100.0 - float(target_stats.get("evasion", 0.0)) * 0.5,
		0.25,
		1.5
	)
	var speed_delta: float = float(attacker_stats.get("speed", 5.0)) - float(target_stats.get("speed", 5.0))
	var speed_factor: float = clampf(1.0 + speed_delta * 0.03, 0.7, 1.3)
	var defense: float = float(target_stats.get("defense", 0.0))
	var variance: float = randf_range(0.85, 1.15)
	var resolved_damage: float = maxf(1.0, (base_damage * accuracy_factor * speed_factor - defense) * variance)
	return max(1, ValueUtils.to_int(round(resolved_damage)))

func _resolve_base_damage(actor: Node) -> int:
	var stats: Dictionary = _get_effective_actor_stats(actor)
	return ValueUtils.to_int(stats.get("attack_power", 1), 1)

func _resolve_defense(actor: Node) -> int:
	var stats: Dictionary = _get_effective_actor_stats(actor)
	return ValueUtils.to_int(stats.get("defense", 0))

func _resolve_crit_chance(actor: Node) -> float:
	var stats: Dictionary = _get_effective_actor_stats(actor)
	return float(stats.get("crit_chance", 0.05))

func _resolve_crit_multiplier(actor: Node) -> float:
	var stats: Dictionary = _get_effective_actor_stats(actor)
	return float(stats.get("crit_damage", 1.5))

func _ensure_actor_runtime_state(actor: Node) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return {}
	var key: String = str(actor.get_instance_id())
	if _runtime_actor_states.has(key):
		var cached_state: Dictionary = (_runtime_actor_states[key] as Dictionary).duplicate(true)
		if cached_state.has("attributes"):
			actor.set_meta("attribute_container", cached_state.get("attributes", {}))
		return cached_state

	var character_id: String = str(actor.get_meta("character_id", ""))
	var enemy_data: Dictionary = _build_runtime_enemy_from_character(character_id)
	if enemy_data.is_empty():
		var fallback_attributes: Dictionary = AttributeSystemScript.create_default_container({}, ["base", "combat"], {"hp": 10})
		fallback_attributes["sets"]["combat"] = {
			"max_hp": 10,
			"attack_power": 3,
			"defense": 0,
			"speed": 4,
			"accuracy": 60,
			"crit_chance": 0.05,
			"crit_damage": 1.5,
			"evasion": 0.0
		}
		fallback_attributes["resources"]["hp"] = {"current": 10}
		enemy_data = {
			"id": character_id,
			"name": actor.name,
			"attributes": fallback_attributes,
			"behavior": "neutral",
			"loot": [],
			"xp": 10
		}
	actor.set_meta("attribute_container", enemy_data.get("attributes", {}))
	_runtime_actor_states[key] = enemy_data.duplicate(true)
	return enemy_data.duplicate(true)

func _apply_damage_to_actor(actor: Node, damage: int) -> int:
	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	if runtime_state.is_empty():
		return 0
	var attributes: Dictionary = runtime_state.get("attributes", {})
	var resources: Dictionary = attributes.get("resources", {})
	var hp_resource: Dictionary = resources.get("hp", {}).duplicate(true)
	var hp_value: int = ValueUtils.to_int(hp_resource.get("current", 0))
	hp_resource["current"] = maxi(0, hp_value - damage)
	resources["hp"] = hp_resource
	attributes["resources"] = resources
	runtime_state["attributes"] = attributes
	actor.set_meta("attribute_container", attributes)
	_runtime_actor_states[str(actor.get_instance_id())] = runtime_state.duplicate(true)
	return ValueUtils.to_int(hp_resource.get("current", 0))

func _check_runtime_actor_death(target: Node, attacker: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.is_in_group("player"):
		if ValueUtils.to_int(GameState.get_player_attributes_snapshot().get("hp", 0)) > 0:
			return
		_combat_state = CombatState.DEFEAT
		combat_ended.emit(false, {})
		return

	var runtime_state: Dictionary = _ensure_actor_runtime_state(target)
	var runtime_attributes: Dictionary = runtime_state.get("attributes", {})
	var hp_value: int = ValueUtils.to_int(((runtime_attributes.get("resources", {}) as Dictionary).get("hp", {}) as Dictionary).get("current", 0))
	if hp_value > 0:
		return

	var rewards: Dictionary = _build_victory_rewards(runtime_state)
	if target.get_parent() != null:
		target.queue_free()
	_runtime_actor_states.erase(str(target.get_instance_id()))

	if attacker != null and attacker.is_in_group("player"):
		_last_combat_victory = true
		_pending_rewards["xp"] = ValueUtils.to_int(_pending_rewards.get("xp", 0)) + ValueUtils.to_int(rewards.get("xp", 0))
		var reward_loot: Array = _pending_rewards.get("loot", [])
		reward_loot.append_array(rewards.get("loot", []))
		_pending_rewards["loot"] = reward_loot

func _build_victory_rewards(enemy_data: Dictionary) -> Dictionary:
	var loot: Array = _calculate_character_loot(enemy_data)
	for item in loot:
		if InventoryModule:
			InventoryModule.add_item(str(item.get("item", "")), ValueUtils.to_int(item.get("amount", 1), 1))
	return {
		"xp": ValueUtils.to_int(enemy_data.get("xp", 10), 10),
		"loot": loot
	}

func _refresh_current_enemy(target: Node) -> void:
	if target == null or not is_instance_valid(target) or target.is_in_group("player"):
		return
	_current_enemy = _build_runtime_enemy_snapshot(target)
	_current_character_id = str(_current_enemy.get("id", target.get_meta("character_id", "")))

func _resolve_current_enemy_actor() -> Node3D:
	if _current_character_id.is_empty():
		return _resolve_first_hostile_actor()
	var ai_manager: Node = AIManagerScript.current as Node
	if ai_manager != null and ai_manager.has_method("find_active_actor_by_character_id"):
		var actor: Variant = ai_manager.call("find_active_actor_by_character_id", _current_character_id)
		if actor is Node3D and is_instance_valid(actor):
			return actor as Node3D
	return _resolve_first_hostile_actor()

func _resolve_target_actor(character_ref: Variant) -> Node3D:
	if character_ref is Node3D and is_instance_valid(character_ref):
		return character_ref as Node3D
	var character_id: String = _resolve_character_id(character_ref)
	if character_id.is_empty():
		return null
	var ai_manager: Node = AIManagerScript.current as Node
	if ai_manager != null and ai_manager.has_method("find_active_actor_by_character_id"):
		var actor: Variant = ai_manager.call("find_active_actor_by_character_id", character_id)
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
	var character: Dictionary = (character_data as Dictionary).duplicate(true)
	if character.is_empty():
		return {}
	if not character.has("attributes"):
		return {}

	var combat: Dictionary = character.get("combat", {})
	var attributes: Dictionary = AttributeSystemScript.normalize_attribute_container(character.get("attributes", {}))

	return {
		"id": str(character.get("id", character_id)),
		"name": str(character.get("name", "未知敌人")),
		"description": str(character.get("description", "")),
		"level": ValueUtils.to_int(character.get("level", 1), 1),
		"attributes": attributes.duplicate(true),
		"behavior": str(combat.get("behavior", "passive")),
		"special_abilities": combat.get("special_abilities", []).duplicate(),
		"weaknesses": combat.get("weaknesses", []).duplicate(),
		"resistances": combat.get("resistances", []).duplicate(),
		"loot": combat.get("loot", []).duplicate(true),
		"xp": ValueUtils.to_int(combat.get("xp", 10), 10)
	}

func _build_runtime_enemy_snapshot(target: Node) -> Dictionary:
	var runtime_state: Dictionary = _ensure_actor_runtime_state(target)
	var snapshot: Dictionary = runtime_state.duplicate(true)
	snapshot["stats"] = _get_effective_actor_stats(target)
	return snapshot

func _get_effective_actor_stats(actor: Node) -> Dictionary:
	if actor != null and actor.is_in_group("player"):
		return GameState.get_player_attributes_snapshot()

	var runtime_state: Dictionary = _ensure_actor_runtime_state(actor)
	var attributes: Dictionary = runtime_state.get("attributes", {})
	if attributes.is_empty():
		return {}
	actor.set_meta("attribute_container", attributes)
	if AttributeSystem and AttributeSystem.has_method("get_actor_attributes_snapshot"):
		return AttributeSystem.get_actor_attributes_snapshot(actor)
	return AttributeSystemScript.resolve_attribute_snapshot(attributes)

func _get_actor_skill_modifiers(actor: Node) -> Dictionary:
	var skill_runtime: Node = _get_actor_skill_runtime(actor)
	if skill_runtime == null or not skill_runtime.has_method("get_total_modifiers"):
		return {}
	var result: Variant = skill_runtime.call("get_total_modifiers")
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {}

func _get_actor_skill_runtime(actor: Node) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	return actor.get_node_or_null("CharacterSkillRuntime")

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
		var min_amount: int = ValueUtils.to_int(entry.get("min", 1), 1)
		var max_amount: int = ValueUtils.to_int(entry.get("max", min_amount), min_amount)
		var amount: int = randi_range(min_amount, max_amount)
		drops.append({
			"item": item_id,
			"amount": amount
		})
	return drops


func _create_target_attack_handler(attacker: Node, context: Dictionary) -> TargetAttackAbility:
	var handler := TargetAttackAbilityScript.new()
	handler.configure_attack({
		"ability_id": str(context.get("ability_id", "basic_attack")),
		"attack_range_cells": resolve_attack_range_cells(attacker, context),
		"shape": str(context.get("shape", "single")),
		"radius": ValueUtils.to_int(context.get("radius", 0)),
		"attack_type": str(context.get("attack_type", "normal")),
		"target_part": str(context.get("target_part", "body"))
	})
	return handler


func _resolve_player_attack_range(attacker: Node) -> int:
	if attacker != null and attacker.has_node("EquipmentSystem"):
		var equipment_system: Node = attacker.get_node_or_null("EquipmentSystem")
		if equipment_system != null and equipment_system.has_method("calculate_combat_stats"):
			var equipment_stats: Variant = equipment_system.call("calculate_combat_stats")
			if equipment_stats is Dictionary:
				return maxi(1, ValueUtils.to_int((equipment_stats as Dictionary).get("range", 1), 1))
			if equipment_system.has_method("get_equipped_data"):
				var main_hand: Variant = equipment_system.call("get_equipped_data", "main_hand")
				if main_hand is Dictionary:
					var weapon_data: Dictionary = (main_hand as Dictionary).get("weapon_data", {})
					return maxi(1, ValueUtils.to_int(weapon_data.get("range", 1), 1))
	return 1


func _resolve_scene_root(attacker: Node, context: Dictionary) -> Node:
	var provided_root: Node = context.get("scene_root", null) as Node
	if provided_root != null and is_instance_valid(provided_root):
		return provided_root
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("get_targeting_scene_root"):
		var resolved_root: Variant = attacker.call("get_targeting_scene_root")
		if resolved_root is Node and is_instance_valid(resolved_root):
			return resolved_root as Node
	if attacker != null and is_instance_valid(attacker) and attacker.get_tree() != null:
		return attacker.get_tree().current_scene
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene

func _resolve_player_actor() -> Node3D:
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node is Node3D and is_instance_valid(player_node):
		return player_node as Node3D
	return null

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
		if ActionPresentationSystem != null and ActionPresentationSystem.has_method("cancel_jobs_by_mode"):
			ActionPresentationSystem.cancel_jobs_by_mode("noncombat")
		_combat_state = CombatState.ACTIVE
		_turn_count = 0
		_last_combat_victory = false
		_pending_rewards = {"xp": 0, "loot": []}
		var enemy_actor: Node3D = _resolve_first_hostile_actor()
		if enemy_actor != null:
			_refresh_current_enemy(enemy_actor)
		combat_started.emit(_current_enemy.duplicate(true))
		return

	_pending_presentation_actions.clear()
	_action_in_progress = false
	if _combat_state == CombatState.ACTIVE:
		if ValueUtils.to_int(GameState.get_player_attributes_snapshot().get("hp", 0)) <= 0:
			_combat_state = CombatState.DEFEAT
			combat_ended.emit(false, {})
		elif _last_combat_victory:
			_combat_state = CombatState.VICTORY
			combat_ended.emit(true, _pending_rewards.duplicate(true))
		else:
			_combat_state = CombatState.IDLE

func _on_actor_turn_started(_actor: Node, _actor_id: String, _group_id: String, side: String, _current_ap: float) -> void:
	if _combat_state != CombatState.ACTIVE:
		return
	_turn_count += 1
	turn_started.emit("player" if side == "player" else "enemy", _turn_count)

func _build_attack_action_result(
	attacker: Node,
	target: Node,
	attack_type: String,
	target_part: String,
	action_result: Dictionary
) -> Dictionary:
	var target_node: Node3D = target as Node3D
	return {
		"actor": attacker,
		"action_type": TurnSystem.ACTION_TYPE_ATTACK,
		"mode": "combat" if is_in_combat() else "noncombat",
		"wait_for_presentation": is_in_combat(),
		"presentation_policy": "FULL_BLOCKING" if is_in_combat() else "FULL_NONBLOCKING",
		"target": target,
		"target_pos": target_node.global_position if target_node != null else Vector3.ZERO,
		"damage": ValueUtils.to_int(action_result.get("damage", 0)),
		"is_critical": bool(action_result.get("is_critical", false)),
		"metadata": {
			"attack_type": attack_type,
			"target_part": target_part
		}
	}

func _start_action_presentation(action_result: Dictionary) -> Dictionary:
	if ActionPresentationSystem == null or not ActionPresentationSystem.has_method("play"):
		return {}
	var result: Variant = ActionPresentationSystem.play(action_result)
	if result is Dictionary:
		return (result as Dictionary).duplicate()
	return {}

func _finalize_attack_action(attacker: Node, target: Node, success: bool, entered_combat: bool) -> void:
	if TurnSystem:
		TurnSystem.request_action(attacker, TurnSystem.ACTION_TYPE_ATTACK, {
			"phase": TurnSystem.ACTION_PHASE_COMPLETE,
			"success": success,
			"entered_combat": entered_combat
		})
		TurnSystem.exit_combat_if_resolved()
	_action_in_progress = false
	_refresh_current_enemy(target)

func _on_action_presentation_completed(job_id: String, _action_result: Dictionary) -> void:
	if not _pending_presentation_actions.has(job_id):
		return
	var pending: Dictionary = _pending_presentation_actions[job_id]
	_pending_presentation_actions.erase(job_id)
	_finalize_attack_action(
		pending.get("attacker", null) as Node,
		pending.get("target", null) as Node,
		bool(pending.get("success", false)),
		bool(pending.get("entered_combat", false))
	)
