extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


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
	var result: Dictionary = _execute_primary_and_complete(game_root)
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
	var before_events: int = game_root.simulation.snapshot().get("events", []).size()
	_press_key(game_root, KEY_SPACE)
	if not _player(game_root).get("active_dialogue_id", "") == "trader_lao_wang":
		errors.append("Space should not close dialogue when choices are available")
	if game_root.simulation.snapshot().get("events", []).size() != before_events:
		errors.append("Space on choice dialogue should not advance world turn or emit events")
	_press_key(game_root, KEY_1)
	if not game_root.trade_panel.visible:
		errors.append("digit 1 should choose first dialogue option and open trade")
	if not _player(game_root).get("active_dialogue_id", "") == "":
		errors.append("digit dialogue choice should close active dialogue after trade action")
	_expect_key_advances_dialogue_without_options(errors, game_root, KEY_SPACE, "Space")
	_expect_key_advances_dialogue_without_options(errors, game_root, KEY_ENTER, "Enter")
	return errors


func _execute_primary_and_complete(game_root: Node, max_waits: int = 16) -> Dictionary:
	var result: Dictionary = game_root.execute_primary_interaction()
	var waits := 0
	while waits < max_waits and _has_pending(game_root) and not _final_interaction_result(result):
		waits += 1
		var wait_result: Dictionary = game_root.simulation.submit_player_command({
			"kind": "wait",
			"topology": game_root.world_result.get("map", {}),
		})
		var pending_result: Dictionary = wait_result.get("pending_result", {})
		result = pending_result if not pending_result.is_empty() else wait_result
		_refresh_runtime_world(game_root, result)
	return result


func _refresh_runtime_world(game_root: Node, result: Dictionary) -> void:
	var rebuilt: Dictionary = WorldSnapshotBuilder.new(game_root.registry).build_from_runtime_snapshot(game_root.simulation.snapshot())
	if bool(rebuilt.get("ok", false)):
		game_root.world_result = rebuilt
		game_root.interaction_controller.world_result = rebuilt
		game_root.simulation.configure_map_interactions(rebuilt.get("map", {}).get("interaction_targets", {}))
	game_root._setup_world_container()
	WorldSceneRenderer.new().render_world(game_root.world_container, game_root.world_result)
	game_root._setup_runtime_input_controller()
	game_root._refresh_fog_overlay()
	game_root._setup_panels()
	game_root.refresh_all_panels(result.get("prompt", {}))


func _has_pending(game_root: Node) -> bool:
	var snapshot: Dictionary = game_root.simulation.snapshot()
	return not snapshot.get("pending_movement", {}).is_empty() or not snapshot.get("pending_interaction", {}).is_empty()


func _final_interaction_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return true
	return bool(result.get("consumed_target", false)) \
		or result.has("dialogue_id") \
		or result.has("container") \
		or _has_context_snapshot(result) \
		or bool(result.get("waited", false)) \
		or bool(result.get("defeated", false))


func _has_context_snapshot(result: Dictionary) -> bool:
	var context: Variant = result.get("context_snapshot", {})
	if typeof(context) != TYPE_DICTIONARY:
		return false
	var context_dictionary: Dictionary = context
	return not context_dictionary.is_empty()


func _speaker_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/SpeakerLine").text


func _text_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/TextLine").text


func _options_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/OptionsLine").text


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)


func _expect_key_advances_dialogue_without_options(errors: Array[String], game_root: Node, key: int, label: String) -> void:
	game_root.close_trade_panel()
	game_root.simulation.close_dialogue(1, "smoke_reset")
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		errors.append("%s dialogue advance setup missing player actor" % label)
		return
	actor.active_dialogue_id = "trader_lao_wang_intro"
	actor.active_dialogue_node_id = "accept_confirm"
	game_root.refresh_dialogue_panel()
	if not game_root.dialogue_panel.visible:
		errors.append("%s dialogue advance setup should show confirmation dialogue" % label)
	if not _options_line(game_root).is_empty():
		errors.append("%s dialogue advance setup should not expose options" % label)
	var before_events: int = game_root.simulation.snapshot().get("events", []).size()
	_press_key(game_root, key)
	if not str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("%s should finish dialogue node without choices" % label)
	if game_root.dialogue_panel.visible:
		errors.append("%s should hide dialogue panel after finishing no-option node" % label)
	if game_root.simulation.snapshot().get("events", []).size() <= before_events:
		errors.append("%s should emit dialogue advancement or finish event" % label)


func _player(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}
