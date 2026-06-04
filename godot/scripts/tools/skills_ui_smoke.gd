extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")


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
	if not _learn_confirm_dialog_visible(game_root):
		errors.append("survival learn button should open skill learn confirmation dialog")
	if not _summary_line(game_root).contains("技能点 1"):
		errors.append("opening skill learn confirmation should not consume skill point")
	if not bool(game_root.gameplay_input_blocked_by_ui()):
		errors.append("skill learn confirmation should block gameplay input")
	if str(game_root.gameplay_input_blocker_name()) != "modal:skill_learn_confirm":
		errors.append("skill learn confirmation blocker should be modal:skill_learn_confirm")
	var esc_learn_result: Dictionary = game_root.close_active_ui("keyboard_escape")
	if str(esc_learn_result.get("closed", "")) != "modal:skill_learn_confirm":
		errors.append("Esc should close skill learn confirmation before skills stage panel")
	if _learn_confirm_dialog_visible(game_root):
		errors.append("Esc should hide skill learn confirmation")
	if not _summary_line(game_root).contains("技能点 1"):
		errors.append("Esc cancelling skill learn confirmation should keep skill point")
	_learn_button(game_root, "survival").pressed.emit()
	await process_frame
	_confirm_learn_dialog(game_root)
	await process_frame
	if not _summary_line(game_root).contains("技能点 0"):
		errors.append("skills summary did not refresh consumed skill point")
	if not _skill_text(game_root).contains("生存本能 1/5"):
		errors.append("skills panel did not show learned survival level")
	if not _event_seen(game_root, "skill_learned"):
		errors.append("learning from skills panel should emit skill_learned")
	if not _feedback_line(game_root).contains("已学习 生存本能"):
		errors.append("learning passive skill should show learned feedback")

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
	game_root.refresh_skills_panel()
	if _learn_button(game_root, "adrenaline_rush") == null or _learn_button(game_root, "adrenaline_rush").disabled:
		errors.append("adrenaline_rush learn button should be enabled after combat prerequisite")
	else:
		_learn_button(game_root, "adrenaline_rush").pressed.emit()
		await process_frame
		_confirm_learn_dialog(game_root)
		await process_frame
	if not _skill_text(game_root).contains("肾上腺激发 1/3"):
		errors.append("adrenaline_rush should be learned through skills UI confirmation")
	if not _feedback_line(game_root).contains("已学习 肾上腺激发") or not _feedback_line(game_root).contains("可绑定到快捷栏"):
		errors.append("learning active skill should suggest hotbar binding")
	if _bind_button(game_root, "adrenaline_rush") == null or _bind_button(game_root, "adrenaline_rush").disabled:
		errors.append("learned active skill should allow hotbar binding")
	if not _drag_skill_to_hud_hotbar(game_root, "adrenaline_rush", "slot_3"):
		errors.append("dragging learned active skill to HUD hotbar should be accepted")
	await process_frame
	if not _hotbar_line(game_root).contains("slot_3:adrenaline_rush"):
		errors.append("skills panel should show dragged hotbar skill")
	game_root.refresh_hud()
	if not _hud_hotbar_slot_text(game_root, "slot_3").contains("Adre"):
		errors.append("HUD hotbar should show dragged adrenaline rush in slot 3")
	if not _hud_hotbar_slot_tooltip(game_root, "slot_3").contains("Adrenaline Rush"):
		errors.append("HUD hotbar slot should expose skill tooltip")
	if _hud_hotbar_cooldown_mask_visible(game_root, "slot_3"):
		errors.append("HUD hotbar cooldown mask should stay hidden before skill cooldown")
	if _use_button(game_root, "adrenaline_rush") == null or _use_button(game_root, "adrenaline_rush").disabled:
		errors.append("bound active skill should be usable before cooldown")
	if not _skill_line(game_root, "adrenaline_rush").contains("可用"):
		errors.append("bound active skill should show available use state")
	if not _skill_line(game_root, "adrenaline_rush").contains("AP 2"):
		errors.append("bound active skill should show activation AP cost")
	var skill_library_before_resource_cost: Dictionary = game_root.registry.libraries.get("skills", {}).duplicate(true)
	_patch_adrenaline_resource_cost(game_root, {"stamina": 3.0})
	_set_player_resource(game_root, "stamina", 5.0, 10.0)
	game_root.refresh_skills_panel()
	if not _skill_line(game_root, "adrenaline_rush").contains("资源 stamina 3"):
		errors.append("bound active skill should show activation resource cost")
	game_root.refresh_hud()
	if not _hud_hotbar_slot_tooltip(game_root, "slot_3").contains("资源 stamina 3"):
		errors.append("HUD hotbar slot tooltip should show activation resource cost")
	if not _press_skill_line(game_root, "adrenaline_rush"):
		errors.append("should select adrenaline rush skill row")
	await process_frame
	if not _detail_text(game_root).contains("详情: 肾上腺激发 1/3"):
		errors.append("skills detail should show active skill level")
	if not _detail_text(game_root).contains("类型: 主动"):
		errors.append("skills detail should show active skill type")
	if not _detail_text(game_root).contains("激活: AP 2 | 资源 stamina 3 | 冷却 20s | 绑定 slot_3 | 使用 可用"):
		errors.append("skills detail should show active skill activation state")
	var toggle_result: Dictionary = game_root.learn_player_skill("low_profile")
	if not bool(toggle_result.get("success", false)):
		errors.append("low_profile learn failed: %s" % toggle_result.get("reason", "unknown"))
	if _bind_button(game_root, "low_profile") == null or _bind_button(game_root, "low_profile").disabled:
		errors.append("learned toggle skill should allow hotbar binding")
	_bind_button(game_root, "low_profile").pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("slot_3:adrenaline_rush"):
		errors.append("binding a second skill should keep dragged hotbar slot")
	if not _hotbar_line(game_root).contains("slot_1:low_profile"):
		errors.append("second auto-bound skill should use the first empty hotbar slot")
	if _clear_button(game_root, "low_profile") == null or _clear_button(game_root, "low_profile").disabled:
		errors.append("bound toggle skill should expose enabled clear button")
	_clear_button(game_root, "low_profile").pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("slot_3:adrenaline_rush"):
		errors.append("clearing second hotbar slot should keep dragged slot")
	if _hotbar_line(game_root).contains("slot_1:low_profile"):
		errors.append("cleared hotbar slot should disappear from skills panel")
	if not _event_seen(game_root, "hotbar_unbound"):
		errors.append("clearing hotbar slot from skills panel should emit hotbar_unbound")
	game_root.panel_controller.close_stage_panels()
	var ap_before_skill: float = _player_ap(game_root)
	var stamina_before_skill: float = _player_resource_current(game_root, "stamina")
	_press_key(game_root, KEY_3)
	await process_frame
	game_root.refresh_skills_panel()
	var skill_event: Dictionary = _last_event(game_root, "skill_used")
	var active_effect: Dictionary = _active_skill_effect(game_root, "adrenaline_rush")
	if abs(_player_ap(game_root) - (ap_before_skill - 2.0)) > 0.001:
		errors.append("hotbar skill activation should spend activation AP cost")
	if abs(_player_resource_current(game_root, "stamina") - (stamina_before_skill - 3.0)) > 0.001:
		errors.append("hotbar skill activation should spend activation resource cost")
	if not _hotbar_line(game_root).contains("cd20"):
		errors.append("digit 3 hotbar activation should write cooldown to hotbar")
	if active_effect.is_empty():
		errors.append("hotbar skill activation should add adrenaline_rush active effect to player snapshot")
	elif absf(float(_dictionary_or_empty(active_effect.get("modifiers", {})).get("damage_bonus", 0.0)) - 0.25) > 0.001:
		errors.append("adrenaline_rush active effect should expose level 1 damage_bonus")
	game_root.refresh_hud()
	if not _hud_hotbar_slot_text(game_root, "slot_3").contains("cd20"):
		errors.append("HUD hotbar should show cooldown after hotbar activation")
	if not _hud_hotbar_slot_disabled(game_root, "slot_3"):
		errors.append("HUD hotbar slot should be disabled while cooldown remains")
	if not _hud_hotbar_slot_tooltip(game_root, "slot_3").contains("冷却 20s"):
		errors.append("HUD hotbar slot tooltip should show cooldown")
	if not _hud_hotbar_cooldown_mask_visible(game_root, "slot_3"):
		errors.append("HUD hotbar should show cooldown mask while cooldown remains")
	if absf(_hud_hotbar_cooldown_mask_value(game_root, "slot_3") - 20.0) > 0.001:
		errors.append("HUD hotbar cooldown mask should expose remaining cooldown value")
	if not _skill_line(game_root, "adrenaline_rush").contains("冷却 20s"):
		errors.append("used active skill should show cooldown use state")
	if not _detail_text(game_root).contains("使用 冷却 20s"):
		errors.append("skills detail should refresh active skill cooldown state")
	if _use_button(game_root, "adrenaline_rush") == null or not _use_button(game_root, "adrenaline_rush").disabled:
		errors.append("active skill use button should be disabled while on cooldown")
	if not _event_seen(game_root, "skill_used"):
		errors.append("digit 3 hotbar activation should emit skill_used")
	if abs(float(_dictionary_or_empty(skill_event.get("payload", {})).get("ap_cost", 0.0)) - 2.0) > 0.001:
		errors.append("skill_used event should include activation AP cost")
	var spent_resources: Array = _array_or_empty(_dictionary_or_empty(skill_event.get("payload", {})).get("spent_resources", []))
	if spent_resources.is_empty() or str(_dictionary_or_empty(spent_resources[0]).get("resource", "")) != "stamina":
		errors.append("skill_used event should include spent stamina resource")
	var event_effect: Dictionary = _dictionary_or_empty(_dictionary_or_empty(skill_event.get("payload", {})).get("effect", {}))
	if absf(float(_dictionary_or_empty(event_effect.get("modifiers", {})).get("damage_bonus", 0.0)) - 0.25) > 0.001:
		errors.append("skill_used event should include resolved damage_bonus effect modifier")
	var ap_before_insufficient: float = _player_ap(game_root)
	var stamina_before_insufficient: float = _player_resource_current(game_root, "stamina")
	var insufficient_result: Dictionary = game_root.simulation.submit_player_command({
		"kind": "use_skill",
		"actor_id": 1,
		"skill_id": "adrenaline_rush",
		"skill_library": game_root.registry.get_library("skills"),
		"target": {"target_type": "self"},
	})
	if bool(insufficient_result.get("success", false)) or str(insufficient_result.get("reason", "")) != "resource_insufficient":
		errors.append("resource-insufficient skill use should be rejected")
	if abs(_player_ap(game_root) - ap_before_insufficient) > 0.001:
		errors.append("resource-insufficient skill use should not spend AP")
	if abs(_player_resource_current(game_root, "stamina") - stamina_before_insufficient) > 0.001:
		errors.append("resource-insufficient skill use should not spend resource")
	game_root.refresh_skills_panel()
	game_root.refresh_hud()
	if not _skill_line(game_root, "adrenaline_rush").contains("冷却 20s"):
		errors.append("cooldown should remain the visible blocker while hotbar slot is cooling down")
	var hotbar_slot: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.simulation.snapshot().get("hotbar", {})).get("slot_3", {})).duplicate(true)
	hotbar_slot["cooldown_remaining"] = 0.0
	game_root.simulation.hotbar["slot_3"] = hotbar_slot
	game_root.refresh_hud()
	if not _hud_hotbar_slot_disabled(game_root, "slot_3"):
		errors.append("HUD hotbar slot should be disabled when activation resource is insufficient")
	if not _hud_hotbar_slot_tooltip(game_root, "slot_3").contains("资源不足 stamina 2/3"):
		errors.append("HUD hotbar slot tooltip should show resource-insufficient state")
	game_root.registry.libraries["skills"] = skill_library_before_resource_cost
	await _expect_targeted_hotbar_skill(errors, game_root)
	return errors


func _summary_line(game_root: Node) -> String:
	return game_root.skills_panel.get_node("SkillsPanel/SkillsLines/SummaryLine").text


func _hotbar_line(game_root: Node) -> String:
	return game_root.skills_panel.get_node("SkillsPanel/SkillsLines/HotbarLine").text


func _feedback_line(game_root: Node) -> String:
	var label: Node = game_root.skills_panel.get_node_or_null("SkillsPanel/SkillsLines/FeedbackLine")
	if label is Label and (label as Label).visible:
		return str((label as Label).text)
	return ""


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


func _hud_hotbar_cooldown_mask_visible(game_root: Node, slot_id: String) -> bool:
	var mask: ColorRect = game_root.hud.find_child("HotbarCooldownMask_%s" % slot_id, true, false) as ColorRect
	return mask != null and mask.visible


func _hud_hotbar_cooldown_mask_value(game_root: Node, slot_id: String) -> float:
	var mask: ColorRect = game_root.hud.find_child("HotbarCooldownMask_%s" % slot_id, true, false) as ColorRect
	if mask == null:
		return 0.0
	return float(mask.get_meta("cooldown_remaining", 0.0))


func _skill_targeting_line(game_root: Node) -> String:
	var label: Label = game_root.hud.find_child("SkillTargetingLine", true, false) as Label
	if label == null or not label.visible:
		return ""
	return str(label.text)


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


func _learn_confirm_dialog_visible(game_root: Node) -> bool:
	var dialog: Node = game_root.skills_panel.get_node_or_null("LearnSkillConfirmDialog")
	if dialog is ConfirmationDialog:
		return bool((dialog as ConfirmationDialog).visible)
	return false


func _confirm_learn_dialog(game_root: Node) -> void:
	var dialog: Node = game_root.skills_panel.get_node_or_null("LearnSkillConfirmDialog")
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).confirmed.emit()
		(dialog as ConfirmationDialog).hide()


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


func _drag_skill_to_hud_hotbar(game_root: Node, skill_id: String, slot_id: String) -> bool:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	var hotbar_slot: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	if row == null or hotbar_slot == null:
		return false
	var line: Control = row.get_node("Line") as Control
	if line == null:
		return false
	var drag_data: Variant = game_root.skills_panel._get_skill_drag_data(Vector2.ZERO, line)
	if typeof(drag_data) != TYPE_DICTIONARY:
		return false
	if not game_root.hud._can_drop_hotbar_skill(Vector2.ZERO, drag_data, hotbar_slot):
		return false
	game_root.hud._drop_hotbar_skill(Vector2.ZERO, drag_data, hotbar_slot)
	return true


func _expect_targeted_hotbar_skill(errors: Array[String], game_root: Node) -> void:
	var original_library: Dictionary = game_root.registry.libraries.get("skills", {}).duplicate(true)
	var targeted_library: Dictionary = original_library.duplicate(true)
	var record: Dictionary = _dictionary_or_empty(targeted_library.get("adrenaline_rush", {})).duplicate(true)
	var data: Dictionary = _dictionary_or_empty(record.get("data", {})).duplicate(true)
	var activation: Dictionary = _dictionary_or_empty(data.get("activation", {})).duplicate(true)
	activation["cooldown"] = 0.0
	activation["targeting"] = {
		"kind": "single",
		"policy": "hostile_only",
		"range": 12,
		"requires_los": false,
	}
	data["activation"] = activation
	record["data"] = data
	targeted_library["adrenaline_rush"] = record
	game_root.registry.libraries["skills"] = targeted_library
	var player_grid: Dictionary = _dictionary_or_empty(_player_actor_snapshot(game_root).get("grid_position", {}))
	var hostile_id: int = game_root.simulation.register_actor({
		"definition_id": "skills_ui_target_hostile",
		"display_name": "skills_ui_target_hostile",
		"kind": "enemy",
		"side": "hostile",
		"group_id": "hostile",
		"grid_position": GridCoord.from_dictionary({
			"x": int(player_grid.get("x", 0)) + 2,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		}),
		"max_hp": 10.0,
		"hp": 10.0,
		"attack_power": 4.0,
		"defense": 0.0,
		"combat_attributes": {
			"attack_power": 4.0,
			"defense": 0.0,
		},
		"xp_reward": 0,
	})
	game_root.bind_player_skill_to_hotbar("slot_4", "adrenaline_rush")
	await game_root.get_tree().process_frame
	_press_key(game_root, KEY_4)
	await game_root.get_tree().process_frame
	if not bool(game_root.has_active_skill_targeting()):
		errors.append("targeted hotbar skill should enter target selection mode")
	if hostile_id <= 0:
		errors.append("targeted hotbar skill smoke needs a hostile actor")
	else:
		var preview: Dictionary = game_root.preview_active_skill_target({"target_type": "actor", "actor_id": hostile_id})
		if not bool(preview.get("success", false)):
			errors.append("targeted hotbar skill preview should succeed: %s" % preview.get("reason", "unknown"))
		game_root.refresh_hud()
		if not _skill_targeting_line(game_root).contains("Skill Target"):
			errors.append("HUD should show active skill targeting preview line")
		if not _skill_targeting_line(game_root).contains("1目标"):
			errors.append("HUD skill targeting preview should show affected actor count")
	var esc_result: Dictionary = game_root.close_active_ui("keyboard_escape")
	if str(esc_result.get("closed", "")) != "skill_targeting":
		errors.append("Esc should close active skill targeting before other UI")
	if bool(game_root.has_active_skill_targeting()):
		errors.append("skill targeting should be inactive after Esc")
	_press_key(game_root, KEY_4)
	await game_root.get_tree().process_frame
	if hostile_id > 0:
		var ap_before: float = _player_ap(game_root)
		var result: Dictionary = game_root.confirm_active_skill_target({"target_type": "actor", "actor_id": hostile_id})
		if not bool(result.get("success", false)):
			errors.append("confirming targeted hotbar skill should use skill: %s" % result.get("reason", "unknown"))
		if bool(game_root.has_active_skill_targeting()):
			errors.append("successful targeted skill should leave target selection mode")
		if abs(_player_ap(game_root) - (ap_before - 2.0)) > 0.001:
			errors.append("targeted hotbar skill confirmation should spend activation AP cost")
		var event: Dictionary = _last_event(game_root, "skill_used")
		var event_preview: Dictionary = _dictionary_or_empty(_dictionary_or_empty(event.get("payload", {})).get("target_preview", {}))
		if int(_array_or_empty(event_preview.get("affected_actor_ids", [])).size()) <= 0:
			errors.append("targeted skill_used event should include affected actor ids")
	game_root.registry.libraries["skills"] = original_library
	if game_root.simulation.actor_registry.get_actor(hostile_id) != null:
		game_root.simulation.actor_registry.unregister_actor(hostile_id)
	game_root.refresh_hud()
	game_root.refresh_skills_panel()


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


func _patch_adrenaline_resource_cost(game_root: Node, resource_costs: Dictionary) -> void:
	var skill_library: Dictionary = game_root.registry.libraries.get("skills", {}).duplicate(true)
	var record: Dictionary = _dictionary_or_empty(skill_library.get("adrenaline_rush", {})).duplicate(true)
	var data: Dictionary = _dictionary_or_empty(record.get("data", {})).duplicate(true)
	var activation: Dictionary = _dictionary_or_empty(data.get("activation", {})).duplicate(true)
	activation["resource_costs"] = resource_costs.duplicate(true)
	data["activation"] = activation
	record["data"] = data
	skill_library["adrenaline_rush"] = record
	game_root.registry.libraries["skills"] = skill_library


func _set_player_resource(game_root: Node, resource_id: String, current: float, max_value: float) -> void:
	var actor: RefCounted = game_root.simulation.actor_registry.get_actor(1)
	if actor == null:
		return
	var normalized_id := "hp" if resource_id == "health" else resource_id
	if normalized_id == "hp":
		actor.max_hp = max(1.0, max_value)
		actor.hp = clampf(current, 0.0, actor.max_hp)
		actor.resources["hp"] = {"current": actor.hp, "max": actor.max_hp}
		return
	actor.resources[normalized_id] = {
		"current": clampf(current, 0.0, max(1.0, max_value)),
		"max": max(1.0, max_value),
	}


func _player_resource_current(game_root: Node, resource_id: String) -> float:
	var normalized_id := "hp" if resource_id == "health" else resource_id
	var resources: Dictionary = _dictionary_or_empty(_dictionary_or_empty(_player_actor_snapshot(game_root).get("combat", {})).get("resources", {}))
	return float(_dictionary_or_empty(resources.get(normalized_id, {})).get("current", 0.0))


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


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _press_key(game_root: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	game_root.runtime_input_controller.input(event)
