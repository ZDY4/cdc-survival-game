extends RefCounted

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const ReasonCatalog = preload("res://scripts/ui/snapshots/reason_catalog.gd")

var registry: RefCounted
var reason_catalog := ReasonCatalog.new()


func _init(p_registry: RefCounted = null) -> void:
	registry = p_registry


func build(runtime_snapshot: Dictionary, world_snapshot: Dictionary, selected_target: Dictionary = {}) -> Dictionary:
	var player := _player_actor(runtime_snapshot)
	var prompt := _prompt_summary(selected_target)
	return {
		"world": {
			"map_id": runtime_snapshot.get("active_map_id", ""),
			"actor_count": runtime_snapshot.get("actors", []).size(),
			"event_count": runtime_snapshot.get("events", []).size(),
		},
		"player": {
			"actor_id": int(player.get("actor_id", 0)),
			"display_name": player.get("display_name", ""),
			"grid_position": player.get("grid_position", {}),
			"inventory": player.get("inventory", {}),
			"active_dialogue_id": player.get("active_dialogue_id", ""),
		},
		"map": {
			"object_count": world_snapshot.get("map", {}).get("object_count", 0),
			"pickup_count": world_snapshot.get("map", {}).get("pickup_objects", []).size(),
			"trigger_count": world_snapshot.get("map", {}).get("trigger_objects", []).size(),
			"interactive_count": world_snapshot.get("map", {}).get("interactive_objects", []).size(),
		},
		"status_badges": _status_badges(runtime_snapshot, player),
		"combat_hud": _combat_hud_summary(runtime_snapshot, player),
		"interaction": prompt,
		"hotbar": _hotbar_summary(runtime_snapshot, player),
		"hotbar_group_labels": _dictionary_or_empty(runtime_snapshot.get("hotbar_group_labels", {})).duplicate(true),
		"event_feedback": _event_feedback(runtime_snapshot),
		"feedback_toasts": _feedback_toasts(runtime_snapshot),
		"tracked_quest": {"active": false, "quest_id": ""},
	}


func _player_actor(runtime_snapshot: Dictionary) -> Dictionary:
	for actor in runtime_snapshot.get("actors", []):
		var actor_data: Dictionary = actor
		if actor_data.get("kind", "") == "player":
			return actor_data
	return {}


func _prompt_summary(selected_target: Dictionary) -> Dictionary:
	if selected_target.is_empty():
		return {
			"has_target": false,
			"target_name": "",
			"target_kind": "",
			"target_type": "",
			"primary_option_id": "",
			"primary_option_kind": "",
			"action_label": "",
			"ap_cost": 0.0,
			"interaction_range": 0,
			"target_distance": -1,
			"requires_approach": false,
			"options": [],
			"disabled_options": [],
		}
	return {
		"has_target": true,
		"target_name": selected_target.get("target_name", selected_target.get("display_name", "")),
		"target_kind": selected_target.get("target_kind", ""),
		"target_type": selected_target.get("target_type", ""),
		"primary_option_id": selected_target.get("primary_option_id", ""),
		"primary_option_kind": selected_target.get("primary_option_kind", ""),
		"action_label": selected_target.get("action_label", ""),
		"ap_cost": float(selected_target.get("ap_cost", 0.0)),
		"interaction_range": int(selected_target.get("interaction_range", 1)),
		"target_distance": int(selected_target.get("target_distance", -1)),
		"requires_approach": bool(selected_target.get("requires_approach", false)),
		"options": selected_target.get("options", []),
		"disabled_options": _disabled_option_summaries(selected_target.get("disabled_options", [])),
	}


func _disabled_option_summaries(options: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in _array_or_empty(options):
		var option: Dictionary = _dictionary_or_empty(value).duplicate(true)
		if option.is_empty():
			continue
		var reason := str(option.get("disabled_reason", ""))
		option["disabled_reason_text"] = reason_catalog.disabled_text_for(reason) if not reason.is_empty() else ""
		output.append(option)
	return output


func _status_badges(runtime_snapshot: Dictionary, player: Dictionary) -> Array[Dictionary]:
	var combat: Dictionary = _dictionary_or_empty(player.get("combat", {}))
	var progression: Dictionary = _dictionary_or_empty(player.get("progression", {}))
	var turn_state: Dictionary = _dictionary_or_empty(runtime_snapshot.get("turn_state", {}))
	var combat_state: Dictionary = _dictionary_or_empty(runtime_snapshot.get("combat_state", {}))
	return [
		{
			"id": "hp",
			"label": "HP",
			"value": "%s/%s" % [
				_number_text(float(combat.get("hp", 0.0))),
				_number_text(float(combat.get("max_hp", 0.0))),
			],
		},
		{
			"id": "ap",
			"label": "AP",
			"value": _number_text(float(player.get("ap", 0.0))),
		},
		{
			"id": "level",
			"label": "Lv",
			"value": str(int(progression.get("level", 1))),
		},
		{
			"id": "round",
			"label": "Round",
			"value": str(int(turn_state.get("round", 0))),
		},
		{
			"id": "phase",
			"label": "Phase",
			"value": str(turn_state.get("phase", "")),
		},
		{
			"id": "combat",
			"label": "Combat",
			"value": "on" if bool(combat_state.get("active", false)) else "off",
		},
	]


func _combat_hud_summary(runtime_snapshot: Dictionary, player: Dictionary) -> Dictionary:
	var turn_state: Dictionary = _dictionary_or_empty(runtime_snapshot.get("turn_state", {}))
	var combat_state: Dictionary = _dictionary_or_empty(runtime_snapshot.get("combat_state", {}))
	var active_actor_id := int(turn_state.get("active_actor_id", 0))
	var active_actor := _actor_by_id(runtime_snapshot, active_actor_id)
	var current_combat_actor_id := int(combat_state.get("current_combat_actor_id", active_actor_id))
	var current_combat_actor := _actor_by_id(runtime_snapshot, current_combat_actor_id)
	var next_combat_actor_id := int(combat_state.get("next_combat_actor_id", 0))
	var next_combat_actor := _actor_by_id(runtime_snapshot, next_combat_actor_id)
	var player_actor_id := int(player.get("actor_id", 0))
	var target_preview := _combat_target_preview(runtime_snapshot)
	return {
		"active": bool(combat_state.get("active", false)),
		"round": int(turn_state.get("round", 0)),
		"combat_round": int(combat_state.get("round", 0)),
		"phase": str(turn_state.get("phase", "")),
		"active_actor_id": active_actor_id,
		"active_actor_name": str(active_actor.get("display_name", "")),
		"active_actor_kind": str(active_actor.get("kind", "")),
		"current_combat_actor_id": current_combat_actor_id,
		"current_combat_actor_name": str(current_combat_actor.get("display_name", "")),
		"next_combat_actor_id": next_combat_actor_id,
		"next_combat_actor_name": str(next_combat_actor.get("display_name", "")),
		"turn_order": _array_or_empty(combat_state.get("turn_order", [])).duplicate(true),
		"initiative": _array_or_empty(combat_state.get("initiative", [])).duplicate(true),
		"player_turn": active_actor_id == player_actor_id and str(turn_state.get("phase", "")) == "player",
		"enemy_count": _hostile_actor_count(runtime_snapshot),
		"participant_count": _array_or_empty(combat_state.get("participants", [])).size(),
		"turns_without_hostile_player_sight": int(combat_state.get("turns_without_hostile_player_sight", 0)),
		"target_preview": target_preview,
	}


func _combat_target_preview(runtime_snapshot: Dictionary) -> Dictionary:
	var preview: Dictionary = _dictionary_or_empty(runtime_snapshot.get("target_preview", {}))
	var target: Dictionary = _dictionary_or_empty(preview.get("target", {}))
	var target_actor_id := int(preview.get("target_actor_id", target.get("actor_id", 0)))
	if target_actor_id <= 0:
		return {}
	var target_actor := _actor_by_id(runtime_snapshot, target_actor_id)
	var target_name := str(preview.get("target_name", target.get("target_name", ""))).strip_edges()
	if target_name.is_empty():
		target_name = str(target_actor.get("display_name", ""))
	var output := {
		"target_actor_id": target_actor_id,
		"target_name": target_name,
		"target_side": str(target_actor.get("side", preview.get("target_side", ""))),
		"can_attack": bool(preview.get("can_attack", preview.get("success", false))),
		"reason": str(preview.get("reason", "")),
		"distance": int(preview.get("distance", -1)),
		"range": int(preview.get("range", preview.get("attack_range", -1))),
		"ap_cost": float(preview.get("ap_cost", 0.0)),
		"ap_available": float(preview.get("ap_available", 0.0)),
		"hit_chance": float(preview.get("hit_chance", -1.0)),
		"crit_chance": float(preview.get("crit_chance", -1.0)),
		"estimated_damage": float(preview.get("estimated_damage", preview.get("damage", -1.0))),
		"minimum_damage": float(preview.get("minimum_damage", -1.0)),
		"maximum_damage": float(preview.get("maximum_damage", -1.0)),
	}
	var combat: Dictionary = _dictionary_or_empty(target_actor.get("combat", {}))
	if not combat.is_empty():
		output["target_hp"] = float(combat.get("hp", 0.0))
		output["target_max_hp"] = float(combat.get("max_hp", 0.0))
	return output


func _hostile_actor_count(runtime_snapshot: Dictionary) -> int:
	var count := 0
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if _actor_defeated(actor_data):
			continue
		var side := str(actor_data.get("side", ""))
		var kind := str(actor_data.get("kind", ""))
		if side == "hostile" or kind == "enemy":
			count += 1
	return count


func _actor_by_id(runtime_snapshot: Dictionary, actor_id: int) -> Dictionary:
	if actor_id <= 0:
		return {}
	for actor in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


func _actor_defeated(actor: Dictionary) -> bool:
	var combat: Dictionary = _dictionary_or_empty(actor.get("combat", {}))
	if combat.is_empty():
		return false
	return float(combat.get("hp", 1.0)) <= 0.0


func _hotbar_summary(runtime_snapshot: Dictionary, player: Dictionary) -> Array[Dictionary]:
	var hotbar: Dictionary = _dictionary_or_empty(runtime_snapshot.get("hotbar", {}))
	var group_id := str(runtime_snapshot.get("active_hotbar_group", "group_1"))
	var group_labels: Dictionary = _dictionary_or_empty(runtime_snapshot.get("hotbar_group_labels", {}))
	var player_ap: float = float(player.get("ap", 0.0))
	var player_resources: Dictionary = _dictionary_or_empty(_dictionary_or_empty(player.get("combat", {})).get("resources", {}))
	var player_inventory: Dictionary = _dictionary_or_empty(player.get("inventory", {}))
	var output: Array[Dictionary] = []
	for slot_index in range(1, 11):
		var slot_id := "slot_%d" % slot_index
		var slot_data: Dictionary = _dictionary_or_empty(hotbar.get(slot_id, {}))
		var kind := str(slot_data.get("kind", ""))
		var skill_id := str(slot_data.get("skill_id", ""))
		var item_id := str(slot_data.get("item_id", ""))
		var entry_id := item_id if kind == "item" else skill_id
		var use_state: Dictionary = _hotbar_use_state(kind, skill_id, item_id, slot_data, player_ap, player_resources, player_inventory)
		output.append({
			"slot_id": slot_id,
			"group_id": group_id,
			"group_label": _hotbar_group_label(group_id, group_labels),
			"key": "0" if slot_index == 10 else str(slot_index),
			"kind": kind,
			"skill_id": skill_id,
			"item_id": item_id,
			"label": _hotbar_label(kind, entry_id),
			"icon_asset": _hotbar_icon_asset(kind, skill_id, item_id),
			"cooldown_remaining": float(slot_data.get("cooldown_remaining", 0.0)),
			"ap_cost": float(use_state.get("ap_cost", 0.0)),
			"resource_costs": _array_or_empty(use_state.get("resource_costs", [])).duplicate(true),
			"effect_summary": _array_or_empty(use_state.get("effect_summary", [])).duplicate(true),
			"item_count": int(use_state.get("item_count", 0)),
			"can_use": bool(use_state.get("can_use", not (slot_data.is_empty() or entry_id.is_empty()))),
			"use_reason": str(use_state.get("reason", "")),
			"missing_resource": _dictionary_or_empty(use_state.get("missing_resource", {})).duplicate(true),
			"empty": slot_data.is_empty() or entry_id.is_empty(),
		})
	return output


func _hotbar_group_label(group_id: String, group_labels: Dictionary = {}) -> String:
	var configured_label := str(group_labels.get(group_id, "")).strip_edges()
	if not configured_label.is_empty():
		return configured_label
	var value := group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if value.is_valid_int():
		return "G%d" % int(value)
	return group_id


func _hotbar_use_state(kind: String, skill_id: String, item_id: String, slot_data: Dictionary, player_ap: float, resources: Dictionary, inventory: Dictionary) -> Dictionary:
	if kind == "skill":
		return _hotbar_skill_state(skill_id, slot_data, player_ap, resources)
	if kind == "item":
		return _hotbar_item_state(item_id, player_ap, inventory)
	return {"can_use": true, "reason": "available"}


func _hotbar_skill_state(skill_id: String, slot_data: Dictionary, player_ap: float, resources: Dictionary) -> Dictionary:
	if skill_id.is_empty():
		return {"can_use": false, "reason": "skill_missing"}
	var skill: Dictionary = _skill_data(skill_id)
	if skill.is_empty():
		return {"can_use": false, "reason": "unknown_skill"}
	var activation: Dictionary = _dictionary_or_empty(skill.get("activation", {}))
	var ap_cost: float = float(activation.get("ap_cost", 0.0))
	var resource_costs: Array[Dictionary] = _resource_costs(activation)
	var cooldown: float = float(slot_data.get("cooldown_remaining", 0.0))
	if cooldown > 0.0:
		return {
			"can_use": false,
			"reason": "cooldown",
			"cooldown_remaining": cooldown,
			"ap_cost": ap_cost,
			"resource_costs": resource_costs.duplicate(true),
		}
	if player_ap + 0.0001 < ap_cost:
		return {
			"can_use": false,
			"reason": "ap_insufficient",
			"ap_cost": ap_cost,
			"available_ap": player_ap,
			"resource_costs": resource_costs.duplicate(true),
		}
	var resource_check: Dictionary = _resource_cost_check(resource_costs, resources)
	if not bool(resource_check.get("success", false)):
		return {
			"can_use": false,
			"reason": "resource_insufficient",
			"ap_cost": ap_cost,
			"resource_costs": resource_costs.duplicate(true),
			"missing_resource": resource_check.duplicate(true),
		}
	return {
		"can_use": true,
		"reason": "available",
		"ap_cost": ap_cost,
		"resource_costs": resource_costs.duplicate(true),
	}


func _hotbar_item_state(item_id: String, player_ap: float, inventory: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {"can_use": false, "reason": "item_missing"}
	var item: Dictionary = _item_data(item_id)
	if item.is_empty():
		return {"can_use": false, "reason": "unknown_item", "item_count": 0}
	var count: int = int(inventory.get(item_id, 0))
	if count <= 0:
		return {"can_use": false, "reason": "not_enough_items", "item_count": count}
	var usable: Dictionary = _fragment_by_kind(item, "usable")
	if usable.is_empty():
		return {"can_use": false, "reason": "item_not_usable", "item_count": count}
	if not _is_item_use_allowed(item):
		return {"can_use": false, "reason": "item_use_forbidden", "item_count": count}
	var ap_cost: float = max(1.0, ceil(float(usable.get("use_time", 1.0))))
	var effect_summary: Array[String] = _item_effect_summary(usable)
	if player_ap + 0.0001 < ap_cost:
		return {
			"can_use": false,
			"reason": "ap_insufficient_use_item",
			"ap_cost": ap_cost,
			"item_count": count,
			"available_ap": player_ap,
			"effect_summary": effect_summary.duplicate(),
		}
	return {
		"can_use": true,
		"reason": "available",
		"ap_cost": ap_cost,
		"item_count": count,
		"effect_summary": effect_summary.duplicate(),
	}


func _hotbar_icon_asset(kind: String, skill_id: String, item_id: String) -> Dictionary:
	if kind == "skill":
		var skill: Dictionary = _skill_data(skill_id)
		return AssetPathResolver.resolve_media_asset(str(skill.get("icon", "")), "skill")
	if kind == "item":
		var item: Dictionary = _item_data(item_id)
		return AssetPathResolver.resolve_media_asset(str(item.get("icon_path", "")), "item")
	return AssetPathResolver.resolve_media_asset("", "generic")


func _skill_data(skill_id: String) -> Dictionary:
	if registry == null or skill_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(registry.get_library("skills").get(skill_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _item_data(item_id: String) -> Dictionary:
	if registry == null or item_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _effect_data(effect_id: String) -> Dictionary:
	if registry == null or effect_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(registry.get_library("json").get(effect_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func _item_effect_summary(usable: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for effect_id in _array_or_empty(usable.get("effect_ids", [])):
		var effect: Dictionary = _effect_data(str(effect_id))
		var deltas: Dictionary = _dictionary_or_empty(_dictionary_or_empty(effect.get("gameplay_effect", {})).get("resource_deltas", {}))
		var keys: Array = deltas.keys()
		keys.sort()
		for key in keys:
			var resource_id := _normalized_resource_id(str(key))
			var delta := float(deltas.get(key, 0.0))
			if is_zero_approx(delta):
				continue
			output.append("%s %s%s" % [
				_resource_label(resource_id),
				"+" if delta > 0.0 else "",
				_number_text(delta),
			])
	return output


func _fragment_by_kind(item: Dictionary, kind: String) -> Dictionary:
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		if str(fragment_data.get("kind", "")) == kind:
			return fragment_data
	return {}


func _is_item_use_allowed(item: Dictionary) -> bool:
	for key in ["usable", "can_use"]:
		if item.has(key) and not bool(item.get(key)):
			return false
	for fragment in _array_or_empty(item.get("fragments", [])):
		var fragment_data: Dictionary = _dictionary_or_empty(fragment)
		var kind: String = str(fragment_data.get("kind", ""))
		if kind in ["quest", "task", "key_item"]:
			return false
		for key in ["usable", "can_use"]:
			if fragment_data.has(key) and not bool(fragment_data.get(key)):
				return false
	return true


func _resource_costs(activation: Dictionary) -> Array[Dictionary]:
	var source: Variant = activation.get("resource_costs", activation.get("resource_cost", {}))
	var output: Array[Dictionary] = []
	if typeof(source) == TYPE_DICTIONARY:
		var costs: Dictionary = source
		for resource_id in costs.keys():
			var amount: float = max(0.0, float(costs.get(resource_id, 0.0)))
			if amount <= 0.0:
				continue
			output.append({"resource": _normalized_resource_id(str(resource_id)), "amount": amount})
	elif typeof(source) == TYPE_ARRAY:
		for entry in source:
			var entry_data: Dictionary = _dictionary_or_empty(entry)
			var resource_id := _normalized_resource_id(str(entry_data.get("resource", entry_data.get("resource_id", ""))))
			var amount: float = max(0.0, float(entry_data.get("amount", entry_data.get("cost", 0.0))))
			if resource_id.is_empty() or amount <= 0.0:
				continue
			output.append({"resource": resource_id, "amount": amount})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("resource", "")) < str(b.get("resource", ""))
	)
	return output


func _resource_cost_check(costs: Array[Dictionary], resources: Dictionary) -> Dictionary:
	for cost in costs:
		var cost_data: Dictionary = _dictionary_or_empty(cost)
		var resource_id := _normalized_resource_id(str(cost_data.get("resource", "")))
		var required: float = max(0.0, float(cost_data.get("amount", 0.0)))
		var resource: Dictionary = _dictionary_or_empty(resources.get(resource_id, {}))
		var available: float = float(resource.get("current", 0.0))
		if available + 0.0001 < required:
			return {
				"success": false,
				"resource": resource_id,
				"required_amount": required,
				"available_amount": available,
			}
	return {"success": true}


func _normalized_resource_id(resource_id: String) -> String:
	if resource_id == "health":
		return "hp"
	return resource_id


func _resource_label(resource_id: String) -> String:
	match resource_id:
		"hp":
			return "HP"
		"stamina":
			return "stamina"
		"hunger":
			return "hunger"
		"thirst":
			return "thirst"
		"immunity":
			return "immunity"
	return resource_id


func _hotbar_label(kind: String, entry_id: String) -> String:
	if kind == "item":
		return _item_label(entry_id)
	return _skill_label(entry_id)


func _skill_label(skill_id: String) -> String:
	if skill_id.is_empty():
		return ""
	var parts := skill_id.split("_")
	for index in range(parts.size()):
		parts[index] = str(parts[index]).capitalize()
	return " ".join(parts)


func _item_label(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	if registry != null:
		var record: Dictionary = _dictionary_or_empty(registry.get_library("items").get(item_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		var name := str(data.get("name", ""))
		if not name.is_empty():
			return name
	return item_id


func _event_feedback(runtime_snapshot: Dictionary) -> Array[Dictionary]:
	var events: Array = runtime_snapshot.get("events", [])
	var output: Array[Dictionary] = []
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		var summary := _event_feedback_entry(event)
		if summary.is_empty():
			continue
		output.push_front(summary)
		if output.size() >= 3:
			break
	return output


func _feedback_toasts(runtime_snapshot: Dictionary) -> Array[Dictionary]:
	var events: Array = runtime_snapshot.get("events", [])
	var output: Array[Dictionary] = []
	var toast_slot := 0
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = _dictionary_or_empty(events[index])
		var summary := _event_feedback_entry(event)
		if summary.is_empty():
			continue
		var toast := _feedback_toast_entry(summary, event, index, toast_slot, events.size())
		if toast.is_empty():
			continue
		output.push_front(toast)
		toast_slot += 1
		if output.size() >= 3:
			break
	for display_slot in range(output.size()):
		output[display_slot]["slot"] = display_slot
	return output


func _feedback_toast_entry(summary: Dictionary, event: Dictionary, event_index: int, slot: int, event_count: int) -> Dictionary:
	var kind := str(summary.get("kind", event.get("kind", "")))
	var text := str(summary.get("text", ""))
	if text.is_empty():
		return {}
	var severity := _feedback_toast_severity(kind, text)
	var age_events: int = max(0, event_count - event_index - 1)
	var ttl_events := 6
	var fade_start := 3
	var alpha := 1.0
	if age_events > fade_start:
		alpha = clamp(1.0 - (float(age_events - fade_start) / float(max(1, ttl_events - fade_start))), 0.25, 1.0)
	var phase := "enter" if age_events == 0 else ("hold" if age_events <= fade_start else "fade")
	return {
		"id": "toast_%d_%s" % [event_index, kind],
		"kind": kind,
		"text": text,
		"severity": severity,
		"phase": phase,
		"slot": slot,
		"event_index": event_index,
		"age_events": age_events,
		"ttl_events": ttl_events,
		"fade_start_event": fade_start,
		"alpha": alpha,
		"visible": alpha > 0.0,
		"transition": {
			"style": "event_age_fade",
			"enter_events": 1,
			"hold_events": fade_start,
			"fade_events": ttl_events - fade_start,
		},
	}


func _feedback_toast_severity(kind: String, text: String) -> String:
	if kind == "player_command_rejected" or kind == "ui_feedback" or text.begins_with("失败"):
		return "error"
	if kind in ["actor_defeated", "quest_completed", "quest_reward_granted", "actor_leveled_up", "skill_learned"]:
		return "success"
	if kind in ["attack_resolved", "relationship_changed", "movement_cancelled", "interaction_cancelled", "crafting_queued", "crafting_cancelled", "pending_cancelled"]:
		return "warning"
	return "info"


func _event_feedback_entry(event: Dictionary) -> Dictionary:
	var kind := str(event.get("kind", ""))
	var payload: Dictionary = _dictionary_or_empty(event.get("payload", {}))
	match kind:
		"interaction_succeeded":
			var target_name := str(payload.get("target_name", payload.get("target_id", "目标")))
			var option_kind := str(payload.get("option_kind", payload.get("option_id", "interact")))
			return {
				"kind": kind,
				"text": "交互 %s: %s" % [option_kind, target_name],
			}
		"actor_waited":
			return {
				"kind": kind,
				"text": "等待: actor#%d" % int(payload.get("actor_id", 0)),
			}
		"movement_step":
			return {
				"kind": kind,
				"text": "移动: actor#%d" % int(payload.get("actor_id", 0)),
			}
		"attack_resolved":
			return {
				"kind": kind,
				"text": _attack_feedback_text(payload),
			}
		"actor_defeated":
			return {
				"kind": kind,
				"text": "击败: actor#%d" % int(payload.get("actor_id", payload.get("target_id", 0))),
			}
		"recipe_crafted":
			return {
				"kind": kind,
				"text": "制作: %s" % str(payload.get("recipe_id", "")),
			}
		"crafting_queued":
			return {
				"kind": kind,
				"text": "制作排队: %s | 剩余AP %.1f" % [
					str(payload.get("recipe_id", "")),
					float(payload.get("remaining_ap", 0.0)),
				],
			}
		"crafting_resumed":
			return {
				"kind": kind,
				"text": "继续制作: %s" % str(payload.get("recipe_id", "")),
			}
		"skill_used":
			return {
				"kind": kind,
				"text": "技能: %s" % str(payload.get("skill_id", "")),
			}
		"experience_granted":
			return {
				"kind": kind,
				"text": "经验 +%d: %s" % [
					int(payload.get("amount", 0)),
					_progression_source_text(str(payload.get("source", ""))),
				],
			}
		"actor_leveled_up":
			return {
				"kind": kind,
				"text": "升级: Lv%d | 属性点 %d | 技能点 %d" % [
					int(payload.get("new_level", 0)),
					int(payload.get("available_stat_points", 0)),
					int(payload.get("available_skill_points", 0)),
				],
			}
		"skill_points_granted":
			return {
				"kind": kind,
				"text": "技能点 +%d | 可用 %d" % [
					int(payload.get("amount", 0)),
					int(payload.get("available_skill_points", 0)),
				],
			}
		"attribute_allocated":
			return {
				"kind": kind,
				"text": "属性: %s %d | 剩余 %d" % [
					_attribute_label(str(payload.get("attribute", ""))),
					int(payload.get("value", 0)),
					int(payload.get("available_stat_points", 0)),
				],
			}
		"skill_learned":
			return {
				"kind": kind,
				"text": "学习技能: %s Lv%d | 技能点 %d" % [
					_skill_label(str(payload.get("skill_id", ""))),
					int(payload.get("level", 0)),
					int(payload.get("available_skill_points", 0)),
				],
			}
		"quest_started":
			return {
				"kind": kind,
				"text": "任务开始: %s" % _quest_title_from_payload(payload),
			}
		"quest_progressed":
			return {
				"kind": kind,
				"text": "任务进度: %s %d/%d" % [
					_quest_title_from_payload(payload),
					int(payload.get("current", 0)),
					int(payload.get("target", 0)),
				],
			}
		"quest_completed":
			return {
				"kind": kind,
				"text": "任务完成: %s" % _quest_title_from_payload(payload),
			}
		"quest_reward_granted":
			return {
				"kind": kind,
				"text": _quest_reward_text(payload),
			}
		"relationship_changed":
			return {
				"kind": kind,
				"text": _relationship_changed_text(payload),
			}
		"movement_cancelled":
			return {
				"kind": kind,
				"text": "已取消移动: %s" % _pending_cancel_reason_text(str(payload.get("reason", ""))),
			}
		"interaction_cancelled":
			return {
				"kind": kind,
				"text": "已取消交互: %s" % _pending_cancel_reason_text(str(payload.get("reason", ""))),
			}
		"crafting_cancelled":
			return {
				"kind": kind,
				"text": "已取消制作: %s" % _pending_cancel_reason_text(str(payload.get("reason", ""))),
			}
		"pending_cancelled":
			return {
				"kind": kind,
				"text": "已取消待执行动作: %s" % _pending_cancel_reason_text(str(payload.get("reason", ""))),
			}
		"player_command_rejected":
			return {
				"kind": kind,
				"text": "失败 %s: %s" % [
					_command_kind_label(str(payload.get("kind", payload.get("result_kind", "")))),
					_failure_reason_text(str(payload.get("reason", "unknown"))),
				],
			}
		"ui_feedback":
			if bool(payload.get("success", true)):
				return {}
			if _is_player_command_kind(str(payload.get("kind", ""))):
				return {}
			return {
				"kind": kind,
				"text": "提示 %s: %s" % [
					_command_kind_label(str(payload.get("kind", ""))),
					_failure_reason_text(str(payload.get("reason", "unknown"))),
				],
			}
		_:
			return {}


func _attack_feedback_text(payload: Dictionary) -> String:
	var actor_id: int = int(payload.get("actor_id", payload.get("attacker_id", 0)))
	var target_actor_id: int = int(payload.get("target_actor_id", payload.get("target_id", 0)))
	var hit_kind: String = str(payload.get("hit_kind", "crit" if bool(payload.get("critical", false)) else "hit"))
	var result_text := "命中"
	match hit_kind:
		"miss":
			result_text = "闪避"
		"blocked":
			result_text = "格挡"
		"crit":
			result_text = "暴击"
	var detail_parts: Array[String] = [result_text]
	if payload.has("damage"):
		detail_parts.append("%s伤害" % _number_text(float(payload.get("damage", 0.0))))
	if payload.has("hit_chance"):
		detail_parts.append("命中率%s" % _percent_text(float(payload.get("hit_chance", 0.0))))
	if bool(payload.get("defeated", false)):
		detail_parts.append("击倒")
	return "攻击: %d -> %d %s" % [
		actor_id,
		target_actor_id,
		" ".join(detail_parts),
	]


func _command_kind_label(kind: String) -> String:
	match kind:
		"move":
			return "移动"
		"interact":
			return "交互"
		"attack":
			return "攻击"
		"wait":
			return "等待"
		"use_skill":
			return "技能"
		"craft":
			return "制作"
		"inventory_action":
			return "背包"
	if kind.is_empty():
		return "命令"
	return kind


func _pending_cancel_reason_text(reason: String) -> String:
	if reason.begins_with("pending_cancelled:"):
		return _pending_cancel_reason_text(reason.trim_prefix("pending_cancelled:"))
	if reason.is_empty():
		return "已取消"
	return reason_catalog.text_for(reason)


func _progression_source_text(source: String) -> String:
	if source.is_empty():
		return "progression"
	match source:
		"quest":
			return "任务"
		"combat":
			return "战斗"
		"crafting":
			return "制作"
	return source


func _attribute_label(attribute: String) -> String:
	match attribute:
		"constitution":
			return "体质"
		"strength":
			return "力量"
		"agility":
			return "敏捷"
	if attribute.is_empty():
		return "属性"
	return attribute


func _quest_title_from_payload(payload: Dictionary) -> String:
	var title := str(payload.get("title", ""))
	if not title.is_empty():
		return title
	var quest_id := str(payload.get("quest_id", ""))
	if registry != null and not quest_id.is_empty():
		var record: Dictionary = _dictionary_or_empty(registry.get_library("quests").get(quest_id, {}))
		var data: Dictionary = _dictionary_or_empty(record.get("data", record))
		return str(data.get("title", quest_id))
	return quest_id if not quest_id.is_empty() else "任务"


func _quest_reward_text(payload: Dictionary) -> String:
	var parts: Array[String] = ["任务奖励: %s" % _quest_title_from_payload(payload)]
	var experience: int = int(payload.get("experience", 0))
	if experience > 0:
		parts.append("XP %d" % experience)
	var skill_points: int = int(payload.get("skill_points", 0))
	if skill_points > 0:
		parts.append("技能点 %d" % skill_points)
	var money: int = int(payload.get("money", 0))
	if money > 0:
		parts.append("金钱 %d" % money)
	var item_count := 0
	for item in _array_or_empty(payload.get("items", [])):
		var item_data: Dictionary = _dictionary_or_empty(item)
		item_count += max(0, int(item_data.get("count", 0)))
	if item_count > 0:
		parts.append("物品 %d" % item_count)
	var unlocked_count: int = _array_or_empty(payload.get("unlocked_locations", [])).size()
	if unlocked_count > 0:
		parts.append("解锁地点 %d" % unlocked_count)
	var flag_count: int = _array_or_empty(payload.get("world_flags", [])).size()
	if flag_count > 0:
		parts.append("世界状态 %d" % flag_count)
	var relationship_count: int = _array_or_empty(payload.get("relationship_changes", [])).size()
	if relationship_count > 0:
		parts.append(_relationship_changes_summary(_array_or_empty(payload.get("relationship_changes", []))))
	return " | ".join(parts)


func _relationship_changed_text(payload: Dictionary) -> String:
	var left_name := _relationship_actor_name(payload, "actor")
	var right_name := _relationship_actor_name(payload, "target_actor")
	var delta: float = float(payload.get("score_delta", float(payload.get("score", 0.0)) - float(payload.get("score_before", 0.0))))
	return "关系: %s / %s %s -> %s (%s)" % [
		left_name,
		right_name,
		_number_text(float(payload.get("score_before", 0.0))),
		_number_text(float(payload.get("score", 0.0))),
		_delta_text(delta),
	]


func _relationship_changes_summary(changes: Array) -> String:
	if changes.is_empty():
		return "关系 0"
	var readable: Array[String] = []
	for change in changes.slice(0, 2):
		var change_data: Dictionary = _dictionary_or_empty(change)
		var left_name := _relationship_actor_name(change_data, "actor")
		var right_name := _relationship_actor_name(change_data, "target_actor")
		var delta: float = float(change_data.get("score_delta", float(change_data.get("score", 0.0)) - float(change_data.get("score_before", 0.0))))
		readable.append("%s/%s %s" % [left_name, right_name, _delta_text(delta)])
	if changes.size() > readable.size():
		readable.append("+%d" % (changes.size() - readable.size()))
	return "关系 %s" % "，".join(readable)


func _relationship_actor_name(payload: Dictionary, prefix: String) -> String:
	var name_key := "%s_name" % prefix
	var id_key := "%s_id" % prefix
	var name := str(payload.get(name_key, ""))
	if not name.is_empty():
		return name
	var actor_id := int(payload.get(id_key, 0))
	if actor_id > 0:
		return "actor#%d" % actor_id
	return "角色"


func _delta_text(delta: float) -> String:
	if delta > 0.001:
		return "+%s" % _number_text(delta)
	if delta < -0.001:
		return _number_text(delta)
	return "+0"


func _is_player_command_kind(kind: String) -> bool:
	return kind in ["move", "wait", "interact", "attack", "use_skill", "craft", "inventory_action", "unknown"]


func _failure_reason_text(reason: String) -> String:
	return reason_catalog.text_for(reason)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _percent_text(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))
