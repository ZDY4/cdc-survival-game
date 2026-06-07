extends RefCounted

const REASONS := {
	"unknown_player_command": {"category": "system", "text": "未知命令"},
	"ui_modal_blocks_player_commands": {"category": "ui", "text": "界面确认中，无法执行"},
	"unknown_actor": {"category": "actor", "text": "未知角色"},
	"command_actor_not_player": {"category": "actor", "text": "非玩家角色"},
	"turn_closed": {"category": "turn", "text": "回合未开启"},
	"interaction_target_unavailable": {"category": "interaction", "text": "目标不可用"},
	"target_self": {"category": "targeting", "text": "不能以自己为目标"},
	"self_target": {"category": "targeting", "text": "不能以自己为目标"},
	"target_not_actor": {"category": "targeting", "text": "目标不是角色"},
	"target_not_container": {"category": "targeting", "text": "目标不是容器"},
	"target_empty": {"category": "targeting", "text": "目标为空"},
	"target_hostile": {"category": "targeting", "text": "敌对目标不能交谈"},
	"target_not_hostile": {"category": "combat", "text": "不能攻击友方或中立目标"},
	"attacker_defeated": {"category": "combat", "text": "攻击者已倒下"},
	"target_defeated": {"category": "combat", "text": "目标已倒下"},
	"unknown_attacker": {"category": "combat", "text": "未知攻击者"},
	"unknown_target": {"category": "targeting", "text": "未知目标"},
	"target_not_visible": {"category": "vision", "text": "目标不可见"},
	"target_invalid_level": {"category": "spatial", "text": "目标楼层无效"},
	"target_out_of_range": {"category": "spatial", "text": "目标超出射程"},
	"target_too_close": {"category": "spatial", "text": "目标过近"},
	"target_blocked_by_los": {"category": "vision", "text": "视线被遮挡"},
	"goal_blocked": {"category": "movement", "text": "目标被阻挡"},
	"goal_occupied": {"category": "movement", "text": "目标被占用"},
	"goal_out_of_bounds": {"category": "movement", "text": "目标越界"},
	"level_mismatch": {"category": "movement", "text": "楼层不匹配"},
	"path_unreachable": {"category": "movement", "text": "无法到达"},
	"ap_insufficient": {"category": "ap", "text": "AP不足"},
	"ap_insufficient_craft": {"category": "ap", "text": "AP不足，无法制作"},
	"ap_insufficient_deconstruct": {"category": "ap", "text": "AP不足，无法拆解"},
	"ap_insufficient_movement_queued": {"category": "ap", "text": "AP不足，移动已排队"},
	"ap_insufficient_interaction_queued": {"category": "ap", "text": "AP不足，交互已排队"},
	"materials_insufficient": {"category": "crafting", "text": "材料不足"},
	"missing_tools": {"category": "crafting", "text": "缺少工具"},
	"missing_consumable_tools": {"category": "crafting", "text": "缺少可消耗工具"},
	"missing_skills": {"category": "skill", "text": "技能不足"},
	"missing_station": {"category": "crafting", "text": "缺少工作台"},
	"station_world_flag_missing": {"category": "crafting", "text": "工作台未启用"},
	"station_world_flag_blocked": {"category": "crafting", "text": "工作台被封锁"},
	"station_item_missing": {"category": "crafting", "text": "缺少工作台钥匙"},
	"station_tool_missing": {"category": "crafting", "text": "缺少工作台工具"},
	"recipe_locked": {"category": "crafting", "text": "配方未解锁"},
	"recipe_output_invalid": {"category": "crafting", "text": "配方产物无效"},
	"unknown_recipe": {"category": "crafting", "text": "未知配方"},
	"not_enough_items": {"category": "inventory", "text": "物品不足"},
	"invalid_quantity": {"category": "inventory", "text": "数量无效"},
	"container_inventory_insufficient": {"category": "container", "text": "容器物品不足"},
	"container_session_missing": {"category": "container", "text": "容器未打开"},
	"unknown_container": {"category": "container", "text": "未知容器"},
	"door_locked": {"category": "door", "text": "门已锁定"},
	"door_key_missing": {"category": "door", "text": "缺少钥匙"},
	"door_tool_missing": {"category": "door", "text": "缺少开锁工具"},
	"scene_transition_world_flag_missing": {"category": "transition", "text": "缺少进入许可"},
	"scene_transition_world_flag_blocked": {"category": "transition", "text": "当前状态无法进入"},
	"scene_transition_location_locked": {"category": "transition", "text": "地点未解锁"},
	"scene_transition_location_blocked": {"category": "transition", "text": "地点已被封锁"},
	"item_not_sellable": {"category": "trade", "text": "物品不可出售"},
	"shop_stock_insufficient": {"category": "trade", "text": "商店库存不足"},
	"player_stock_insufficient": {"category": "trade", "text": "玩家库存不足"},
	"player_money_insufficient": {"category": "trade", "text": "玩家资金不足"},
	"shop_money_insufficient": {"category": "trade", "text": "商店资金不足"},
	"skill_not_learned": {"category": "skill", "text": "技能未学习"},
	"skill_not_active": {"category": "skill", "text": "技能不是主动技能"},
	"skill_on_cooldown": {"category": "skill", "text": "技能冷却中"},
	"resource_insufficient": {"category": "skill", "text": "资源不足"},
	"skill_target_out_of_range": {"category": "skill", "text": "技能目标超出范围"},
	"skill_target_blocked_by_los": {"category": "skill", "text": "技能视线被遮挡"},
	"skill_target_not_hostile": {"category": "skill", "text": "技能需要敌对目标"},
	"skill_target_not_ally": {"category": "skill", "text": "技能需要友方目标"},
	"skill_target_grid_occupied": {"category": "skill", "text": "技能目标格被占用"},
}


func text_for(reason: String) -> String:
	if reason.is_empty():
		return "未知原因"
	var entry := _dictionary_or_empty(REASONS.get(reason, {}))
	return str(entry.get("text", reason))


func entry_for(reason: String) -> Dictionary:
	if REASONS.has(reason):
		var entry: Dictionary = _dictionary_or_empty(REASONS.get(reason, {})).duplicate(true)
		entry["reason"] = reason
		entry["known"] = true
		return entry
	return {
		"reason": reason,
		"known": false,
		"category": "unknown",
		"text": text_for(reason),
	}


func category_counts() -> Dictionary:
	var counts: Dictionary = {}
	for reason in REASONS.keys():
		var category := str(_dictionary_or_empty(REASONS[reason]).get("category", "unknown"))
		counts[category] = int(counts.get(category, 0)) + 1
	return counts


func catalog_snapshot() -> Dictionary:
	var reasons: Array[String] = []
	for reason in REASONS.keys():
		reasons.append(str(reason))
	reasons.sort()
	return {
		"reason_count": reasons.size(),
		"category_counts": category_counts(),
		"reasons": reasons,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
