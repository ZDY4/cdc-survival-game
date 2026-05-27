extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	var errors: Array[String] = _run_checks(game_root)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("dialogue_ui_smoke passed:")
	print(JSON.stringify({
		"speaker": _speaker_line(game_root),
		"text": _text_line(game_root),
		"options": _options_line(game_root),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	var trader_node: Node = game_root.find_child("Actor_trader_lao_wang_2", true, false)
	if trader_node == null:
		return ["missing generated trader actor node"]

	var selection: Dictionary = game_root.select_interaction_node(trader_node)
	if not bool(selection.get("success", false)):
		errors.append("trader selection failed")
	var result: Dictionary = game_root.execute_primary_interaction()
	if not bool(result.get("success", false)):
		errors.append("talk execution failed: %s" % result.get("reason", "unknown"))

	if game_root.dialogue_panel == null:
		return ["dialogue panel was not created"]
	if not game_root.dialogue_panel.visible:
		errors.append("dialogue panel is not visible after talk")
	if _speaker_line(game_root) != "老王":
		errors.append("dialogue speaker mismatch: %s" % _speaker_line(game_root))
	if not _text_line(game_root).contains("要看看货吗"):
		errors.append("dialogue text missing start node")
	if not _options_line(game_root).contains("交易") or not _options_line(game_root).contains("离开"):
		errors.append("dialogue options missing expected choices")
	return errors


func _speaker_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/SpeakerLine").text


func _text_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/TextLine").text


func _options_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/OptionsLine").text
