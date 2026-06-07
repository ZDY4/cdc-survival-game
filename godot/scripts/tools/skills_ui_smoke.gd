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
	if not _skill_line_has_icon(game_root, "survival", "res://assets/icons/skills/survival.svg"):
		errors.append("survival skill row should render migrated skill icon")
	if _bind_button(game_root, "survival") == null or not str(_bind_button(game_root, "survival").tooltip_text).contains("未学习"):
		errors.append("unlearned passive bind button should use reason catalog disabled tooltip")
	var survival_thumbnail := _dictionary_or_empty(_skill_snapshot(game_root, "survival").get("thumbnail_asset", {}))
	if str(survival_thumbnail.get("resource_path", "")) != "res://assets/icons/skills/survival.svg" or str(survival_thumbnail.get("thumbnail_domain", "")) != "skill":
		errors.append("survival skill snapshot should expose thumbnail asset: %s" % survival_thumbnail)
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
	if not _detail_text(game_root).contains("链路: 生存本能 -> 医疗知识"):
		errors.append("skills detail should show prerequisite chain highlight")
	if not _skill_line_tooltip(game_root, "medicine").contains("链路 生存本能 -> 医疗知识"):
		errors.append("skills row tooltip should expose prerequisite chain")
	if not _detail_text(game_root).contains("属性: 体质 6"):
		errors.append("skills detail should show attribute requirements")
	if not _press_skill_line(game_root, "survival"):
		errors.append("should select survival skill row")
	await process_frame
	if not _detail_text(game_root).contains("解锁: 医疗知识 / 观察力 / 低姿潜行"):
		errors.append("skills detail should show direct unlock chain for survival")
	if not _skill_line_tooltip(game_root, "survival").contains("解锁 医疗知识 / 观察力 / 低姿潜行"):
		errors.append("skills row tooltip should expose unlock chain")
	_assert_skill_tree_graph(errors, game_root, "initial skill tree graph")
	if not _open_skill_context_menu(game_root, "survival"):
		errors.append("should open skill context menu for survival")
	else:
		_assert_skill_context_menu(errors, game_root, "survival", "skill survival context")
		_close_skill_context_menu(game_root)
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
	await _assert_skill_tree_graph_pan(errors, game_root)

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
	_assert_modal_stack(errors, game_root, "skill_learn_confirm", "skills", "skill learn confirmation")
	_assert_modal_menu_event(errors, game_root, "skill_learn_confirm", "skills", "skill learn confirmation menu event")
	game_root.refresh_hud()
	_assert_runtime_control_line(errors, game_root, "ModalEvent modal_opened:skill_learn_confirm", "skill learn confirmation menu event HUD")
	_expect_modal_player_commands_blocked(errors, game_root, "skill_learn_confirm")
	var esc_learn_result: Dictionary = game_root.close_active_ui("keyboard_escape")
	if str(esc_learn_result.get("closed", "")) != "modal:skill_learn_confirm":
		errors.append("Esc should close skill learn confirmation before skills stage panel")
	if _learn_confirm_dialog_visible(game_root):
		errors.append("Esc should hide skill learn confirmation")
	_assert_no_modal_menu_event(errors, game_root, "skill learn confirmation Esc close menu event clear")
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
	if _bind_button(game_root, "survival") == null or not str(_bind_button(game_root, "survival").tooltip_text).contains("被动技能"):
		errors.append("learned passive bind button should use reason catalog disabled tooltip")

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
	else:
		_assert_drag_state_snapshot(errors, game_root, _skill_drag_data(game_root, "adrenaline_rush"), _hud_hotbar_slot_control(game_root, "slot_3"), "skill_hotbar", "skills", "hotbar_slot", "adrenaline skill to HUD hotbar")
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
	if not _hud_hotbar_slot_has_icon(game_root, "slot_3", "res://assets/icons/skills/adrenaline_rush.svg"):
		errors.append("HUD hotbar slot should render migrated adrenaline rush icon")
	_assert_hover_tooltip_snapshot(errors, game_root, _hud_hotbar_slot_control(game_root, "slot_3"), "hud", "Adrenaline Rush", "HUD skill hotbar tooltip snapshot")
	if _hud_hotbar_cooldown_mask_visible(game_root, "slot_3"):
		errors.append("HUD hotbar cooldown mask should stay hidden before skill cooldown")
	var group2_button := _hud_hotbar_group_button(game_root, "group_2")
	if group2_button == null:
		errors.append("HUD should expose hotbar group 2 button")
	else:
		group2_button.pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("快捷栏 G2 空"):
		errors.append("HUD hotbar group button should switch skills panel to empty group 2")
	var label_result: Dictionary = game_root.set_hotbar_group_label("group_2", "Tools")
	if not bool(label_result.get("success", false)):
		errors.append("renaming hotbar group 2 should succeed: %s" % label_result.get("reason", "unknown"))
	await process_frame
	if not _hotbar_line(game_root).contains("快捷栏 Tools 空"):
		errors.append("Skills panel should show renamed hotbar group label")
	game_root.refresh_hud()
	if not _hud_hotbar_group_active(game_root, "group_2"):
		errors.append("HUD hotbar group 2 button should expose active state")
	var renamed_group2_button := _hud_hotbar_group_button(game_root, "group_2")
	if renamed_group2_button == null or renamed_group2_button.text != "Tools":
		errors.append("HUD hotbar group 2 button should show renamed label")
	if not _hud_hotbar_slot_text(game_root, "slot_3").contains("3:-"):
		errors.append("HUD hotbar group 2 slot 3 should be empty")
	var group1_button := _hud_hotbar_group_button(game_root, "group_1")
	if group1_button == null:
		errors.append("HUD should expose hotbar group 1 button")
	else:
		group1_button.pressed.emit()
	await process_frame
	if not _hotbar_line(game_root).contains("快捷栏 G1") or not _hotbar_line(game_root).contains("slot_3:adrenaline_rush"):
		errors.append("HUD hotbar group button should restore dragged hotbar skill in group 1")
	game_root.refresh_hud()
	if not _hud_hotbar_group_active(game_root, "group_1"):
		errors.append("HUD hotbar group 1 button should expose active state")
	if not _hud_hotbar_slot_text(game_root, "slot_3").contains("Adre"):
		errors.append("HUD hotbar group 1 slot 3 should restore adrenaline rush")
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
	_press_key(game_root, KEY_2, true)
	await process_frame
	game_root.refresh_hud()
	if not _hud_hotbar_group_active(game_root, "group_2") or not _hud_hotbar_slot_text(game_root, "slot_3").contains("3:-"):
		errors.append("Alt+2 should switch active hotbar group through runtime input")
	_press_key(game_root, KEY_1, true)
	await process_frame
	game_root.refresh_hud()
	if not _hud_hotbar_group_active(game_root, "group_1") or not _hud_hotbar_slot_text(game_root, "slot_3").contains("Adre"):
		errors.append("Alt+1 should switch back to hotbar group 1 through runtime input")
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


func _hud_hotbar_slot_control(game_root: Node, slot_id: String) -> Control:
	return game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Control


func _assert_hover_tooltip_snapshot(errors: Array[String], game_root: Node, control: Control, expected_owner: String, expected_text: String, context: String) -> void:
	if control == null:
		errors.append("%s: tooltip source control should exist" % context)
		return
	if not game_root.has_method("hover_tooltip_snapshot"):
		errors.append("%s: game root should expose hover_tooltip_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.hover_tooltip_snapshot(control))
	if not bool(snapshot.get("active", false)):
		errors.append("%s: tooltip snapshot should be active: %s" % [context, snapshot])
	if str(snapshot.get("owner_panel", "")) != expected_owner:
		errors.append("%s: tooltip owner expected %s, got %s" % [context, expected_owner, snapshot])
	if not str(snapshot.get("text", "")).contains(expected_text):
		errors.append("%s: tooltip text should include %s, got %s" % [context, expected_text, snapshot])
	if str(snapshot.get("source_name", "")).is_empty() or str(snapshot.get("source_path", "")).is_empty():
		errors.append("%s: tooltip snapshot should expose source identity: %s" % [context, snapshot])
	if str(snapshot.get("lifecycle_state", "")) != "active":
		errors.append("%s: tooltip snapshot should expose active lifecycle: %s" % [context, snapshot])
	if str(snapshot.get("delay_policy", "")) != "godot_default" or int(snapshot.get("delay_ms", 0)) != -1:
		errors.append("%s: tooltip snapshot should expose Godot default delay policy: %s" % [context, snapshot])
	var source_rect: Dictionary = _dictionary_or_empty(snapshot.get("source_rect", {}))
	if source_rect.is_empty() or float(source_rect.get("w", 0.0)) <= 0.0 or float(source_rect.get("h", 0.0)) <= 0.0:
		errors.append("%s: tooltip snapshot should expose non-empty source rect: %s" % [context, snapshot])
	var screen_position: Dictionary = _dictionary_or_empty(snapshot.get("screen_position", {}))
	var viewport_size: Dictionary = _dictionary_or_empty(snapshot.get("viewport_size", {}))
	if not screen_position.has("x") or not screen_position.has("y") or float(viewport_size.get("x", 0.0)) <= 0.0 or float(viewport_size.get("y", 0.0)) <= 0.0:
		errors.append("%s: tooltip snapshot should expose screen and viewport geometry: %s" % [context, snapshot])
	if not snapshot.has("visible") or not snapshot.has("mouse_filter") or not snapshot.has("mouse_blocks_world"):
		errors.append("%s: tooltip snapshot should expose visibility and mouse filter diagnostics: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_tooltip: Dictionary = _dictionary_or_empty(runtime.get("tooltip", {}))
	if not runtime_tooltip.has("active") or not runtime_tooltip.has("text"):
		errors.append("%s: runtime control should expose tooltip state shape: %s" % [context, runtime_tooltip])


func _hud_hotbar_slot_disabled(game_root: Node, slot_id: String) -> bool:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	return button == null or button.disabled


func _hud_hotbar_group_button(game_root: Node, group_id: String) -> Button:
	return game_root.hud.find_child("HotbarGroup_%s" % group_id, true, false) as Button


func _hud_hotbar_group_active(game_root: Node, group_id: String) -> bool:
	var button := _hud_hotbar_group_button(game_root, group_id)
	return button != null and bool(button.get_meta("active", false)) and button.button_pressed


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


func _skill_line_has_icon(game_root: Node, skill_id: String, expected_resource_path: String) -> bool:
	var button := _skill_line_button(game_root, skill_id)
	return button != null and button.icon != null and str(button.get_meta("icon_resource_path", "")) == expected_resource_path


func _skill_snapshot(game_root: Node, skill_id: String) -> Dictionary:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.skills_panel.get("_last_snapshot"))
	for tree in _array_or_empty(snapshot.get("trees", [])):
		var tree_data: Dictionary = _dictionary_or_empty(tree)
		for skill in _array_or_empty(tree_data.get("skills", [])):
			var skill_data: Dictionary = _dictionary_or_empty(skill)
			if str(skill_data.get("skill_id", "")) == skill_id:
				return skill_data
	return {}


func _assert_skill_tree_graph(errors: Array[String], game_root: Node, context: String) -> void:
	if not game_root.skills_panel.has_method("skill_tree_graph_snapshot"):
		errors.append("%s: skills panel should expose skill_tree_graph_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.skills_panel.skill_tree_graph_snapshot())
	if not bool(snapshot.get("active", false)):
		errors.append("%s: graph snapshot should be active: %s" % [context, snapshot])
	if int(snapshot.get("node_count", 0)) < 4:
		errors.append("%s: graph should expose visible skill nodes: %s" % [context, snapshot])
	if int(snapshot.get("edge_count", 0)) <= 0:
		errors.append("%s: graph should expose prerequisite edges: %s" % [context, snapshot])
	if str(snapshot.get("selected_skill_id", "")) != "survival":
		errors.append("%s: graph selected skill should follow selected detail: %s" % [context, snapshot])
	var medicine_edge_seen := false
	for edge in _array_or_empty(snapshot.get("edges", [])):
		var edge_data: Dictionary = _dictionary_or_empty(edge)
		if str(edge_data.get("from", "")) == "survival" and str(edge_data.get("to", "")) == "medicine":
			medicine_edge_seen = true
	if not medicine_edge_seen:
		errors.append("%s: graph should connect survival prerequisite to medicine: %s" % [context, snapshot.get("edges", [])])
	var selected_node_seen := false
	for node in _array_or_empty(snapshot.get("nodes", [])):
		var node_data: Dictionary = _dictionary_or_empty(node)
		if str(node_data.get("skill_id", "")) == "survival":
			selected_node_seen = true
			if not bool(node_data.get("selected", false)):
				errors.append("%s: selected survival node should be marked selected: %s" % [context, node_data])
			if str(node_data.get("tree_id", "")) != "survival":
				errors.append("%s: survival graph node should expose tree id: %s" % [context, node_data])
	if not selected_node_seen:
		errors.append("%s: graph should include survival node summary" % context)
	var canvas: Control = game_root.skills_panel.find_child("SkillTreeGraphCanvas", true, false) as Control
	var status: Label = game_root.skills_panel.find_child("SkillTreeGraphStatusLine", true, false) as Label
	if canvas == null:
		errors.append("%s: missing SkillTreeGraphCanvas" % context)
	elif canvas.custom_minimum_size.y < 120.0:
		errors.append("%s: graph canvas should reserve stable height" % context)
	if status == null or not str(status.text).contains("节点") or not str(status.text).contains("pan"):
		errors.append("%s: graph status should expose node/link/pan diagnostics" % context)


func _assert_skill_tree_graph_pan(errors: Array[String], game_root: Node) -> void:
	var canvas: Control = game_root.skills_panel.find_child("SkillTreeGraphCanvas", true, false) as Control
	if canvas == null:
		errors.append("skill tree graph pan: missing graph canvas")
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	game_root.skills_panel.call("_handle_skill_graph_input", press)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(38, 22)
	game_root.skills_panel.call("_handle_skill_graph_input", drag)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(38, 22)
	game_root.skills_panel.call("_handle_skill_graph_input", release)
	var moved_snapshot: Dictionary = _dictionary_or_empty(game_root.skills_panel.skill_tree_graph_snapshot())
	var moved_pan: Dictionary = _dictionary_or_empty(moved_snapshot.get("pan", {}))
	if absf(float(moved_pan.get("x", 0.0))) < 0.001 and absf(float(moved_pan.get("y", 0.0))) < 0.001:
		errors.append("skill tree graph pan should change after drag: %s" % moved_snapshot)
	var reset_button: Button = game_root.skills_panel.find_child("SkillTreeResetPanButton", true, false) as Button
	if reset_button == null:
		errors.append("skill tree graph should expose reset pan button")
	else:
		reset_button.pressed.emit()
		await game_root.get_tree().process_frame
		var reset_snapshot: Dictionary = _dictionary_or_empty(game_root.skills_panel.skill_tree_graph_snapshot())
		var reset_pan: Dictionary = _dictionary_or_empty(reset_snapshot.get("pan", {}))
		if absf(float(reset_pan.get("x", 0.0))) > 0.001 or absf(float(reset_pan.get("y", 0.0))) > 0.001:
			errors.append("skill tree graph reset should clear pan: %s" % reset_snapshot)
	var survival_node := _skill_graph_node_summary(game_root, "survival")
	if survival_node.is_empty():
		errors.append("skill tree graph click selection needs survival node")
		return
	var position: Dictionary = _dictionary_or_empty(survival_node.get("position", {}))
	var click_position := Vector2(float(position.get("x", 0.0)) + 8.0, float(position.get("y", 0.0)) + 8.0)
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click_position
	game_root.skills_panel.call("_handle_skill_graph_input", press)
	release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click_position
	game_root.skills_panel.call("_handle_skill_graph_input", release)
	await game_root.get_tree().process_frame
	if not _detail_text(game_root).contains("详情: 生存本能"):
		errors.append("clicking graph node should select matching skill detail")


func _skill_graph_node_summary(game_root: Node, skill_id: String) -> Dictionary:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.skills_panel.skill_tree_graph_snapshot())
	for node in _array_or_empty(snapshot.get("nodes", [])):
		var node_data: Dictionary = _dictionary_or_empty(node)
		if str(node_data.get("skill_id", "")) == skill_id:
			return node_data
	return {}


func _skill_line_button(game_root: Node, skill_id: String) -> Button:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return null
	return row.get_node_or_null("Line") as Button


func _skill_line_tooltip(game_root: Node, skill_id: String) -> String:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return ""
	var label: Node = row.get_node_or_null("Line")
	if label is Button:
		return str((label as Button).tooltip_text)
	return ""


func _hud_hotbar_slot_has_icon(game_root: Node, slot_id: String, expected_resource_path: String) -> bool:
	var button: Button = game_root.hud.find_child("HotbarSlot_%s" % slot_id, true, false) as Button
	return button != null and button.icon != null and str(button.get_meta("icon_resource_path", "")) == expected_resource_path


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


func _skill_drag_data(game_root: Node, skill_id: String) -> Dictionary:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return {}
	var line: Control = row.get_node("Line") as Control
	if line == null:
		return {}
	return _dictionary_or_empty(game_root.skills_panel._get_skill_drag_data(Vector2.ZERO, line))


func _open_skill_context_menu(game_root: Node, skill_id: String) -> bool:
	var row: Node = game_root.skills_panel.find_child("Skill_%s" % skill_id, true, false)
	if row == null:
		return false
	var line: Control = row.get_node("Line") as Control
	if line == null or not line.has_meta("skill_drag_data"):
		return false
	game_root.skills_panel.call("_open_context_menu_for_skill", line.get_meta("skill_drag_data"), Vector2.ZERO)
	return true


func _close_skill_context_menu(game_root: Node) -> void:
	if game_root.skills_panel != null and game_root.skills_panel.has_method("close_context_menu"):
		game_root.skills_panel.call("close_context_menu")


func _assert_skill_context_menu(errors: Array[String], game_root: Node, expected_skill_id: String, context: String) -> void:
	if not game_root.has_method("context_menu_snapshot"):
		errors.append("%s: game root should expose context_menu_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.context_menu_snapshot())
	if not bool(snapshot.get("active", false)):
		errors.append("%s: context menu snapshot should be active: %s" % [context, snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(snapshot.get("top", {}))
	if str(top.get("id", "")) != "skill_context_menu" or str(top.get("kind", "")) != "skill_item":
		errors.append("%s: expected skill context top, got %s" % [context, top])
	if str(top.get("owner_panel", "")) != "skills":
		errors.append("%s: skill context owner should be skills: %s" % [context, top])
	if str(top.get("skill_id", "")) != expected_skill_id:
		errors.append("%s: skill context id expected %s, got %s" % [context, expected_skill_id, top])
	if int(top.get("option_count", 0)) != 5:
		errors.append("%s: skill context should expose inspect/learn/bind/use/clear options: %s" % [context, top])
	var inspect_seen := false
	var bind_seen := false
	for option in _array_or_empty(top.get("options", [])):
		var option_data: Dictionary = _dictionary_or_empty(option)
		if int(option_data.get("id", -1)) == 1:
			inspect_seen = true
			if bool(option_data.get("disabled", false)):
				errors.append("%s: inspect option should be enabled: %s" % [context, option_data])
		if int(option_data.get("id", -1)) == 3:
			bind_seen = true
			if not bool(option_data.get("disabled", false)):
				errors.append("%s: unlearned passive bind option should be disabled: %s" % [context, option_data])
	if not inspect_seen or not bind_seen:
		errors.append("%s: skill context should include inspect and bind options: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_context: Dictionary = _dictionary_or_empty(runtime.get("context_menu", {}))
	var runtime_top: Dictionary = _dictionary_or_empty(runtime_context.get("top", {}))
	if str(runtime_top.get("id", "")) != "skill_context_menu" or str(runtime_top.get("skill_id", "")) != expected_skill_id:
		errors.append("%s: runtime context menu should expose skill %s: %s" % [context, expected_skill_id, runtime_context])


func _assert_drag_state_snapshot(errors: Array[String], game_root: Node, drag_data: Dictionary, target: Control, expected_kind: String, expected_source_owner: String, expected_target_kind: String, context: String) -> void:
	if drag_data.is_empty():
		errors.append("%s: drag data should be available" % context)
		return
	if not game_root.has_method("drag_state_snapshot"):
		errors.append("%s: game root should expose drag_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.drag_state_snapshot(drag_data, target))
	if not bool(snapshot.get("active", false)):
		errors.append("%s: drag snapshot should be active: %s" % [context, snapshot])
	if str(snapshot.get("kind", "")) != expected_kind:
		errors.append("%s: drag kind expected %s, got %s" % [context, expected_kind, snapshot])
	var source: Dictionary = _dictionary_or_empty(snapshot.get("source", {}))
	if str(source.get("owner_panel", "")) != expected_source_owner:
		errors.append("%s: source owner expected %s, got %s" % [context, expected_source_owner, snapshot])
	var target_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("target", {}))
	if str(target_snapshot.get("target_kind", "")) != expected_target_kind:
		errors.append("%s: target kind expected %s, got %s" % [context, expected_target_kind, snapshot])
	var preview: Dictionary = _dictionary_or_empty(snapshot.get("preview", {}))
	if not bool(preview.get("has_preview", false)) or str(preview.get("text", "")).is_empty():
		errors.append("%s: drag snapshot should expose preview text: %s" % [context, snapshot])
	var runtime_drag: Dictionary = _dictionary_or_empty(_dictionary_or_empty(game_root.runtime_control_snapshot()).get("drag", {}))
	if not runtime_drag.has("active") or not runtime_drag.has("target"):
		errors.append("%s: runtime control should expose drag state shape: %s" % [context, runtime_drag])


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
		_validate_skill_target_preview_markers(errors, game_root, true, 1, 1, hostile_id, "valid hostile skill preview")
		game_root.refresh_hud()
		if not _skill_targeting_line(game_root).contains("Skill Target"):
			errors.append("HUD should show active skill targeting preview line")
		if not _skill_targeting_line(game_root).contains("单体") or not _skill_targeting_line(game_root).contains("仅敌对"):
			errors.append("HUD skill targeting preview should localize shape and policy")
		if not _skill_targeting_line(game_root).contains("射程 12") or not _skill_targeting_line(game_root).contains("距离 2"):
			errors.append("HUD skill targeting preview should show range and distance")
		if not _skill_targeting_line(game_root).contains("1目标"):
			errors.append("HUD skill targeting preview should show affected actor count")
	var friendly_preview: Dictionary = game_root.preview_active_skill_target({"target_type": "actor", "actor_id": 2})
	if bool(friendly_preview.get("success", false)) or str(friendly_preview.get("reason", "")) != "skill_target_not_hostile":
		errors.append("targeted hotbar skill preview should reject friendly target")
	_validate_skill_target_preview_markers(errors, game_root, false, 0, 0, 0, "invalid friendly skill preview")
	game_root.refresh_hud()
	if not _skill_targeting_line(game_root).contains("需要敌对目标"):
		errors.append("HUD skill targeting failure should localize invalid target reason")
	var esc_result: Dictionary = game_root.close_active_ui("keyboard_escape")
	if str(esc_result.get("closed", "")) != "skill_targeting":
		errors.append("Esc should close active skill targeting before other UI")
	if bool(game_root.has_active_skill_targeting()):
		errors.append("skill targeting should be inactive after Esc")
	_validate_skill_target_preview_markers(errors, game_root, false, 0, 0, 0, "Esc skill preview clear")
	_press_key(game_root, KEY_4)
	await game_root.get_tree().process_frame
	if hostile_id > 0:
		game_root.preview_active_skill_target({"target_type": "actor", "actor_id": hostile_id})
		_validate_skill_target_preview_markers(errors, game_root, true, 1, 1, hostile_id, "confirm setup skill preview")
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
		_validate_skill_target_preview_markers(errors, game_root, false, 0, 0, 0, "confirmed skill preview clear")
	game_root.registry.libraries["skills"] = original_library
	if game_root.simulation.actor_registry.get_actor(hostile_id) != null:
		game_root.simulation.actor_registry.unregister_actor(hostile_id)
	game_root.refresh_hud()
	game_root.refresh_skills_panel()


func _validate_skill_target_preview_markers(errors: Array[String], game_root: Node, expected_success: bool, expected_cell_count: int, expected_actor_count: int, expected_actor_id: int, context: String) -> void:
	var container: Node = game_root.find_child("SkillTargetPreviewMarkers", true, false)
	if container == null:
		errors.append("%s: missing SkillTargetPreviewMarkers container" % context)
		return
	if bool(container.get_meta("preview_success", false)) != expected_success:
		errors.append("%s: preview_success should be %s" % [context, str(expected_success)])
	if int(container.get_meta("cell_marker_count", -1)) != expected_cell_count:
		errors.append("%s: cell marker count expected %d got %d" % [context, expected_cell_count, int(container.get_meta("cell_marker_count", -1))])
	if int(container.get_meta("actor_marker_count", -1)) != expected_actor_count:
		errors.append("%s: actor marker count expected %d got %d" % [context, expected_actor_count, int(container.get_meta("actor_marker_count", -1))])
	if expected_actor_id > 0:
		var marker: Node = container.find_child("SkillTargetActorMarker", true, false)
		if marker == null:
			errors.append("%s: missing SkillTargetActorMarker" % context)
		else:
			if int(marker.get_meta("actor_id", 0)) != expected_actor_id:
				errors.append("%s: actor marker should expose affected actor id" % context)
			if str(marker.get_meta("skill_id", "")) != "adrenaline_rush":
				errors.append("%s: actor marker should expose skill id" % context)
		var cell: Node = container.find_child("SkillTargetCellMarker", true, false)
		if cell == null:
			errors.append("%s: missing SkillTargetCellMarker" % context)
		elif str(cell.get_meta("skill_id", "")) != "adrenaline_rush":
			errors.append("%s: cell marker should expose skill id" % context)


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


func _assert_modal_stack(errors: Array[String], game_root: Node, expected_id: String, expected_owner: String, context: String) -> void:
	if not game_root.has_method("modal_stack_snapshot"):
		errors.append("%s: game root should expose modal_stack_snapshot" % context)
		return
	var stack_snapshot: Dictionary = _dictionary_or_empty(game_root.modal_stack_snapshot())
	if not bool(stack_snapshot.get("active", false)) or int(stack_snapshot.get("count", 0)) <= 0:
		errors.append("%s: modal stack should be active: %s" % [context, stack_snapshot])
		return
	var top: Dictionary = _dictionary_or_empty(stack_snapshot.get("top", {}))
	if str(top.get("id", "")) != expected_id:
		errors.append("%s: modal stack top expected %s, got %s" % [context, expected_id, top])
	if str(top.get("owner_panel", "")) != expected_owner:
		errors.append("%s: modal stack owner expected %s, got %s" % [context, expected_owner, top])
	if not bool(top.get("blocks_gameplay", false)) or not bool(top.get("mouse_blocks_world", false)):
		errors.append("%s: modal stack top should block gameplay and mouse world input: %s" % [context, top])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_stack: Dictionary = _dictionary_or_empty(runtime.get("modal_stack", {}))
	if str(_dictionary_or_empty(runtime_stack.get("top", {})).get("id", "")) != expected_id:
		errors.append("%s: runtime modal stack should expose top %s: %s" % [context, expected_id, runtime_stack])


func _assert_modal_menu_event(errors: Array[String], game_root: Node, expected_id: String, expected_owner: String, context: String) -> void:
	if not game_root.has_method("menu_state_snapshot"):
		errors.append("%s: game root should expose menu_state_snapshot" % context)
		return
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot())
	var event: Dictionary = _dictionary_or_empty(snapshot.get("modal_event", {}))
	if event.is_empty():
		errors.append("%s: menu state should expose modal_event: %s" % [context, snapshot])
		return
	if str(event.get("event", "")) != "modal_opened" or str(event.get("panel_id", "")) != expected_id:
		errors.append("%s: modal event expected opened:%s, got %s" % [context, expected_id, event])
	if str(event.get("owner_panel", "")) != expected_owner:
		errors.append("%s: modal event owner expected %s, got %s" % [context, expected_owner, event])
	if not bool(event.get("blocks_gameplay", false)) or not bool(event.get("mouse_blocks_world", false)):
		errors.append("%s: modal event should expose gameplay and mouse blockers: %s" % [context, event])
	if not _recent_menu_events_contain(snapshot, "modal_opened", expected_id):
		errors.append("%s: recent events should include modal event %s: %s" % [context, expected_id, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	var runtime_event: Dictionary = _dictionary_or_empty(runtime_menu.get("modal_event", {}))
	if str(runtime_event.get("event", "")) != "modal_opened" or str(runtime_event.get("panel_id", "")) != expected_id:
		errors.append("%s: runtime menu should expose modal event %s: %s" % [context, expected_id, runtime_menu])
	if not _recent_menu_events_contain(runtime_menu, "modal_opened", expected_id):
		errors.append("%s: runtime recent events should include modal event %s: %s" % [context, expected_id, runtime_menu])


func _assert_no_modal_menu_event(errors: Array[String], game_root: Node, context: String) -> void:
	var snapshot: Dictionary = _dictionary_or_empty(game_root.menu_state_snapshot() if game_root.has_method("menu_state_snapshot") else {})
	if not _dictionary_or_empty(snapshot.get("modal_event", {})).is_empty():
		errors.append("%s: modal_event should clear when no modal is active: %s" % [context, snapshot])
	var runtime: Dictionary = _dictionary_or_empty(game_root.runtime_control_snapshot())
	var runtime_menu: Dictionary = _dictionary_or_empty(runtime.get("menu_state", {}))
	if not _dictionary_or_empty(runtime_menu.get("modal_event", {})).is_empty():
		errors.append("%s: runtime modal_event should clear when no modal is active: %s" % [context, runtime_menu])


func _assert_runtime_control_line(errors: Array[String], game_root: Node, expected: String, context: String) -> void:
	var label: Node = game_root.hud.find_child("RuntimeControlLine", true, false)
	if not label is Label:
		errors.append("%s: HUD should expose RuntimeControlLine" % context)
		return
	if not str((label as Label).text).contains(expected):
		errors.append("%s: RuntimeControlLine expected to contain %s, got %s" % [context, expected, str((label as Label).text)])


func _recent_menu_events_contain(menu_state: Dictionary, expected_event: String, expected_id: String) -> bool:
	for value in _array_or_empty(menu_state.get("recent_events", [])):
		var event: Dictionary = _dictionary_or_empty(value)
		if str(event.get("event", "")) == expected_event and str(event.get("panel_id", "")) == expected_id:
			return true
	return false


func _expect_modal_player_commands_blocked(errors: Array[String], game_root: Node, expected_modal_id: String) -> void:
	if game_root.has_method("can_issue_player_commands") and bool(game_root.can_issue_player_commands()):
		errors.append("modal should make can_issue_player_commands false")
	var move_result: Dictionary = _dictionary_or_empty(game_root.execute_move_to_grid({"x": 2, "y": 0, "z": 2}) if game_root.has_method("execute_move_to_grid") else {})
	_expect_modal_command_rejected(errors, move_result, "move", expected_modal_id)
	var hotbar_result: Dictionary = _dictionary_or_empty(game_root.use_hotbar_slot("slot_1") if game_root.has_method("use_hotbar_slot") else {})
	_expect_modal_command_rejected(errors, hotbar_result, "hotbar", expected_modal_id)
	var craft_result: Dictionary = _dictionary_or_empty(game_root.craft_player_recipe("recipe_bandage_basic", 1) if game_root.has_method("craft_player_recipe") else {})
	_expect_modal_command_rejected(errors, craft_result, "craft", expected_modal_id)
	var previous_targeting: Dictionary = _dictionary_or_empty(game_root.get("active_skill_targeting")).duplicate(true)
	game_root.set("active_skill_targeting", {"active": true, "slot_id": "slot_1", "skill_id": "adrenaline_rush"})
	var confirm_skill_result: Dictionary = _dictionary_or_empty(game_root.confirm_active_skill_target({"target_type": "self"}) if game_root.has_method("confirm_active_skill_target") else {})
	_expect_modal_command_rejected(errors, confirm_skill_result, "use_skill", expected_modal_id)
	game_root.set("active_skill_targeting", previous_targeting)


func _expect_modal_command_rejected(errors: Array[String], result: Dictionary, expected_action: String, expected_modal_id: String) -> void:
	if bool(result.get("success", false)):
		errors.append("modal should reject %s command while active" % expected_action)
	if str(result.get("reason", "")) != "ui_modal_blocks_player_commands":
		errors.append("modal command reject reason expected for %s, got %s" % [expected_action, result.get("reason", "")])
	if str(result.get("action", "")) != expected_action:
		errors.append("modal command reject action expected %s, got %s" % [expected_action, result.get("action", "")])
	if str(result.get("modal_id", "")) != expected_modal_id:
		errors.append("modal command reject should expose modal id %s, got %s" % [expected_modal_id, result.get("modal_id", "")])
	var blocker: Dictionary = _dictionary_or_empty(result.get("blocker", {}))
	if str(blocker.get("name", "")) != "modal:%s" % expected_modal_id:
		errors.append("modal command reject should include modal blocker snapshot for %s: %s" % [expected_action, blocker])


func _press_key(game_root: Node, key: int, alt_pressed: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	event.alt_pressed = alt_pressed
	game_root.runtime_input_controller.input(event)
