extends RefCounted

## 技能运行时层：学习技能、激活资源消耗、目标预览（自身/单体/网格/范围/直线/锥形）、射程/可见性/视线/策略校验与效果修正。
## 无状态规则计算；权威 actor 状态由 simulation 持有，所有读写经 simulation 转发。

const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


func learn_skill(simulation: RefCounted, actor_id: int, skill_id: String, skill_library: Dictionary) -> Dictionary:
	var result: Dictionary = simulation._progression_runner.learn_skill(simulation, simulation._progression_rules, actor_id, skill_id, skill_library)
	if not bool(result.get("success", false)):
		return result
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor != null:
		var skill: Dictionary = simulation._skill_data(str(result.get("skill_id", skill_id)), skill_library)
		var passive_effect: Dictionary = simulation._refresh_passive_skill_effect(actor, str(result.get("skill_id", skill_id)), int(result.get("level", 0)), skill)
		if not passive_effect.is_empty():
			result["passive_effect"] = passive_effect.duplicate(true)
	return result


func preview_skill_target(simulation: RefCounted, actor_id: int, skill_id: String, skill_library: Dictionary, target: Dictionary = {}, topology: Dictionary = {}) -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "unknown_actor", "actor_id": actor_id}
	var skill: Dictionary = simulation._skill_data(skill_id, skill_library)
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": skill_id}
	var activation: Dictionary = simulation._dictionary_or_empty(skill.get("activation", {}))
	var command := {
		"target": target.duplicate(true),
		"topology": simulation._topology_with_runtime_door_states(topology),
	}
	return simulation._skill_target_preview(actor, skill_id, activation, command)


func skill_resource_costs(simulation: RefCounted, activation: Dictionary) -> Array[Dictionary]:
	var source: Variant = activation.get("resource_costs", activation.get("resource_cost", {}))
	var output: Array[Dictionary] = []
	if typeof(source) == TYPE_DICTIONARY:
		var costs: Dictionary = source
		for resource_id in costs.keys():
			var amount: float = max(0.0, float(costs.get(resource_id, 0.0)))
			if amount <= 0.0:
				continue
			output.append({
				"resource": simulation._normalized_resource_id(str(resource_id)),
				"amount": amount,
			})
	elif typeof(source) == TYPE_ARRAY:
		for entry in source:
			var entry_data: Dictionary = simulation._dictionary_or_empty(entry)
			var resource_id: String = simulation._normalized_resource_id(str(entry_data.get("resource", entry_data.get("resource_id", ""))))
			var amount: float = max(0.0, float(entry_data.get("amount", entry_data.get("cost", 0.0))))
			if resource_id.is_empty() or amount <= 0.0:
				continue
			output.append({
				"resource": resource_id,
				"amount": amount,
			})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("resource", "")) < str(b.get("resource", ""))
	)
	return output


func skill_resource_cost_check(simulation: RefCounted, actor: RefCounted, costs: Array[Dictionary]) -> Dictionary:
	for cost in costs:
		var cost_data: Dictionary = simulation._dictionary_or_empty(cost)
		var resource_id: String = simulation._normalized_resource_id(str(cost_data.get("resource", "")))
		var required: float = max(0.0, float(cost_data.get("amount", 0.0)))
		var available: float = simulation._actor_resource_current(actor, resource_id)
		if available + 0.0001 < required:
			return {
				"success": false,
				"reason": "resource_insufficient",
				"resource": resource_id,
				"required_resource": resource_id,
				"required_amount": required,
				"available_amount": available,
				"resource_costs": costs.duplicate(true),
			}
	return {"success": true, "resource_costs": costs.duplicate(true)}


func apply_skill_activation_effect(simulation: RefCounted, actor: RefCounted, skill_id: String, learned_level: int, activation: Dictionary, mode: String) -> Dictionary:
	var effect_definition: Dictionary = simulation._dictionary_or_empty(activation.get("effect", {}))
	if effect_definition.is_empty():
		return {"success": true, "effect": {}, "removed": false, "removed_effects": []}
	var effect_id := "skill:%s" % skill_id
	var active_effects: Array[Dictionary] = []
	var removed_effects: Array[Dictionary] = []
	for effect in actor.active_effects:
		var effect_data: Dictionary = effect.duplicate(true)
		if str(effect_data.get("effect_id", "")) == effect_id:
			removed_effects.append(effect_data)
			continue
		active_effects.append(effect_data)
	var toggled_off: bool = mode == "toggle" and not removed_effects.is_empty()
	if toggled_off:
		actor.active_effects = active_effects
		simulation._emit("skill_effect_removed", {
			"actor_id": actor.actor_id,
			"effect_id": effect_id,
			"skill_id": skill_id,
			"reason": "toggle_off",
			"removed_effects": removed_effects.duplicate(true),
		})
		return {
			"success": true,
			"effect": {},
			"removed": true,
			"removed_effects": removed_effects.duplicate(true),
		}

	var effect: Dictionary = simulation._build_skill_effect(skill_id, learned_level, effect_definition)
	active_effects.append(effect)
	actor.active_effects = active_effects
	simulation._emit("skill_effect_applied", {
		"actor_id": actor.actor_id,
		"effect": effect.duplicate(true),
		"replaced_effects": removed_effects.duplicate(true),
	})
	return {
		"success": true,
		"effect": effect.duplicate(true),
		"removed": false,
		"removed_effects": removed_effects.duplicate(true),
	}


func skill_target_preview(simulation: RefCounted, actor: RefCounted, skill_id: String, activation: Dictionary, command: Dictionary) -> Dictionary:
	var targeting: Dictionary = simulation._skill_targeting_definition(activation)
	var target_kind: String = str(targeting.get("kind", targeting.get("target_kind", targeting.get("shape", "self"))))
	var topology: Dictionary = simulation._topology_with_runtime_door_states(simulation._dictionary_or_empty(command.get("topology", {})))
	match target_kind:
		"self":
			return simulation._skill_self_target_preview(actor, skill_id, targeting)
		"single", "actor", "single_actor":
			return simulation._skill_actor_target_preview(actor, skill_id, targeting, simulation._dictionary_or_empty(command.get("target", {})), topology)
		"grid", "point":
			return simulation._skill_grid_target_preview(actor, skill_id, targeting, simulation._dictionary_or_empty(command.get("target", {})), topology)
		"radius", "circle":
			return simulation._skill_radius_target_preview(actor, skill_id, targeting, simulation._dictionary_or_empty(command.get("target", {})), topology)
		"line":
			return simulation._skill_line_target_preview(actor, skill_id, targeting, simulation._dictionary_or_empty(command.get("target", {})), topology)
		"cone":
			return simulation._skill_cone_target_preview(actor, skill_id, targeting, simulation._dictionary_or_empty(command.get("target", {})), topology)
	return {
		"success": false,
		"reason": "skill_target_shape_unknown",
		"skill_id": skill_id,
		"target_shape": target_kind,
	}


func skill_targeting_definition(simulation: RefCounted, activation: Dictionary) -> Dictionary:
	var targeting: Dictionary = simulation._dictionary_or_empty(activation.get("targeting", {})).duplicate(true)
	if targeting.is_empty():
		targeting = simulation._dictionary_or_empty(activation.get("target", {})).duplicate(true)
	if targeting.is_empty():
		targeting = {
			"kind": "self",
			"policy": "self",
		}
	if not targeting.has("policy"):
		targeting["policy"] = simulation._default_skill_target_policy(str(targeting.get("kind", targeting.get("shape", "self"))))
	return targeting


func skill_self_target_preview(_simulation: RefCounted, actor: RefCounted, skill_id: String, _targeting: Dictionary) -> Dictionary:
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "self",
		"target_policy": "self",
		"target": {
			"target_type": "actor",
			"actor_id": actor.actor_id,
			"grid_position": actor.grid_position.to_dictionary(),
		},
		"center": actor.grid_position.to_dictionary(),
		"affected_actor_ids": [actor.actor_id],
		"affected_cells": [actor.grid_position.to_dictionary()],
		"friendly_fire": false,
	}


func skill_actor_target_preview(simulation: RefCounted, actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var target_actor_id: int = int(target.get("actor_id", target.get("target_actor_id", 0)))
	var target_actor: RefCounted = simulation.actor_registry.get_actor(target_actor_id)
	if target_actor == null:
		return {"success": false, "reason": "skill_target_actor_missing", "skill_id": skill_id, "target_actor_id": target_actor_id}
	var policy_result: Dictionary = simulation._skill_actor_policy_check(actor, target_actor, str(targeting.get("policy", "any_actor")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		policy_result["target_actor_id"] = target_actor_id
		return policy_result
	var range_result: Dictionary = simulation._skill_range_check(actor, target_actor.grid_position.to_dictionary(), targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		range_result["target_actor_id"] = target_actor_id
		return range_result
	var visibility_result: Dictionary = simulation._skill_visibility_check(actor, target_actor.grid_position.to_dictionary())
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		visibility_result["target_actor_id"] = target_actor_id
		return visibility_result
	var los_result: Dictionary = simulation._skill_los_check(actor, target_actor.grid_position.to_dictionary(), targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		los_result["target_actor_id"] = target_actor_id
		return los_result
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "single",
		"target_policy": str(targeting.get("policy", "any_actor")),
		"target": {
			"target_type": "actor",
			"actor_id": target_actor_id,
			"grid_position": target_actor.grid_position.to_dictionary(),
		},
		"center": target_actor.grid_position.to_dictionary(),
		"affected_actor_ids": [target_actor_id],
		"affected_cells": [target_actor.grid_position.to_dictionary()],
		"friendly_fire": not simulation._can_attack(actor, target_actor) and actor.actor_id != target_actor.actor_id,
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
	}


func skill_grid_target_preview(simulation: RefCounted, actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var grid: Dictionary = simulation._skill_target_grid_from(target)
	if grid.is_empty():
		return {"success": false, "reason": "skill_target_grid_missing", "skill_id": skill_id}
	var policy_result: Dictionary = simulation._skill_grid_policy_check(grid, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = simulation._skill_range_check(actor, grid, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = simulation._skill_visibility_check(actor, grid)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = simulation._skill_los_check(actor, grid, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "grid",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"target": {
			"target_type": "grid",
			"grid": grid.duplicate(true),
		},
		"center": grid.duplicate(true),
		"affected_actor_ids": simulation._actor_ids_at_cells([grid]),
		"affected_cells": [grid.duplicate(true)],
		"friendly_fire": simulation._cells_include_non_hostile(actor, [grid]),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
	}


func skill_radius_target_preview(simulation: RefCounted, actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var center: Dictionary = simulation._skill_target_grid_from(target)
	if center.is_empty():
		center = actor.grid_position.to_dictionary()
	var policy_result: Dictionary = simulation._skill_grid_policy_check(center, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = simulation._skill_range_check(actor, center, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = simulation._skill_visibility_check(actor, center)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = simulation._skill_los_check(actor, center, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	var radius: int = max(0, int(targeting.get("radius", targeting.get("aoe_radius", 0))))
	var cells: Array[Dictionary] = simulation._skill_radius_cells(center, radius, topology, targeting)
	var affected_actor_ids: Array[int] = simulation._actor_ids_at_cells(cells)
	var filtered_actor_ids: Array[int] = simulation._filter_actor_ids_by_policy(actor, affected_actor_ids, str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))))
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "radius",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"affected_policy": str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))),
		"target": {
			"target_type": "grid",
			"grid": center.duplicate(true),
		},
		"center": center.duplicate(true),
		"radius": radius,
		"affected_actor_ids": filtered_actor_ids,
		"affected_cells": cells,
		"friendly_fire": simulation._actor_ids_include_non_hostile(actor, filtered_actor_ids),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
		"respect_los": simulation._skill_respects_los(targeting),
	}


func skill_line_target_preview(simulation: RefCounted, actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var target_grid: Dictionary = simulation._skill_target_grid_from(target)
	if target_grid.is_empty():
		return {"success": false, "reason": "skill_target_grid_missing", "skill_id": skill_id}
	var policy_result: Dictionary = simulation._skill_grid_policy_check(target_grid, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = simulation._skill_range_check(actor, target_grid, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = simulation._skill_visibility_check(actor, target_grid)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = simulation._skill_los_check(actor, target_grid, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	var max_length: int = int(targeting.get("length", targeting.get("max_length", range_result.get("range", -1))))
	if max_length < 0:
		max_length = int(range_result.get("distance", 0))
	var cells: Array[Dictionary] = simulation._skill_line_cells(actor.grid_position.to_dictionary(), target_grid, max_length, topology, targeting)
	var affected_actor_ids: Array[int] = simulation._actor_ids_at_cells(cells)
	var filtered_actor_ids: Array[int] = simulation._filter_actor_ids_by_policy(actor, affected_actor_ids, str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))))
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "line",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"affected_policy": str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))),
		"target": {
			"target_type": "grid",
			"grid": target_grid.duplicate(true),
		},
		"origin": actor.grid_position.to_dictionary(),
		"center": target_grid.duplicate(true),
		"length": max_length,
		"affected_actor_ids": filtered_actor_ids,
		"affected_cells": cells,
		"friendly_fire": simulation._actor_ids_include_non_hostile(actor, filtered_actor_ids),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
		"respect_los": simulation._skill_respects_los(targeting),
	}


func skill_cone_target_preview(simulation: RefCounted, actor: RefCounted, skill_id: String, targeting: Dictionary, target: Dictionary, topology: Dictionary) -> Dictionary:
	var target_grid: Dictionary = simulation._skill_target_grid_from(target)
	if target_grid.is_empty():
		return {"success": false, "reason": "skill_target_grid_missing", "skill_id": skill_id}
	var policy_result: Dictionary = simulation._skill_grid_policy_check(target_grid, str(targeting.get("policy", "any_grid")))
	if not bool(policy_result.get("success", false)):
		policy_result["skill_id"] = skill_id
		return policy_result
	var range_result: Dictionary = simulation._skill_range_check(actor, target_grid, targeting)
	if not bool(range_result.get("success", false)):
		range_result["skill_id"] = skill_id
		return range_result
	var visibility_result: Dictionary = simulation._skill_visibility_check(actor, target_grid)
	if not bool(visibility_result.get("success", false)):
		visibility_result["skill_id"] = skill_id
		return visibility_result
	var los_result: Dictionary = simulation._skill_los_check(actor, target_grid, targeting, topology)
	if not bool(los_result.get("success", false)):
		los_result["skill_id"] = skill_id
		return los_result
	var length: int = int(targeting.get("length", targeting.get("max_length", range_result.get("range", -1))))
	if length < 0:
		length = int(range_result.get("distance", 0))
	var width: int = max(0, int(targeting.get("width", targeting.get("half_width", max(1, int(ceil(float(length) / 2.0)))))))
	var cells: Array[Dictionary] = simulation._skill_cone_cells(actor.grid_position.to_dictionary(), target_grid, length, width, topology, targeting)
	var affected_actor_ids: Array[int] = simulation._actor_ids_at_cells(cells)
	var filtered_actor_ids: Array[int] = simulation._filter_actor_ids_by_policy(actor, affected_actor_ids, str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))))
	return {
		"success": true,
		"skill_id": skill_id,
		"target_shape": "cone",
		"target_policy": str(targeting.get("policy", "any_grid")),
		"affected_policy": str(targeting.get("affected_policy", targeting.get("policy", "any_actor"))),
		"target": {
			"target_type": "grid",
			"grid": target_grid.duplicate(true),
		},
		"origin": actor.grid_position.to_dictionary(),
		"center": target_grid.duplicate(true),
		"length": length,
		"width": width,
		"affected_actor_ids": filtered_actor_ids,
		"affected_cells": cells,
		"friendly_fire": simulation._actor_ids_include_non_hostile(actor, filtered_actor_ids),
		"range": int(range_result.get("range", 0)),
		"distance": int(range_result.get("distance", 0)),
		"line_of_sight": bool(los_result.get("line_of_sight", true)),
		"respect_los": simulation._skill_respects_los(targeting),
	}


func skill_range_check(simulation: RefCounted, actor: RefCounted, target_grid: Dictionary, targeting: Dictionary) -> Dictionary:
	if actor.grid_position.y != int(target_grid.get("y", actor.grid_position.y)):
		return {"success": false, "reason": "skill_target_invalid_level", "target_grid": target_grid.duplicate(true)}
	var distance: int = simulation._grid_distance(actor.grid_position, GridCoord.from_dictionary(target_grid))
	var max_range: int = int(targeting.get("range", targeting.get("max_range", -1)))
	if max_range >= 0 and distance > max_range:
		return {
			"success": false,
			"reason": "skill_target_out_of_range",
			"range": max_range,
			"distance": distance,
			"target_grid": target_grid.duplicate(true),
		}
	return {"success": true, "range": max_range, "distance": distance}


func skill_visibility_check(simulation: RefCounted, actor: RefCounted, target_grid: Dictionary) -> Dictionary:
	if actor == null:
		return {"success": false, "reason": "actor_missing"}
	if not simulation.has_active_actor_vision(actor.actor_id):
		return {"success": true, "visibility_checked": false}
	var normalized_grid: Dictionary = {
		"x": int(target_grid.get("x", 0)),
		"y": int(target_grid.get("y", actor.grid_position.y)),
		"z": int(target_grid.get("z", 0)),
	}
	if simulation.is_cell_visible_to_actor(actor.actor_id, normalized_grid):
		return {"success": true, "visibility_checked": true}
	return {
		"success": false,
		"reason": "target_not_visible",
		"skill_target_not_visible": true,
		"actor_id": actor.actor_id,
		"target_grid": normalized_grid,
		"actor_grid": actor.grid_position.to_dictionary(),
	}


func skill_los_check(simulation: RefCounted, actor: RefCounted, target_grid: Dictionary, targeting: Dictionary, topology: Dictionary) -> Dictionary:
	if not simulation._skill_requires_center_los(targeting):
		return {"success": true, "line_of_sight": false, "line_of_sight_required": false}
	if topology.is_empty():
		return {"success": true, "line_of_sight": true, "line_of_sight_required": true}
	var target_coord: RefCounted = GridCoord.from_dictionary(target_grid)
	if actor.grid_position.y != target_coord.y:
		return {
			"success": false,
			"reason": "skill_target_invalid_level",
			"target_grid": target_coord.to_dictionary(),
		}
	if not simulation._vision_rules.has_line_of_sight(actor.grid_position.to_dictionary(), target_coord.to_dictionary(), topology):
		return {
			"success": false,
			"reason": "skill_target_blocked_by_los",
			"target_grid": target_coord.to_dictionary(),
			"origin": actor.grid_position.to_dictionary(),
			"line_of_sight_required": true,
		}
	return {"success": true, "line_of_sight": true, "line_of_sight_required": true}


func skill_requires_center_los(_simulation: RefCounted, targeting: Dictionary) -> bool:
	if targeting.has("requires_los"):
		return bool(targeting.get("requires_los", true))
	if targeting.has("line_of_sight"):
		return bool(targeting.get("line_of_sight", true))
	return true


func skill_respects_los(_simulation: RefCounted, targeting: Dictionary) -> bool:
	if targeting.has("respect_los"):
		return bool(targeting.get("respect_los", true))
	if targeting.has("aoe_respects_los"):
		return bool(targeting.get("aoe_respects_los", true))
	return true


func skill_actor_policy_check(simulation: RefCounted, actor: RefCounted, target_actor: RefCounted, policy: String) -> Dictionary:
	match policy:
		"self":
			if actor.actor_id != target_actor.actor_id:
				return {"success": false, "reason": "skill_target_not_self", "target_policy": policy}
		"hostile_only", "hostile":
			if not simulation._can_attack(actor, target_actor):
				return {"success": false, "reason": "skill_target_not_hostile", "target_policy": policy}
		"ally_only", "ally":
			if actor.actor_id != target_actor.actor_id and simulation._can_attack(actor, target_actor):
				return {"success": false, "reason": "skill_target_not_ally", "target_policy": policy}
		"any_actor", "any":
			pass
		_:
			return {"success": false, "reason": "skill_target_policy_unknown", "target_policy": policy}
	return {"success": true}


func skill_grid_policy_check(simulation: RefCounted, grid: Dictionary, policy: String) -> Dictionary:
	match policy:
		"empty_grid":
			if not simulation._actor_ids_at_cells([grid]).is_empty():
				return {"success": false, "reason": "skill_target_grid_occupied", "target_policy": policy, "target_grid": grid.duplicate(true)}
		"any_grid", "any", "any_actor", "hostile_only", "ally_only":
			pass
		_:
			return {"success": false, "reason": "skill_target_policy_unknown", "target_policy": policy}
	return {"success": true}


func skill_target_grid_from(simulation: RefCounted, target: Dictionary) -> Dictionary:
	var grid: Dictionary = simulation._dictionary_or_empty(target.get("grid", target.get("target_position", target.get("grid_position", {}))))
	if not grid.is_empty():
		return {
			"x": int(grid.get("x", 0)),
			"y": int(grid.get("y", 0)),
			"z": int(grid.get("z", 0)),
		}
	var actor_id: int = int(target.get("actor_id", target.get("target_actor_id", 0)))
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor != null:
		return actor.grid_position.to_dictionary()
	return {}


func skill_radius_cells(simulation: RefCounted, center: Dictionary, radius: int, topology: Dictionary, targeting: Dictionary = {}) -> Array[Dictionary]:
	var center_coord: RefCounted = GridCoord.from_dictionary(center)
	if radius <= 0:
		return [center_coord.to_dictionary()]
	var bounds: Dictionary = simulation._dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = max(int(bounds.get("min_x", center_coord.x - radius)), center_coord.x - radius)
	var max_x: int = min(int(bounds.get("max_x", center_coord.x + radius)), center_coord.x + radius)
	var min_z: int = max(int(bounds.get("min_z", center_coord.z - radius)), center_coord.z - radius)
	var max_z: int = min(int(bounds.get("max_z", center_coord.z + radius)), center_coord.z + radius)
	var cells: Array[Dictionary] = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var distance: int = abs(x - center_coord.x) + abs(z - center_coord.z)
			if distance <= radius:
				var cell := {"x": x, "y": center_coord.y, "z": z}
				if simulation._skill_radius_cell_visible_from_center(center_coord, cell, topology, targeting):
					cells.append(cell)
	return simulation._sorted_grid_cells(cells)


func skill_radius_cell_visible_from_center(simulation: RefCounted, center_coord: RefCounted, cell: Dictionary, topology: Dictionary, targeting: Dictionary) -> bool:
	if not simulation._skill_respects_los(targeting):
		return true
	if topology.is_empty():
		return true
	var cell_coord: RefCounted = GridCoord.from_dictionary(cell)
	if center_coord.y != cell_coord.y:
		return false
	return simulation._vision_rules.has_line_of_sight(center_coord.to_dictionary(), cell_coord.to_dictionary(), topology)


func skill_line_cells(simulation: RefCounted, origin: Dictionary, target: Dictionary, max_length: int, topology: Dictionary, targeting: Dictionary) -> Array[Dictionary]:
	var origin_coord: RefCounted = GridCoord.from_dictionary(origin)
	var target_coord: RefCounted = GridCoord.from_dictionary(target)
	if origin_coord.y != target_coord.y:
		return []
	var output: Array[Dictionary] = []
	var x: int = origin_coord.x
	var z: int = origin_coord.z
	var dx: int = abs(target_coord.x - x)
	var dz: int = abs(target_coord.z - z)
	var sx: int = 1 if x < target_coord.x else -1
	var sz: int = 1 if z < target_coord.z else -1
	var err: int = dx - dz
	while not (x == target_coord.x and z == target_coord.z):
		var e2: int = err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
		var cell := {"x": x, "y": origin_coord.y, "z": z}
		var distance: int = simulation._grid_distance(origin_coord, GridCoord.from_dictionary(cell))
		if max_length >= 0 and distance > max_length:
			break
		if simulation._skill_respects_los(targeting) and not simulation._skill_line_cell_visible_from_origin(origin_coord, cell, topology):
			break
		output.append(cell)
	return simulation._sorted_grid_cells(output)


func skill_line_cell_visible_from_origin(simulation: RefCounted, origin_coord: RefCounted, cell: Dictionary, topology: Dictionary) -> bool:
	if topology.is_empty():
		return true
	var cell_coord: RefCounted = GridCoord.from_dictionary(cell)
	if origin_coord.y != cell_coord.y:
		return false
	return simulation._vision_rules.has_line_of_sight(origin_coord.to_dictionary(), cell_coord.to_dictionary(), topology)


func skill_cone_cells(simulation: RefCounted, origin: Dictionary, target: Dictionary, length: int, width: int, topology: Dictionary, targeting: Dictionary) -> Array[Dictionary]:
	var origin_coord: RefCounted = GridCoord.from_dictionary(origin)
	var target_coord: RefCounted = GridCoord.from_dictionary(target)
	if origin_coord.y != target_coord.y:
		return []
	var direction_x: int = signi(target_coord.x - origin_coord.x)
	var direction_z: int = signi(target_coord.z - origin_coord.z)
	if direction_x == 0 and direction_z == 0:
		return []
	var normalized_length: int = max(1, length)
	var normalized_width: int = max(0, width)
	var bounds: Dictionary = simulation._dictionary_or_empty(topology.get("bounds", {}))
	var min_x: int = max(int(bounds.get("min_x", origin_coord.x - normalized_length)), origin_coord.x - normalized_length)
	var max_x: int = min(int(bounds.get("max_x", origin_coord.x + normalized_length)), origin_coord.x + normalized_length)
	var min_z: int = max(int(bounds.get("min_z", origin_coord.z - normalized_length)), origin_coord.z - normalized_length)
	var max_z: int = min(int(bounds.get("max_z", origin_coord.z + normalized_length)), origin_coord.z + normalized_length)
	var cells: Array[Dictionary] = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			if x == origin_coord.x and z == origin_coord.z:
				continue
			var dx: int = x - origin_coord.x
			var dz: int = z - origin_coord.z
			var forward: int = dx * direction_x + dz * direction_z
			if forward <= 0 or forward > normalized_length:
				continue
			var lateral: int = abs(dx * direction_z - dz * direction_x)
			var allowed_width: int = int(ceil(float(max(1, forward)) * float(normalized_width) / float(normalized_length)))
			if lateral > allowed_width:
				continue
			var cell := {"x": x, "y": origin_coord.y, "z": z}
			if simulation._skill_line_cell_visible_from_origin(origin_coord, cell, topology) or not simulation._skill_respects_los(targeting):
				cells.append(cell)
	return simulation._sorted_grid_cells(cells)


func skill_effect_modifiers(simulation: RefCounted, modifier_definitions: Dictionary, learned_level: int) -> Dictionary:
	var output: Dictionary = {}
	for key in modifier_definitions.keys():
		var definition: Dictionary = simulation._dictionary_or_empty(modifier_definitions.get(key, {}))
		var per_level: float = float(definition.get("per_level", 0.0))
		var value: float = 0.0
		if definition.has("base"):
			value = float(definition.get("base", 0.0)) + per_level * max(0, learned_level - 1)
		else:
			value = per_level * max(1, learned_level)
		var max_value: float = float(definition.get("max_value", 0.0))
		if max_value > 0.0:
			value = min(value, max_value)
		output[str(key)] = value
	return output


func skill_data(simulation: RefCounted, skill_id: String, skills: Dictionary) -> Dictionary:
	var record: Dictionary = simulation._dictionary_or_empty(skills.get(skill_id, {}))
	if record.is_empty():
		return {}
	return simulation._dictionary_or_empty(record.get("data", record))
