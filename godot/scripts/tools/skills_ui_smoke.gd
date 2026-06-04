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
	if not _detail_text(game_root).contains("详情: 战斗训练 0/5"):
		errors.append("skills detail should select the first visible skill by default")
	if not _press_skill_line(game_root, "medicine"):
		errors.append("should select medicine skill row")
	await process_frame
	if not _detail_text(game_root).contains("详情: 医疗知识 0/3"):
		errors.append("skills detail should show selected skill title")
	if not _detail_text(game_root).contains("提升治疗与恢复相关判定"):
		errors.append("skills detail should show selected skill description")
	if not _detail_text(game_root).contains("前置: 生存本能"):
		errors.append("skills detail should show prerequisite names")
	if not _detail_text(game_root).contains("属性: 体质 6"):
		errors.append("skills detail should show attribute requirements")
	if _learn_button(game_root, "medicine") == null or not _learn_button(game_root, "medicine").disabled:
		errors.append("medicine learn button should be disabled before survival prerequisite")
	if _filter_button(game_root, "FilterActiveButton") == null:
		errors.append("skills panel should expose active filter button")
	else:
		_filter_button(game_root, "FilterActiveButton").pressed.emit()
		await process_frame
		if not _skill_text(game_root).contains("肾上腺激发 0/3"):
			errors.append("active filter should keep active skill rows")
		if not _skill_text(game_root).contains("低姿潜行 0/3"):
			errors.append("active filter should keep toggle skill rows")
		if _skill_text(game_root).contains("生存本能 0/5"):
			errors.append("active filter should hide passive skill rows")
		if _filter_button(game_root, "FilterAllButton") == null:
			errors.append("skills panel should expose all filter button")
		else:
			_filter_button(game_root, "FilterAllButton").pressed.emit()
			await process_frame
			if not _skill_text(game_root).contains("生存本能 0/5"):
				errors.append("all filter should restore passive skill rows")
	if _tree_filter_button(game_root, "survival") == null:
		errors.append("skills panel should expose survival tree filter button")
	else:
		_tree_filter_button(game_root, "survival").pressed.emit()
		await process_frame
		if not _skill_text(game_root).contains("生存本能 0/5"):
			errors.append("survival tree filter should keep survival skill rows")
		if _skill_text(game_root).contains("战斗训练 0/5"):
			errors.append("survival tree filter should hide combat skill rows")
		if _tree_filter_button(game_root, "all") == null:
			errors.append("skills panel should expose all tree filter button")
		else:
			_tree_filter_button(game_root, "all").pressed.emit()
			await process_frame
			if not _skill_text(game_root).contains("战斗训练 0/5"):
				errors.append("all tree filter should restore combat skill rows")

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
	var combat_effect: Dictionary = _active_skill_effect(game_root, "combat")
	if combat_effect.is_empty():
		errors.append("learning passive combat skill should add active effect snapshot entry")
	elif absf(float(_dictionary_or_empty(combat_effect.get("modifiers", {})).get("damage_bonus", 0.0)) - 0.04) > 0.001:
		errors.append("combat passive skill should expose damage_bonus 0.04")
	if not _event_seen(game_root, "skill_passive_effect_refreshed"):
		errors.append("learning passive combat skill should emit skill_passive_effect_refreshed")
	var active_result: Dictionary = game_root.learn_player_skill("adrenaline_rush")
	if not bool(active_result.get("success", false)):
		errors.append("adrenaline_rush learn failed: %s" % active_result.get("reason", "unknown"))
	if _bind_button(game_root, "adrenaline_rush") == null or _bind_button(game_root, "adrenaline_rush").disabled:
		errors.append("learned active skill should allow hotbar binding")
	_bind_button(game_root, "adrenaline_rush").pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("slot_1:adrenaline_rush"):
		errors.append("skills panel should show bound hotbar skill")
	game_root.refresh_hud()
	if not _hud_hotbar_slot_text(game_root, "slot_1").contains("Adre"):
		errors.append("HUD hotbar should show bound adrenaline rush in slot 1")
	if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("Adrenaline Rush"):
		errors.append("HUD hotbar slot should expose skill tooltip")
	if _use_button(game_root, "adrenaline_rush") == null or _use_button(game_root, "adrenaline_rush").disabled:
		errors.append("bound active skill should be usable before cooldown")
	if not _skill_line(game_root, "adrenaline_rush").contains("可用"):
		errors.append("bound active skill should show available use state")
	if not _skill_line(game_root, "adrenaline_rush").contains("AP 2"):
		errors.append("bound active skill should show activation AP cost")
	if not _press_skill_line(game_root, "adrenaline_rush"):
		errors.append("should select adrenaline rush skill row")
	await process_frame
	if not _detail_text(game_root).contains("详情: 肾上腺激发 1/3"):
		errors.append("skills detail should show active skill level")
	if not _detail_text(game_root).contains("类型: 主动"):
		errors.append("skills detail should show active skill type")
	if not _detail_text(game_root).contains("激活: AP 2 | 冷却 20s | 绑定 slot_1 | 使用 可用"):
		errors.append("skills detail should show active skill activation state")
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
	var ap_before_skill: float = _player_ap(game_root)
	_press_key(game_root, KEY_1)
	await process_frame
	game_root.refresh_skills_panel()
	var skill_event: Dictionary = _last_event(game_root, "skill_used")
	var active_effect: Dictionary = _active_skill_effect(game_root, "adrenaline_rush")
	if abs(_player_ap(game_root) - (ap_before_skill - 2.0)) > 0.001:
		errors.append("hotbar skill activation should spend activation AP cost")
	if not _hotbar_line(game_root).contains("cd20"):
		errors.append("digit 1 hotbar activation should write cooldown to hotbar")
	if active_effect.is_empty():
		errors.append("hotbar skill activation should add adrenaline_rush active effect to player snapshot")
	elif absf(float(_dictionary_or_empty(active_effect.get("modifiers", {})).get("damage_bonus", 0.0)) - 0.25) > 0.001:
		errors.append("adrenaline_rush active effect should expose level 1 damage_bonus")
	game_root.refresh_hud()
	if not _hud_hotbar_slot_text(game_root, "slot_1").contains("cd20"):
		errors.append("HUD hotbar should show cooldown after hotbar activation")
	if not _hud_hotbar_slot_disabled(game_root, "slot_1"):
		errors.append("HUD hotbar slot should be disabled while cooldown remains")
	if not _hud_hotbar_slot_tooltip(game_root, "slot_1").contains("冷却 20s"):
		errors.append("HUD hotbar slot tooltip should show cooldown")
	if not _skill_line(game_root, "adrenaline_rush").contains("冷却 20s"):
		errors.append("used active skill should show cooldown use state")
	if not _detail_text(game_root).contains("使用 冷却 20s"):
		errors.append("skills detail should refresh active skill cooldown state")
	if _use_button(game_root, "adrenaline_rush") == null or not _use_button(game_root, "adrenaline_rush").disabled:
		errors.append("active skill use button should be disabled while on cooldown")
	if not _event_seen(game_root, "skill_used"):
		errors.append("digit 1 hotbar activation should emit skill_used")
	if abs(float(_dictionary_or_empty(skill_event.get("payload", {})).get("ap_cost", 0.0)) - 2.0) > 0.001:
		errors.append("skill_used event should include activation AP cost")
	var event_effect: Dictionary = _dictionary_or_empty(_dictionary_or_empty(skill_event.get("payload", {})).get("effect", {}))
	if absf(float(_dictionary_or_empty(event_effect.get("modifiers", {})).get("damage_bonus", 0.0)) - 0.25) > 0.001:
		errors.append("skill_used event should include resolved damage_bonus effect modifier")
	return errors


func _summary_line(game_root: Node) -> String:
	return game_root.skills_panel.get_node("SkillsPanel/SkillsLines/SummaryLine").text


func _hotbar_line(game_root: Node) -> String:
	return game_root.skills_panel.get_node("SkillsPanel/SkillsLines/HotbarLine").text


func _hud_hotbar_slot_text(game_root: Node, slot_id: String) -> String:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	if button == null:
		return ""
	return str(button.text)


func _hud_hotbar_slot_tooltip(game_root: Node, slot_id: String) -> String:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	if button == null:
		return ""
	return str(button.tooltip_text)


func _hud_hotbar_slot_disabled(game_root: Node, slot_id: String) -> bool:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	return button == null or button.disabled


func _skill_lines(game_root: Node) -> Array[String]:
	var output: Array[String] = []
	var tree_box: Node = game_root.skills_panel.get_node("SkillsPanel/SkillsLines/TreeLines")
	for child in tree_box.get_children():
		if child is Label:
			output.append((child as Label).text)
		elif child is HBoxContainer:
			var line: Node = child.get_node("Line")
			if line is Button:
				output.append((line as Button).text)
			elif line is Label:
				output.append((line as Label).text)
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
	if label is Button:
		return str((label as Button).text)
	return ""


func _press_skill_line(game_root: Node, skill_id: String) -> bool:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return false
	var line: Button = row.get_node("Line") as Button
	if line == null:
		return false
	line.pressed.emit()
	return true


func _detail_text(game_root: Node) -> String:
	var title: Node = game_root.skills_panel.find_child("DetailTitleLine", true, false)
	var body: Node = game_root.skills_panel.find_child("DetailBodyLine", true, false)
	var parts: Array[String] = []
	if title is Label:
		parts.append((title as Label).text)
	if body is Label:
		parts.append((body as Label).text)
	return "\n".join(parts)


func _filter_button(game_root: Node, node_name: String) -> Button:
	return game_root.skills_panel.find_child(node_name, true, false) as Button


func _tree_filter_button(game_root: Node, tree_id: String) -> Button:
	var node_name: String = "TreeFilterAllButton" if tree_id == "all" else "TreeFilter_%s" % tree_id
	return game_root.skills_panel.find_child(node_name, true, false) as Button


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


func _last_event(game_root: Node, kind: String) -> Dictionary:
	var events: Array = game_root.simulation.snapshot().get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = events[index]
		if str(event_data.get("kind", "")) == kind:
			return event_data
	return {}


func _player_ap(game_root: Node) -> float:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return float(actor_data.get("ap", 0.0))
	return 0.0


func _active_skill_effect(game_root: Node, skill_id: String) -> Dictionary:
	for effect in _dictionary_or_empty(_player_actor_snapshot(game_root).get("combat", {})).get("active_effects", []):
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		if str(effect_data.get("skill_id", "")) == skill_id:
			return effect_data
	return {}


func _player_actor_snapshot(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = actor
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)
