extends RefCounted

var active_targeting: Dictionary = {}
var active_preview: Dictionary = {}


func skill_requires_runtime_target(skill_id: String, skill_library: Dictionary) -> bool:
	if skill_id.is_empty():
		return false
	var skill: Dictionary = skill_data(skill_id, skill_library)
	if skill.is_empty():
		return false
	var targeting: Dictionary = skill_targeting_definition(_dictionary_or_empty(skill.get("activation", {})))
	return skill_target_kind(targeting) != "self"


func begin_targeting(slot_id: String, skill_id: String, runtime_snapshot: Dictionary, skill_library: Dictionary) -> Dictionary:
	var resolved_skill_id := skill_id
	if resolved_skill_id.is_empty():
		var slot: Dictionary = _dictionary_or_empty(_dictionary_or_empty(runtime_snapshot.get("hotbar", {})).get(slot_id, {}))
		resolved_skill_id = str(slot.get("skill_id", ""))
	if resolved_skill_id.is_empty():
		return {"success": false, "reason": "skill_missing", "slot_id": slot_id}
	var skill: Dictionary = skill_data(resolved_skill_id, skill_library)
	if skill.is_empty():
		return {"success": false, "reason": "unknown_skill", "skill_id": resolved_skill_id}
	var targeting: Dictionary = skill_targeting_definition(_dictionary_or_empty(skill.get("activation", {})))
	var target_kind := skill_target_kind(targeting)
	if target_kind == "self":
		return {
			"success": true,
			"immediate": true,
			"slot_id": slot_id,
			"skill_id": resolved_skill_id,
			"target": {"target_type": "self"},
		}
	active_targeting = {
		"active": true,
		"slot_id": slot_id,
		"skill_id": resolved_skill_id,
		"skill_name": str(skill.get("name", resolved_skill_id)),
		"target_kind": target_kind,
		"target_policy": str(targeting.get("policy", "")),
		"range": int(targeting.get("range", targeting.get("max_range", -1))),
		"radius": int(targeting.get("radius", targeting.get("aoe_radius", -1))),
		"length": int(targeting.get("length", targeting.get("max_length", -1))),
		"width": int(targeting.get("width", targeting.get("half_width", -1))),
	}
	active_preview = {
		"success": false,
		"reason": "skill_target_pending",
		"skill_id": resolved_skill_id,
		"target_shape": target_kind,
	}
	return {"success": true, "targeting": active_targeting.duplicate(true), "preview": active_preview.duplicate(true)}


func record_preview(preview: Dictionary) -> Dictionary:
	active_preview = preview.duplicate(true)
	return active_preview.duplicate(true)


func confirm_target(target: Dictionary) -> Dictionary:
	if active_targeting.is_empty():
		return {"success": false, "reason": "skill_targeting_inactive"}
	var command_target: Dictionary = _dictionary_or_empty(target).duplicate(true)
	if command_target.is_empty():
		command_target = _dictionary_or_empty(active_preview.get("target", {})).duplicate(true)
	return {
		"success": true,
		"slot_id": str(active_targeting.get("slot_id", "")),
		"skill_id": str(active_targeting.get("skill_id", "")),
		"target": command_target,
	}


func complete_confirm(success: bool) -> void:
	if not success:
		return
	clear()


func cancel(reason: String = "cancelled") -> Dictionary:
	if active_targeting.is_empty():
		return {"success": false, "reason": "skill_targeting_inactive"}
	var cancelled := active_targeting.duplicate(true)
	clear()
	return {"success": true, "closed": "skill_targeting", "reason": reason, "targeting": cancelled}


func clear() -> void:
	active_targeting = {}
	active_preview = {}


func has_active_targeting() -> bool:
	return not active_targeting.is_empty()


func snapshot() -> Dictionary:
	if active_targeting.is_empty():
		return {"active": false}
	var result: Dictionary = active_targeting.duplicate(true)
	result["preview"] = active_preview.duplicate(true)
	return result


func skill_data(skill_id: String, skill_library: Dictionary) -> Dictionary:
	if skill_id.is_empty():
		return {}
	var record: Dictionary = _dictionary_or_empty(skill_library.get(skill_id, {}))
	return _dictionary_or_empty(record.get("data", record)).duplicate(true)


func skill_targeting_definition(activation: Dictionary) -> Dictionary:
	var targeting: Dictionary = _dictionary_or_empty(activation.get("targeting", {})).duplicate(true)
	if targeting.is_empty():
		targeting = _dictionary_or_empty(activation.get("target", {})).duplicate(true)
	if targeting.is_empty():
		targeting = {
			"kind": "self",
			"policy": "self",
		}
	if not targeting.has("policy"):
		targeting["policy"] = default_skill_target_policy(skill_target_kind(targeting))
	return targeting


func skill_target_kind(targeting: Dictionary) -> String:
	return str(targeting.get("kind", targeting.get("target_kind", targeting.get("shape", "self"))))


func default_skill_target_policy(target_kind: String) -> String:
	match target_kind:
		"self":
			return "self"
		"single", "actor", "single_actor":
			return "any_actor"
		"grid", "point", "radius", "circle", "line", "cone":
			return "any_grid"
	return "any"


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
