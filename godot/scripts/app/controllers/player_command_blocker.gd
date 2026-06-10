extends RefCounted


func player_command_rejection(action: String, observe_mode: bool, modal_name: String, presenter_blocks: bool, blocker: Dictionary = {}) -> Dictionary:
	if observe_mode:
		return observe_command_rejected(action, observe_mode)
	if not modal_name.is_empty():
		return ui_modal_command_rejected(action, modal_name, blocker)
	if presenter_blocks:
		return action_presenter_command_rejected(action, blocker)
	return {}


func observe_command_rejected(action: String, observe_mode: bool) -> Dictionary:
	return {
		"success": false,
		"reason": "observe_mode_blocks_player_commands",
		"action": action,
		"observe_mode": observe_mode,
	}


func action_presenter_command_rejected(action: String, blocker: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"reason": "world_action_presenter_blocks_player_commands",
		"action": action,
		"blocker": blocker.duplicate(true),
		"action_kind": str(blocker.get("action_kind", "")),
	}


func ui_modal_command_rejected(action: String, modal_name: String, blocker: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"reason": "ui_modal_blocks_player_commands",
		"action": action,
		"modal_id": modal_name.trim_prefix("modal:"),
		"blocker": blocker.duplicate(true),
	}
