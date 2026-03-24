extends "res://modules/interaction/options/interaction_option.gd"
class_name AttackInteractionOption
## LEGACY AUTHORITY BOUNDARY:
## This option is a temporary Godot-side compatibility bridge for attack entry.
## Do not expand combat rule authority here. Long-term validation/resolution
## should be handled by Rust runtime/protocol, while Godot consumes results.

const CharacterRelationResolverScript = preload("res://systems/character_relation_resolver.gd")

@export var hostile_priority: int = 1000
@export var neutral_priority: int = -100
@export var default_attack_range: float = 1.2
@export var enemy_id: String = "enemy"
@export var enemy_name: String = "敌人"
@export var enemy_hp: int = 30
@export var enemy_max_hp: int = 30
@export var enemy_damage: int = 5
@export var custom_enemy_data: Dictionary = {}

var _relation_resolver = CharacterRelationResolverScript.new()

func _init() -> void:
	option_id = "attack"
	display_name = "攻击"
	priority = hostile_priority

func get_priority(interactable: Node) -> int:
	if _is_hostile(interactable):
		return hostile_priority
	return neutral_priority

func is_dangerous(interactable: Node) -> bool:
	return not _is_hostile(interactable)

func get_action_type(_interactable: Node) -> String:
	return "attack"

func uses_external_action_flow(_interactable: Node) -> bool:
	return true

func requires_proximity(_interactable: Node) -> bool:
	return false

func get_required_distance(interactable: Node) -> float:
	return _resolve_attack_range(interactable)

func get_interaction_anchor_position(interactable: Node) -> Vector3:
	var actor := _resolve_actor(interactable)
	if actor:
		return actor.global_position
	return super.get_interaction_anchor_position(interactable)

func execute(interactable: Node) -> void:
	var character_id := _resolve_character_id(interactable)
	if not character_id.is_empty() and not _is_hostile(interactable):
		_force_hostile(character_id)

	var combat_data := custom_enemy_data.duplicate(true)
	if combat_data.is_empty():
		var combat_target_id: String = character_id if not character_id.is_empty() else enemy_id
		combat_data = {
			"id": combat_target_id,
			"name": _resolve_enemy_name(interactable),
			"hp": enemy_hp,
			"max_hp": enemy_max_hp,
			"damage": enemy_damage
		}

	var target_actor := _resolve_actor(interactable)
	var player_actor := _resolve_player_actor()
	if target_actor != null and player_actor != null and CombatSystem and CombatSystem.has_method("begin_targeted_attack"):
		var targeting_result: Dictionary = CombatSystem.begin_targeted_attack(player_actor, {
			"preferred_cell": GridMovementSystem.world_to_grid(target_actor.global_position),
			"target_actor": target_actor,
			"attack_range_cells": maxi(1, int(ceil(_resolve_attack_range(interactable)))),
			"scene_root": _resolve_scene_root(player_actor)
		})
		if bool(targeting_result.get("success", false)):
			return
	elif character_id.is_empty():
		if CombatModule and CombatModule.has_method("start_combat"):
			CombatModule.start_combat(combat_data)
	elif CombatSystem and CombatSystem.has_method("start_combat"):
		CombatSystem.start_combat(character_id)
	
	var event_target: String = character_id
	if event_target.is_empty() and interactable:
		event_target = str(interactable.name)
	if EventBus:
		EventBus.emit(EventBus.EventType.SCENE_INTERACTION, {
			"type": "attack_targeting_started",
			"target": event_target,
			"data": combat_data
		})

func _is_hostile(interactable: Node) -> bool:
	var relation_result := _resolve_relation_result(interactable)
	return str(relation_result.get("resolved_attitude", "neutral")) == "hostile"

func _resolve_attack_range(interactable: Node) -> float:
	var character_id := _resolve_character_id(interactable)
	if character_id.is_empty():
		return default_attack_range

	var character_data := _get_character_data(character_id)
	if character_data.is_empty():
		return default_attack_range

	var combat: Dictionary = character_data.get("combat", {})
	var ai_data: Dictionary = combat.get("ai", {})
	var resolved_range: float = float(ai_data.get("attack_range", combat.get("attack_range", default_attack_range)))
	return maxf(0.0, resolved_range)

func _force_hostile(character_id: String) -> void:
	if character_id.is_empty():
		return
	if GameStateManager and GameStateManager.has_method("set_character_hostile"):
		GameStateManager.set_character_hostile(character_id, true)

func _resolve_relation_result(interactable: Node) -> Dictionary:
	var actor := _resolve_actor(interactable)
	if actor and actor.has_meta("relation_result"):
		var meta_result: Variant = actor.get_meta("relation_result")
		if meta_result is Dictionary:
			return (meta_result as Dictionary).duplicate(true)

	var character_id := _resolve_character_id(interactable)
	if character_id.is_empty():
		return {}
	var character_data := _get_character_data(character_id)
	if character_data.is_empty():
		return {}
	return _relation_resolver.resolve_for_player(character_id, character_data)

func _resolve_character_id(interactable: Node) -> String:
	if interactable and interactable.has_meta("character_id"):
		return str(interactable.get_meta("character_id"))
	if interactable and interactable.has_meta("npc_id"):
		return str(interactable.get_meta("npc_id"))
	if interactable and interactable.has_meta("enemy_id"):
		return str(interactable.get_meta("enemy_id"))

	var actor := _resolve_actor(interactable)
	if actor == null:
		return ""
	if actor.has_meta("character_id"):
		return str(actor.get_meta("character_id"))
	if actor.has_meta("npc_id"):
		return str(actor.get_meta("npc_id"))
	if actor.has_meta("enemy_id"):
		return str(actor.get_meta("enemy_id"))
	return ""

func _resolve_enemy_name(interactable: Node) -> String:
	var character_id := _resolve_character_id(interactable)
	if not character_id.is_empty():
		var character_data := _get_character_data(character_id)
		var character_name := str(character_data.get("name", "")).strip_edges()
		if not character_name.is_empty():
			return character_name
	if interactable:
		return interactable.name
	return enemy_name

func _resolve_actor(interactable: Node) -> Node3D:
	var node := interactable
	while node != null:
		if node is Node3D and node.has_meta("character_id"):
			return node as Node3D
		node = node.get_parent()
	return null

func _resolve_player_actor() -> Node3D:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	var player_node := (tree as SceneTree).get_first_node_in_group("player")
	if player_node is Node3D and is_instance_valid(player_node):
		return player_node as Node3D
	return null

func _resolve_scene_root(player_actor: Node) -> Node:
	if player_actor != null and is_instance_valid(player_actor) and player_actor.has_method("get_targeting_scene_root"):
		var scene_root: Variant = player_actor.call("get_targeting_scene_root")
		if scene_root is Node:
			return scene_root as Node
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).current_scene
	return null

func _get_character_data(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	var ai_manager: Node = _resolve_ai_manager()
	if ai_manager != null and ai_manager.has_method("get_character_data"):
		var data: Variant = ai_manager.call("get_character_data", character_id)
		if data is Dictionary:
			return data
	return {}

func _resolve_ai_manager() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree := loop as SceneTree
	if tree.current_scene != null:
		var matches: Array[Node] = tree.current_scene.find_children("*", "AIManager", true, false)
		if not matches.is_empty():
			return matches[0]
	return null
