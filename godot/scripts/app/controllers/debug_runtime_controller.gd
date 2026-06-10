extends RefCounted

const DebugConsoleCommandRunner = preload("res://scripts/app/debug_console_command_runner.gd")

var _command_runner := DebugConsoleCommandRunner.new()
var debug_overlay_mode: String = "off"


func command_schema() -> Array[Dictionary]:
	return _command_runner.command_schema()


func command_suggestions() -> Array[String]:
	return _command_runner.command_suggestions()


func help_text() -> String:
	return _command_runner.help_text()


func permission_snapshot(game_root: Node) -> Dictionary:
	return _command_runner.permission_snapshot(game_root)


func execute(game_root: Node, command: String) -> Dictionary:
	var normalized := command.to_lower().strip_edges()
	var mutation_result: Dictionary = _command_runner.execute(game_root, command)
	if not mutation_result.is_empty():
		return mutation_result
	match normalized:
		"":
			return {"success": false, "reason": "empty_command", "message": "empty command"}
		"help":
			return {"success": true, "message": help_text()}
		"show fps":
			return _debug_intent("toggle_fps_panel")
		"show overlays":
			return _debug_intent("cycle_debug_overlay")
		"observe mode":
			return _debug_intent("toggle_observe_mode")
		"clear":
			return _debug_intent("clear_console")
	return {"success": false, "reason": "unknown_command", "message": "unknown command: %s" % command}


func cycle_debug_overlay_mode() -> Dictionary:
	var modes := ["off", "walkable", "vision", "blocked_sight", "level"]
	var index := modes.find(debug_overlay_mode)
	if index < 0:
		index = 0
	debug_overlay_mode = modes[(index + 1) % modes.size()]
	return {"success": true, "mode": debug_overlay_mode}


func current_debug_overlay_mode() -> String:
	return debug_overlay_mode


func _debug_intent(action: String) -> Dictionary:
	return {
		"success": true,
		"debug_intent": action,
	}
