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
	"ap_insufficient_craft_queued": {"category": "ap", "text": "AP不足，制作已排队"},
	"ap_insufficient_deconstruct": {"category": "ap", "text": "AP不足，无法拆解"},
	"ap_insufficient_movement_queued": {"category": "ap", "text": "AP不足，移动已排队"},
	"ap_insufficient_interaction_queued": {"category": "ap", "text": "AP不足，交互已排队"},
	"new_target_command": {"category": "pending", "text": "选择了新目标"},
	"keyboard": {"category": "pending", "text": "键盘取消"},
	"crafting_ui": {"category": "pending", "text": "制作面板取消"},
	"location_change": {"category": "pending", "text": "地点切换取消"},
	"smoke_cancel": {"category": "pending", "text": "测试取消"},
	"movement_smoke_cancelled": {"category": "pending", "text": "测试取消"},
	"keyboard_escape_smoke": {"category": "pending", "text": "键盘取消"},
	"combat_smoke_cancel": {"category": "pending", "text": "测试取消"},
	"materials_insufficient": {"category": "crafting", "text": "材料不足"},
	"missing_tools": {"category": "crafting", "text": "缺少工具"},
	"missing_consumable_tools": {"category": "crafting", "text": "缺少可消耗工具"},
	"tool_durability_insufficient": {"category": "crafting", "text": "工具耐久不足"},
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
	"inventory_over_capacity": {"category": "inventory", "text": "背包容量不足"},
	"ap_insufficient_use_item": {"category": "ap", "text": "AP不足，无法使用物品"},
	"item_not_usable": {"category": "inventory", "text": "物品不可使用"},
	"item_use_forbidden": {"category": "inventory", "text": "物品当前禁止使用"},
	"item_not_droppable": {"category": "inventory", "text": "物品不可丢弃"},
	"item_not_in_inventory": {"category": "inventory", "text": "物品不在背包中"},
	"item_not_equippable": {"category": "equipment", "text": "物品不可装备"},
	"inventory_action_requires_inventory_item": {"category": "inventory", "text": "背包操作只接受背包物品"},
	"inventory_action_missing_item": {"category": "inventory", "text": "缺少背包物品"},
	"unknown_inventory_action": {"category": "inventory", "text": "未知背包操作"},
	"inventory_split_requires_stack_model": {"category": "inventory", "text": "需要多堆叠背包模型"},
	"unknown_item": {"category": "inventory", "text": "未知物品"},
	"unknown_effect": {"category": "inventory", "text": "未知物品效果"},
	"container_inventory_insufficient": {"category": "container", "text": "容器物品不足"},
	"container_money_insufficient": {"category": "container", "text": "容器金钱不足"},
	"container_session_missing": {"category": "container", "text": "容器未打开"},
	"unknown_container": {"category": "container", "text": "未知容器"},
	"active_container_missing": {"category": "container", "text": "没有打开的容器"},
	"container_empty": {"category": "container", "text": "容器为空"},
	"inventory_empty": {"category": "inventory", "text": "背包为空"},
	"container_locked": {"category": "container", "text": "容器已锁定"},
	"container_take_forbidden": {"category": "container", "text": "禁止从容器拿取"},
	"container_store_forbidden": {"category": "container", "text": "禁止向容器存放"},
	"container_world_flag_missing": {"category": "container", "text": "缺少容器操作许可"},
	"container_world_flag_blocked": {"category": "container", "text": "容器操作许可已失效"},
	"container_active_quest_missing": {"category": "container", "text": "需要进行中任务"},
	"container_completed_quest_missing": {"category": "container", "text": "需要已完成任务"},
	"container_active_quest_blocked": {"category": "container", "text": "进行中任务阻止容器操作"},
	"container_completed_quest_blocked": {"category": "container", "text": "已完成任务阻止容器操作"},
	"container_owner_forbidden": {"category": "container", "text": "容器属于其他角色"},
	"container_owner_relationship_too_low": {"category": "container", "text": "与容器拥有者关系不足"},
	"container_owner_relationship_too_high": {"category": "container", "text": "与容器拥有者关系过高"},
	"container_key_missing": {"category": "container", "text": "缺少容器钥匙"},
	"container_tool_missing": {"category": "container", "text": "缺少容器工具"},
	"container_over_capacity": {"category": "container", "text": "容器容量不足"},
	"container_inactive": {"category": "container", "text": "容器未激活"},
	"container_target_missing": {"category": "container", "text": "容器目标不存在"},
	"unknown_container_transfer_source": {"category": "container", "text": "未知容器转移来源"},
	"container_drop_target_missing": {"category": "container", "text": "缺少容器拖拽目标"},
	"container_drop_source_missing": {"category": "container", "text": "缺少容器拖拽来源"},
	"container_drop_item_missing": {"category": "container", "text": "缺少容器拖拽物品"},
	"container_drop_same_column": {"category": "container", "text": "不能拖回同一栏"},
	"container_drop_requires_container_column": {"category": "container", "text": "背包物品只能存入容器栏"},
	"container_drop_unsupported_drag_data": {"category": "container", "text": "不支持的容器拖拽数据"},
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
	"cart_entry_missing_index": {"category": "trade", "text": "购物车条目索引缺失"},
	"cart_entry_requires_cart_target": {"category": "trade", "text": "购物车条目只能拖到购物车"},
	"trade_cart_unsupported_drag_data": {"category": "trade", "text": "不支持的购物车拖拽数据"},
	"equipment_slot_requires_inventory_item": {"category": "equipment", "text": "装备槽只接受背包物品"},
	"equipment_slot_missing_item": {"category": "equipment", "text": "缺少装备物品"},
	"equipment_slot_missing_slot": {"category": "equipment", "text": "缺少装备槽位"},
	"equipment_slot_incompatible": {"category": "equipment", "text": "物品不能装备到该槽位"},
	"hotbar_slot_requires_skill_hotbar": {"category": "skill", "text": "热栏槽只接受技能拖拽"},
	"hotbar_slot_missing_skill": {"category": "skill", "text": "缺少热栏技能"},
	"hotbar_slot_missing_slot": {"category": "skill", "text": "缺少热栏槽位"},
	"hotbar_group_drag_unsupported": {"category": "skill", "text": "热栏组不支持拖拽放置"},
	"quest_not_active": {"category": "quest", "text": "任务未激活"},
	"quest_not_waiting_for_turn_in": {"category": "quest", "text": "任务不需要手动交付"},
	"quest_objective_incomplete": {"category": "quest", "text": "任务目标尚未完成"},
	"turn_in_requires_dialogue": {"category": "quest", "text": "需要通过指定对话交付"},
	"turn_in_dialogue_mismatch": {"category": "quest", "text": "当前对话不符合交付条件"},
	"turn_in_target_mismatch": {"category": "quest", "text": "当前交付对象不符合条件"},
	"turn_in_target_missing": {"category": "quest", "text": "交付对象未指定"},
	"objective_incomplete": {"category": "quest", "text": "目标尚未完成"},
	"target_in_attack_range": {"category": "ai", "text": "目标在攻击范围内"},
	"target_inside_min_range": {"category": "ai", "text": "目标距离过近"},
	"target_in_aggro_range": {"category": "ai", "text": "目标在警戒范围内"},
	"target_visible": {"category": "ai", "text": "目标可见"},
	"no_target_in_aggro_range": {"category": "ai", "text": "警戒范围内没有目标"},
	"weapon_magazine_empty": {"category": "ai", "text": "武器弹匣为空"},
	"weapon_ammo_unavailable": {"category": "ai", "text": "武器弹药不可用"},
	"no_ai_profile": {"category": "ai", "text": "缺少 AI 配置"},
	"settlement_missing": {"category": "ai", "text": "缺少 settlement 上下文"},
	"same_side": {"category": "ai", "text": "同阵营目标"},
	"side_hostile": {"category": "ai", "text": "敌对阵营目标"},
	"neutral": {"category": "ai", "text": "中立目标"},
	"slot_id_empty": {"category": "save", "text": "存档槽位为空"},
	"slot_display_name_empty": {"category": "save", "text": "存档名称为空"},
	"save_file_missing": {"category": "save", "text": "存档文件缺失"},
	"save_file_unreadable": {"category": "save", "text": "存档无法读取"},
	"save_file_unwritable": {"category": "save", "text": "存档无法写入"},
	"save_json_invalid": {"category": "save", "text": "存档 JSON 损坏"},
	"save_schema_unsupported": {"category": "save", "text": "存档版本不兼容"},
	"runtime_snapshot_missing": {"category": "save", "text": "存档缺少运行时快照"},
	"map_scene_missing": {"category": "map_asset", "text": "地图场景缺失"},
	"map_scene_load_failed": {"category": "map_asset", "text": "地图场景加载失败"},
	"map_scene_root_invalid": {"category": "map_asset", "text": "地图场景根节点无效"},
	"map_scene_definition_missing": {"category": "map_asset", "text": "地图场景定义缺失"},
	"maxed": {"category": "skill", "text": "技能已满级"},
	"missing_skill_points": {"category": "skill", "text": "缺少技能点"},
	"missing_prerequisites": {"category": "skill", "text": "缺少前置技能"},
	"missing_attributes": {"category": "skill", "text": "属性不足"},
	"not_learned": {"category": "skill", "text": "技能未学习"},
	"passive": {"category": "skill", "text": "被动技能不可主动使用"},
	"unbound": {"category": "skill", "text": "技能未绑定"},
	"cooldown": {"category": "skill", "text": "技能冷却中"},
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
	"pending": {
		"source_module": "godot/scripts/core/simulation/simulation.gd pending cancellation",
		"payload_fields": ["actor_id", "reason", "movement", "interaction", "crafting"],
		"disabled_text": "已取消待执行动作",
		"remediation": "检查取消来源、新目标替换、UI 关闭顺序和 pending movement / interaction / crafting payload。",
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
	"quest": {
		"source_module": "godot/scripts/core/quests/quest_runner.gd turn-in validation",
		"payload_fields": ["quest_id", "objective_id", "current", "target"],
		"disabled_text": "任务交付不可用",
		"remediation": "检查任务状态、目标进度、交付 NPC、对话上下文和奖励配置。",
	},
	"ai": {
		"source_module": "godot/scripts/core/ai/ai_rules.gd intent and hostility selection",
		"payload_fields": ["actor_id", "target_actor_id", "intent", "distance"],
		"disabled_text": "AI 行为不可用",
		"remediation": "检查阵营、感知范围、视线、武器弹药、目标距离和 AI context。",
	},
	"save": {
		"source_module": "godot/scripts/app/save_service.gd slot and envelope validation",
		"payload_fields": ["slot_id", "path", "schema_version"],
		"disabled_text": "存档不可用",
		"remediation": "检查槽位 id、文件可读写、JSON envelope、schema_version 和 runtime_snapshot。",
	},
	"map_asset": {
		"source_module": "godot/scripts/world/map_scene_loader.gd Godot map scene loading",
		"payload_fields": ["map_id", "path", "error"],
		"disabled_text": "地图资源不可用",
		"remediation": "检查 godot/scenes/maps/*.tscn 是否存在、可加载，并且根节点暴露 to_definition()。",
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
	"new_target_command": {
		"payload_fields": ["actor_id", "replacement_kind", "replacement", "movement", "interaction", "crafting"],
		"disabled_text": "选择了新目标",
	},
	"keyboard": {
		"payload_fields": ["actor_id", "reason", "turn_policy"],
		"disabled_text": "键盘取消",
	},
	"crafting_ui": {
		"payload_fields": ["actor_id", "pending_crafting", "turn_policy"],
		"disabled_text": "制作面板取消",
	},
	"location_change": {
		"payload_fields": ["actor_id", "location_id", "entry_point_id", "movement", "interaction", "crafting"],
		"disabled_text": "地点切换取消",
	},
	"inventory_over_capacity": {
		"payload_fields": ["item_id", "count", "limit_kind", "capacity_kind", "current_weight", "max_weight", "projected_item_count", "max_items", "projected_stack_count", "max_stacks"],
		"disabled_text": "背包容量不足",
	},
	"ap_insufficient_use_item": {
		"payload_fields": ["item_id", "required_ap", "available_ap"],
		"disabled_text": "AP 不足",
	},
	"item_not_droppable": {
		"payload_fields": ["item_id", "count"],
		"disabled_text": "物品不可丢弃",
	},
	"item_not_equippable": {
		"payload_fields": ["item_id", "equip_slots"],
		"disabled_text": "物品不可装备",
	},
	"inventory_action_requires_inventory_item": {
		"payload_fields": ["drag_kind", "action_id"],
		"disabled_text": "只接受背包物品",
	},
	"inventory_action_missing_item": {
		"payload_fields": ["item_id", "action_id"],
		"disabled_text": "缺少背包物品",
	},
	"unknown_inventory_action": {
		"payload_fields": ["action_id"],
		"disabled_text": "未知背包操作",
	},
	"inventory_split_requires_stack_model": {
		"payload_fields": ["item_id", "count"],
		"disabled_text": "需要多堆叠背包模型",
	},
	"unknown_effect": {
		"payload_fields": ["item_id", "effect_id"],
		"disabled_text": "物品效果不可用",
	},
	"container_inventory_insufficient": {
		"payload_fields": ["container_id", "item_id", "count", "available"],
		"disabled_text": "容器数量不足",
	},
	"container_over_capacity": {
		"payload_fields": ["container_id", "item_id", "count", "limit_kind"],
		"disabled_text": "容器容量不足",
	},
	"container_key_missing": {
		"payload_fields": ["container_id", "item_id", "required_item_ids"],
		"disabled_text": "缺少容器钥匙",
	},
	"container_tool_missing": {
		"payload_fields": ["container_id", "item_id", "required_tool_ids"],
		"disabled_text": "缺少容器工具",
	},
	"container_owner_relationship_too_low": {
		"payload_fields": ["container_id", "owner_actor_id", "owner_relationship_min", "relationship_score"],
		"disabled_text": "关系不足",
	},
	"unknown_container_transfer_source": {
		"payload_fields": ["source", "container_id", "item_id", "count"],
		"disabled_text": "未知容器转移来源",
	},
	"container_drop_target_missing": {
		"payload_fields": ["target_source"],
		"disabled_text": "缺少容器拖拽目标",
	},
	"container_drop_source_missing": {
		"payload_fields": ["source", "target_source"],
		"disabled_text": "缺少容器拖拽来源",
	},
	"container_drop_item_missing": {
		"payload_fields": ["item_id", "source", "target_source"],
		"disabled_text": "缺少容器拖拽物品",
	},
	"container_drop_same_column": {
		"payload_fields": ["source", "target_source", "item_id"],
		"disabled_text": "不能拖回同一栏",
	},
	"container_drop_requires_container_column": {
		"payload_fields": ["source", "target_source", "item_id"],
		"disabled_text": "只能存入容器栏",
	},
	"container_drop_unsupported_drag_data": {
		"payload_fields": ["drag_kind", "target_source"],
		"disabled_text": "不支持的拖拽数据",
	},
	"player_money_insufficient": {
		"payload_fields": ["shop_id", "price", "player_money"],
		"disabled_text": "资金不足",
	},
	"quest_objective_incomplete": {
		"payload_fields": ["quest_id", "objective_id", "current", "target"],
		"disabled_text": "目标尚未完成",
	},
	"turn_in_requires_dialogue": {
		"payload_fields": ["quest_id", "target_definition_id", "dialogue_id", "dialogue_rule_id"],
		"disabled_text": "需要通过指定对话交付",
	},
	"turn_in_dialogue_mismatch": {
		"payload_fields": ["quest_id", "dialogue_id", "expected_dialogue_id"],
		"disabled_text": "当前对话不符合交付条件",
	},
	"turn_in_target_mismatch": {
		"payload_fields": ["quest_id", "target_actor_id", "target_definition_id", "expected_target_definition_id"],
		"disabled_text": "当前交付对象不符合条件",
	},
	"turn_in_target_missing": {
		"payload_fields": ["quest_id", "target_definition_id", "target_actor_id"],
		"disabled_text": "交付对象未指定",
	},
	"target_in_attack_range": {
		"payload_fields": ["actor_id", "target_actor_id", "distance", "attack_range"],
		"disabled_text": "可攻击目标",
	},
	"weapon_magazine_empty": {
		"payload_fields": ["actor_id", "weapon_item_id", "weapon_slot_id", "loaded", "capacity"],
		"disabled_text": "需要换弹",
	},
	"no_target_in_aggro_range": {
		"payload_fields": ["actor_id", "aggro_range", "candidate_count"],
		"disabled_text": "未发现目标",
	},
	"save_schema_unsupported": {
		"payload_fields": ["slot_id", "path", "schema_version"],
		"disabled_text": "存档版本不兼容",
	},
	"save_json_invalid": {
		"payload_fields": ["slot_id", "path"],
		"disabled_text": "存档 JSON 损坏",
	},
	"runtime_snapshot_missing": {
		"payload_fields": ["slot_id", "path"],
		"disabled_text": "存档缺少运行时快照",
	},
	"map_scene_missing": {
		"payload_fields": ["map_id", "path"],
		"disabled_text": "地图场景缺失",
	},
	"map_scene_load_failed": {
		"payload_fields": ["map_id", "path", "error"],
		"disabled_text": "地图场景加载失败",
	},
	"map_scene_root_invalid": {
		"payload_fields": ["map_id", "path", "error"],
		"disabled_text": "地图场景根节点无效",
	},
	"buy_zone_requires_shop_source": {
		"payload_fields": ["source", "drop_zone"],
		"disabled_text": "购买区只接受店铺物品",
	},
	"sell_zone_requires_player_or_equipment_source": {
		"payload_fields": ["source", "drop_zone"],
		"disabled_text": "出售区只接受背包或装备物品",
	},
	"cart_entry_missing_index": {
		"payload_fields": ["index"],
		"disabled_text": "购物车条目索引缺失",
	},
	"cart_entry_requires_cart_target": {
		"payload_fields": ["index", "target_kind"],
		"disabled_text": "购物车条目只能拖到购物车",
	},
	"trade_cart_unsupported_drag_data": {
		"payload_fields": ["drag_kind", "target_kind"],
		"disabled_text": "不支持的购物车拖拽数据",
	},
	"equipment_slot_requires_inventory_item": {
		"payload_fields": ["drag_kind", "slot_id"],
		"disabled_text": "装备槽只接受背包物品",
	},
	"equipment_slot_missing_item": {
		"payload_fields": ["item_id", "slot_id"],
		"disabled_text": "缺少装备物品",
	},
	"equipment_slot_missing_slot": {
		"payload_fields": ["item_id", "slot_id"],
		"disabled_text": "缺少装备槽位",
	},
	"equipment_slot_incompatible": {
		"payload_fields": ["item_id", "slot_id", "equip_slots"],
		"disabled_text": "物品不能装备到该槽位",
	},
	"hotbar_slot_requires_skill_hotbar": {
		"payload_fields": ["drag_kind", "slot_id"],
		"disabled_text": "只接受技能拖拽",
	},
	"hotbar_slot_missing_skill": {
		"payload_fields": ["skill_id", "slot_id"],
		"disabled_text": "缺少技能",
	},
	"hotbar_slot_missing_slot": {
		"payload_fields": ["skill_id", "slot_id"],
		"disabled_text": "缺少热栏槽位",
	},
	"hotbar_group_drag_unsupported": {
		"payload_fields": ["drag_kind", "group_id"],
		"disabled_text": "不能拖到热栏组",
	},
	"skill_on_cooldown": {
		"payload_fields": ["skill_id", "cooldown_remaining", "actor_id"],
		"disabled_text": "技能冷却中",
	},
	"missing_skill_points": {
		"payload_fields": ["skill_id", "available_skill_points"],
		"disabled_text": "缺技能点",
	},
	"missing_prerequisites": {
		"payload_fields": ["skill_id", "missing_prerequisites"],
		"disabled_text": "缺少前置技能",
	},
	"missing_attributes": {
		"payload_fields": ["skill_id", "missing_attributes"],
		"disabled_text": "属性不足",
	},
	"not_learned": {
		"payload_fields": ["skill_id", "level"],
		"disabled_text": "未学习",
	},
	"passive": {
		"payload_fields": ["skill_id", "activation_mode"],
		"disabled_text": "被动技能",
	},
	"unbound": {
		"payload_fields": ["skill_id", "bound_slot"],
		"disabled_text": "未绑定",
	},
	"cooldown": {
		"payload_fields": ["skill_id", "cooldown_remaining"],
		"disabled_text": "技能冷却中",
	},
}


func text_for(reason: String) -> String:
	if reason.is_empty():
		return "未知原因"
	var entry := entry_for(reason)
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
	var normalized: Dictionary = _dynamic_entry_for(reason)
	if not normalized.is_empty():
		return normalized
	return {
		"reason": reason,
		"known": false,
		"category": "unknown",
		"text": reason,
		"source_module": "",
		"payload_fields": [],
		"disabled_text": reason,
		"remediation": "",
	}


func _dynamic_entry_for(reason: String) -> Dictionary:
	var prefix := ""
	if reason.begins_with("scene_transition:"):
		prefix = "scene_transition"
	elif reason.begins_with("location_changed:"):
		prefix = "location_changed"
	if prefix.is_empty():
		return {}
	var entry := {
		"reason": reason,
		"known": true,
		"category": "pending",
		"text": "地图切换取消",
	}
	_apply_metadata(entry)
	entry["payload_fields"] = ["actor_id", "reason", "movement", "interaction", "crafting", "crafting_queue"]
	entry["disabled_text"] = "地图切换取消"
	entry["remediation"] = "地图切换时清理旧地图上的 pending 行动和制作队列。"
	entry["dynamic_prefix"] = prefix
	return entry


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
