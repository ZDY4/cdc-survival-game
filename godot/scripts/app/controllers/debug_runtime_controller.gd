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
			return _toggle_fps_panel(game_root)
		"show overlays":
			return _cycle_debug_overlay(game_root)
		"observe mode":
			return _toggle_observe_mode(game_root)
		"clear":
			return _clear_console(game_root)
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


func _toggle_fps_panel(game_root: Node) -> Dictionary:
	if not game_root.has_method("toggle_debug_panel"):
		return {"success": false, "reason": "debug_panel_missing", "message": "debug panel missing"}
	var panel_result: Dictionary = game_root.toggle_debug_panel()
	return {
		"success": bool(panel_result.get("success", false)),
		"message": "fps panel=%s" % ("on" if bool(panel_result.get("visible", false)) else "off"),
		"visible": bool(panel_result.get("visible", false)),
	}


func _cycle_debug_overlay(game_root: Node) -> Dictionary:
	if not game_root.has_method("cycle_debug_overlay_mode"):
		return {"success": false, "reason": "debug_overlay_missing", "message": "debug overlay missing"}
	var overlay_result: Dictionary = game_root.cycle_debug_overlay_mode()
	return {
		"success": bool(overlay_result.get("success", false)),
		"message": "overlay=%s" % str(overlay_result.get("mode", "")),
	}


func _toggle_observe_mode(game_root: Node) -> Dictionary:
	if not game_root.has_method("toggle_observe_mode"):
		return {"success": false, "reason": "observe_mode_missing", "message": "observe mode missing"}
	var observe_result: Dictionary = game_root.toggle_observe_mode()
	var observe_mode := bool(observe_result.get("observe_mode", false))
	return {
		"success": bool(observe_result.get("success", false)),
		"message": "observe=%s" % ("on" if observe_mode else "off"),
	}


func _clear_console(game_root: Node) -> Dictionary:
	var hud: Node = game_root.get("hud")
	if hud != null and hud.has_method("clear_debug_console_history"):
		hud.clear_debug_console_history()
	return {"success": true, "message": "console cleared"}
