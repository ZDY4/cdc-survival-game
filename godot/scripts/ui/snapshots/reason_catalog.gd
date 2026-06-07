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
	"missing_skill_requirements": {"category": "skill", "text": "技能不足"},
	"missing_station": {"category": "crafting", "text": "缺少工作台"},
	"required_tools_unsupported": {"category": "crafting", "text": "缺少工具流程"},
	"required_station_unsupported": {"category": "crafting", "text": "缺少工作台"},
	"station_world_flag_missing": {"category": "crafting", "text": "工作台未启用"},
	"station_world_flag_blocked": {"category": "crafting", "text": "工作台被封锁"},
	"station_item_missing": {"category": "crafting", "text": "缺少工作台钥匙"},
	"station_tool_missing": {"category": "crafting", "text": "缺少工作台工具"},
	"recipe_locked": {"category": "crafting", "text": "配方未解锁"},
	"recipe_output_invalid": {"category": "crafting", "text": "配方产物无效"},
	"unknown_recipe": {"category": "crafting", "text": "未知配方"},
	"not_enough_items": {"category": "inventory", "text": "物品不足"},
	"invalid_quantity": {"category": "inventory", "text": "数量无效"},
	"inventory_over_capacity": {"category": "inventory", "text": "背包负重不足"},
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
	"buy_zone_requires_shop_source": {"category": "trade", "text": "购买区只接受店铺物品"},
	"sell_zone_requires_player_or_equipment_source": {"category": "trade", "text": "出售区只接受背包或装备物品"},
	"drop_zone_source_mismatch": {"category": "trade", "text": "拖拽来源不匹配"},
	"trade_item_rejected": {"category": "trade", "text": "交易物品被拒绝"},
	"unknown_trade_item": {"category": "trade", "text": "未知交易物品"},
	"skill_not_learned": {"category": "skill", "text": "技能未学习"},
	"skill_not_active": {"category": "skill", "text": "技能不是主动技能"},
	"skill_on_cooldown": {"category": "skill", "text": "技能冷却中"},
	"resource_insufficient": {"category": "skill", "text": "资源不足"},
	"skill_target_out_of_range": {"category": "skill", "text": "技能目标超出范围"},
	"skill_target_blocked_by_los": {"category": "skill", "text": "技能视线被遮挡"},
	"skill_target_not_hostile": {"category": "skill", "text": "技能需要敌对目标"},
	"skill_target_not_ally": {"category": "skill", "text": "技能需要友方目标"},
	"skill_target_grid_occupied": {"category": "skill", "text": "技能目标格被占用"},
	"simulation_missing": {"category": "system", "text": "运行时未就绪"},
	"actor_missing": {"category": "actor", "text": "角色不存在"},
}

const CATEGORY_METADATA := {
	"system": {
		"source_module": "godot/scripts/core/simulation/simulation.gd::submit_player_command",
		"payload_fields": ["kind", "reason", "command"],
		"disabled_text": "命令暂不可用",
		"remediation": "检查提交的 command kind 和 app 层入口映射。",
	},
	"ui": {
		"source_module": "godot/scripts/app/game_app.gd modal blocker",
		"payload_fields": ["action", "modal_id", "blocker_snapshot"],
		"disabled_text": "先关闭当前确认窗口",
		"remediation": "检查 UI layer stack 和 active modal blocker。",
	},
	"actor": {
		"source_module": "godot/scripts/core/simulation/simulation.gd actor lookup",
		"payload_fields": ["actor_id", "reason"],
		"disabled_text": "角色不可用",
		"remediation": "确认 actor 已注册且玩家命令只由 player actor 发起。",
	},
	"turn": {
		"source_module": "godot/scripts/core/simulation/simulation.gd turn state",
		"payload_fields": ["actor_id", "turn_state", "round"],
		"disabled_text": "当前不是可行动回合",
		"remediation": "检查 turn_state、AP 和 pending action 是否已推进。",
	},
	"interaction": {
		"source_module": "godot/scripts/core/simulation/simulation.gd interaction query",
		"payload_fields": ["target_type", "target_id", "option_id"],
		"disabled_text": "无法互动",
		"remediation": "检查 interaction prompt、目标距离、可见性和目标类型。",
	},
	"targeting": {
		"source_module": "godot/scripts/core/simulation/simulation.gd target validation",
		"payload_fields": ["target_type", "target_id", "target_actor_id"],
		"disabled_text": "目标不符合要求",
		"remediation": "检查 hover / selection 转换出的 InteractionTarget。",
	},
	"combat": {
		"source_module": "godot/scripts/core/simulation/simulation.gd combat runner",
		"payload_fields": ["actor_id", "target_actor_id", "weapon_id"],
		"disabled_text": "不能攻击该目标",
		"remediation": "检查敌对关系、目标状态、武器、射程和弹药。",
	},
	"vision": {
		"source_module": "godot/scripts/core/simulation/simulation.gd visibility check",
		"payload_fields": ["actor_id", "target_grid", "visible_cells"],
		"disabled_text": "目标不可见",
		"remediation": "检查 active vision、雾战刷新和 LOS 阻挡。",
	},
	"spatial": {
		"source_module": "godot/scripts/core/grid and movement topology",
		"payload_fields": ["grid", "target_grid", "level"],
		"disabled_text": "位置不符合要求",
		"remediation": "检查楼层、距离、footprint 和目标坐标。",
	},
	"movement": {
		"source_module": "godot/scripts/core/movement and pathfinder",
		"payload_fields": ["grid", "goal", "path", "blocker"],
		"disabled_text": "无法移动到这里",
		"remediation": "检查目标格阻挡、占用、边界、楼层和路径可达性。",
	},
	"ap": {
		"source_module": "godot/scripts/core/simulation/simulation.gd AP spending",
		"payload_fields": ["actor_id", "ap_cost", "ap_available", "pending"],
		"disabled_text": "AP 不足",
		"remediation": "检查 AP 消耗、pending 行动和自动推进回合策略。",
	},
	"crafting": {
		"source_module": "godot/scripts/core/crafting and recipe runner",
		"payload_fields": ["recipe_id", "materials", "tools", "station_id"],
		"disabled_text": "暂不能制作",
		"remediation": "检查材料、工具、技能、配方解锁和工作台权限。",
	},
	"skill": {
		"source_module": "godot/scripts/core/simulation/simulation.gd skill runner",
		"payload_fields": ["skill_id", "actor_id", "target", "resource_costs"],
		"disabled_text": "技能暂不可用",
		"remediation": "检查学习状态、冷却、资源、目标策略和技能 LOS。",
	},
	"inventory": {
		"source_module": "godot/scripts/core/economy inventory services",
		"payload_fields": ["item_id", "count", "slot_id", "inventory"],
		"disabled_text": "背包操作不可用",
		"remediation": "检查数量、堆叠、负重、关键物品和装备状态。",
	},
	"container": {
		"source_module": "godot/scripts/core/economy container runner",
		"payload_fields": ["container_id", "item_id", "count", "session"],
		"disabled_text": "容器操作不可用",
		"remediation": "检查容器会话、权限、锁、容量和物品数量。",
	},
	"door": {
		"source_module": "godot/scripts/core/simulation/simulation.gd door interaction",
		"payload_fields": ["target_id", "door_id", "key_item_id", "tool_id"],
		"disabled_text": "门无法打开",
		"remediation": "检查锁定状态、钥匙、工具和 world flag 条件。",
	},
	"transition": {
		"source_module": "godot/scripts/core/simulation/simulation.gd scene transition",
		"payload_fields": ["target_id", "location_id", "entry_id", "world_flags"],
		"disabled_text": "无法进入",
		"remediation": "检查地点解锁、入口、world flag 和 active map 状态。",
	},
	"trade": {
		"source_module": "godot/scripts/core/economy trade runner",
		"payload_fields": ["shop_id", "item_id", "count", "price"],
		"disabled_text": "交易不可用",
		"remediation": "检查买卖方向、库存、资金、价格和出售权限。",
	},
}

const REASON_METADATA := {
	"unknown_player_command": {
		"payload_fields": ["kind", "command", "known_kinds"],
		"disabled_text": "未知操作",
	},
	"ui_modal_blocks_player_commands": {
		"payload_fields": ["action", "modal_id", "blocker_snapshot"],
		"disabled_text": "先处理当前弹窗",
	},
	"path_unreachable": {
		"payload_fields": ["grid", "goal", "visited_cell_count"],
		"disabled_text": "没有可达路径",
	},
	"target_not_hostile": {
		"payload_fields": ["actor_id", "target_actor_id", "relationship"],
		"disabled_text": "不能攻击友方或中立目标",
	},
	"materials_insufficient": {
		"payload_fields": ["recipe_id", "missing_materials", "inventory"],
		"disabled_text": "材料不足",
	},
	"inventory_over_capacity": {
		"payload_fields": ["item_id", "count", "current_weight", "max_weight"],
		"disabled_text": "背包负重不足",
	},
	"container_inventory_insufficient": {
		"payload_fields": ["container_id", "item_id", "count", "available"],
		"disabled_text": "容器数量不足",
	},
	"player_money_insufficient": {
		"payload_fields": ["shop_id", "price", "player_money"],
		"disabled_text": "资金不足",
	},
	"buy_zone_requires_shop_source": {
		"payload_fields": ["source", "drop_zone"],
		"disabled_text": "购买区只接受店铺物品",
	},
	"sell_zone_requires_player_or_equipment_source": {
		"payload_fields": ["source", "drop_zone"],
		"disabled_text": "出售区只接受背包或装备物品",
	},
	"skill_on_cooldown": {
		"payload_fields": ["skill_id", "cooldown_remaining", "actor_id"],
		"disabled_text": "技能冷却中",
	},
}


func text_for(reason: String) -> String:
	if reason.is_empty():
		return "未知原因"
	var entry := _dictionary_or_empty(REASONS.get(reason, {}))
	return str(entry.get("text", reason))


func disabled_text_for(reason: String) -> String:
	return str(entry_for(reason).get("disabled_text", text_for(reason)))


func entry_for(reason: String) -> Dictionary:
	if REASONS.has(reason):
		var entry: Dictionary = _dictionary_or_empty(REASONS.get(reason, {})).duplicate(true)
		_apply_metadata(entry)
		entry["reason"] = reason
		entry["known"] = true
		var reason_metadata: Dictionary = _dictionary_or_empty(REASON_METADATA.get(reason, {}))
		_merge_metadata(entry, reason_metadata)
		return entry
	return {
		"reason": reason,
		"known": false,
		"category": "unknown",
		"text": text_for(reason),
		"source_module": "",
		"payload_fields": [],
		"disabled_text": text_for(reason),
		"remediation": "",
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
		"metadata_coverage": metadata_coverage(),
		"reasons": reasons,
	}


func metadata_coverage() -> Dictionary:
	var missing_source := 0
	var missing_payload := 0
	var missing_disabled_text := 0
	var missing_remediation := 0
	for reason in REASONS.keys():
		var entry := entry_for(str(reason))
		if str(entry.get("source_module", "")).is_empty():
			missing_source += 1
		if _array_or_empty(entry.get("payload_fields", [])).is_empty():
			missing_payload += 1
		if str(entry.get("disabled_text", "")).is_empty():
			missing_disabled_text += 1
		if str(entry.get("remediation", "")).is_empty():
			missing_remediation += 1
	return {
		"reason_count": REASONS.keys().size(),
		"missing_source_module": missing_source,
		"missing_payload_fields": missing_payload,
		"missing_disabled_text": missing_disabled_text,
		"missing_remediation": missing_remediation,
	}


func _apply_metadata(entry: Dictionary) -> void:
	var category := str(entry.get("category", "unknown"))
	var metadata: Dictionary = _dictionary_or_empty(CATEGORY_METADATA.get(category, {}))
	_merge_metadata(entry, metadata)


func _merge_metadata(entry: Dictionary, metadata: Dictionary) -> void:
	for key in metadata.keys():
		entry[key] = metadata[key]


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
