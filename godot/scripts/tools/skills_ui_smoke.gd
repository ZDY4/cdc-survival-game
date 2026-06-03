extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")


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

	print("skills_ui_smoke passed:")
	print(JSON.stringify({
		"summary": _summary_line(game_root),
		"skills": _skill_lines(game_root).slice(0, 5),
	}, "\t"))
	quit(0)


func _run_checks(game_root: Node) -> Array[String]:
	var errors: Array[String] = []
	if game_root.skills_panel == null:
		return ["skills panel was not created"]
	if not _summary_line(game_root).contains("技能点 0"):
		errors.append("initial skills summary should show zero skill points")
	if not _skill_text(game_root).contains("生存本能 0/5"):
		errors.append("skills panel missing survival skill row")
	if not _skill_text(game_root).contains("医疗知识 0/3"):
		errors.append("skills panel missing medicine skill row")
	if _learn_button(game_root, "medicine") == null or not _learn_button(game_root, "medicine").disabled:
		errors.append("medicine learn button should be disabled before survival prerequisite")

	var grant_result: Dictionary = game_root.simulation.grant_skill_points(1, 1, "skills_ui_smoke")
	if not bool(grant_result.get("success", false)):
		errors.append("grant skill points failed: %s" % grant_result.get("reason", "unknown"))
	game_root.refresh_skills_panel()
	if not _summary_line(game_root).contains("技能点 1"):
		errors.append("skills summary did not refresh granted skill points")
	if _learn_button(game_root, "survival") == null or _learn_button(game_root, "survival").disabled:
		errors.append("survival learn button should be enabled after granting skill point")

	_learn_button(game_root, "survival").pressed.emit()
	await process_frame
	if not _summary_line(game_root).contains("技能点 0"):
		errors.append("skills summary did not refresh consumed skill point")
	if not _skill_text(game_root).contains("生存本能 1/5"):
		errors.append("skills panel did not show learned survival level")
	if not _event_seen(game_root, "skill_learned"):
		errors.append("learning from skills panel should emit skill_learned")

	game_root.simulation.grant_skill_points(1, 1, "skills_ui_smoke")
	game_root.refresh_skills_panel()
	if _learn_button(game_root, "medicine") == null or _learn_button(game_root, "medicine").disabled:
		errors.append("medicine learn button should become enabled after survival prerequisite")
	game_root.simulation.grant_skill_points(1, 2, "skills_ui_smoke")
	var combat_result: Dictionary = game_root.learn_player_skill("combat")
	if not bool(combat_result.get("success", false)):
		errors.append("combat learn failed: %s" % combat_result.get("reason", "unknown"))
	var active_result: Dictionary = game_root.learn_player_skill("adrenaline_rush")
	if not bool(active_result.get("success", false)):
		errors.append("adrenaline_rush learn failed: %s" % active_result.get("reason", "unknown"))
	if _bind_button(game_root, "adrenaline_rush") == null or _bind_button(game_root, "adrenaline_rush").disabled:
		errors.append("learned active skill should allow hotbar binding")
	_bind_button(game_root, "adrenaline_rush").pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("slot_1:adrenaline_rush"):
		errors.append("skills panel should show bound hotbar skill")
	if _use_button(game_root, "adrenaline_rush") == null or _use_button(game_root, "adrenaline_rush").disabled:
		errors.append("bound active skill should be usable before cooldown")
	if not _skill_line(game_root, "adrenaline_rush").contains("可用"):
		errors.append("bound active skill should show available use state")
	var toggle_result: Dictionary = game_root.learn_player_skill("low_profile")
	if not bool(toggle_result.get("success", false)):
		errors.append("low_profile learn failed: %s" % toggle_result.get("reason", "unknown"))
	if _bind_button(game_root, "low_profile") == null or _bind_button(game_root, "low_profile").disabled:
		errors.append("learned toggle skill should allow hotbar binding")
	_bind_button(game_root, "low_profile").pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("slot_1:adrenaline_rush"):
		errors.append("binding a second skill should keep first hotbar slot")
	if not _hotbar_line(game_root).contains("slot_2:low_profile"):
		errors.append("second auto-bound skill should use the first empty hotbar slot")
	if _clear_button(game_root, "low_profile") == null or _clear_button(game_root, "low_profile").disabled:
		errors.append("bound toggle skill should expose enabled clear button")
	_clear_button(game_root, "low_profile").pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("slot_1:adrenaline_rush"):
		errors.append("clearing second hotbar slot should keep first slot")
	if _hotbar_line(game_root).contains("slot_2:low_profile"):
		errors.append("cleared hotbar slot should disappear from skills panel")
	if not _event_seen(game_root, "hotbar_unbound"):
		errors.append("clearing hotbar slot from skills panel should emit hotbar_unbound")
	game_root.panel_controller.close_stage_panels()
	_press_key(game_root, KEY_1)
	await process_frame
	game_root.refresh_skills_panel()
	if not _hotbar_line(game_root).contains("cd20"):
		errors.append("digit 1 hotbar activation should write cooldown to hotbar")
	if not _skill_line(game_root, "adrenaline_rush").contains("冷却 20s"):
		errors.append("used active skill should show cooldown use state")
	if _use_button(game_root, "adrenaline_rush") == null or not _use_button(game_root, "adrenaline_rush").disabled:
		errors.append("active skill use button should be disabled while on cooldown")
	if not _event_seen(game_root, "skill_used"):
		errors.append("digit 1 hotbar activation should emit skill_used")
	return errors


func _summary_line(game_root: Node) -> String:
	return game_root.skills_panel.get_node("SkillsPanel/SkillsLines/SummaryLine").text


func _hotbar_line(game_root: Node) -> String:
	return game_root.skills_panel.get_node("SkillsPanel/SkillsLines/HotbarLine").text


func _skill_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var tree_box: Node = game_root.skills_panel.get_node("SkillsPanel/SkillsLines/TreeLines")
	for child in tree_box.get_children():
		if child is Label:
			output.append((child as Label).text)
		elif child is HBoxContainer:
			var line: Label = child.get_node("Line")
			output.append(line.text)
	return output


func _skill_text(game_root: Node) -> String:
	return "\n".join(_skill_lines(game_root))


func _skill_line(game_root: Node, skill_id: String) -> String:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return ""
	var label: Node = row.get_node_or_null("Line")
	if label is Label:
		return str((label as Label).text)
	return ""


func _learn_button(game_root: Node, skill_id: String) -> Button:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return null
	return row.get_node("LearnButton") as Button


func _bind_button(game_root: Node, skill_id: String) -> Button:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return null
	return row.get_node("BindButton") as Button


func _use_button(game_root: Node, skill_id: String) -> Button:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return null
	return row.get_node("UseButton") as Button


func _clear_button(game_root: Node, skill_id: String) -> Button:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return null
	return row.get_node("ClearButton") as Button


func _event_seen(game_root: Node, kind: String) -> bool:
	for event in game_root.simulation.snapshot().get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			return true
	return false


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)
