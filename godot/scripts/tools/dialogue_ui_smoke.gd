extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	var errors: Array[String] = await _run_checks(game_root)
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
	_finish_presentations(game_root)

	if game_root.dialogue_panel == null:
		return ["dialogue panel was not created"]
	if not game_root.dialogue_panel.visible:
		errors.append("dialogue panel is not visible after talk")
	_assert_panel_mouse_blocker(errors, game_root.dialogue_panel, "DialoguePanel", "dialogue open")
	if _speaker_line(game_root) != "老王":
		errors.append("dialogue speaker mismatch: %s" % _speaker_line(game_root))
	if result.get("dialogue_id", "") != "trader_lao_wang_tutorial_active":
		errors.append("talk should use dialogue rule variant for tutorial-active trader")
	if not _text_line(game_root).contains("警戒区"):
		errors.append("dialogue text missing start node")
	if not _target_line(game_root).contains("老王"):
		errors.append("dialogue target line should show target actor display name")
	var dialogue_snapshot: Dictionary = DialogueSnapshot.new(game_root.registry).build(game_root.simulation.snapshot())
	var portrait_asset := _dictionary_or_empty(dialogue_snapshot.get("portrait_asset", {}))
	if str(portrait_asset.get("reason", "")) != "legacy_root_asset_reference":
		errors.append("dialogue snapshot should expose legacy portrait path diagnostic: %s" % portrait_asset)
	if str(portrait_asset.get("fallback_key", "")) != "portrait":
		errors.append("dialogue snapshot should expose portrait fallback key: %s" % portrait_asset)
	var text_scroll: ScrollContainer = _text_scroll(game_root)
	if text_scroll == null:
		errors.append("dialogue text should be wrapped in a scroll container")
	elif text_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		errors.append("dialogue text scroll should disable horizontal scrolling")
	if str(game_root.dialogue_panel.get_meta("dialogue_id", "")) != "trader_lao_wang_tutorial_active":
		errors.append("dialogue panel diagnostic meta should expose dialogue id")
	if int(game_root.dialogue_panel.get_meta("target_actor_id", 0)) <= 0:
		errors.append("dialogue panel diagnostic meta should expose target actor id")
	if not _options_line(game_root).contains("看看货") or not _options_line(game_root).contains("明白"):
		errors.append("dialogue options missing expected choices")
	if not _options_line(game_root).contains("选择:"):
		errors.append("dialogue options line should show explicit choice hint")
	var close_button: Button = _close_button(game_root)
	if close_button == null:
		errors.append("dialogue panel should expose close button")
	elif not str(close_button.tooltip_text).contains("关闭对话"):
		errors.append("dialogue close button should expose tooltip")
	var trade_button: Button = _option_button(game_root, 2)
	if trade_button == null:
		errors.append("dialogue panel should expose option button 2")
	elif not str(trade_button.text).contains("看看货"):
		errors.append("dialogue option button 2 should show option text")
	elif not str(trade_button.tooltip_text).contains("trade_action"):
		errors.append("dialogue option button tooltip should expose next node id")
	var before_events: int = game_root.simulation.snapshot().get("events", []).size()
	_press_key(game_root, KEY_SPACE)
	if not _player(game_root).get("active_dialogue_id", "") == "trader_lao_wang_tutorial_active":
		errors.append("Space should not close dialogue when choices are available")
	if game_root.simulation.snapshot().get("events", []).size() != before_events:
		errors.append("Space on choice dialogue should not advance world turn or emit events")
	if trade_button != null:
		trade_button.pressed.emit()
		await process_frame
	if not game_root.trade_panel.visible:
		errors.append("dialogue option button should choose trade dialogue option and open trade")
	if not _player(game_root).get("active_dialogue_id", "") == "":
		errors.append("dialogue option button should close active dialogue after trade action")
	await _expect_close_button_closes_dialogue(errors, game_root)
	_expect_key_advances_dialogue_without_options(errors, game_root, KEY_SPACE, "Space")
	_expect_key_advances_dialogue_without_options(errors, game_root, KEY_ENTER, "Enter")
	_expect_missing_dialogue_fallback(errors, game_root)
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
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/DialogueHeader/SpeakerLine").text


func _target_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/TargetLine").text


func _text_line(game_root: Node) -> String:
	var label: Label = game_root.dialogue_panel.find_child("TextLine", true, false) as Label
	return "" if label == null else label.text


func _text_scroll(game_root: Node) -> ScrollContainer:
	return game_root.dialogue_panel.find_child("TextScroll", true, false) as ScrollContainer


func _options_line(game_root: Node) -> String:
	return game_root.dialogue_panel.get_node("DialoguePanel/DialogueLines/OptionsLine").text


func _option_button(game_root: Node, index: int) -> Button:
	return game_root.dialogue_panel.find_child("DialogueOption_%d" % index, true, false) as Button


func _close_button(game_root: Node) -> Button:
	return game_root.dialogue_panel.find_child("CloseButton", true, false) as Button


func _option_button_count(game_root: Node) -> int:
	var box: Node = game_root.dialogue_panel.get_node_or_null("DialoguePanel/DialogueLines/OptionButtons")
	if box == null:
		return 0
	return box.get_child_count()


func _assert_panel_mouse_blocker(errors: Array[String], panel: Control, content_name: String, context: String) -> void:
	if panel == null:
		errors.append("%s: panel should exist" % context)
		return
	if panel.mouse_filter != Control.MOUSE_FILTER_STOP:
		errors.append("%s: panel root should stop mouse input" % context)
	var content := panel.find_child(content_name, true, false) as Control
	if content == null or content.mouse_filter != Control.MOUSE_FILTER_STOP:
		errors.append("%s: %s should stop mouse input" % [context, content_name])


func _finish_presentations(game_root: Node) -> void:
	if game_root.has_method("finish_world_action_presentations"):
		game_root.finish_world_action_presentations()


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
	if not _options_line(game_root).contains("Space / Enter 继续"):
		errors.append("%s dialogue advance setup should show no-choice continue hint" % label)
	if _option_button_count(game_root) != 0:
		errors.append("%s dialogue advance setup should not expose option buttons" % label)
	var before_events: int = game_root.simulation.snapshot().get("events", []).size()
	_press_key(game_root, key)
	if not str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("%s should finish dialogue node without choices" % label)
	if game_root.dialogue_panel.visible:
		errors.append("%s should hide dialogue panel after finishing no-option node" % label)
	if game_root.simulation.snapshot().get("events", []).size() <= before_events:
		errors.append("%s should emit dialogue advancement or finish event" % label)


func _expect_close_button_closes_dialogue(errors: Array[String], game_root: Node) -> void:
	game_root.close_trade_panel()
	game_root.simulation.close_dialogue(1, "smoke_reset")
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		errors.append("close button setup missing player actor")
		return
	actor.active_dialogue_id = "trader_lao_wang_intro"
	actor.active_dialogue_node_id = ""
	game_root.refresh_dialogue_panel()
	var close_button: Button = _close_button(game_root)
	if close_button == null:
		errors.append("close button setup should find close button")
		return
	var before_events: int = game_root.simulation.snapshot().get("events", []).size()
	close_button.pressed.emit()
	await process_frame
	if not str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("dialogue close button should clear active dialogue runtime state")
	if game_root.dialogue_panel.visible:
		errors.append("dialogue close button should hide dialogue panel")
	if game_root.simulation.snapshot().get("events", []).size() <= before_events:
		errors.append("dialogue close button should emit dialogue_closed event")


func _expect_missing_dialogue_fallback(errors: Array[String], game_root: Node) -> void:
	game_root.close_trade_panel()
	game_root.simulation.close_dialogue(1, "smoke_reset")
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		errors.append("missing dialogue fallback setup missing player actor")
		return
	actor.active_dialogue_id = "missing_dialogue_smoke"
	actor.active_dialogue_node_id = ""
	game_root.refresh_dialogue_panel()
	if not game_root.dialogue_panel.visible:
		errors.append("missing dialogue fallback should keep dialogue panel visible")
	if _speaker_line(game_root) != "对话":
		errors.append("missing dialogue fallback should show generic speaker")
	if not _text_line(game_root).contains("missing_dialogue_smoke"):
		errors.append("missing dialogue fallback should show missing dialogue id")
	if not _options_line(game_root).contains("Space / Enter 继续"):
		errors.append("missing dialogue fallback should expose no-choice continue hint")
	if bool(game_root.dialogue_panel.get_meta("dialogue_id", "") != "missing_dialogue_smoke"):
		errors.append("missing dialogue fallback should preserve dialogue id meta")
	_press_key(game_root, KEY_SPACE)
	if not str(_player(game_root).get("active_dialogue_id", "")).is_empty():
		errors.append("Space should close missing dialogue fallback")
	if game_root.dialogue_panel.visible:
		errors.append("missing dialogue fallback should hide after Space")
	var payload: Dictionary = _last_event_payload(game_root, "dialogue_finished")
	if str(payload.get("end_type", "")) != "missing_dialogue":
		errors.append("missing dialogue fallback should emit missing_dialogue end type")


func _player(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _last_event_payload(game_root: Node, kind: String) -> Dictionary:
	var events: Array = game_root.simulation.snapshot().get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
