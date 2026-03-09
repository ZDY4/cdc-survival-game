extends Node
## NPC招募组件
## 处理招募条件检查和招募流程

class_name NPCRecruitmentComponent

signal recruitment_checked(passed: bool, reasons: Array)
signal recruited

var npc: Node

func initialize(parent_npc: Node):
	npc = parent_npc

## 检查招募条件
func check_conditions() -> Dictionary:
	var result = {
		"success": true,
		"passed": [],
		"failed": [],
		"warnings": []
	}
	
	if not npc or not npc.npc_data:
		result.success = false
		result.failed.append("NPC数据不存在")
		return result
	
	if not npc.npc_data.can_recruit:
		result.success = false
		result.failed.append("此NPC不可招募")
		return result
	
	if npc.npc_data.state.is_recruited:
		result.success = false
		result.failed.append("此NPC已被招募")
		return result
	
	var recruitment = npc.npc_data.recruitment
	
	# 检查任务
	if not recruitment.required_quests.is_empty():
		var completed_all = true
		for quest_id in recruitment.required_quests:
			if QuestSystem and not QuestSystem.is_quest_completed(quest_id):
				completed_all = false
				result.failed.append("需要完成任务: %s" % quest_id)
		
		if completed_all:
			result.passed.append("已完成所有必需任务")
	
	# 检查物品
	if not recruitment.required_items.is_empty():
		var has_all = true
		for item_req in recruitment.required_items:
			var item_id = item_req.get("id", "")
			var count = item_req.get("count", 1)
			if InventoryModule and not InventoryModule.has_item(item_id, count):
				has_all = false
				result.failed.append("需要物品: %s x%d" % [item_id, count])
		
		if has_all:
			result.passed.append("拥有所有必需物品")
	
	# 检查魅力
	if recruitment.min_charisma > 0:
		var player_charisma = _get_player_charisma()
		if player_charisma >= recruitment.min_charisma:
			result.passed.append("魅力达标 (%d/%d)" % [player_charisma, recruitment.min_charisma])
		else:
			result.failed.append("需要魅力 %d (当前 %d)" % [recruitment.min_charisma, player_charisma])
	
	# 检查友好度
	if recruitment.min_friendliness > 0:
		var friendliness = npc.npc_data.mood.friendliness
		if friendliness >= recruitment.min_friendliness:
			result.passed.append("友好度达标 (%d/%d)" % [friendliness, recruitment.min_friendliness])
		else:
			result.failed.append("需要友好度 %d (当前 %d)" % [recruitment.min_friendliness, friendliness])
	
	# 检查信任度
	if recruitment.min_trust > 0:
		var trust = npc.npc_data.mood.trust
		if trust >= recruitment.min_trust:
			result.passed.append("信任度达标 (%d/%d)" % [trust, recruitment.min_trust])
		else:
			result.warnings.append("信任度较低 (%d/%d)" % [trust, recruitment.min_trust])
	
	# 检查招募金钱成本
	if recruitment.cost_money > 0:
		if GameState and GameState.has_money(recruitment.cost_money):
			result.passed.append("金钱充足 (%d/%d)" % [GameState.player_money, recruitment.cost_money])
		else:
			var current_money = GameState.player_money if GameState else 0
			result.failed.append("需要金钱 %d (当前 %d)" % [recruitment.cost_money, current_money])
	
	# 最终决定
	result.success = result.failed.is_empty()
	
	recruitment_checked.emit(result.success, result.failed)
	
	return result

## 执行招募
func on_recruited() -> bool:
	# 再次检查条件
	var check = check_conditions()
	if not check.success:
		push_warning("[NPCRecruitmentComponent] 招募条件不满足")
		return false
	
	# 扣除招募成本
	if not _deduct_recruitment_cost():
		push_warning("[NPCRecruitmentComponent] 无法扣除招募成本")
		return false
	
	# 标记为已招募
	npc.npc_data.state.is_recruited = true
	
	# 添加到队伍
	_add_to_party()
	
	# 显示招募成功消息
	if npc:
		npc.show_floating_text("%s加入了队伍！" % npc.npc_name, Color.GREEN)
	
	recruited.emit()
	
	print("[NPCRecruitmentComponent] NPC %s 已被招募" % npc.npc_name)
	
	return true

## 获取招募预览信息
func get_recruitment_preview() -> Dictionary:
	if not npc or not npc.npc_data:
		return {}
	
	var recruitment = npc.npc_data.recruitment
	
	return {
		"can_recruit": npc.can_be_recruited(),
		"requirements": {
			"quests": recruitment.required_quests,
			"items": recruitment.required_items,
			"min_charisma": recruitment.min_charisma,
			"min_friendliness": recruitment.min_friendliness,
			"min_trust": recruitment.min_trust
		},
		"costs": {
			"items": recruitment.cost_items,
			"money": recruitment.cost_money
		},
		"npc_attributes": npc.npc_data.attributes.duplicate(),
		"npc_skills": _get_npc_skills()
	}

## 获取NPC技能（作为队友时的特殊能力）
func _get_npc_skills() -> Array:
	var skills = []
	
	if not npc or not npc.npc_data:
		return skills
	
	var attrs = npc.npc_data.attributes
	
	if attrs.get("intelligence", 0) >= 12:
		skills.append("医疗")  # 可以治疗玩家
	
	if attrs.get("agility", 0) >= 12:
		skills.append("开锁")  # 可以开一些锁
	
	if attrs.get("strength", 0) >= 12:
		skills.append("负重")  # 可以帮玩家携带更多物品
	
	if attrs.get("perception", 0) >= 12:
		skills.append("侦察")  # 可以发现隐藏物品
	
	return skills

## 扣除招募成本
func _deduct_recruitment_cost() -> bool:
	if not npc or not npc.npc_data:
		return false
	
	var recruitment = npc.npc_data.recruitment
	
	# 检查并扣除物品
	for item_req in recruitment.cost_items:
		var item_id = item_req.get("id", "")
		var count = item_req.get("count", 1)
		
		if InventoryModule and not InventoryModule.has_item(item_id, count):
			return false
	
	# 实际扣除
	for item_req in recruitment.cost_items:
		var item_id = item_req.get("id", "")
		var count = item_req.get("count", 1)
		
		if InventoryModule:
			InventoryModule.remove_item(item_id, count)
	
	# 扣除金钱
	if recruitment.cost_money > 0:
		if GameState and not GameState.remove_money(recruitment.cost_money):
			push_warning("[NPCRecruitmentComponent] 金钱不足，无法招募")
			return false
	
	return true

## 添加到队伍
func _add_to_party():
	# TODO: 集成到现有的队友系统
	# 这里应该调用PartySystem或类似系统
	
	# 临时实现：存储在GameState
	if GameState:
		if not GameState.has("party_members"):
			GameState.party_members = []
		
		GameState.party_members.append({
			"npc_id": npc.npc_id,
			"name": npc.npc_name,
			"attributes": npc.npc_data.attributes.duplicate(),
			"portrait": npc.npc_data.portrait_path
		})
	
	# 发送事件
	EventBus.emit(EventBus.EventType.NPC_RECRUITED, {
		"npc_id": npc.npc_id,
		"npc_name": npc.npc_name
	})

func _get_player_charisma() -> int:
	if GameState and GameState.has("player_charisma"):
		return GameState.player_charisma
	return 10
