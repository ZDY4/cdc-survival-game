extends RefCounted

## 热栏运行时层：维护热栏组、绑定技能/物品、组标签与冷却 tick。
## 无状态规则计算；权威 hotbar / hotbar_groups / active_hotbar_group 由 simulation 持有。


func set_active_hotbar_group(simulation: RefCounted, group_id: String) -> Dictionary:
	simulation._ensure_hotbar_groups()
	var normalized_group_id: String = simulation._normalized_hotbar_group_id(group_id)
	if normalized_group_id.is_empty():
		return {"success": false, "reason": "hotbar_group_missing"}
	var previous_group_id: String = simulation.active_hotbar_group
	simulation._sync_active_hotbar_group()
	simulation.active_hotbar_group = normalized_group_id
	if not simulation.hotbar_groups.has(simulation.active_hotbar_group):
		simulation.hotbar_groups[simulation.active_hotbar_group] = {}
	simulation.hotbar = simulation._dictionary_or_empty(simulation.hotbar_groups.get(simulation.active_hotbar_group, {})).duplicate(true)
	if simulation.active_hotbar_group != previous_group_id:
		simulation._emit("hotbar_group_changed", {
			"previous_group_id": previous_group_id,
			"group_id": simulation.active_hotbar_group,
		})
	return {
		"success": true,
		"group_id": simulation.active_hotbar_group,
		"previous_group_id": previous_group_id,
		"changed": simulation.active_hotbar_group != previous_group_id,
	}


func cycle_hotbar_group(simulation: RefCounted, direction: int) -> Dictionary:
	simulation._ensure_hotbar_groups()
	var step: int = 1 if direction >= 0 else -1
	var current_index: int = simulation._hotbar_group_index(simulation.active_hotbar_group)
	var next_index: int = posmod(current_index + step, simulation.HOTBAR_GROUP_COUNT)
	return simulation.set_active_hotbar_group("group_%d" % (next_index + 1))


func set_hotbar_group_label(simulation: RefCounted, group_id: String, label: String) -> Dictionary:
	simulation._ensure_hotbar_groups()
	var normalized_group_id: String = simulation._normalized_hotbar_group_id(group_id)
	if normalized_group_id.is_empty():
		return {"success": false, "reason": "hotbar_group_missing"}
	var normalized_label: String = label.strip_edges()
	if normalized_label.is_empty():
		normalized_label = simulation._default_hotbar_group_label(normalized_group_id)
	var previous_label: String = str(simulation.hotbar_group_labels.get(normalized_group_id, simulation._default_hotbar_group_label(normalized_group_id)))
	simulation.hotbar_group_labels[normalized_group_id] = normalized_label
	if previous_label != normalized_label:
		simulation._emit("hotbar_group_label_changed", {
			"group_id": normalized_group_id,
			"previous_label": previous_label,
			"label": normalized_label,
		})
	return {
		"success": true,
		"group_id": normalized_group_id,
		"label": normalized_label,
		"previous_label": previous_label,
		"changed": previous_label != normalized_label,
	}


func ensure_hotbar_groups(simulation: RefCounted) -> void:
	simulation.active_hotbar_group = simulation._normalized_hotbar_group_id(simulation.active_hotbar_group)
	if simulation.active_hotbar_group.is_empty():
		simulation.active_hotbar_group = simulation.DEFAULT_HOTBAR_GROUP_ID
	if simulation.hotbar_groups.is_empty():
		simulation.hotbar_groups[simulation.active_hotbar_group] = simulation.hotbar.duplicate(true)
	if not simulation.hotbar_groups.has(simulation.active_hotbar_group):
		simulation.hotbar_groups[simulation.active_hotbar_group] = simulation.hotbar.duplicate(true)
	for index in range(1, simulation.HOTBAR_GROUP_COUNT + 1):
		var group_id: String = "group_%d" % index
		if not simulation.hotbar_groups.has(group_id):
			simulation.hotbar_groups[group_id] = {}
		if not simulation.hotbar_group_labels.has(group_id) or str(simulation.hotbar_group_labels.get(group_id, "")).strip_edges().is_empty():
			simulation.hotbar_group_labels[group_id] = simulation._default_hotbar_group_label(group_id)
	simulation.hotbar = simulation._dictionary_or_empty(simulation.hotbar_groups.get(simulation.active_hotbar_group, {})).duplicate(true)


func sync_active_hotbar_group(simulation: RefCounted) -> void:
	simulation.active_hotbar_group = simulation._normalized_hotbar_group_id(simulation.active_hotbar_group)
	if simulation.active_hotbar_group.is_empty():
		simulation.active_hotbar_group = simulation.DEFAULT_HOTBAR_GROUP_ID
	simulation.hotbar_groups[simulation.active_hotbar_group] = simulation.hotbar.duplicate(true)


func normalized_hotbar_group_id(simulation: RefCounted, group_id: String) -> String:
	var value: String = group_id.strip_edges().to_lower()
	if value.is_empty():
		return simulation.DEFAULT_HOTBAR_GROUP_ID
	if value.is_valid_int():
		value = "group_%d" % int(value)
	if value.begins_with("hotbar_"):
		value = "group_%s" % value.trim_prefix("hotbar_")
	if not value.begins_with("group_"):
		value = "group_%s" % value
	var index: int = simulation._hotbar_group_index(value)
	if index < 0:
		return simulation.DEFAULT_HOTBAR_GROUP_ID
	return "group_%d" % (index + 1)


func hotbar_group_index(simulation: RefCounted, group_id: String) -> int:
	var value: String = group_id.strip_edges().to_lower()
	if value.begins_with("group_"):
		value = value.trim_prefix("group_")
	if not value.is_valid_int():
		return -1
	var index: int = int(value) - 1
	if index < 0 or index >= simulation.HOTBAR_GROUP_COUNT:
		return -1
	return index


func default_hotbar_group_label(simulation: RefCounted, group_id: String) -> String:
	var index: int = simulation._hotbar_group_index(group_id)
	if index < 0:
		return group_id
	return "G%d" % (index + 1)


func submit_bind_hotbar_command(simulation: RefCounted, actor: RefCounted, command: Dictionary) -> Dictionary:
	simulation._ensure_hotbar_groups()
	var slot_id: String = str(command.get("slot_id", ""))
	var kind: String = str(command.get("hotbar_kind", command.get("bind_kind", "")))
	var skill_id: String = str(command.get("skill_id", ""))
	var item_id: String = simulation._inventory_entries.normalize_content_id(command.get("item_id", ""))
	if kind.is_empty():
		kind = "item" if not item_id.is_empty() else "skill"
	if skill_id.is_empty() and item_id.is_empty():
		if slot_id.is_empty():
			return {"success": false, "reason": "hotbar_slot_missing"}
		simulation.hotbar.erase(slot_id)
		simulation._sync_active_hotbar_group()
		simulation._emit("hotbar_unbound", {
			"actor_id": actor.actor_id,
			"slot_id": slot_id,
			"group_id": simulation.active_hotbar_group,
		})
		return {"success": true, "slot_id": slot_id, "cleared": true, "group_id": simulation.active_hotbar_group}
	if kind == "item":
		return simulation._bind_item_to_hotbar(actor, slot_id, item_id, command)
	if kind != "skill":
		return {"success": false, "reason": "unknown_hotbar_kind", "hotbar_kind": kind}
	var skill: Dictionary = simulation._skill_data(skill_id, simulation._dictionary_or_empty(command.get("skill_library", {})))
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": skill_id}
	if int(simulation._dictionary_or_empty(actor.progression.get("learned_skills", {})).get(skill_id, 0)) <= 0:
		return {"success": false, "reason": "skill_not_learned", "skill_id": skill_id}
	var activation_mode: String = str(simulation._dictionary_or_empty(skill.get("activation", {})).get("mode", "passive"))
	if activation_mode == "passive":
		return {"success": false, "reason": "skill_not_bindable", "skill_id": skill_id}
	var resolved_slot_id: String = simulation._resolve_hotbar_bind_slot(skill_id, slot_id)
	if resolved_slot_id.is_empty():
		return {"success": false, "reason": "hotbar_full", "skill_id": skill_id}
	var auto_slot: bool = slot_id.is_empty()
	slot_id = resolved_slot_id
	simulation.hotbar[slot_id] = {
		"slot_id": slot_id,
		"kind": "skill",
		"skill_id": skill_id,
		"cooldown_remaining": 0.0,
	}
	simulation._sync_active_hotbar_group()
	simulation._emit("hotbar_bound", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"group_id": simulation.active_hotbar_group,
		"kind": "skill",
		"skill_id": skill_id,
	})
	return {"success": true, "slot_id": slot_id, "skill_id": skill_id, "auto_slot": auto_slot, "group_id": simulation.active_hotbar_group}


func bind_item_to_hotbar(simulation: RefCounted, actor: RefCounted, slot_id: String, item_id: String, command: Dictionary) -> Dictionary:
	if item_id.is_empty():
		return {"success": false, "reason": "item_id_missing"}
	var items: Dictionary = simulation._dictionary_or_empty(command.get("item_library", simulation.item_library))
	var effects: Dictionary = simulation._dictionary_or_empty(command.get("effect_library", simulation.effect_library))
	var validation: Dictionary = simulation._item_use_runner.validate_use_item(simulation, actor.actor_id, item_id, items, effects)
	if not bool(validation.get("success", false)):
		validation["hotbar_kind"] = "item"
		return validation
	var resolved_slot_id: String = simulation._resolve_hotbar_bind_slot_for_entry("item", item_id, slot_id)
	if resolved_slot_id.is_empty():
		return {"success": false, "reason": "hotbar_full", "item_id": item_id, "hotbar_kind": "item"}
	var auto_slot: bool = slot_id.is_empty()
	slot_id = resolved_slot_id
	simulation.hotbar[slot_id] = {
		"slot_id": slot_id,
		"kind": "item",
		"item_id": item_id,
		"cooldown_remaining": 0.0,
	}
	simulation._sync_active_hotbar_group()
	simulation._emit("hotbar_bound", {
		"actor_id": actor.actor_id,
		"slot_id": slot_id,
		"group_id": simulation.active_hotbar_group,
		"kind": "item",
		"item_id": item_id,
	})
	return {"success": true, "slot_id": slot_id, "item_id": item_id, "hotbar_kind": "item", "auto_slot": auto_slot, "group_id": simulation.active_hotbar_group}


func resolve_hotbar_bind_slot(simulation: RefCounted, skill_id: String, requested_slot_id: String) -> String:
	return simulation._resolve_hotbar_bind_slot_for_entry("skill", skill_id, requested_slot_id)


func resolve_hotbar_bind_slot_for_entry(simulation: RefCounted, kind: String, entry_id: String, requested_slot_id: String) -> String:
	if not requested_slot_id.is_empty():
		return requested_slot_id
	for slot_id in simulation.hotbar.keys():
		var slot: Dictionary = simulation._dictionary_or_empty(simulation.hotbar.get(slot_id, {}))
		var id_key: String = "skill_id" if kind == "skill" else "item_id"
		if str(slot.get("kind", "")) == kind and str(slot.get(id_key, "")) == entry_id:
			return str(slot_id)
	for index in range(1, simulation.HOTBAR_SLOT_COUNT + 1):
		var candidate: String = "slot_%d" % index
		if simulation._dictionary_or_empty(simulation.hotbar.get(candidate, {})).is_empty():
			return candidate
	return ""


func tick_hotbar_cooldowns(simulation: RefCounted) -> void:
	simulation._ensure_hotbar_groups()
	for group_id_value in simulation.hotbar_groups.keys():
		var group_id: String = str(group_id_value)
		var group_hotbar: Dictionary = simulation._dictionary_or_empty(simulation.hotbar_groups.get(group_id, {})).duplicate(true)
		for slot_id in group_hotbar.keys():
			var slot: Dictionary = simulation._dictionary_or_empty(group_hotbar.get(slot_id, {})).duplicate(true)
			var before: float = float(slot.get("cooldown_remaining", 0.0))
			if before <= 0.0:
				continue
			slot["cooldown_remaining"] = max(0.0, before - 1.0)
			group_hotbar[slot_id] = slot
			simulation._emit("hotbar_cooldown_ticked", {
				"group_id": group_id,
				"slot_id": str(slot_id),
				"before": before,
				"after": float(slot.get("cooldown_remaining", 0.0)),
			})
		simulation.hotbar_groups[group_id] = group_hotbar
	simulation.hotbar = simulation._dictionary_or_empty(simulation.hotbar_groups.get(simulation.active_hotbar_group, {})).duplicate(true)
