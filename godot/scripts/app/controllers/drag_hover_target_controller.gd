extends RefCounted


func observe_hotbar_target(drag_data: Dictionary, observe_key: String) -> Dictionary:
	var reject_reason := "observe_hotbar_drag_unsupported" if not drag_data.is_empty() else ""
	return {
		"target_kind": "observe_hotbar",
		"target_id": observe_key,
		"observe_key": observe_key,
		"accepts": "",
		"last_accept": false,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "observe_hotbar", observe_key, reject_reason, false),
	}


func hotbar_slot_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var slot_id := str(control.get_meta("hotbar_slot_id", "")) if control != null else ""
	var group_id := str(control.get_meta("hotbar_group_id", "")) if control != null else ""
	var acceptance: Dictionary = hotbar_slot_acceptance(slot_id, drag_data)
	var last_accept := bool(acceptance.get("accept", false))
	var reject_reason := str(acceptance.get("reason", ""))
	return {
		"target_kind": "hotbar_slot",
		"target_id": slot_id,
		"slot_id": slot_id,
		"group_id": group_id,
		"accepts": "skill_hotbar",
		"last_accept": last_accept,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "hotbar_slot", slot_id, reject_reason, last_accept),
	}


func hotbar_slot_acceptance(slot_id: String, drag_data: Dictionary) -> Dictionary:
	if drag_data.is_empty():
		return {"accept": false, "reason": ""}
	if str(drag_data.get("kind", "")) != "skill_hotbar":
		return {"accept": false, "reason": "hotbar_slot_requires_skill_hotbar"}
	if str(drag_data.get("skill_id", "")).is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_skill"}
	if slot_id.is_empty():
		return {"accept": false, "reason": "hotbar_slot_missing_slot"}
	return {"accept": true, "reason": ""}


func hotbar_group_target(control: Control, drag_data: Dictionary) -> Dictionary:
	var group_id := str(control.get_meta("hotbar_group_id", "")) if control != null else ""
	var reject_reason := "hotbar_group_drag_unsupported" if not drag_data.is_empty() else ""
	return {
		"target_kind": "hotbar_group",
		"target_id": group_id,
		"group_id": group_id,
		"accepts": "",
		"last_accept": false,
		"reject_reason": reject_reason,
		"hover_highlight": hover_highlight(not drag_data.is_empty(), "hotbar_group", group_id, reject_reason, false),
	}


func hover_highlight(active: bool, target_kind: String, target_id: String, reject_reason: String, accepted: bool) -> Dictionary:
	var style := "accept" if accepted else "reject"
	var color := "#4ecb71" if accepted else "#e25c5c"
	if not active:
		style = "inactive"
		color = "#00000000"
	return {
		"active": active,
		"style": style,
		"color": color,
		"target_kind": target_kind,
		"target_id": target_id,
		"accepted": accepted,
		"reject_reason": reject_reason,
		"reject_reason_text": "",
		"outline_width": 2.0 if active else 0.0,
	}
