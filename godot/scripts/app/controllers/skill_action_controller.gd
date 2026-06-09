extends RefCounted


func learn_skill(skill_id: String, submit_command: Callable, skill_library: Dictionary) -> Dictionary:
	if not submit_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_command.call({
		"kind": "learn_skill",
		"actor_id": 1,
		"skill_id": skill_id,
		"skill_library": skill_library,
	}))
	return _operation_result(result, ["character", "skills"])


func bind_skill_to_hotbar(slot_id: String, skill_id: String, submit_command: Callable, skill_library: Dictionary) -> Dictionary:
	if not submit_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_command.call({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_id": skill_id,
		"skill_library": skill_library,
	}))
	return _operation_result(result, ["hud", "skills"])


func bind_item_to_hotbar(slot_id: String, item_id: String, submit_command: Callable, item_library: Dictionary, effect_library: Dictionary) -> Dictionary:
	if not submit_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_command.call({
		"kind": "bind_hotbar",
		"actor_id": 1,
		"slot_id": slot_id,
		"hotbar_kind": "item",
		"item_id": item_id,
		"item_library": item_library,
		"effect_library": effect_library,
	}))
	return _operation_result(result, ["hud", "inventory"])


func set_hotbar_group(group_id: String, set_group: Callable) -> Dictionary:
	if not set_group.is_valid():
		return _operation_result({"success": false, "reason": "hotbar_group_unsupported"}, [])
	return _operation_result(dictionary_or_empty(set_group.call(group_id)), ["hud", "skills", "inventory"])


func set_hotbar_group_label(group_id: String, label: String, set_label: Callable) -> Dictionary:
	if not set_label.is_valid():
		return _operation_result({"success": false, "reason": "hotbar_group_label_unsupported"}, [])
	return _operation_result(dictionary_or_empty(set_label.call(group_id, label)), ["hud", "skills"])


func cycle_hotbar_group(direction: int, cycle_group: Callable) -> Dictionary:
	if not cycle_group.is_valid():
		return _operation_result({"success": false, "reason": "hotbar_group_unsupported"}, [])
	return _operation_result(dictionary_or_empty(cycle_group.call(direction)), ["hud", "skills", "inventory"])


func use_hotbar_slot(
	slot_id: String,
	runtime_snapshot: Dictionary,
	skill_library: Dictionary,
	item_library: Dictionary,
	effect_library: Dictionary,
	submit_skill_command: Callable,
	submit_inventory_action: Callable,
	targeting_controller: RefCounted
) -> Dictionary:
	var slot: Dictionary = dictionary_or_empty(dictionary_or_empty(runtime_snapshot.get("hotbar", {})).get(slot_id, {}))
	if str(slot.get("kind", "")) == "item":
		if not submit_inventory_action.is_valid():
			return _operation_result({"success": false, "reason": "simulation_missing"}, [])
		var item_result: Dictionary = dictionary_or_empty(submit_inventory_action.call({
			"action": "use_item",
			"item_id": str(slot.get("item_id", "")),
			"item_library": item_library,
			"effect_library": effect_library,
		}))
		return _operation_result(item_result, ["hud", "character", "inventory"])
	var skill_id := str(slot.get("skill_id", ""))
	if _skill_requires_runtime_target(skill_id, skill_library, targeting_controller):
		return begin_skill_targeting(slot_id, skill_id, runtime_snapshot, skill_library, submit_skill_command, targeting_controller)
	if not submit_skill_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var skill_result: Dictionary = dictionary_or_empty(submit_skill_command.call({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": slot_id,
		"skill_library": skill_library,
		"target": {"target_type": "self"},
	}))
	return _operation_result(skill_result, ["hud", "character", "skills"])


func begin_skill_targeting(
	slot_id: String,
	skill_id: String,
	runtime_snapshot: Dictionary,
	skill_library: Dictionary,
	submit_skill_command: Callable,
	targeting_controller: RefCounted
) -> Dictionary:
	if targeting_controller == null or not targeting_controller.has_method("begin_targeting"):
		return _operation_result({"success": false, "reason": "skill_targeting_unsupported"}, [])
	var result: Dictionary = dictionary_or_empty(targeting_controller.call(
		"begin_targeting",
		slot_id,
		skill_id,
		runtime_snapshot,
		skill_library
	))
	if not bool(result.get("success", false)):
		return _operation_result(result, [])
	if bool(result.get("immediate", false)):
		if not submit_skill_command.is_valid():
			return _operation_result({"success": false, "reason": "simulation_missing"}, [])
		var immediate_result: Dictionary = dictionary_or_empty(submit_skill_command.call({
			"kind": "use_skill",
			"actor_id": 1,
			"slot_id": slot_id,
			"skill_id": str(result.get("skill_id", skill_id)),
			"skill_library": skill_library,
			"target": dictionary_or_empty(result.get("target", {"target_type": "self"})),
		}))
		return _operation_result(immediate_result, [])
	var operation: Dictionary = _operation_result(result, ["hud"])
	operation["selected_prompt"] = true
	return operation


func preview_active_skill_target(
	target: Dictionary,
	preview_target: Callable,
	targeting_controller: RefCounted
) -> Dictionary:
	if targeting_controller == null or not targeting_controller.has_method("snapshot"):
		return _operation_result({"success": false, "reason": "skill_targeting_inactive"}, [])
	var active_targeting: Dictionary = dictionary_or_empty(targeting_controller.call("snapshot"))
	if not bool(active_targeting.get("active", false)):
		return _operation_result({"success": false, "reason": "skill_targeting_inactive"}, [])
	if not preview_target.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var skill_id := str(active_targeting.get("skill_id", ""))
	var preview: Dictionary = dictionary_or_empty(preview_target.call(skill_id, target))
	if targeting_controller.has_method("record_preview"):
		targeting_controller.call("record_preview", preview)
	return {
		"result": preview.duplicate(true),
		"refresh": ["hud"],
		"target_markers": dictionary_or_empty(targeting_controller.get("active_preview")).duplicate(true),
		"selected_prompt": true,
	}


func confirm_active_skill_target(
	target: Dictionary,
	submit_skill_command: Callable,
	skill_library: Dictionary,
	topology: Dictionary,
	targeting_controller: RefCounted
) -> Dictionary:
	if targeting_controller == null or not targeting_controller.has_method("confirm_target"):
		return _operation_result({"success": false, "reason": "skill_targeting_inactive"}, [])
	var active_targeting: Dictionary = dictionary_or_empty(targeting_controller.call("snapshot"))
	if not bool(active_targeting.get("active", false)):
		return _operation_result({"success": false, "reason": "skill_targeting_inactive"}, [])
	var confirm: Dictionary = dictionary_or_empty(targeting_controller.call("confirm_target", target))
	if not bool(confirm.get("success", false)):
		return _operation_result(confirm, [])
	if not submit_skill_command.is_valid():
		return _operation_result({"success": false, "reason": "simulation_missing"}, [])
	var result: Dictionary = dictionary_or_empty(submit_skill_command.call({
		"kind": "use_skill",
		"actor_id": 1,
		"slot_id": str(confirm.get("slot_id", "")),
		"skill_id": str(confirm.get("skill_id", "")),
		"skill_library": skill_library,
		"target": dictionary_or_empty(confirm.get("target", {})),
		"topology": topology,
	}))
	if targeting_controller.has_method("complete_confirm"):
		targeting_controller.call("complete_confirm", bool(result.get("success", false)))
	var operation: Dictionary = _operation_result(result, ["hud", "character", "skills"])
	operation["selected_prompt"] = true
	if bool(result.get("success", false)):
		operation["target_markers"] = {}
	return operation


func cancel_active_skill_targeting(reason: String, targeting_controller: RefCounted) -> Dictionary:
	if targeting_controller == null or not targeting_controller.has_method("cancel"):
		return _operation_result({"success": false, "reason": "skill_targeting_inactive"}, [])
	var result: Dictionary = dictionary_or_empty(targeting_controller.call("cancel", reason))
	var operation: Dictionary = _operation_result(result, ["hud"] if bool(result.get("success", false)) else [])
	operation["selected_prompt"] = true
	if bool(result.get("success", false)):
		operation["target_markers"] = {}
	return operation


func _operation_result(result: Dictionary, refresh_panels: Array) -> Dictionary:
	return {
		"result": result.duplicate(true),
		"refresh": refresh_panels.duplicate(true),
	}


func _skill_requires_runtime_target(skill_id: String, skill_library: Dictionary, targeting_controller: RefCounted) -> bool:
	if targeting_controller == null or not targeting_controller.has_method("skill_requires_runtime_target"):
		return false
	return bool(targeting_controller.call("skill_requires_runtime_target", skill_id, skill_library))


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
