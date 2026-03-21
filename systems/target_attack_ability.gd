class_name TargetAttackAbility
extends "res://systems/target_ability_base.gd"

var attack_range_cells: int = 1
var attack_type: String = "normal"
var target_part: String = "body"


func configure_attack(config: Dictionary) -> void:
	ability_id = str(config.get("ability_id", "basic_attack"))
	ability_kind = "attack"
	attack_range_cells = maxi(1, int(config.get("attack_range_cells", 1)))
	attack_type = str(config.get("attack_type", "normal"))
	target_part = str(config.get("target_part", "body"))
	_configure_targeting({
		"range_cells": attack_range_cells,
		"shape": str(config.get("shape", SHAPE_SINGLE)),
		"radius": int(config.get("radius", 0))
	})


func is_preview_valid(preview: Dictionary, context: Dictionary) -> Dictionary:
	var base_validation: Dictionary = super.is_preview_valid(preview, context)
	if not bool(base_validation.get("valid", false)):
		return base_validation
	var target_actor: Node = _resolve_target_actor(preview, context)
	if target_actor == null:
		return {"valid": false, "reason": "missing_target"}
	return {"valid": true, "reason": ""}


func confirm_target(preview: Dictionary, context: Dictionary) -> Dictionary:
	if not bool(preview.get("valid", false)):
		return {"success": false, "reason": str(preview.get("reason", "invalid_preview")), "ability_id": ability_id}
	var attacker: Node = context.get("caster", null) as Node
	var target_actor: Node = _resolve_target_actor(preview, context)
	if attacker == null or target_actor == null:
		return {"success": false, "reason": "missing_attack_participants", "ability_id": ability_id}
	if CombatSystem == null or not CombatSystem.has_method("perform_attack"):
		return {"success": false, "reason": "combat_system_unavailable", "ability_id": ability_id}
	return CombatSystem.perform_attack(attacker, target_actor, attack_type, target_part)


func _resolve_target_actor(preview: Dictionary, context: Dictionary) -> Node:
	var explicit_target: Node = context.get("target_actor", null) as Node
	if explicit_target != null and is_instance_valid(explicit_target):
		var explicit_cell: Vector3i = _resolve_grid_cell_from_node(explicit_target)
		var center_cell: Vector3i = Vector3i.ZERO
		var center_value: Variant = preview.get("center_cell", Vector3i.ZERO)
		if center_value is Vector3i:
			center_cell = center_value
		if explicit_cell == center_cell and _is_hostile(context.get("caster", null) as Node, explicit_target):
			return explicit_target

	var attacker: Node = context.get("caster", null) as Node
	var center: Vector3i = Vector3i.ZERO
	var preview_center: Variant = preview.get("center_cell", Vector3i.ZERO)
	if preview_center is Vector3i:
		center = preview_center
	for candidate in _collect_candidate_targets(attacker):
		if candidate == null or not is_instance_valid(candidate):
			continue
		if _resolve_grid_cell_from_node(candidate) != center:
			continue
		if not _is_hostile(attacker, candidate):
			continue
		return candidate
	return null


func _collect_candidate_targets(attacker: Node) -> Array[Node]:
	var results: Array[Node] = []
	var tree: SceneTree = _resolve_tree(attacker)
	if tree == null:
		return results

	for group_name in ["player", "enemy"]:
		for node_variant in tree.get_nodes_in_group(group_name):
			if node_variant is Node:
				var node: Node = node_variant as Node
				if node == attacker:
					continue
				results.append(node)
	return results


func _resolve_tree(node: Node) -> SceneTree:
	if node != null and is_instance_valid(node):
		return node.get_tree()
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return loop as SceneTree
	return null


func _is_hostile(attacker: Node, target: Node) -> bool:
	if attacker == null or target == null or attacker == target:
		return false
	if TurnSystem != null and TurnSystem.has_method("get_actor_side"):
		var attacker_side: String = str(TurnSystem.get_actor_side(attacker))
		var target_side: String = str(TurnSystem.get_actor_side(target))
		if not attacker_side.is_empty() and not target_side.is_empty():
			if attacker_side == target_side:
				return false
			if attacker_side == "player":
				return target_side == "hostile"
			if target_side == "player":
				return attacker_side == "hostile"
			return true
	if attacker.is_in_group("player"):
		return not target.is_in_group("player")
	if target.is_in_group("player"):
		return true
	return attacker.is_in_group("enemy") != target.is_in_group("enemy")
